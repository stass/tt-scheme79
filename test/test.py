# SPDX-FileCopyrightText: Copyright (c) 2026 Stanislav Sedov
# SPDX-License-Identifier: Apache-2.0
#

import struct
import zlib

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

# The minimal image, padded to its capacity:
# node 0 NIL, node 1 MEMTOP 100:000020, node 2 the boot cell.
CAPACITY = 32
NODES = [(0, 0), (0x40000010, 0), (0x4000002A, 0)] + [(0, 0)] * (CAPACITY - 3)
PAYLOAD = struct.pack("<%dI" % (2 * CAPACITY), *[w for cell in NODES for w in cell])
HEADER = struct.pack("<4sHHIIIIIIQ", b"S79I", 3, 0, CAPACITY, CAPACITY, 2, 0, 0,
                     zlib.crc32(PAYLOAD), 0) + bytes(24)
IMAGE = list(struct.unpack("<%dI" % (16 + 2 * CAPACITY), HEADER + PAYLOAD))

GOLDEN = [("A", 0x000001), ("R", 0, 0x40000010), ("I", 0x00000002), ("A", 0x000000),
          ("W", 0, 0x21000002), ("A", 0x000000), ("R", 0, 0x21000002)]
RESULT = 0x4000002A           # VAL: type 100, data 52 octal
GLYPH_A = 0x77                # seven-segment "A", VAL's low four bits
BUDGET = 3000                 # cycles; the RTL takes about 700

MEMORY_OPS = {0x08, 0x02, 0x03, 0x04, 0x05, 0x12}
REQUEST_BYTES = {0x08: 3, 0x02: 0, 0x03: 0, 0x04: 4, 0x05: 4, 0x12: 0, 0x20: 4}


class MemorySystem:

    def __init__(self, words):
        self.mem = list(words)
        self.reset()

    def reset(self):
        self.phase, self.op, self.count, self.buffer = "idle", None, 0, []
        self.latch = None
        self.boot_pending, self.gc_pending, self.user_pending, self.gc_seen = True, False, False, False
        self.irq, self.result, self.word = 0, None, 0
        self.capacity = self.mem[3]
        self.records = []

    def fault(self, why):
        raise AssertionError("memory-system fault: " + why)

    def response_byte(self):
        """ui_in for the coming edge."""
        return (self.word >> (8 * self.count)) & 0xFF if self.phase == "response" else 0

    def edge(self, tx_valid, rx_ready, tx_byte, gc_needed):
        """What the coming rising edge does, from the pins the chip shows."""
        if tx_valid and rx_ready:
            self.fault("framing: TX_VALID with RX_READY")
        if self.phase == "idle":
            if rx_ready:
                self.fault("framing: RX_READY between transactions")
            if tx_valid:
                self.opcode(tx_byte, gc_needed)
        elif self.phase == "request":
            if not tx_valid:
                self.fault("framing: short request")
            self.buffer.append(tx_byte)
            if len(self.buffer) == REQUEST_BYTES[self.op]:
                self.request_done()
        elif self.phase == "response":
            if not rx_ready:
                self.fault("framing: short response")
            self.count += 1
            if self.count == 4:
                self.phase, self.count = "gap", 0
        else:
            if tx_valid or rx_ready:
                self.fault("framing: no gap after a transaction")
            self.phase = "idle"

    def node_word(self, cdr):
        return 16 + 2 * self.latch + cdr

    def opcode(self, op, gc_needed):
        if op not in REQUEST_BYTES:
            self.fault("opcode %02x" % op)
        if op in (0x02, 0x03, 0x04, 0x05) and self.latch is None:
            self.fault("nolatch")
        if op == 0x20 and self.result is not None:
            self.fault("result")
        self.op, self.buffer, self.count = op, [], 0
        if op in MEMORY_OPS:
            # C4, C5 (no user requests here), C3, C6, in that order.
            self.gc_pending |= bool(gc_needed) and not self.gc_seen
            self.gc_seen = bool(gc_needed)
            if op == 0x12:
                if self.boot_pending:
                    vector, self.boot_pending = 4, False
                elif self.user_pending:
                    vector, self.user_pending = 6, False
                elif self.gc_pending:
                    vector, self.gc_pending = 5, False
                else:
                    self.fault("spurious")
                self.word = self.mem[vector]
                if self.word == 0:
                    self.fault("novector")
                self.records.append(("I", self.word))
            elif op in (0x02, 0x03):
                self.word = self.mem[self.node_word(op & 1)]
                self.records.append(("R", op & 1, self.word))
            self.irq = int(self.gc_pending or self.user_pending)
        self.phase = "response" if op in (0x02, 0x03, 0x12) else "request"

    def request_done(self):
        value = sum(b << (8 * i) for i, b in enumerate(self.buffer))
        if self.op == 0x08:
            if value >= self.capacity:
                self.fault("range")
            self.latch = value
            self.records.append(("A", value))
        elif self.op in (0x04, 0x05):
            self.mem[self.node_word(self.op & 1)] = value
            self.records.append(("W", self.op & 1, value))
        else:
            self.result = value
            self.records.append(("D", value))
        self.phase = "gap"


@cocotb.test()
async def test_minimal_image_boots_to_result_52(dut):
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    memory = MemorySystem(IMAGE)
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1

    for cycle in range(BUDGET):
        await FallingEdge(dut.clk)
        uio = int(dut.uio_out.value)
        assert int(dut.uio_oe.value) == 0xE9
        # Drive the byte the coming edge samples, and IRQ as the last
        # opcode edge left it (rule C6), then account for that edge.
        dut.ui_in.value = memory.response_byte()
        dut.uio_in.value = memory.irq << 4
        memory.edge(uio & 1, (uio >> 3) & 1, int(dut.uo_out.value), (uio >> 6) & 1)
        if memory.result is not None:
            break

    dut._log.info("RESULT %s after %d cycles", memory.result, cycle)
    assert memory.result == RESULT, "no RESULT 100:000052 within %d cycles" % BUDGET
    assert memory.records[:len(GOLDEN)] == GOLDEN
    assert [r[0] for r in memory.records].count("I") == 1, "the boot collection raises no interrupt"

    await ClockCycles(dut.clk, 2)
    await FallingEdge(dut.clk)
    uio = int(dut.uio_out.value)
    assert (uio >> 5) & 1 == 1, "DONE is up after RESULT"
    assert int(dut.uo_out.value) == GLYPH_A, "uo_out shows VAL's low four bits"

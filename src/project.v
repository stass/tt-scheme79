`default_nettype none

module tt_um_stass_scheme79 (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n

);

    wire        commit, gc_needed;
    wire        step_read, step_write, step_ale, step_cdr, step_read_interrupt, step_merge_mark_1;
    wire [31:0] bus, rx_word;
    wire [8:0]  upc;
    wire [30:0] val;
    wire        tx_valid, rx_ready, result_sent;
    wire [7:0]  tx_byte;

    s79_core core (
        .clk(clk), .rst_n(rst_n), .irq(uio_in[4]),
        .commit(commit), .rx_word(rx_word),
        .step_read(step_read), .step_write(step_write), .step_ale(step_ale), .step_cdr(step_cdr),
        .step_read_interrupt(step_read_interrupt), .step_merge_mark_1(step_merge_mark_1),
        .bus(bus), .upc(upc), .val_out(val), .gc_needed(gc_needed)
    );

    s79_pads pads (
        .clk(clk), .rst_n(rst_n), .ui_in(ui_in),
        .step_read(step_read), .step_write(step_write), .step_ale(step_ale), .step_cdr(step_cdr),
        .step_read_interrupt(step_read_interrupt), .step_merge_mark_1(step_merge_mark_1),
        .bus(bus), .upc(upc), .val(val),
        .commit(commit), .rx_word(rx_word),
        .tx_valid(tx_valid), .tx_byte(tx_byte), .rx_ready(rx_ready), .result_sent(result_sent)
    );

    wire [15:0] digit = 16'd1 << val[3:0];
    wire [6:0]  glyph = {
        |(digit & 16'b1110111101111100),
        |(digit & 16'b1101111101110001),
        |(digit & 16'b1111110101000101),
        |(digit & 16'b0111101101101101),
        |(digit & 16'b0010111111111011),
        |(digit & 16'b0010011110011111),
        |(digit & 16'b1101011111101101)
    };

    assign uo_out  = tx_valid ? tx_byte : result_sent ? {1'b0, glyph} : upc[7:0];
    assign uio_out = {upc[8], gc_needed, result_sent, 1'b0, rx_ready, 2'b00, tx_valid};
    assign uio_oe  = 8'hE9;

    wire _unused = &{1'b0, ena, uio_in[7:5], uio_in[3:0]};

endmodule

`default_nettype wire

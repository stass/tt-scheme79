//Generated
`default_nettype none

module s79_control_pla (
    input  wire dispatch,
    input  wire nano_run,
    input  wire external_freeze,
    input  wire external_read_state,
    input  wire external_load_state,
    input  wire allow_interrupts,
    input  wire external_interrupt_request,
    input  wire read,
    input  wire ph1,
    input  wire read_interrupt,
    output wire micro_from_next,
    output wire micro_hold,
    output wire micro_from_dispatch,
    output wire micro_from_interrupt,
    output wire micro_msb_from_bus,
    output wire micro_msb_from_0,
    output wire pads_in,
    output wire nano_hold,
    output wire nano_from_micro,
    output wire nano_from_next
);

    wire [9:0] pla_in = {read_interrupt, ph1, read, external_interrupt_request, allow_interrupts, external_load_state, external_read_state, external_freeze, nano_run, dispatch};
    wire [9:0] pla_out =
        10'd0

        | ({10{(pla_in & 10'o0407) == 10'o0400}} & 10'o0001)

        | ({10{(pla_in & 10'o0406) == 10'o0400}} & 10'o0400)

        | ({10{(pla_in & 10'o0406) == 10'o0402}} & 10'o1002)

        | ({10{(pla_in & 10'o0424) == 10'o0404}} & 10'o0202)

        | ({10{(pla_in & 10'o0410) == 10'o0410}} & 10'o0026)

        | ({10{(pla_in & 10'o0420) == 10'o0420}} & 10'o0424)

        | ({10{(pla_in & 10'o0447) == 10'o0401}} & 10'o0044)

        | ({10{(pla_in & 10'o0507) == 10'o0401}} & 10'o0044)

        | ({10{(pla_in & 10'o0547) == 10'o0541}} & 10'o0010)

        | ({10{(pla_in & 10'o0020) == 10'o0020}} & 10'o0100)

        | ({10{(pla_in & 10'o0204) == 10'o0200}} & 10'o0100);

    assign micro_from_next = pla_out[0];
    assign micro_hold = pla_out[1];
    assign micro_from_dispatch = pla_out[2];
    assign micro_from_interrupt = pla_out[3];
    assign micro_msb_from_bus = pla_out[4];
    assign micro_msb_from_0 = pla_out[5];
    assign pads_in = pla_out[6];
    assign nano_hold = pla_out[7];
    assign nano_from_micro = pla_out[8];
    assign nano_from_next = pla_out[9];

endmodule

`default_nettype wire

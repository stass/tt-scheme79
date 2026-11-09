`default_nettype none

module s79_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        irq,

    input  wire        commit,
    input  wire [31:0] rx_word,

    output wire        step_read,
    output wire        step_write,
    output wire        step_ale,
    output wire        step_cdr,
    output wire        step_read_interrupt,
    output wire        step_merge_mark_1,
    output wire [31:0] bus,
    output reg  [8:0]  upc,
    output wire [30:0] val_out,
    output reg         gc_needed

);

    wire [27:0] uw;
    wire [8:0]  uw_next = uw[8:0];
    wire [7:0]  uw_nano = uw[16:9];
    wire [6:0]  uw_from = uw[23:17];
    wire [3:0]  uw_to   = uw[27:24];

    s79_micro_pla micro_pla (.state(upc), .word(uw));

    reg  [7:0]  nst;
    reg         first;
    wire [7:0]  nstate = first ? uw_nano : nst;
    wire [50:0] nc;

    s79_nano_pla nano_pla (.to(uw_to), .from(uw_from[3:0]), .state(nstate), .nc(nc));

    wire [7:0] nano_or_state        = nc[7:0];
    wire       from_constant        = nc[8];
    wire [2:0] branch               = nc[11:9];
    wire       dispatch             = nc[12];
    wire       nano_run             = nc[13];
    wire       allow_interrupts     = nc[14];
    wire       to_frame_exp         = nc[15];
    wire       to_displacement_exp  = nc[16];
    wire       to_type_exp          = nc[17];
    wire       from_exp             = nc[18];
    wire       from_decremented_exp = nc[19];
    wire       to_address_newcell   = nc[20];
    wire       to_type_newcell      = nc[21];
    wire       from_newcell         = nc[22];
    wire       from_incremented_newcell = nc[23];
    wire       to_address_val       = nc[24];
    wire       to_type_val          = nc[25];
    wire       from_val             = nc[26];
    wire       to_address_stack     = nc[27];
    wire       to_address_retpc     = nc[28];
    wire       to_type_retpc        = nc[29];
    wire       from_retpc           = nc[30];
    wire       to_type_stack        = nc[31];
    wire       from_stack           = nc[32];
    wire       to_intermediate_argument   = nc[33];
    wire       from_intermediate_argument = nc[34];
    wire       to_display           = nc[35];
    wire       from_display         = nc[36];
    wire       to_args              = nc[37];
    wire       from_args            = nc[38];
    wire       to_memtop            = nc[39];
    wire       from_memtop          = nc[40];
    wire       from_nil             = nc[41];
    wire       read                 = nc[42];
    wire       merge_mark_1         = nc[43];
    wire       merge_mark_0         = nc[44];
    wire       set_gc_needed        = nc[45];
    wire       clr_gc_needed        = nc[46];
    wire       read_interrupt       = nc[47];
    wire       write                = nc[48];
    wire       ale                  = nc[49];
    wire       cdr                  = nc[50];

    reg  [30:0] exp;
    reg  [30:0] newcell;
    reg  [30:0] val;
    reg  [30:0] retpc_count_mark;
    reg  [30:0] stack;
    reg  [30:0] args;
    reg  [30:0] display;
    reg  [30:0] intermediate_argument;
    reg  [30:1] memtop_high;
    reg         memtop_0;
    wire [30:0] memtop = {memtop_high, memtop_0};

    wire [23:0] exp_decremented     = exp[23:0] - 24'd1;
    wire [23:0] newcell_incremented = newcell[23:0] + 24'd1;

    wire [30:0] bus_low =
          ({31{from_exp}}                   & exp)
        | ({31{from_decremented_exp}}       & {exp[30:24], exp_decremented})
        | ({31{from_newcell}}               & newcell)
        | ({31{from_incremented_newcell}}   & {newcell[30:24], newcell_incremented})
        | ({31{from_val}}                   & val)
        | ({31{from_retpc}}                 & retpc_count_mark)
        | ({31{from_stack}}                 & stack)
        | ({31{from_intermediate_argument}} & intermediate_argument)
        | ({31{from_display}}               & display)
        | ({31{from_args}}                  & args)
        | ({31{from_memtop}}                & memtop)
        | ({31{from_constant}}              & {uw_from, 24'd0})
        | ({31{read}}                       & rx_word[30:0]);

    assign bus = {read & rx_word[31], bus_low};

    wire newcell_equals_bus = bus[23:0] == newcell[23:0];
    reg  condition;
    always @* begin
        case (branch)
            3'd1:    condition = bus[11:0] == 12'd0;
            3'd2:    condition = bus[23:0] == 24'd0;
            3'd3:    condition = newcell_equals_bus;
            3'd4:    condition = bus[30:24] == val[30:24];
            3'd5:    condition = bus[30:0] == val;
            3'd6:    condition = bus[30];
            3'd7:    condition = bus[31];
            default: condition = 1'b0;
        endcase
    end

    wire micro_from_next, micro_hold, micro_from_dispatch, micro_from_interrupt;
    wire micro_msb_from_bus, micro_msb_from_0, pads_in;
    wire nano_hold, nano_from_micro, nano_from_next;
    reg  irq_q;

    s79_control_pla control_pla (
        .dispatch(dispatch),
        .nano_run(nano_run),
        .external_freeze(~commit),
        .external_read_state(1'b0),
        .external_load_state(1'b0),
        .allow_interrupts(allow_interrupts),
        .external_interrupt_request(irq_q),
        .read(read),
        .ph1(1'b1),
        .read_interrupt(read_interrupt),
        .micro_from_next(micro_from_next),
        .micro_hold(micro_hold),
        .micro_from_dispatch(micro_from_dispatch),
        .micro_from_interrupt(micro_from_interrupt),
        .micro_msb_from_bus(micro_msb_from_bus),
        .micro_msb_from_0(micro_msb_from_0),
        .pads_in(pads_in),
        .nano_hold(nano_hold),
        .nano_from_micro(nano_from_micro),
        .nano_from_next(nano_from_next)
    );

    wire [8:0] upc_next =
          ({9{micro_from_next}}      & {uw_next[8:1], uw_next[0] | condition})
        | ({9{micro_from_dispatch}}  & {2'b00, bus[30:24]})
        | ({9{micro_from_interrupt}} & 9'o777)
        | ({9{micro_hold}}           & upc);

    wire [7:0] nst_next   = nano_from_next ? nano_or_state : nst;
    wire       first_next = nano_from_micro | (nano_hold & first);

    always @(posedge clk)
        if (!rst_n)      upc <= 9'o776;
        else if (commit) upc <= upc_next;

    always @(posedge clk)
        if (commit) nst <= nst_next;

    always @(posedge clk)
        if (!rst_n)      first <= 1'b1;
        else if (commit) first <= first_next;

    always @(posedge clk)
        if (!rst_n) irq_q <= 1'b0;
        else        irq_q <= irq;

    always @(posedge clk)
        if (commit) begin
            if (to_frame_exp)              exp[11:0]                <= bus[11:0];
            if (to_displacement_exp)       exp[23:12]               <= bus[23:12];
            if (to_type_exp)               exp[30:24]               <= bus[30:24];
            if (to_address_newcell)        newcell[23:0]            <= bus[23:0];
            if (to_type_newcell)           newcell[30:24]           <= bus[30:24];
            if (to_address_val)            val[23:0]                <= bus[23:0];
            if (to_type_val)               val[30:24]               <= bus[30:24];
            if (to_address_stack)          stack[23:0]              <= bus[23:0];
            if (to_type_stack)             stack[30:24]             <= bus[30:24];
            if (to_address_retpc)          retpc_count_mark[23:0]   <= bus[23:0];
            if (to_type_retpc)             retpc_count_mark[30:24]  <= bus[30:24];
            if (to_intermediate_argument)  intermediate_argument    <= bus[30:0];
            if (to_display)                display                  <= bus[30:0];
            if (to_args)                   args                     <= bus[30:0];
            if (to_memtop)                 memtop_high              <= bus[30:1];
        end

    always @(posedge clk)
        if (!rst_n)                   memtop_0 <= 1'b1;
        else if (commit && to_memtop) memtop_0 <= bus[0];

    always @(posedge clk)
        if (!rst_n)      gc_needed <= 1'b0;
        else if (commit) gc_needed <= (gc_needed & ~clr_gc_needed) | (set_gc_needed & newcell_equals_bus);

    assign step_read           = read;
    assign step_write          = write;
    assign step_ale            = ale;
    assign step_cdr            = cdr;
    assign step_read_interrupt = read_interrupt;
    assign step_merge_mark_1   = merge_mark_1;
    assign val_out             = val;

    wire _unused = &{1'b0, pads_in, micro_msb_from_bus, micro_msb_from_0, merge_mark_0, from_nil};

endmodule

`default_nettype wire

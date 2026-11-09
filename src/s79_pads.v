`default_nettype none

module s79_pads (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  ui_in,

    input  wire        step_read,
    input  wire        step_write,
    input  wire        step_ale,
    input  wire        step_cdr,
    input  wire        step_read_interrupt,
    input  wire        step_merge_mark_1,
    input  wire [31:0] bus,
    input  wire [8:0]  upc,
    input  wire [30:0] val,

    output wire        commit,
    output wire [31:0] rx_word,

    output wire        tx_valid,
    output wire [7:0]  tx_byte,
    output wire        rx_ready,
    output wire        result_sent
);

    reg        tx_valid_q;
    reg        rx_ready_q;
    reg [7:0]  tx_byte_q;
    reg [2:0]  bcount;

    reg [23:0] rxhold;
    reg        result_sent_q;

    wire result_go = upc == 9'o124 && !result_sent_q;
    wire step_go   = !result_go && (step_read | step_write | step_ale | step_read_interrupt);
    wire need      = result_go | step_go;

    wire [7:0] opcode = result_go ? 8'h20 :
                        {3'b000, step_read_interrupt, step_ale, step_write, step_read, step_cdr};

    wire [2:0] request_bytes = result_go ? 3'd4 :
                               step_ale  ? 3'd3 :
                               step_write ? 3'd4 : 3'd0;
    wire       has_response  = step_go & step_read;

    wire [31:0] payload = result_go ? {1'b0, val} :
                          {step_merge_mark_1, bus[30:0]};
    wire [7:0] payload_byte = bcount == 3'd0 ? payload[7:0]   :
                              bcount == 3'd1 ? payload[15:8]  :
                              bcount == 3'd2 ? payload[23:16] : payload[31:24];

    wire idle          = !tx_valid_q && !rx_ready_q;
    wire last_request  = tx_valid_q && bcount == request_bytes;
    wire last_response = rx_ready_q && bcount == 3'd3;
    wire ends          = (last_request && !has_response) || last_response;

    assign commit = rst_n && ((idle && !need) || (ends && step_go));

    assign rx_word = {ui_in, rxhold};

    always @(posedge clk)
        if (!rst_n) begin
            tx_valid_q <= 1'b0;
            rx_ready_q <= 1'b0;
            bcount     <= 3'd0;
        end else if (idle) begin
            if (need) begin
                tx_valid_q <= 1'b1;
                bcount     <= 3'd0;
            end
        end else if (tx_valid_q) begin
            if (last_request) begin
                tx_valid_q <= 1'b0;
                rx_ready_q <= has_response;
                bcount     <= 3'd0;
            end else begin
                bcount     <= bcount + 3'd1;
            end
        end else begin
            if (last_response) begin
                rx_ready_q <= 1'b0;
                bcount     <= 3'd0;
            end else begin
                bcount     <= bcount + 3'd1;
            end
        end

    always @(posedge clk)
        if (idle) tx_byte_q <= opcode;
        else if (tx_valid_q && !last_request) tx_byte_q <= payload_byte;

    always @(posedge clk)
        if (rx_ready_q && !last_response) begin
            if (bcount == 3'd0) rxhold[7:0]   <= ui_in;
            if (bcount == 3'd1) rxhold[15:8]  <= ui_in;
            if (bcount == 3'd2) rxhold[23:16] <= ui_in;
        end

    always @(posedge clk)
        if (!rst_n)                        result_sent_q <= 1'b0;
        else if (last_request && result_go) result_sent_q <= 1'b1;

    wire _unused = &{1'b0, bus[31]};

    assign tx_valid    = tx_valid_q;
    assign tx_byte     = tx_byte_q;
    assign rx_ready    = rx_ready_q;
    assign result_sent = result_sent_q;

endmodule

`default_nettype wire

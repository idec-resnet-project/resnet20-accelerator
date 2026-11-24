
`timescale 1ns / 1ps

module mac_v3
#(
    parameter integer WORD_W   = 16,
    parameter integer ACC_W    = WORD_W*2+1,
    parameter integer ITER_CNT = 5
)
(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     enable,
    input  wire                     valid_in,
    input  wire [ITER_CNT-1:0]      iter,

    input  wire signed [WORD_W-1:0] fmap_in,
    input  wire signed [WORD_W-1:0] weight_in,
    input  wire signed [WORD_W-1:0] bias_in,

    output wire                     proc,
    output reg                      valid_out,
    output reg signed [ACC_W:0]     data_out
);

    localparam integer Q_SCALE = 8;


    //========================================
    // Input Control
    //========================================

    reg [ITER_CNT-1:0] iter_cnt;

    wire count_zero;
    wire input_busy;

    wire accept;
    wire first_in;
    wire last_in;
    wire zero_iter;

    assign count_zero = !(|iter_cnt);

    assign input_busy = !count_zero;

    assign accept =
        valid_in && (enable || input_busy);

    assign first_in = count_zero;

    assign last_in =
        count_zero ? (iter <= 1)
                   : (iter_cnt == 1);

    assign zero_iter =
        count_zero && (iter == 0);


    //========================================
    // Stage 1 Registers
    //========================================

    reg signed [WORD_W-1:0] fmap;
    reg signed [WORD_W-1:0] weight;
    reg signed [WORD_W-1:0] bias_s1;

    reg valid_s1;
    reg first_s1;
    reg last_s1;


    //========================================
    // Stage 2 Registers
    //========================================

    reg signed [WORD_W*2-1:0] multi;
    reg signed [WORD_W-1:0]   bias_s2;

    reg valid_s2;
    reg first_s2;
    reg last_s2;


    //========================================
    // MAC Processing Status
    //========================================

    assign proc =
        input_busy || valid_s1 || valid_s2;


    //========================================
    // Stage 3 Accumulator
    //========================================

    reg signed [ACC_W:0] acc;

    wire signed [ACC_W:0] bias_ext;
    wire signed [ACC_W:0] acc_base;
    wire signed [ACC_W:0] acc_next;

    assign bias_ext = {
        {(ACC_W+1-WORD_W-Q_SCALE)
        {bias_s2[WORD_W-1]}},
        bias_s2,
        {Q_SCALE{1'b0}}
    };

    assign acc_base =
        first_s2 ? bias_ext : acc;

    assign acc_next =
        acc_base + multi;


    //========================================
    // Input Down Counter
    //========================================

    always @(posedge clk)
    begin
        if (!rst_n)
        begin
            iter_cnt <= 0;
        end
        else
        begin
            if (accept)
            begin
                if (count_zero)
                begin
                    if (iter > 1)
                        iter_cnt <= iter - 1'b1;
                    else
                        iter_cnt <= 0;
                end
                else
                begin
                    iter_cnt <= iter_cnt - 1'b1;
                end
            end
        end
    end


    //========================================
    // Stage 1: Input Capture
    //========================================

    always @(posedge clk)
    begin
        if (!rst_n)
        begin
            fmap     <= 0;
            weight   <= 0;
            bias_s1  <= 0;

            valid_s1 <= 0;
            first_s1 <= 0;
            last_s1  <= 0;
        end
        else
        begin

            valid_s1 <= accept;

            if (accept)
            begin

                // Bias-only operation
                if (zero_iter)
                    fmap <= 0;
                else
                    fmap <= fmap_in;

                weight <= weight_in;

                first_s1 <= first_in;
                last_s1  <= last_in;

                // Capture bias once per window
                if (first_in)
                    bias_s1 <= bias_in;

            end
        end
    end


    //========================================
    // Stage 2: Multiplication
    //========================================

    always @(posedge clk)
    begin
        if (!rst_n)
        begin
            multi    <= 0;
            bias_s2  <= 0;

            valid_s2 <= 0;
            first_s2 <= 0;
            last_s2  <= 0;
        end
        else
        begin

            valid_s2 <= valid_s1;

            if (valid_s1)
            begin

                multi <= $signed(fmap)
                       * $signed(weight);

                first_s2 <= first_s1;
                last_s2  <= last_s1;

                // Transfer bias with first data
                if (first_s1)
                    bias_s2 <= bias_s1;

            end
        end
    end


    //========================================
    // Stage 3: Accumulation and Output
    //========================================

    always @(posedge clk)
    begin
        if (!rst_n)
        begin
            acc       <= 0;
            data_out  <= 0;
            valid_out <= 0;
        end
        else
        begin

            valid_out <= 1'b0;

            if (valid_s2)
            begin

                if (last_s2)
                begin
                    data_out  <= acc_next;
                    valid_out <= 1'b1;
                end
                else
                begin
                    acc <= acc_next;
                end

            end
        end
    end

endmodule

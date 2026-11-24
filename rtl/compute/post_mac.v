
`timescale 1ns / 1ps

module post_mac #(
    parameter integer WORD_W = 16,
    parameter integer ACC_W  = WORD_W*2+1
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     valid_in,
    input  wire signed [ACC_W:0]    data_in,

    output reg                      valid_out,
    output reg signed [WORD_W-1:0]  data_out
);

    localparam integer Q_SCALE = 8;
    localparam integer SIGN_POS = WORD_W + Q_SCALE - 1;

    localparam signed [WORD_W-1:0] INT_MAX =
        {1'b0, {(WORD_W-1){1'b1}}};

    localparam signed [WORD_W-1:0] INT_MIN =
        {1'b1, {(WORD_W-1){1'b0}}};

    // Stage 1 registers

    reg [WORD_W-1:0] data_slice;
    reg round_reg;
    reg pos_ovf_s1;
    reg neg_ovf_s1;

    reg proc;

    // Guard / Sticky rounding

    wire guard_bit;
    wire sticky_bit;
    wire round_up;

    assign guard_bit = data_in[Q_SCALE-1];

    assign sticky_bit = |data_in[Q_SCALE-2:0];

    assign round_up = guard_bit &&
                      (!data_in[ACC_W] || sticky_bit);

    // Early saturation detection (V3.1)

    wire pos_overflow;
    wire neg_overflow;

    assign pos_overflow = !data_in[ACC_W] &&
        (
            (|data_in[ACC_W-1:SIGN_POS]) ||
            (&data_in[SIGN_POS-1:Q_SCALE-1])
        );

    assign neg_overflow = data_in[ACC_W] &&
                          !(&data_in[ACC_W-1:SIGN_POS]);


    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            data_slice <= 0;
            round_reg  <= 0;

            pos_ovf_s1 <= 0;
            neg_ovf_s1 <= 0;

            proc       <= 1'b0;
            data_out   <= 0;
            valid_out  <= 1'b0;
        end

        else
        begin

            proc      <= valid_in;
            valid_out <= proc;

            if (valid_in)
            begin
                data_slice <= data_in[SIGN_POS:Q_SCALE];

                round_reg  <= round_up;
                pos_ovf_s1 <= pos_overflow;
                neg_ovf_s1 <= neg_overflow;
            end


            // STEP 5.1
            // Stage 2: Rounding + Saturation

            if (proc)
            begin
                if (pos_ovf_s1)
                    data_out <= INT_MAX;

                else if (neg_ovf_s1)
                    data_out <= INT_MIN;

                else
                    data_out <= data_slice + round_reg;
                end

        end
    end

endmodule

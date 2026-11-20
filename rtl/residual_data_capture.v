module residual_data_capture
#(
    parameter integer WORD_W = 16,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16,
    // parallelism
    parameter integer PARALLEL_PC                = 1,
    parameter integer PARALLEL_PF                = 1
)
(
    input  wire                                  clk,
    input  wire                                  nrst,
    input  wire [PARALLEL_PC*WORD_W-1:0]         residual_data,

    output reg  [PARALLEL_PC*WORD_W-1:0]         residual_data_out
);

reg [WORD_W-1:0] residual_data_capture[PARALLEL_PC-1:0];

always @(posedge clk or negedge nrst) 
begin
    if(!nrst) begin
        residual_data_out <= {PARALLEL_PC*WORD_W{1'b0}};
        for (integer i = 0; i < PARALLEL_PC; i = i + 1) 
        begin
            residual_data_capture[i] <= residual_data{WORD_W{1'b0}};
        end
    end
    else 
    begin
        for (integer i = 0; i < PARALLEL_PC; i = i + 1) 
        begin : capture_loop
            residual_data_capture[i] <= residual_data[i*WORD_W +: WORD_W];
            residual_data_out[i*WORD_W +: WORD_W] <= residual_data_capture[i];
        end
        
    end
end
    
endmodule
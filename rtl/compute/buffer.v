module buffer #(
    parameter integer DEPTH    = 11,  // Address bits. Capacity is 2**DEPTH words.
    parameter integer BITWIDTH = 16
)(
    input  wire                clka,
    input  wire                wea,
    input  wire [DEPTH-1:0]    addra,
    input  wire [BITWIDTH-1:0] dina,
    input  wire                clkb,
    input  wire [DEPTH-1:0]    addrb,
    output reg  [BITWIDTH-1:0] doutb
);

localparam integer WORD_COUNT = 2 ** DEPTH;

(* ram_style = "block" *) reg [BITWIDTH-1:0] mem [0:WORD_COUNT-1];
integer i;

initial begin
    doutb = {BITWIDTH{1'b0}};
    for (i = 0; i < WORD_COUNT; i = i + 1) begin
        mem[i] = {BITWIDTH{1'b0}};
    end
end

always @(posedge clka) begin
    if (wea) begin
        mem[addra] <= dina;
    end
end

// With independent clocks, avoid overlapping reads and writes to the same address.
always @(posedge clkb) begin
    doutb <= mem[addrb];
end

endmodule

interface axis_if (
    input logic clk,
    input logic nrst
);
    // Payload and packet boundary
    logic [15:0] tdata;
    logic [1:0]  tkeep;
    logic        tlast;

    // Handshake
    logic tvalid;
    logic tready;
endinterface

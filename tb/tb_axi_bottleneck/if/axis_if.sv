interface axis_if(input logic clk, input logic nrst);
    logic [15:0] tdata;
    logic [1:0] tkeep;
    logic tvalid, tlast, tready;
endinterface

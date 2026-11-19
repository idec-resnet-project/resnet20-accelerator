interface axi_lite_if (
    input logic clk,
    input logic nrst
);
    // Test-controlled reset request
    logic reset_request = 1;

    // Write address
    logic [31:0] awaddr;
    logic [2:0]  awprot;
    logic        awvalid;
    logic        awready;

    // Write data
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;

    // Write response
    logic [1:0] bresp;
    logic       bvalid;
    logic       bready;

    // Read address
    logic [31:0] araddr;
    logic [2:0]  arprot;
    logic        arvalid;
    logic        arready;

    // Read data and response
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;
endinterface

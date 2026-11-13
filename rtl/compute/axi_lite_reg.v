module axi_lite_reg #(
    parameter AXI_LITE_ADDR_WIDTH = 32,
    parameter AXI_LITE_DATA_WIDTH = 32,
    parameter DEFAULT = 0
) (
    // AXI4-Lite slave clock and active-low reset
    input  wire                             s_axi_aclk,
    input  wire                             s_axi_aresetn,

    // Write address
    input  wire [AXI_LITE_ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [2:0]                       s_axi_awprot,
    input  wire                             s_axi_awvalid,
    output wire                             s_axi_awready,

    // Write data
    input  wire [AXI_LITE_DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [AXI_LITE_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                             s_axi_wvalid,
    output wire                             s_axi_wready,

    // Write response
    output wire [1:0]                       s_axi_bresp,
    output wire                             s_axi_bvalid,
    input  wire                             s_axi_bready,

    // Read address
    input  wire [AXI_LITE_ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [2:0]                       s_axi_arprot,
    input  wire                             s_axi_arvalid,
    output wire                             s_axi_arready,

    // Read data and response
    output wire [AXI_LITE_DATA_WIDTH-1:0]   s_axi_rdata,
    output wire [1:0]                       s_axi_rresp,
    output wire                             s_axi_rvalid,
    input  wire                             s_axi_rready,

    // Configuration register value for the UART core
    output wire [31:0]                      cfg_data,
    output reg                              cfg_data_enable 
);

// Protection attributes are accepted but not interpreted.

//------------------------Parameter----------------------
localparam
    //register address
    ADDR_CONFIG 				    = 32'h60000000,

    //Write Channel state 
    WRIDLE                  = 2'd0,
    WRDATA                  = 2'd1,
    WRRESP                  = 2'd2,
    //Read Channel state 
    RDIDLE                  = 2'd0,
    RDDATA                  = 2'd1,
    // Cntl/Sts state
    IDLE					= 2'd0,
    SEND 					= 2'd1,
    CHECK					= 2'd2;

//------------------------Local signal-------------------
reg  [1:0]                    			wstate;
reg  [1:0]                    			wnext;
reg  [AXI_LITE_ADDR_WIDTH-1:0]          waddr;
wire                          			aw_hs;
wire                          			w_hs;
reg  [1:0]                    			rstate;
reg  [1:0]                    			rnext;
reg  [31:0]                   			rdata;
wire                          			ar_hs;
wire [AXI_LITE_ADDR_WIDTH-1:0]          raddr;
reg [31:0] reg_config = 0;

//------------------------AXI read fsm-------------------
assign s_axi_arready = (rstate == RDIDLE);
assign s_axi_rdata   = rdata;
assign s_axi_rresp   = 2'b00;  // OKAY
assign s_axi_rvalid  = (rstate == RDDATA);
assign ar_hs   = s_axi_arvalid & s_axi_arready;
assign raddr   = s_axi_araddr[AXI_LITE_ADDR_WIDTH-1:0];

// rstate
always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn)
        rstate <= RDIDLE;
    else 
        rstate <= rnext;
end

// rnext
always @(*) begin
    case (rstate)
        RDIDLE:
            if (s_axi_arvalid)
                rnext = RDDATA;
            else
                rnext = RDIDLE;
        RDDATA:
            if (s_axi_rready & s_axi_rvalid)
                rnext = RDIDLE;
            else
                rnext = RDDATA;
        default:
            rnext = RDIDLE;
    endcase
end

// rdata
always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn)
        rdata <= 0;
    else if (ar_hs) begin
        case (raddr)
            ADDR_CONFIG: 
                rdata <= reg_config;
            default : 
                rdata <= 0;
        endcase
    end
end

//------------------------AXI write fsm------------------
assign s_axi_awready = (wstate == WRIDLE);
assign s_axi_wready  = (wstate == WRDATA);
assign s_axi_bresp   = 2'b00;  // OKAY
assign s_axi_bvalid  = (wstate == WRRESP);
assign aw_hs   = s_axi_awvalid & s_axi_awready;
assign w_hs    = s_axi_wvalid & s_axi_wready;

// wstate
always @(posedge s_axi_aclk) begin
if (!s_axi_aresetn)
wstate <= WRIDLE;
else 
wstate <= wnext;
end

// wnext
always @(*) begin
case (wstate)
WRIDLE:
    if (s_axi_awvalid)
        wnext = WRDATA;
    else
        wnext = WRIDLE;
WRDATA:
    if (s_axi_wvalid)
        wnext = WRRESP;
    else
        wnext = WRDATA;
WRRESP:
    if (s_axi_bready)
        wnext = WRIDLE;
    else
        wnext = WRRESP;
default:
    wnext = WRIDLE;
endcase
end

// waddr
always @(posedge s_axi_aclk) begin
if (aw_hs)
waddr <= s_axi_awaddr[AXI_LITE_ADDR_WIDTH-1:0];
end

// internal registers 

always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
        reg_config <= DEFAULT;
    end
    else if (w_hs && waddr == ADDR_CONFIG) begin
        reg_config <= s_axi_wdata;
    end
    else begin
        reg_config <= reg_config;
    end
end   

always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
        cfg_data_enable <= '0;
    end
    else if (w_hs && waddr == ADDR_CONFIG) begin
        cfg_data_enable <= '1;
    end
    else begin
        cfg_data_enable <= '0;
    end
end   

assign cfg_data = reg_config;

endmodule


`timescale 1ns/1ps

interface axi_if #(
    parameter int ID_WIDTH   = 4,
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
)(
    input logic clk,
    input logic rst
);
    // Write Address Channel (AW)
    logic [ID_WIDTH-1:0]   m_axi_awid;
    logic [ADDR_WIDTH-1:0] m_axi_awaddr;
    logic [7:0]            m_axi_awlen;
    logic [2:0]            m_axi_awsize;
    logic [1:0]            m_axi_awburst;
    logic                  m_axi_awlock;
    logic [3:0]            m_axi_awcache;
    logic [2:0]            m_axi_awprot;
    logic [3:0]            m_axi_awqos;
    logic                  m_axi_awvalid;
    logic                  m_axi_awready;

    // Write Data Channel (W)
    logic [DATA_WIDTH-1:0] m_axi_wdata;
    logic [STRB_WIDTH-1:0] m_axi_wstrb;
    logic                  m_axi_wlast;
    logic                  m_axi_wvalid;
    logic                  m_axi_wready;

    // Write Response Channel (B)
    logic [ID_WIDTH-1:0]   m_axi_bid;
    logic [1:0]            m_axi_bresp;
    logic                  m_axi_bvalid;
    logic                  m_axi_bready;

    // Read Address Channel (AR)
    logic [ID_WIDTH-1:0]   m_axi_arid;
    logic [ADDR_WIDTH-1:0] m_axi_araddr;
    logic [7:0]            m_axi_arlen;
    logic [2:0]            m_axi_arsize;
    logic [1:0]            m_axi_arburst;
    logic                  m_axi_arlock;
    logic [3:0]            m_axi_arcache;
    logic [2:0]            m_axi_arprot;
    logic [3:0]            m_axi_arqos;
    logic                  m_axi_arvalid;
    logic                  m_axi_arready;

    // Read Data Channel (R)
    logic [ID_WIDTH-1:0]   m_axi_rid;
    logic [DATA_WIDTH-1:0] m_axi_rdata;
    logic [1:0]            m_axi_rresp;
    logic                  m_axi_rlast;
    logic                  m_axi_rvalid;
    logic                  m_axi_rready;

    // Master Driver Clocking Block
    clocking cb @(posedge clk);
        default input #1step output #0;

        // AW
        output m_axi_awid, m_axi_awaddr;
        output m_axi_awlen, m_axi_awsize;
        output m_axi_awburst, m_axi_awlock;
        output m_axi_awcache, m_axi_awprot;
        output m_axi_awqos, m_axi_awvalid;
        input  m_axi_awready;

        // W
        output m_axi_wdata, m_axi_wstrb;
        output m_axi_wlast, m_axi_wvalid;
        input  m_axi_wready;

        // B
        input  m_axi_bid, m_axi_bresp;
        input  m_axi_bvalid;
        output m_axi_bready;

        // AR
        output m_axi_arid, m_axi_araddr;
        output m_axi_arlen, m_axi_arsize;
        output m_axi_arburst, m_axi_arlock;
        output m_axi_arcache, m_axi_arprot;
        output m_axi_arqos, m_axi_arvalid;
        input  m_axi_arready;

        // R
        input  m_axi_rid, m_axi_rdata;
        input  m_axi_rresp, m_axi_rlast;
        input  m_axi_rvalid;
        output m_axi_rready;
    endclocking

    // Monitor Clocking Block
    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst;
        input m_axi_rvalid, m_axi_rready;
        input m_axi_rdata, m_axi_rresp, m_axi_rlast;
    endclocking

endinterface

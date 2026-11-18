//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/10 14:07:48
// Design Name: 
// Module Name: mac_packed
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module conv_valid_dcd
(
    // 레지스터된 enable
    input  wire mac_enable,
    input  wire relu_enable,
    input  wire residual_enable,
    input  wire pooling_enable,
    input  wire gap_enable,

    // 체인 입력 valid
    input  wire in_valid,

    // 각 모듈 valid_out
    input  wire mac_valid_out,
    input  wire relu_valid_out,
    input  wire residual_valid_out,
    input  wire pooling_valid_out,

    // 각 모듈 valid_in
    output wire mac_valid_in,
    output wire relu_valid_in,
    output wire residual_valid_in,
    output wire pooling_valid_in,

    // 체인 최종 valid
    output wire valid_out
);

    wire v_mac  = mac_enable                     ? mac_valid_out      : in_valid;
    wire v_relu = relu_enable                    ? relu_valid_out     : v_mac;
    wire v_res  = residual_enable                ? residual_valid_out : v_relu;
    wire v_pool = (pooling_enable || gap_enable) ? pooling_valid_out  : v_res;

    assign mac_valid_in      = in_valid;
    assign relu_valid_in     = v_mac;
    assign residual_valid_in = v_relu;
    assign pooling_valid_in  = v_res;
    assign valid_out         = v_pool;

endmodule

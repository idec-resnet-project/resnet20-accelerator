`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/09 19:58:58
// Design Name: 
// Module Name: tb_ReLU
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


module tb_ReLU#(
parameter integer BITWIDTH = 16
    );
    reg clk;                          
    reg nrst;                         
    reg enable;                       
    reg in_enable;                    
    reg signed [BITWIDTH-1:0] in_data;
                                   
    wire out_enable;                   
    wire signed [BITWIDTH-1:0] out_data;
    
    ReLU uut_relu
    (
    .clk(clk),                           
    .nrst(nrst),                          
    .enable(enable),                        
    .in_enable(in_enable),                     
    .in_data(in_data), 
                               
    .out_enable(out_enable),
    .out_data(out_data)
    );
    
    always #2 clk = ~clk;
    
    task send_data(input signed [BITWIDTH-1:0] data);
        begin
            @(posedge clk);
            in_enable <= 1'b1;
            enable  <=1;
            in_data   <= data;
        end
    endtask
    
    task send_bypass(input signed [BITWIDTH-1:0] data);
        begin
            @(posedge clk);
            in_enable <= 1'b1;
            enable <= 0;
            in_data   <= data;
        end
    endtask
    initial
    begin
        clk = 0;
        nrst = 0;
        enable = 0;
        in_enable = 0;
        in_data = 0;
        
        #1000;
        nrst = 1;
        #4
        send_data(-50);
        send_data(-30);
        send_data(10);
        send_data(60);
        send_data(-29450);
        send_data(24813);
        send_bypass(50);
        send_bypass(30);
        send_bypass(-10);
        send_bypass(-60);
        send_bypass(29846);
        send_bypass(-27458);
    end
    
endmodule

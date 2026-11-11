//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/10 12:54:19
// Design Name: 
// Module Name: mac
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

`timescale 1ns / 1ps

module mac_v2 #(
    parameter integer BITWIDTH = 16, //input data size = 16
    parameter integer ACC_WIDTH= 64, 
    parameter integer ITER_CNT = 5   
)(
    input wire clk, 
    input wire nrst,
    input wire enable,                               //en = 0 -> data bypass, en = 1 -> using mac
    input wire [ITER_CNT-1:0] iteration,                      //if iteration = 3 -> Y = X0W0 + X1W1 + X2W2
                                  //buffer --in_vaild--> mac

    input wire signed [BITWIDTH-1:0] in_data,       //feature value
    input wire signed [BITWIDTH-1:0] kernel_data,   //weight value

    output reg out_valid, //mac --out_vaild--> other    
    output reg signed [ACC_WIDTH-1:0] out_data //mac --out_data--> other
    );

    //mac's inner reg & wire

    reg signed [ACC_WIDTH-1:0] acc; //accumulator    
    reg [4:0] count; //if count == iteration -> finish acc & get output
    reg [4:0] iter_reg;
    reg iter_stop;

    //product and accumulation  
    always @(posedge clk or negedge nrst) 
        begin
            if(!nrst) 
               begin
                  acc         <= {ACC_WIDTH{1'b0}};
                  count       <= {ITER_CNT{1'b0}};
                  out_data    <= {ACC_WIDTH{1'b0}};
                  out_valid   <= 0;
                  iter_stop   <= 1;    
               end
            else 
               begin
                   if(enable && (iteration != {ITER_CNT{1'b0}})) //if iteration == 0, 0-1 = 31 -> mul 31 -> false
                      begin
                           iter_stop <= 0;
                           iter_reg <= iteration;
                           out_data <= 0;             
                           if(count + 1 == iter_reg) 
                                begin
                                    out_data <= acc;
                                    acc <= 0;
                                    out_valid <= 1;
                                    count <= 0;         
                                    iter_stop   <= 1;                
                                end                    
                           else 
                                begin
                                    acc     <= acc + $signed(in_data)*$signed(kernel_data);
                                    count   <= (!iter_stop) ? count + 1'b1 : 0;

                                end
                      end  
                   else 
                       begin
                           out_data  <= {{(ACC_WIDTH-BITWIDTH){in_data[BITWIDTH-1]}}, in_data}; //just output <- input
                           acc       <= {ACC_WIDTH{1'b0}};
                           count     <= {ITER_CNT{1'b0}};          
                       end        
               end
        end            

endmodule
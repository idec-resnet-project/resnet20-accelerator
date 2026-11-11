  
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

module mac #(
    parameter integer BITWIDTH = 16, //input data size = 16
    parameter integer ACC_WIDTH= 64,
    parameter integer ITER_CNT = 5
)(
    input wire clk, 
    input wire nrst,
    input wire enable, //en = 0 -> data bypass, en = 1 -> using mac
    input wire [ITER_CNT-1:0] iteration, //if iteration = 3 -> Y = X0W0 + X1W1 + X2W2
    
    /*
    //input in_valid, //buffer --in_vaild--> mac
    //output in_ready, //buffer <--in_ready-- mac
    //input out_ready, //mac <--out_ready-- other
    */
    
    input wire signed [BITWIDTH-1:0]    in_data,     //feature value
    input wire signed [BITWIDTH-1:0]    kernel_data, //weight value
   
    output reg                          out_valid, //mac --out_vaild--> other    
    output reg signed [ACC_WIDTH-1:0]   out_data //mac --out_data--> other
    );
   
    //mac's inner reg & wire
    wire signed [2*BITWIDTH-1:0] product; //16bit * 16bit = 32bit
    reg signed [ACC_WIDTH-1:0] acc; //accumulator
    wire signed[ACC_WIDTH-1:0] acc_next; //next_acc
    reg [ITER_CNT-1:0] count; //if count == iteration -> finish acc & get output
    
    /*
    // input ready signal
    //assign in_ready = nrst && !out_valid && (!enable || iteration != 0);
   */
   
    //product and accumulation
    
    assign  product = in_data * kernel_data;
    assign  acc_next = acc + $signed(product);
   
    always @(posedge clk or negedge nrst) begin
         if(!nrst) begin
            acc         <= {ACC_WIDTH{1'b0}};
            count       <= {ITER_CNT{1'b0}};
            out_data    <= {ACC_WIDTH{1'b0}};
            out_valid   <= 0;    
         end
         else begin
             if(enable) begin
                 if(iteration != {ITER_CNT{1'b0}}) begin //if iteration == 0, 0-1 = 31 -> mul 31 -> false            
                    if(count == iteration - 1'b1) begin
                        out_data <= acc_next;
                        out_valid <= 1;
                        acc     <= {ACC_WIDTH{1'b0}};
                        count   <= {ITER_CNT{1'b0}};
                    end
                    else begin
                        count   <= count + 1'b1;
                        acc     <= acc_next;
                    end                  
                 end
                 else begin
                     acc <= {ACC_WIDTH{1'b0}};
                     count <= {ITER_CNT{1'b0}};
                 end          
            end  
            else begin
                out_data  <= {{(64-BITWIDTH){in_data[BITWIDTH-1]}}, in_data}; //just output <- input
                acc   <= {ACC_WIDTH{1'b0}};
                count <= {ITER_CNT{1'b0}};          
            end        
         end
    end            
     
    /*always @(posedge clk or negedge nrst) begin
   
        if(!nrst) begin //reset regs
            acc         <= 64'd0;
            count       <= 5'd0;
            out_valid   <= 1'b0;
            out_data    <= 64'd0;      
        end
        else begin //non-reset
            if (out_valid && out_ready) begin //when output --> other module
                out_valid <= 1'b0; //output is empty
            end
           
            if (in_valid && in_ready) begin //when input --> mac
                if (enable) begin //when using mac
                    if (count == iteration - 1'b1) begin //when final data
                        out_data <= acc_next;
                        out_valid <=1'b1; //output is ready
                       
                        acc <= 64'd0; //acc initialization
                        count <= 5'd0; //count initialization
                    end
                    else begin
                        count <= count + 1'b1; //count + 1
                        acc <= acc_next; //keep going to acc                  
                    end                  
                end
               
                else begin //bypass
                    out_data  <= {{(64-BITWIDTH){in_data[BITWIDTH-1]}}, in_data}; //just output <- input
                    out_valid <= 1'b1; //output is ready

                    acc   <= 64'd0;
                    count <= 5'd0;
                end          
            end                    
        end      
    end*/
endmodule

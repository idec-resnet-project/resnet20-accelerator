`timescale 1ns / 1ps

module post_mac #(
    parameter integer WORD_W = 16, 
    parameter integer ACC_W  = WORD_W*2+1,
    parameter integer Q_SCALE  = 10
)(
    input   wire                     clk,
    input   wire                     rst_n,
    input   wire                     valid_in,    
    input   wire signed [ACC_W:0]    data_in,
    output  reg                      valid_out,
    output  reg  signed [WORD_W-1:0] data_out
);

    //localparam integer Q_SCALE = 10;

    localparam signed [WORD_W-1:0] INT_MAX = {1'b0, {(WORD_W-1){1'b1}}}; 
    localparam signed [WORD_W-1:0] INT_MIN = {1'b1, {(WORD_W-1){1'b0}}}; 

    localparam signed [Q_SCALE:0] M_Q = {1'b0, 1'b0, {(Q_SCALE-1){1'b1}}}; 
    localparam signed [Q_SCALE:0] P_Q = {1'b0, 1'b1, {(Q_SCALE-1){1'b0}}}; 

    reg signed [ACC_W+1:0]          data_ext;
    reg signed [Q_SCALE:0]          bias;
    reg signed [ACC_W+1-Q_SCALE:0]  shifted;
    //reg signed [WORD_W-1:0]         data_res;
    reg                             proc;   
    reg                             load;   
    //reg                             proc_done;
    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            data_ext  <= 0;
            bias      <= 0;
            shifted   <= 0;
            proc      <= 1'b0;
            load      <= 1'b0;
            data_out  <= {WORD_W{1'b0}};
            valid_out <= 1'b0;
            //proc_done <= 0;
        end
        else
        begin
            
            
            if (valid_in)
            begin
                data_ext <= {data_in[ACC_W], data_in};
                bias     <= data_in[ACC_W] ? M_Q : P_Q;
                proc <= valid_in;
            end
            
            if (proc)
            begin
                shifted <= (data_ext + bias) >>> Q_SCALE;
                load <= proc;
                proc <= 0;
            end
           
            if (load)
            begin                
                 load      <= 0;
                if (shifted > INT_MAX)
                    data_out <= INT_MAX;
                else if (shifted < INT_MIN)
                    data_out <= INT_MIN;
                else
                    data_out <= shifted[WORD_W-1:0];
                valid_out <= load;
            end
            /*
            if(proc_done)
            begin
                proc_done <= 0;
                data_out  <= data_res;
                valid_out <= proc_done;
            end
            */
             if(valid_out)
             begin
                valid_out <= 0;                
             end
        end
    end

endmodule
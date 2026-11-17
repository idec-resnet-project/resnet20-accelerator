`timescale 1ns / 1ps

module post_mac #(
    parameter integer WORD_W = 16, 
    parameter integer ACC_W  = WORD_W*2+1
)(
    input   wire                     clk,
    input   wire                     rst_n,
    input   wire                     valid_in,    
    input   wire signed [ACC_W:0]    data_in,
    output  reg                      valid_out,
    output  reg  signed [WORD_W-1:0] data_out
);

    localparam integer Q_SCALE = 8;

    localparam signed [WORD_W-1:0] INT_MAX = {1'b0, {(WORD_W-1){1'b1}}}; 
    localparam signed [WORD_W-1:0] INT_MIN = {1'b1, {(WORD_W-1){1'b0}}}; 

    localparam signed [Q_SCALE:0] M_Q = {1'b0, 1'b0, {(Q_SCALE-1){1'b1}}}; 
    localparam signed [Q_SCALE:0] P_Q = {1'b0, 1'b1, {(Q_SCALE-1){1'b0}}}; 

    //=======================================================================
    // Shift and Round Logic    
    // bias: 반올림 위한 소수비트
    // shifted: bias를 더한 후 Q_SCALE만큼 오른쪽으로 시프트
    //=======================================================================    
    
    reg     signed [ACC_W+1:0]        data_ext;// = {data_in[ACC_W-1], data_in};
    reg     signed [Q_SCALE:0]        bias;//     = data_in[ACC_W-1] ? M_Q : P_Q; 
    reg     signed [ACC_W+1-Q_SCALE:0]shifted;//  = (data_ext + bias) >>> Q_SCALE;
    reg     signed [WORD_W-1:0]       data;
    reg                               done;
    reg                               proc;
    reg                               shift_load;  
    
    always @(posedge clk or negedge rst_n)
    if(!rst_n)
    begin
        data        <= {WORD_W{1'b0}};
        done        <= 0;
        shifted     <= 0;
        data_ext    <= 0;
        bias        <= 0;
        shift_load  <= 0;
        data_out    <= {WORD_W{1'b0}};
        valid_out   <= 0; 
        proc        <= 0;
    end
    
    else
    begin        
        if(valid_in && !done) 
        begin              
            proc <= 1;   
            data_ext  <= {data_in[ACC_W], data_in};
            bias      <= data_in[ACC_W] ? M_Q : P_Q;            
        end    
        if(proc && !done)
        begin
            shifted    <= (data_ext + bias) >>> Q_SCALE;    
            shift_load <= 1; 
            if(shift_load)
            begin
                if (shifted > INT_MAX)
                    data <= INT_MAX;
                else if (shifted < INT_MIN)
                    data <= INT_MIN;
                else
                    data <= shifted[WORD_W-1:0];
                done <= 1;
            end
        end
        else if(done)
        begin
            data_out    <= data;
            valid_out   <= 1;
            proc        <= 0;            
            shifted     <= 0;
            shift_load  <= 0;
            done        <= 0;
        end
        else
            valid_out <= 0;
    end

endmodule
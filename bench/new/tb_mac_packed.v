`timescale 1ns / 1ps

module tb_mac_packed;

    // Parameters
    parameter integer BITWIDTH  = 16;
    parameter integer ACC_WIDTH = 64;
    parameter integer ITER_CNT  = 5;

    // Testbench Signals (DUT Inputs -> reg, Outputs -> wire)
    reg clk;
    reg nrst;
    reg enable;
    reg [4:0] iteration;
    reg signed [BITWIDTH-1:0] in_data;
    reg signed [BITWIDTH-1:0] kernel_data;

    wire out_valid;
    wire signed [ACC_WIDTH-1:0] out_data;

    // Clock definition (10ns = 100MHz)
    localparam CLK_PERIOD = 10;

    // Design Under Test (DUT) Instantiation
    mac_packed #(
        .BITWIDTH (BITWIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .ITER_CNT (ITER_CNT)
    ) uut (
        .clk        (clk),
        .nrst       (nrst),
        .enable     (enable),
        .iteration  (iteration),
        .in_data    (in_data),
        .kernel_data(kernel_data),
        .out_valid  (out_valid),
        .out_data   (out_data)
    );

    // Clock Generation
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Monitor Output Signal Changes
    always @(posedge clk) begin
        if (out_valid) begin
            $display("[%0t ns] [OUTPUT ASSERTED] out_valid = %b | out_data = %d (0x%h)", 
                      $time, out_valid, out_data, out_data);
        end
    end

    // Test Stimulus Sequence (Synchronized to posedge clk)
    initial begin
        // ----------------------------------------------------
        // 1. Initialize Signal States
        // ----------------------------------------------------
        nrst        = 1'b0;
        enable      = 1'b0;
        iteration   = 5'd0;
        in_data     = {BITWIDTH{1'b0}};
        kernel_data = {BITWIDTH{1'b0}};

        // ----------------------------------------------------
        // 2. Synchronous Reset Release
        // ----------------------------------------------------
        repeat (2) @(posedge clk);
        nrst <= 1'b0; // posedge clk에 비차단 할당
        nrst <= 1'b1;
        $display("[%0t ns] --- Reset De-asserted ---", $time);

        // ----------------------------------------------------
        // Test Case 1: Bypass Mode (enable = 0)
        // ----------------------------------------------------
        $display("\n[%0t ns] --- Test Case 1: Bypass Mode (enable = 0) ---", $time);
        @(posedge clk);
        enable  <= 1'b0;
        in_data <= 16'sd123;
        
        @(posedge clk);
        $display("[%0t ns] Bypass Output: expected=123, actual=%d", $time, out_data);

        in_data <= -16'sd456;
        
        @(posedge clk);
        $display("[%0t ns] Bypass Output: expected=-456, actual=%d", $time, out_data);

        // ----------------------------------------------------
        // Test Case 2: MAC Mode (iteration = 3)
        // expected result: (10 * 2) + (-5 * 4) + (7 * 3) = 21
        // ----------------------------------------------------
        $display("\n[%0t ns] --- Test Case 2: MAC Mode (iteration = 3) ---", $time);
        @(posedge clk);
        enable    <= 1'b1;
        iteration <= 5'd3;

        send_data(16'sd10, 16'sd2);  // Term 0 (posedge clk 1)
        send_data(-16'sd5, 16'sd4);  // Term 1 (posedge clk 2)
        send_data(16'sd7,  16'sd3);  // Term 2 (posedge clk 3)

        // Clear Inputs
        @(posedge clk);
        in_data     <= 16'sd0;
        kernel_data <= 16'sd0;

        repeat (4) @(posedge clk);

        // ----------------------------------------------------
        // Test Case 3: MAC Mode (iteration = 5)
        // expected result: (1*1) + (2*2) + (3*3) + (-4*4) + (5*-5) = -27
        // ----------------------------------------------------
        $display("\n[%0t ns] --- Test Case 3: MAC Mode (iteration = 5) ---", $time);
        @(posedge clk);
        enable    <= 1'b1;
        iteration <= 5'd5;

        send_data(16'sd1,  16'sd1);   // Term 0
        send_data(16'sd2,  16'sd2);   // Term 1
        send_data(16'sd3,  16'sd3);   // Term 2
        send_data(-16'sd4, 16'sd4);   // Term 3
        send_data(16'sd5, -16'sd5);   // Term 4

        @(posedge clk);
        in_data     <= 16'sd0;
        kernel_data <= 16'sd0;

        repeat (5) @(posedge clk);

        // Finish Simulation
        $display("\n[%0t ns] --- Simulation Completed ---", $time);
        $finish;
    end

    // Helper Task: Drive inputs aligned with posedge clk
    task send_data(input signed [BITWIDTH-1:0] feature, input signed [BITWIDTH-1:0] weight);
        begin
            @(posedge clk);
            in_data     <= feature;
            kernel_data <= weight;
        end
    endtask

endmodule
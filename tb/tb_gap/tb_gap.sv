`timescale 1ns/1ps

module tb_gap;
    localparam integer BITWIDTH = 16;
    localparam integer CW = 16;
    localparam integer MAX_EXPECTED = 1024;
    reg clk = 0;
    always #5 clk = ~clk;
    reg nrst = 0, enable = 1, in_enable = 0;
    reg [CW-1:0] iteration = 0;
    reg signed [BITWIDTH-1:0] in_data = 0;
    wire out_enable;
    wire signed [BITWIDTH-1:0] out_data;
    integer expected_value [0:MAX_EXPECTED-1];
    integer expected_cycle [0:MAX_EXPECTED-1];
    integer write_idx = 0, read_idx = 0, errors = 0, cycle = 0;
    integer total, v, k, n, result;

    gap #(.BITWIDTH(BITWIDTH), .BITWIDTH_GAP_ITERATION(CW)) dut (
        .clk(clk), .nrst(nrst), .enable(enable), .iteration(iteration),
        .in_enable(in_enable), .in_data(in_data),
        .out_enable(out_enable), .out_data(out_data)
    );

    // All stimulus is driven on falling edges; check after the next rising edge.
    // A completed window on rising edge C produces out_enable on edge C+1.
    task automatic expect_result(input integer value);
        begin
            if (write_idx >= MAX_EXPECTED) $fatal(1, "Scoreboard overflow");
            expected_value[write_idx] = value;
            expected_cycle[write_idx] = cycle + 2;
            write_idx = write_idx + 1;
        end
    endtask

    always @(posedge clk) begin
        cycle = cycle + 1;
        #1;
        if (nrst) begin
            if ($isunknown(out_enable)) begin
                $display("FAIL cycle %0d: out_enable X/Z", cycle);
                errors = errors + 1;
            end else if (out_enable) begin
                if (read_idx >= write_idx) begin
                    $display("FAIL cycle %0d: unexpected output %0d", cycle, out_data);
                    errors = errors + 1;
                end else begin
                    if (cycle != expected_cycle[read_idx]) begin
                        $display("FAIL output %0d: expected cycle %0d, got %0d",
                                 read_idx, expected_cycle[read_idx], cycle);
                        errors = errors + 1;
                    end
                    if ($isunknown(out_data) || $signed(out_data) !== expected_value[read_idx]) begin
                        $display("FAIL output %0d: expected %0d, got %0d",
                                 read_idx, expected_value[read_idx], $signed(out_data));
                        errors = errors + 1;
                    end else
                        $display("PASS output %0d: %0d (cycle %0d)",
                                 read_idx, $signed(out_data), cycle);
                end
                read_idx = read_idx + 1;
            end else if (read_idx < write_idx && cycle >= expected_cycle[read_idx]) begin
                $display("FAIL cycle %0d: missing output %0d", cycle, read_idx);
                errors = errors + 1;
                read_idx = read_idx + 1;
            end
        end
    end

    task automatic drive(input integer value, input bit valid);
        begin
            @(negedge clk);
            in_data = value;
            in_enable = valid;
        end
    endtask

    // All values are representable in signed 16 bits. Rounded ties away from zero.
    function automatic integer rounded_avg(input integer s, input integer count);
        integer mag;
        begin
            mag = (s < 0) ? -s : s;
            rounded_avg = (mag + count/2) / count;
            if (s < 0) rounded_avg = -rounded_avg;
        end
    endfunction

    // pattern: 0 ascending, 1 descending negative, 2 alternating extremes, 3 constant.
    task automatic run_square(input integer side, input integer pattern,
                              input bit insert_bubbles);
        integer idx, count, s, x;
        begin
            count = side*side;
            s = 0;
            @(negedge clk);
            enable = 1;
            iteration = count;
            in_enable = 0;
            for (idx = 0; idx < count; idx = idx + 1) begin
                case (pattern)
                    0: x = idx + 1;
                    1: x = -(idx + 1);
                    2: x = (idx % 2) ? -32768 : 32767;
                    default: x = 7;
                endcase
                s = s + x;
                if (insert_bubbles && idx % 3 == 1) drive(0, 0);
                // The expected output is queued before the final input edge.
                if (idx == count-1) expect_result(rounded_avg(s, count));
                drive(x, 1);
            end
            // Finish last sample on the next rising edge; clear valid on falling edge.
            drive(0, 0);
        end
    endtask

    task automatic flush_and_reset;
        begin
            @(negedge clk);
            nrst = 0;
            in_enable = 0;
            // Clear pending expected outputs (reset cancels in-flight results).
            write_idx = read_idx;
            repeat (3) @(negedge clk);
            nrst = 1;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        nrst = 1;
        run_square(2, 0, 0);
        run_square(4, 1, 1);
        run_square(6, 2, 0);
        run_square(8, 3, 1);
        run_square(10, 0, 0);

        // Consecutive 2x2 windows, no idle cycle between windows.
        @(negedge clk);
        iteration = 4;
        enable = 1;
        for (n = 0; n < 3; n = n + 1) begin
            for (k = 0; k < 4; k = k + 1) begin
                if (k == 3) expect_result(n + 1);
                drive(n + 1, 1);
            end
        end
        drive(0, 0);
        repeat (3) @(negedge clk);

        // Bypass: every valid sample must produce an output.
        enable = 0;
        iteration = 0;
        for (k = 0; k < 4; k = k + 1) begin
            expect_result(-123 + k);
            drive(-123 + k, 1);
        end
        drive(0, 0);
        repeat (3) @(negedge clk);

        // Zero iteration: no output, and partial accumulator must be cleared.
        enable = 1;
        iteration = 0;
        drive(123, 1);
        drive(0, 0);
        repeat (3) @(negedge clk);
        run_square(2, 0, 0);

        // Mid-window reset discards the unfinished accumulation.
        @(negedge clk);
        iteration = 16;
        enable = 1;
        drive(99, 1);
        drive(99, 1);
        drive(0, 0);
        flush_and_reset();
        run_square(2, 0, 0);
        repeat (5) @(negedge clk);
        if (read_idx != write_idx) begin
            $display("FAIL: expected %0d outputs, observed %0d", write_idx, read_idx);
            errors = errors + 1;
        end
        if (errors == 0) $display("[PASS] ALL GAP TESTS PASSED (%0d outputs)", read_idx);
        else $fatal(1, "[FAIL] GAP TESTS: %0d errors", errors);
        $finish;
    end
endmodule

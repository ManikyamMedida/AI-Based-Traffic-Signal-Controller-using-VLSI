`timescale 1ns/1ps

// One self-contained test unit per parameter set. The testbench source is
// never edited between configurations: only the instantiation parameters
// (COUNTER_WIDTH, TARGET) differ.
module timer_test_unit #(
    parameter int COUNTER_WIDTH = 8,
    parameter int TARGET        = 3,
    parameter int ID            = 0
) (
    input  logic clk,
    output logic finished
);
    logic                     rst;
    logic                     start;
    logic [COUNTER_WIDTH-1:0] count_target;
    logic                     done;

    generic_timer #(.COUNTER_WIDTH(COUNTER_WIDTH)) dut (
        .clk         (clk),
        .rst         (rst),
        .start       (start),
        .count_target(count_target),
        .done        (done)
    );

    localparam int RESET_TARGET = TARGET + 4;   // must fit COUNTER_WIDTH

    task automatic run_target(input int tgt);
        int i;
        begin
            count_target = COUNTER_WIDTH'(tgt);
            @(negedge clk); start = 1'b1;
            @(negedge clk); start = 1'b0;             // after start edge
            if (tgt == 0) begin
                if (done !== 1'b1)
                    $fatal(1, "[W%0d T%0d] target=0: done not asserted on start edge", COUNTER_WIDTH, tgt);
            end else begin
                if (done !== 1'b0)
                    $fatal(1, "[W%0d T%0d] done asserted too early (at start)", COUNTER_WIDTH, tgt);
                for (i = 1; i <= tgt; i = i + 1) begin
                    @(negedge clk);
                    if (i < tgt && done !== 1'b0)
                        $fatal(1, "[W%0d T%0d] done early at count %0d", COUNTER_WIDTH, tgt, i);
                    if (i == tgt && done !== 1'b1)
                        $fatal(1, "[W%0d T%0d] done not asserted at count %0d", COUNTER_WIDTH, tgt, i);
                end
            end
            @(negedge clk);
            if (done !== 1'b0)
                $fatal(1, "[W%0d T%0d] done is not a one-cycle pulse", COUNTER_WIDTH, tgt);
            repeat (3) begin
                @(negedge clk);
                if (done !== 1'b0)
                    $fatal(1, "[W%0d T%0d] spurious done after completion", COUNTER_WIDTH, tgt);
            end
        end
    endtask

    initial begin
        int j;
        finished     = 1'b0;
        rst          = 1'b1;
        start        = 1'b0;
        count_target = '0;
        repeat (3) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        run_target(TARGET);
        $display("TIMER TEST %0d PASS: COUNTER_WIDTH=%0d target=%0d", ID, COUNTER_WIDTH, TARGET);

        run_target(0);
        $display("TIMER TEST %0d PASS: COUNTER_WIDTH=%0d target=0 (zero-target)", ID, COUNTER_WIDTH);

        // back-to-back restart with a different target
        run_target(1);
        $display("TIMER TEST %0d PASS: COUNTER_WIDTH=%0d target=1", ID, COUNTER_WIDTH);

        // reset while counting: no completion, no spurious done afterwards
        count_target = COUNTER_WIDTH'(RESET_TARGET);
        @(negedge clk); start = 1'b1;
        @(negedge clk); start = 1'b0;
        repeat (2) @(negedge clk);
        rst = 1'b1;
        @(negedge clk);
        if (done !== 1'b0)
            $fatal(1, "[W%0d] reset during count: done not cleared", COUNTER_WIDTH);
        rst = 1'b0;
        for (j = 0; j < RESET_TARGET + 4; j = j + 1) begin
            @(negedge clk);
            if (done !== 1'b0)
                $fatal(1, "[W%0d] reset during count: spurious done after reset", COUNTER_WIDTH);
        end
        // timer still usable after reset
        run_target(TARGET);
        $display("TIMER TEST %0d PASS: COUNTER_WIDTH=%0d reset-while-counting", ID, COUNTER_WIDTH);

        finished = 1'b1;
    end
endmodule

module tb_generic_timer;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic f0, f1, f2;

    timer_test_unit #(.COUNTER_WIDTH(4),  .TARGET(3), .ID(1)) u_t1 (.clk(clk), .finished(f0));
    timer_test_unit #(.COUNTER_WIDTH(8),  .TARGET(5), .ID(2)) u_t2 (.clk(clk), .finished(f1));
    timer_test_unit #(.COUNTER_WIDTH(16), .TARGET(8), .ID(3)) u_t3 (.clk(clk), .finished(f2));

    initial begin
        wait (f0 && f1 && f2);
        #1;
        $display("========================================");
        $display("GENERIC TIMER TESTBENCH: ALL TESTS PASS");
        $display("========================================");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "GENERIC TIMER TESTBENCH: global timeout");
    end
endmodule

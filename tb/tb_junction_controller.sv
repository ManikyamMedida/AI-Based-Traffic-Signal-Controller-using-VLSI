`timescale 1ns/1ps

// Standalone self-checking testbench for junction_controller.
// Two instances of the SAME RTL (A: GREEN=3, B: GREEN=5).
// ns_go is tied high (no green-wave gating); the grant is driven by the
// testbench so grant-withheld behaviour can be tested.
// Phase lengths, safety rules, phase order and emergency/reset behaviour are
// checked automatically by junction_monitor (tb_monitors.sv).

module tb_junction_controller;

    // A: base 3, +1/level, floor 3, cap 6   B: base 2 (<floor), +2/level, floor 4, cap 9
    localparam int A_GREEN = 3, A_EXT = 1, A_MING = 3, A_MAXG = 6;
    localparam int B_GREEN = 2, B_EXT = 2, B_MING = 4, B_MAXG = 9;
    localparam int YELLOW  = 2;
    localparam int RED     = 2;
    localparam int PED     = 3;
    localparam int TIMEOUT = 2000;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic emergency_override = 1'b0;
    logic ns_go_tie          = 1'b1;

    logic ped_req_A = 1'b0, ped_grant_A = 1'b0;
    logic ped_req_B = 1'b0, ped_grant_B = 1'b0;

    logic ped_pending_A, ns_green_start_A, ns_wait_A, ped_active_A;
    logic ns_red_A, ns_yellow_A, ns_green_A, ew_red_A, ew_yellow_A, ew_green_A;
    logic ped_pending_B, ns_green_start_B, ns_wait_B, ped_active_B;
    logic ns_red_B, ns_yellow_B, ns_green_B, ew_red_B, ew_yellow_B, ew_green_B;

    int ped_cnt_A, nsg_cnt_A, ped_cnt_B, nsg_cnt_B;
    int lastg_A, runs_A, lastg_B, runs_B;
    logic [2:0] dens_A = 3'd0, dens_B = 3'd0;

    junction_controller #(
        .COUNTER_WIDTH(8), .GREEN_TIME(A_GREEN), .GREEN_EXT_STEP(A_EXT),
        .MIN_GREEN_TIME(A_MING), .MAX_GREEN_TIME(A_MAXG), .YELLOW_TIME(YELLOW),
        .RED_TIME(RED), .PED_TIME(PED)
    ) dut_A (
        .clk(clk), .rst(rst), .emergency_override(emergency_override),
        .ped_req(ped_req_A), .ped_grant(ped_grant_A), .traffic_density(dens_A), .ns_go(ns_go_tie),
        .ped_req_pending(ped_pending_A), .ns_green_start(ns_green_start_A),
        .ns_wait(ns_wait_A), .ped_active(ped_active_A),
        .ns_red(ns_red_A), .ns_yellow(ns_yellow_A), .ns_green(ns_green_A),
        .ew_red(ew_red_A), .ew_yellow(ew_yellow_A), .ew_green(ew_green_A)
    );

    junction_controller #(
        .COUNTER_WIDTH(8), .GREEN_TIME(B_GREEN), .GREEN_EXT_STEP(B_EXT),
        .MIN_GREEN_TIME(B_MING), .MAX_GREEN_TIME(B_MAXG), .YELLOW_TIME(YELLOW),
        .RED_TIME(RED), .PED_TIME(PED)
    ) dut_B (
        .clk(clk), .rst(rst), .emergency_override(emergency_override),
        .ped_req(ped_req_B), .ped_grant(ped_grant_B), .traffic_density(dens_B), .ns_go(ns_go_tie),
        .ped_req_pending(ped_pending_B), .ns_green_start(ns_green_start_B),
        .ns_wait(ns_wait_B), .ped_active(ped_active_B),
        .ns_red(ns_red_B), .ns_yellow(ns_yellow_B), .ns_green(ns_green_B),
        .ew_red(ew_red_B), .ew_yellow(ew_yellow_B), .ew_green(ew_green_B)
    );

    junction_monitor #(.GREEN_TIME(A_GREEN), .GREEN_EXT_STEP(A_EXT), .MIN_GREEN_TIME(A_MING), .MAX_GREEN_TIME(A_MAXG),
                       .YELLOW_TIME(YELLOW), .PED_TIME(PED), .OWNER("A")) mon_A (
        .clk(clk), .rst(rst), .emergency_override(emergency_override),
        .ns_red(ns_red_A), .ns_yellow(ns_yellow_A), .ns_green(ns_green_A),
        .ew_red(ew_red_A), .ew_yellow(ew_yellow_A), .ew_green(ew_green_A),
        .ped_active(ped_active_A), .traffic_density(dens_A), .ped_count(ped_cnt_A), .ns_green_count(nsg_cnt_A),
        .last_green_len(lastg_A), .green_runs(runs_A)
    );

    junction_monitor #(.GREEN_TIME(B_GREEN), .GREEN_EXT_STEP(B_EXT), .MIN_GREEN_TIME(B_MING), .MAX_GREEN_TIME(B_MAXG),
                       .YELLOW_TIME(YELLOW), .PED_TIME(PED), .OWNER("B")) mon_B (
        .clk(clk), .rst(rst), .emergency_override(emergency_override),
        .ns_red(ns_red_B), .ns_yellow(ns_yellow_B), .ns_green(ns_green_B),
        .ew_red(ew_red_B), .ew_yellow(ew_yellow_B), .ew_green(ew_green_B),
        .ped_active(ped_active_B), .traffic_density(dens_B), .ped_count(ped_cnt_B), .ns_green_count(nsg_cnt_B),
        .last_green_len(lastg_B), .green_runs(runs_B)
    );

    // ------------------------------------------------------------
    task automatic wait_nsg_A(input int target);
        int t;
        begin
            t = 0;
            while (nsg_cnt_A < target) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for A NS green #%0d", target);
            end
        end
    endtask

    task automatic wait_nsg_B(input int target);
        int t;
        begin
            t = 0;
            while (nsg_cnt_B < target) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for B NS green #%0d", target);
            end
        end
    endtask

    task automatic wait_ped_A(input int target);
        int t;
        begin
            t = 0;
            while (ped_cnt_A < target) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for A pedestrian phase #%0d", target);
            end
        end
    endtask

    task automatic wait_ns_yellow_A();
        int t;
        begin
            t = 0;
            while (ns_yellow_A !== 1'b1) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for A NS yellow");
            end
        end
    endtask

    task automatic pulse_req_A();
        begin
            @(negedge clk); ped_req_A = 1'b1;
            @(negedge clk); ped_req_A = 1'b0;
        end
    endtask

    task automatic pulse_req_B();
        begin
            @(negedge clk); ped_req_B = 1'b1;
            @(negedge clk); ped_req_B = 1'b0;
        end
    endtask

    task automatic emergency(input int hold);
        begin
            @(negedge clk); emergency_override = 1'b1;
            repeat (hold) @(negedge clk);
            emergency_override = 1'b0;
        end
    endtask

    task automatic wait_runs_A(input int target);
        int t;
        begin
            t = 0;
            while (runs_A < target) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for A green run #%0d", target);
            end
        end
    endtask

    task automatic wait_runs_B(input int target);
        int t;
        begin
            t = 0;
            while (runs_B < target) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for B green run #%0d", target);
            end
        end
    endtask

    // Independent expectation of the adaptive green length
    function automatic int exp_green(input int base, input int ext,
                                     input int mn, input int mx, input int d);
        int t;
        begin
            t = base + d * ext;
            if (t < mn) t = mn;
            if (t > mx) t = mx;
            exp_green = t;
        end
    endfunction

    // ------------------------------------------------------------
    int a0, b0, k;
    int d, ra, rb, expA, expB, prevA, prevB;

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;

        // T01-T04 + parameterization: 3 full cycles, lengths/order checked by monitors
        wait_nsg_A(3);
        wait_nsg_B(3);
        $display("PASS: NORMAL FSM SEQUENCE + PARAMETERIZATION (density 0: A green=%0d, B green=%0d)", lastg_A, lastg_B);

        // Task 4: minimum-green floor (B base 2 < floor 4)
        if (lastg_B != B_MING) $fatal(1, "MIN GREEN: B green=%0d at density 0, expected floor %0d", lastg_B, B_MING);
        $display("PASS: MIN-GREEN FLOOR ENFORCED (B base %0d -> %0d)", B_GREEN, lastg_B);

        // Task 4: density sweep 0..7 (every value), cap and monotonic checks
        prevA = 0; prevB = 0;
        for (d = 0; d < 8; d = d + 1) begin
            @(negedge clk); dens_A = d[2:0]; dens_B = d[2:0];
            ra = runs_A; rb = runs_B;
            wait_runs_A(ra + 2);
            wait_runs_B(rb + 2);
            expA = exp_green(A_GREEN, A_EXT, A_MING, A_MAXG, d);
            expB = exp_green(B_GREEN, B_EXT, B_MING, B_MAXG, d);
            if (lastg_A != expA) $fatal(1, "DENSITY %0d: A green=%0d expected %0d", d, lastg_A, expA);
            if (lastg_B != expB) $fatal(1, "DENSITY %0d: B green=%0d expected %0d", d, lastg_B, expB);
            if (lastg_A > A_MAXG || lastg_B > B_MAXG) $fatal(1, "DENSITY %0d: MAX green exceeded", d);
            if (lastg_A < A_MING || lastg_B < B_MING) $fatal(1, "DENSITY %0d: below MIN green", d);
            if (lastg_A < prevA || lastg_B < prevB)   $fatal(1, "DENSITY %0d: green decreased as density rose", d);
            $display("  density=%0d : A green=%0d%s  B green=%0d%s", d,
                     lastg_A, (lastg_A == A_MAXG) ? " (cap)" : "",
                     lastg_B, (lastg_B == B_MAXG) ? " (cap)" : "");
            prevA = lastg_A; prevB = lastg_B;
        end
        $display("PASS: DENSITY SWEEP 0..7 (green rises with density, saturates at MAX)");

        // Task 4: density change during a green phase is ignored (sampled at green start)
        @(negedge clk); dens_A = 3'd0; dens_B = 3'd0;
        wait_runs_A(runs_A + 2);
        wait_nsg_A(nsg_cnt_A + 1);
        @(negedge clk); dens_A = 3'd7;           // mid-green change: monitor expects old length
        wait_runs_A(runs_A + 2);
        $display("PASS: DENSITY CHANGE DURING GREEN IGNORED UNTIL NEXT GREEN");

        // constrained-random density (changes every cycle); monitors check sample-at-start semantics
        for (k = 0; k < 400; k = k + 1) begin
            @(negedge clk);
            dens_A = $urandom_range(7, 0);
            dens_B = $urandom_range(7, 0);
        end
        @(negedge clk); dens_A = 3'd0; dens_B = 3'd0;
        wait_runs_A(runs_A + 2);
        $display("PASS: RANDOM DENSITY (400 cycles)");

        // T11: request during yellow is retained while grant is withheld,
        //      then serviced exactly once.
        wait_ns_yellow_A();
        pulse_req_A();
        repeat (3) @(posedge clk);
        if (ped_pending_A !== 1'b1) $fatal(1, "PED: request not latched");
        a0 = ped_cnt_A;
        repeat (4 * (A_GREEN + YELLOW + RED)) @(posedge clk);
        if (ped_cnt_A != a0)         $fatal(1, "PED: serviced without grant");
        if (ped_pending_A !== 1'b1)  $fatal(1, "PED: pending request lost");
        @(negedge clk); ped_grant_A = 1'b1;
        wait_ped_A(a0 + 1);
        @(negedge clk); ped_grant_A = 1'b0;
        repeat (6 * (A_GREEN + YELLOW + RED + PED)) @(posedge clk);
        if (ped_cnt_A != a0 + 1)     $fatal(1, "PED: request serviced more than once");
        if (ped_pending_A !== 1'b0)  $fatal(1, "PED: pending not cleared after service");
        $display("PASS: PEDESTRIAN DURING YELLOW RETAINED AND SERVICED ONCE (PED=%0d cycles)", PED);

        // Emergency sweep over every phase of A (and B, which drifts relative to A)
        for (k = 0; k < 20; k = k + 1) begin
            wait_nsg_A(nsg_cnt_A + 1);
            repeat (k) @(negedge clk);
            emergency(3);
        end
        wait_nsg_A(nsg_cnt_A + 1);
        wait_nsg_B(nsg_cnt_B + 1);
        $display("PASS: EMERGENCY SWEEP (All-Red <= 1 clock after assertion, safe NS restart)");

        // Emergency during pedestrian phase (A then B)
        @(negedge clk); ped_grant_A = 1'b1;
        a0 = ped_cnt_A;
        pulse_req_A();
        wait_ped_A(a0 + 1);
        emergency(5);
        @(negedge clk); ped_grant_A = 1'b0;
        wait_nsg_A(nsg_cnt_A + 1);

        @(negedge clk); ped_grant_B = 1'b1;
        b0 = ped_cnt_B;
        pulse_req_B();
        begin : wait_b_ped
            int t;
            t = 0;
            while (ped_cnt_B <= b0) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for B pedestrian phase");
            end
        end
        emergency(5);
        @(negedge clk); ped_grant_B = 1'b0;
        wait_nsg_B(nsg_cnt_B + 1);
        $display("PASS: EMERGENCY DURING PEDESTRIAN PHASE");

        // Back-to-back assert/deassert with no idle cycle
        for (k = 0; k < 12; k = k + 1) begin
            @(negedge clk); emergency_override = 1'b1;
            @(negedge clk); emergency_override = 1'b0;
        end
        wait_nsg_A(nsg_cnt_A + 1);
        wait_nsg_B(nsg_cnt_B + 1);
        $display("PASS: REPEATED EMERGENCY TOGGLE (no delay between operations)");

        // Reset asserted during active operation
        repeat (7) @(negedge clk);
        rst = 1'b1;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        wait_nsg_A(nsg_cnt_A + 1);
        wait_nsg_B(nsg_cnt_B + 1);
        $display("PASS: RESET DURING OPERATION");

        $display("============================================");
        $display("JUNCTION CONTROLLER TESTBENCH: ALL PASS");
        $display("============================================");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "JUNCTION CONTROLLER TESTBENCH: global timeout");
    end

endmodule

`timescale 1ns/1ps

// Task 3 integration testbench for amtgc_top (self-checking).
//   * both junctions run simultaneously (different parameters)
//   * green-wave offset is MEASURED on every B NS-green start (3..5 cycles)
//   * repeated simultaneous pedestrian requests: grant order must alternate,
//     nobody starves (FAIR_ROUNDS rounds x 2 requests)
//   * emergency during NS green, EW green and pedestrian phases; held; release
//   * repeated emergency toggle, reset during operation
// Per-junction safety/phase checks come from junction_monitor.

module tb_amtgc_top;

    localparam int A_GREEN = 4, A_EXT = 2, A_MING = 3, A_MAXG = 12, A_YELLOW = 2, A_RED = 2, A_PED = 3;
    localparam int B_GREEN = 3, B_EXT = 1, B_MING = 3, B_MAXG = 8,  B_YELLOW = 2, B_RED = 3, B_PED = 2;
    localparam int RAND_CYCLES = 4000;
    localparam int WAVE_OFFSET = 4;
    localparam int WAVE_MIN    = 3;
    localparam int WAVE_MAX    = 5;
    localparam int FAIR_ROUNDS = 60;       // 60 rounds x 2 requests = 120 requests
    localparam int TIMEOUT     = 3000;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic emergency_override = 1'b0;
    logic ped_req_A = 1'b0, ped_req_B = 1'b0;
    logic [2:0] dens_A = 3'd0, dens_B = 3'd0;

    logic a_ns_red, a_ns_yellow, a_ns_green, a_ew_red, a_ew_yellow, a_ew_green;
    logic b_ns_red, b_ns_yellow, b_ns_green, b_ew_red, b_ew_yellow, b_ew_green;
    logic ped_grant_A, ped_grant_B, ped_active_A, ped_active_B;
    logic ped_pending_A, ped_pending_B;
    logic a_ns_green_start, b_ns_green_start, wave_release;

    int a_ped_cnt, a_nsg_cnt, b_ped_cnt, b_nsg_cnt;
    int a_last, a_runs, b_last, b_runs;

    amtgc_top #(
        .COUNTER_WIDTH(8),
        .A_GREEN_TIME(A_GREEN), .A_GREEN_EXT_STEP(A_EXT), .A_MIN_GREEN_TIME(A_MING), .A_MAX_GREEN_TIME(A_MAXG),
        .A_YELLOW_TIME(A_YELLOW), .A_RED_TIME(A_RED), .A_PED_TIME(A_PED),
        .B_GREEN_TIME(B_GREEN), .B_GREEN_EXT_STEP(B_EXT), .B_MIN_GREEN_TIME(B_MING), .B_MAX_GREEN_TIME(B_MAXG),
        .B_YELLOW_TIME(B_YELLOW), .B_RED_TIME(B_RED), .B_PED_TIME(B_PED),
        .WAVE_OFFSET(WAVE_OFFSET)
    ) dut (
        .clk(clk), .rst(rst), .emergency_override(emergency_override),
        .ped_req_A(ped_req_A), .ped_req_B(ped_req_B),
        .traffic_density_A(dens_A), .traffic_density_B(dens_B),
        .a_ns_red(a_ns_red), .a_ns_yellow(a_ns_yellow), .a_ns_green(a_ns_green),
        .a_ew_red(a_ew_red), .a_ew_yellow(a_ew_yellow), .a_ew_green(a_ew_green),
        .b_ns_red(b_ns_red), .b_ns_yellow(b_ns_yellow), .b_ns_green(b_ns_green),
        .b_ew_red(b_ew_red), .b_ew_yellow(b_ew_yellow), .b_ew_green(b_ew_green),
        .ped_grant_A(ped_grant_A), .ped_grant_B(ped_grant_B),
        .ped_active_A(ped_active_A), .ped_active_B(ped_active_B),
        .ped_pending_A(ped_pending_A), .ped_pending_B(ped_pending_B),
        .a_ns_green_start(a_ns_green_start), .b_ns_green_start(b_ns_green_start),
        .wave_release(wave_release)
    );

    junction_monitor #(.GREEN_TIME(A_GREEN), .GREEN_EXT_STEP(A_EXT), .MIN_GREEN_TIME(A_MING), .MAX_GREEN_TIME(A_MAXG),
                       .YELLOW_TIME(A_YELLOW), .PED_TIME(A_PED), .OWNER("A")) mon_a (
        .clk(clk), .rst(rst), .emergency_override(emergency_override),
        .ns_red(a_ns_red), .ns_yellow(a_ns_yellow), .ns_green(a_ns_green),
        .ew_red(a_ew_red), .ew_yellow(a_ew_yellow), .ew_green(a_ew_green),
        .ped_active(ped_active_A), .traffic_density(dens_A), .ped_count(a_ped_cnt), .ns_green_count(a_nsg_cnt),
        .last_green_len(a_last), .green_runs(a_runs)
    );

    junction_monitor #(.GREEN_TIME(B_GREEN), .GREEN_EXT_STEP(B_EXT), .MIN_GREEN_TIME(B_MING), .MAX_GREEN_TIME(B_MAXG),
                       .YELLOW_TIME(B_YELLOW), .PED_TIME(B_PED), .OWNER("B")) mon_b (
        .clk(clk), .rst(rst), .emergency_override(emergency_override),
        .ns_red(b_ns_red), .ns_yellow(b_ns_yellow), .ns_green(b_ns_green),
        .ew_red(b_ew_red), .ew_yellow(b_ew_yellow), .ew_green(b_ew_green),
        .ped_active(ped_active_B), .traffic_density(dens_B), .ped_count(b_ped_cnt), .ns_green_count(b_nsg_cnt),
        .last_green_len(b_last), .green_runs(b_runs)
    );

    // ------------------------------------------------------------
    // Green-wave and arbiter monitor
    // ------------------------------------------------------------
    int cyc = 0;
    int a_rise_cyc = 0;
    bit a_rise_valid = 1'b0;
    int wave_count = 0, wave_min = 1000, wave_max = -1;
    bit a_nsg_p = 1'b0, b_nsg_p = 1'b0, ga_p = 1'b0, gb_p = 1'b0;
    int round_first = 0;            // 0 none, 1 A, 2 B
    int off;

    always @(posedge clk) begin
        cyc = cyc + 1;

        if (a_ns_green === 1'b1 && !a_nsg_p) begin
            a_rise_cyc   = cyc;
            a_rise_valid = 1'b1;
        end

        if (b_ns_green === 1'b1 && !b_nsg_p) begin
            if (!a_rise_valid)
                $fatal(1, "GREEN-WAVE FAIL: B NS green started without a preceding A NS green");
            off = cyc - a_rise_cyc;
            if (off < WAVE_MIN || off > WAVE_MAX)
                $fatal(1, "GREEN-WAVE FAIL: offset=%0d cycles (allowed %0d..%0d)", off, WAVE_MIN, WAVE_MAX);
            wave_count = wave_count + 1;
            if (off < wave_min) wave_min = off;
            if (off > wave_max) wave_max = off;
            a_rise_valid = 1'b0;
        end

        if (ped_grant_A === 1'b1 && ped_grant_B === 1'b1)
            $fatal(1, "ARBITER FAIL: both grants asserted together");

        if (ped_grant_A === 1'b1 && !ga_p && round_first == 0) round_first = 1;
        if (ped_grant_B === 1'b1 && !gb_p && round_first == 0) round_first = 2;

        a_nsg_p = (a_ns_green === 1'b1);
        b_nsg_p = (b_ns_green === 1'b1);
        ga_p    = (ped_grant_A === 1'b1);
        gb_p    = (ped_grant_B === 1'b1);
    end

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------
    task automatic wait_wave(input int n);
        int t, target;
        begin
            t = 0;
            target = wave_count + n;
            while (wave_count < target) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for %0d green-wave measurement(s)", n);
            end
        end
    endtask

    task automatic wait_a_ns_green();
        int t;
        begin
            t = 0;
            while (a_ns_green !== 1'b1) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for A NS green");
            end
        end
    endtask

    task automatic wait_a_ew_green();
        int t;
        begin
            t = 0;
            while (a_ew_green !== 1'b1) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for A EW green");
            end
        end
    endtask

    task automatic wait_a_ns_yellow();
        int t;
        begin
            t = 0;
            while (a_ns_yellow !== 1'b1) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for A NS yellow");
            end
        end
    endtask

    task automatic wait_ped_active_A();
        int t;
        begin
            t = 0;
            while (ped_active_A !== 1'b1) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for A pedestrian phase");
            end
        end
    endtask

    task automatic wait_ped_active_B();
        int t;
        begin
            t = 0;
            while (ped_active_B !== 1'b1) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for B pedestrian phase");
            end
        end
    endtask

    task automatic wait_ped_idle();
        int t;
        begin
            t = 0;
            while (ped_grant_A || ped_grant_B || ped_active_A || ped_active_B ||
                   ped_pending_A || ped_pending_B) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for pedestrian logic to go idle");
            end
        end
    endtask

    task automatic pulse_req(input bit a, input bit b);
        begin
            @(negedge clk);
            ped_req_A = a;
            ped_req_B = b;
            @(negedge clk);
            ped_req_A = 1'b0;
            ped_req_B = 1'b0;
        end
    endtask

    task automatic emergency(input int hold);
        begin
            @(negedge clk); emergency_override = 1'b1;
            repeat (hold) @(negedge clk);
            emergency_override = 1'b0;
        end
    endtask

    // Repeated SIMULTANEOUS requests; first grant of every round must
    // alternate; every round must complete (no starvation).
    int a_first_wins, b_first_wins;

    task automatic fairness_rounds(input int n);
        int r, a0, b0, t, prev_first;
        begin
            prev_first   = 0;
            a_first_wins = 0;
            b_first_wins = 0;
            for (r = 0; r < n; r = r + 1) begin
                wait_ped_idle();
                repeat (2) @(posedge clk);
                a0 = a_ped_cnt;
                b0 = b_ped_cnt;
                round_first = 0;
                pulse_req(1'b1, 1'b1);
                t = 0;
                while (a_ped_cnt == a0 || b_ped_cnt == b0) begin
                    @(posedge clk);
                    t = t + 1;
                    if (t > TIMEOUT)
                        $fatal(1, "STARVATION: round %0d incomplete (A served=%0d, B served=%0d)",
                               r, a_ped_cnt - a0, b_ped_cnt - b0);
                end
                if (round_first == 0)
                    $fatal(1, "ARBITER: round %0d served without a grant", r);
                if (r == 0 && round_first != 1)
                    $fatal(1, "ARBITER: reset preference should be A on first contested round");
                if (r > 0 && round_first == prev_first)
                    $fatal(1, "ARBITER FAIRNESS FAIL: same junction won contested rounds %0d and %0d",
                           r - 1, r);
                if (round_first == 1) a_first_wins = a_first_wins + 1;
                else                  b_first_wins = b_first_wins + 1;
                prev_first = round_first;
            end
        end
    endtask

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------
    task automatic wait_runs_A(input int target);
        int t;
        begin
            t = 0;
            while (a_runs < target) begin
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
            while (b_runs < target) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for B green run #%0d", target);
            end
        end
    endtask

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

    int a0, b0, k;
    int d, i, ra, rb, expA, expB, prevA, prevB;
    int comboA [8] = '{0, 7, 0, 7, 3, 5, 2, 6};
    int comboB [8] = '{0, 7, 7, 0, 5, 2, 6, 1};

    initial begin
        // T01 reset at start-up (monitors check All-Red during reset)
        repeat (3) @(negedge clk);
        rst = 1'b0;

        // T02-T04 + T17: both junctions run; measure green wave
        wait_wave(5);
        $display("PASS: T17 GREEN-WAVE %0d measurements, offset min=%0d max=%0d (target %0d, window %0d..%0d)",
                 wave_count, wave_min, wave_max, WAVE_OFFSET, WAVE_MIN, WAVE_MAX);

        // T07 / T08: single requests
        a0 = a_ped_cnt;
        pulse_req(1'b1, 1'b0);
        begin : wait_a
            int t;
            t = 0;
            while (a_ped_cnt <= a0) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "T07: A request never serviced");
            end
        end
        b0 = b_ped_cnt;
        pulse_req(1'b0, 1'b1);
        begin : wait_b
            int t;
            t = 0;
            while (b_ped_cnt <= b0) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "T08: B request never serviced");
            end
        end
        $display("PASS: T07/T08 single pedestrian requests serviced");

        // T09 / T10: >100 simultaneous requests, round-robin fairness
        wait_ped_idle();
        fairness_rounds(FAIR_ROUNDS);
        $display("PASS: T09/T10 FAIRNESS %0d simultaneous rounds (%0d requests): A first %0d, B first %0d",
                 FAIR_ROUNDS, 2 * FAIR_ROUNDS, a_first_wins, b_first_wins);

        // T11: request during yellow retained and serviced once
        wait_ped_idle();
        wait_a_ns_yellow();
        a0 = a_ped_cnt;
        pulse_req(1'b1, 1'b0);
        begin : wait_y
            int t;
            t = 0;
            while (a_ped_cnt <= a0) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "T11: request during yellow was lost");
            end
        end
        repeat (200) @(posedge clk);
        if (a_ped_cnt != a0 + 1) $fatal(1, "T11: request during yellow serviced %0d times", a_ped_cnt - a0);
        $display("PASS: T11 pedestrian request during yellow serviced exactly once");

        // T12: emergency during NS green (held 10 cycles = T15), then release (T16)
        wait_a_ns_green();
        emergency(10);
        wait_wave(1);
        $display("PASS: T12/T15/T16 emergency during A NS green, held, released, re-synchronised");

        // T13: emergency during EW green
        wait_a_ew_green();
        emergency(4);
        wait_wave(1);
        $display("PASS: T13 emergency during A EW green");

        // T14: emergency during pedestrian phase (A and B)
        wait_ped_idle();
        pulse_req(1'b1, 1'b0);
        wait_ped_active_A();
        emergency(5);
        wait_wave(1);

        wait_ped_idle();
        pulse_req(1'b0, 1'b1);
        wait_ped_active_B();
        emergency(5);
        wait_wave(1);
        $display("PASS: T14 emergency during pedestrian phase (A and B)");

        // Emergency sweep through all phases of A
        for (k = 0; k < 24; k = k + 1) begin
            wait_a_ns_green();
            repeat (k) @(negedge clk);
            emergency(2);
            wait_wave(1);
        end
        $display("PASS: emergency sweep across all phases (24 offsets)");

        // Repeated assert/deassert with no idle cycle
        for (k = 0; k < 12; k = k + 1) begin
            @(negedge clk); emergency_override = 1'b1;
            @(negedge clk); emergency_override = 1'b0;
        end
        wait_wave(1);
        $display("PASS: repeated emergency toggle with no delay");

        // Reset during active operation
        wait_a_ns_green();
        repeat (3) @(negedge clk);
        rst = 1'b1;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        wait_wave(2);
        $display("PASS: reset during operation, system restarts with green wave intact");

        // ================= Task 4: adaptive timing =================
        // Density sweep (both junctions), cap + monotonic checks
        prevA = 0; prevB = 0;
        for (d = 0; d < 8; d = d + 1) begin
            @(negedge clk); dens_A = d[2:0]; dens_B = d[2:0];
            ra = a_runs; rb = b_runs;
            wait_runs_A(ra + 2);
            wait_runs_B(rb + 2);
            expA = exp_green(A_GREEN, A_EXT, A_MING, A_MAXG, d);
            expB = exp_green(B_GREEN, B_EXT, B_MING, B_MAXG, d);
            if (a_last != expA) $fatal(1, "DENSITY %0d: A green=%0d expected %0d", d, a_last, expA);
            if (b_last != expB) $fatal(1, "DENSITY %0d: B green=%0d expected %0d", d, b_last, expB);
            if (a_last > A_MAXG || b_last > B_MAXG) $fatal(1, "DENSITY %0d: MAX green exceeded", d);
            if (a_last < A_MING || b_last < B_MING) $fatal(1, "DENSITY %0d: below MIN green", d);
            if (a_last < prevA || b_last < prevB)   $fatal(1, "DENSITY %0d: green decreased as density rose", d);
            $display("  density=%0d : A green=%0d%s  B green=%0d%s", d,
                     a_last, (a_last == A_MAXG) ? " (cap)" : "",
                     b_last, (b_last == B_MAXG) ? " (cap)" : "");
            prevA = a_last; prevB = b_last;
        end
        $display("PASS: T18/T19/T20 DENSITY SWEEP 0..7 (min respected, rises, saturates at MAX)");

        // Both junctions at maximum density: nobody starves, min/max respected
        @(negedge clk); dens_A = 3'd7; dens_B = 3'd7;
        ra = a_runs; rb = b_runs;
        wait_wave(4);
        if (a_runs - ra < 4 || b_runs - rb < 4)
            $fatal(1, "MAX DENSITY: a direction was starved (A runs=%0d, B runs=%0d)", a_runs - ra, b_runs - rb);
        if (a_last != A_MAXG || b_last != B_MAXG)
            $fatal(1, "MAX DENSITY: green lengths A=%0d B=%0d, expected %0d / %0d", a_last, b_last, A_MAXG, B_MAXG);
        $display("PASS: BOTH JUNCTIONS AT MAX DENSITY (A green=%0d, B green=%0d, NS and EW both served)", a_last, b_last);

        // Density changed mid-green is ignored (monitor expects start-sampled length)
        @(negedge clk); dens_A = 3'd0; dens_B = 3'd0;
        wait_runs_A(a_runs + 2);
        wait_a_ns_green();
        @(negedge clk); dens_A = 3'd7; dens_B = 3'd7;
        wait_wave(2);
        $display("PASS: DENSITY CHANGE DURING GREEN IGNORED UNTIL NEXT GREEN");

        // Green wave under 8 different density combinations
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk); dens_A = comboA[i]; dens_B = comboB[i];
            wait_wave(3);
        end
        $display("PASS: GREEN-WAVE under 8 density combinations (offset min=%0d max=%0d)", wave_min, wave_max);

        // Constrained-random density + pedestrian requests
        for (i = 0; i < RAND_CYCLES; i = i + 1) begin
            @(negedge clk);
            dens_A    = $urandom_range(7, 0);
            dens_B    = $urandom_range(7, 0);
            ped_req_A = ($urandom_range(19, 0) == 0);
            ped_req_B = ($urandom_range(19, 0) == 0);
        end
        @(negedge clk); ped_req_A = 1'b0; ped_req_B = 1'b0; dens_A = 3'd0; dens_B = 3'd0;
        wait_wave(2);
        $display("PASS: CONSTRAINED-RANDOM DENSITY + PEDESTRIAN (%0d cycles)", RAND_CYCLES);

        $display("SUMMARY: green-wave measurements=%0d (offset %0d..%0d), A ped=%0d, B ped=%0d",
                 wave_count, wave_min, wave_max, a_ped_cnt, b_ped_cnt);
        $display("============================================");
        $display("AMTGC TOP INTEGRATION TESTBENCH: ALL PASS");
        $display("============================================");
        $finish;
    end

    initial begin
        #20000000;
        $fatal(1, "AMTGC TOP TESTBENCH: global timeout");
    end

endmodule
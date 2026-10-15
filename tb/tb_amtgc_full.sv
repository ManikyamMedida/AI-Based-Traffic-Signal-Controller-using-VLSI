`timescale 1ns/1ps

// Task 5 - unified, self-checking verification environment for the whole AMTGC.
// Superset of the Task 3/4 integration tests plus: timer scenarios (T05/T06),
// emergency in EVERY phase of BOTH junctions (coverage bins), pedestrian
// starvation watchdog, constrained-random run with random emergency/reset,
// and a final coverage statement against the Task 1 plan (T01..T20).
//
// RANDOM RUN: RAND_CYCLES = 20000 clock cycles. Justification: the longest
// system cycle (both junctions at cap density plus pedestrian phases and
// green-wave waiting) is < 150 cycles, so 20000 cycles = >130 complete system
// cycles; density changes every cycle (64 A/B density pairs seen many times),
// pedestrian requests ~1/20 per cycle per junction, emergency starts ~1/150
// cycles (~130 events, 1..4 cycles long) and reset ~1/3000 cycles.
//
// Original Task 3 description:
// Task 3 integration testbench for amtgc_top (self-checking).
//   * both junctions run simultaneously (different parameters)
//   * green-wave offset is MEASURED on every B NS-green start (3..5 cycles)
//   * repeated simultaneous pedestrian requests: grant order must alternate,
//     nobody starves (FAIR_ROUNDS rounds x 2 requests)
//   * emergency during NS green, EW green and pedestrian phases; held; release
//   * repeated emergency toggle, reset during operation
// Per-junction safety/phase checks come from junction_monitor.

module tb_amtgc_full;

    localparam int A_GREEN = 4, A_EXT = 2, A_MING = 3, A_MAXG = 12, A_YELLOW = 2, A_RED = 2, A_PED = 3;
    // B base (2) is deliberately BELOW its floor (3) so the minimum-green clamp is exercised in the system bench
    localparam int B_GREEN = 2, B_EXT = 1, B_MING = 3, B_MAXG = 8,  B_YELLOW = 2, B_RED = 3, B_PED = 2;
    localparam int RAND_CYCLES = 20000;
    localparam int PED_MAX_WAIT = 1500;   // starvation watchdog (cycles)
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

    // ---- coverage bookkeeping ----
    int cov [0:40];
    int emg_cov_a [0:5];
    int emg_cov_b [0:5];
    int pend_age_A = 0, pend_age_B = 0;
    bit emg_tb_p = 1'b0;
    int ph, emg_left, rst_left;

    // phase code of a junction: 0 all-red/wait, 1 NS G, 2 NS Y, 3 EW G, 4 EW Y, 5 PED
    function automatic int cur_phase(input int who);
        if (who == 0)
            cur_phase = (ped_active_A === 1'b1) ? 5 : (a_ns_green === 1'b1) ? 1 :
                        (a_ns_yellow === 1'b1) ? 2 : (a_ew_green === 1'b1) ? 3 :
                        (a_ew_yellow === 1'b1) ? 4 : 0;
        else
            cur_phase = (ped_active_B === 1'b1) ? 5 : (b_ns_green === 1'b1) ? 1 :
                        (b_ns_yellow === 1'b1) ? 2 : (b_ew_green === 1'b1) ? 3 :
                        (b_ew_yellow === 1'b1) ? 4 : 0;
    endfunction

    // record the phase of both junctions each time an emergency is first sampled
    always @(posedge clk) begin
        if (emergency_override === 1'b1 && !emg_tb_p) begin
            emg_cov_a[cur_phase(0)] = 1;
            emg_cov_b[cur_phase(1)] = 1;
        end
        emg_tb_p = (emergency_override === 1'b1);
    end

    // pedestrian starvation watchdog (age resets during emergency/reset)
    always @(posedge clk) begin
        if (ped_pending_A === 1'b1 && emergency_override !== 1'b1 && rst !== 1'b1) pend_age_A = pend_age_A + 1;
        else pend_age_A = 0;
        if (ped_pending_B === 1'b1 && emergency_override !== 1'b1 && rst !== 1'b1) pend_age_B = pend_age_B + 1;
        else pend_age_B = 0;
        if (pend_age_A > PED_MAX_WAIT) $fatal(1, "STARVATION: junction A request pending > %0d cycles", PED_MAX_WAIT);
        if (pend_age_B > PED_MAX_WAIT) $fatal(1, "STARVATION: junction B request pending > %0d cycles", PED_MAX_WAIT);
    end

    task automatic emerg_in_phase(input int who, input int phs);
        int t;
        begin
            if (phs == 5) begin
                wait_ped_idle();
                if (who == 0) pulse_req(1'b1, 1'b0); else pulse_req(1'b0, 1'b1);
            end
            t = 0;
            while (cur_phase(who) != phs) begin
                @(posedge clk);
                t = t + 1;
                if (t > TIMEOUT) $fatal(1, "TIMEOUT waiting for junction %0d phase %0d", who, phs);
            end
            emergency(2);
            wait_wave(1);
        end
    endtask

    // prints the simulation time at which each test finished (helps locate
    // the waveform window for screenshots: the test ran just BEFORE this time)
    task automatic stamp();
        $display("[sim time %0t]", $time);
    endtask

    task automatic show(input string id, input string desc, input int hit);
        $display("  %-5s %-64s %s", id, desc, hit ? "COVERED" : "NOT COVERED");
    endtask

    // ---- timer scenarios inside the unified bench (T05, T06) ----
    logic tf0, tf1, tf2;
    timer_test_unit #(.COUNTER_WIDTH(4),  .TARGET(3), .ID(1)) u_timer_t1 (.clk(clk), .finished(tf0));
    timer_test_unit #(.COUNTER_WIDTH(8),  .TARGET(5), .ID(2)) u_timer_t2 (.clk(clk), .finished(tf1));
    timer_test_unit #(.COUNTER_WIDTH(16), .TARGET(8), .ID(3)) u_timer_t3 (.clk(clk), .finished(tf2));

    int a0, b0, k;
    int d, i, ra, rb, expA, expB, prevA, prevB;
    int comboA [8] = '{0, 7, 0, 7, 3, 5, 2, 6};
    int comboB [8] = '{0, 7, 7, 0, 5, 2, 6, 1};

    initial begin
        $timeformat(-9, 0, " ns", 0);
        // T01 reset at start-up (monitors check All-Red during reset)
        repeat (3) @(negedge clk);
        rst = 1'b0;

        // T02-T04 + T17: both junctions run; measure green wave
        wait_wave(5);
        cov[1]=1; cov[2]=1; cov[3]=1; cov[4]=1; cov[17]=1;
        stamp();
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
        cov[7]=1; cov[8]=1;
        stamp();
        $display("PASS: T07/T08 single pedestrian requests serviced");

        // T09 / T10: >100 simultaneous requests, round-robin fairness
        wait_ped_idle();
        fairness_rounds(FAIR_ROUNDS);
        cov[9]=1; cov[10]=1;
        stamp();
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
        cov[11]=1;
        stamp();
        $display("PASS: T11 pedestrian request during yellow serviced exactly once");

        // T12: emergency during NS green (held 10 cycles = T15), then release (T16)
        wait_a_ns_green();
        emergency(10);
        wait_wave(1);
        cov[12]=1; cov[15]=1; cov[16]=1;
        stamp();
        $display("PASS: T12/T15/T16 emergency during A NS green, held, released, re-synchronised");

        // T13: emergency during EW green
        wait_a_ew_green();
        emergency(4);
        wait_wave(1);
        cov[13]=1;
        stamp();
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
        cov[14]=1;
        stamp();
        $display("PASS: T14 emergency during pedestrian phase (A and B)");

        // Task 5: emergency asserted in EVERY phase of BOTH junctions
        for (ph = 0; ph < 6; ph = ph + 1) begin
            emerg_in_phase(0, ph);
            emerg_in_phase(1, ph);
        end
        stamp();
        $display("PASS: EMERGENCY DIRECTED IN EACH PHASE (all-red, NS G/Y, EW G/Y, pedestrian) for A and B");

        // Emergency sweep through all phases of A
        for (k = 0; k < 24; k = k + 1) begin
            wait_a_ns_green();
            repeat (k) @(negedge clk);
            emergency(2);
            wait_wave(1);
        end
        cov[21]=1;
        stamp();
        $display("PASS: emergency sweep across all phases (24 offsets)");

        // Repeated assert/deassert with no idle cycle
        for (k = 0; k < 12; k = k + 1) begin
            @(negedge clk); emergency_override = 1'b1;
            @(negedge clk); emergency_override = 1'b0;
        end
        wait_wave(1);
        cov[22]=1;
        stamp();
        $display("PASS: repeated emergency toggle with no delay");

        // Reset during active operation
        wait_a_ns_green();
        repeat (3) @(negedge clk);
        rst = 1'b1;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        wait_wave(2);
        cov[23]=1;
        stamp();
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
        cov[18]=1; cov[19]=1; cov[20]=1;
        stamp();
        $display("PASS: T18/T19/T20 DENSITY SWEEP 0..7 (min respected, rises, saturates at MAX)");

        // Both junctions at maximum density: nobody starves, min/max respected
        @(negedge clk); dens_A = 3'd7; dens_B = 3'd7;
        ra = a_runs; rb = b_runs;
        wait_wave(4);
        if (a_runs - ra < 4 || b_runs - rb < 4)
            $fatal(1, "MAX DENSITY: a direction was starved (A runs=%0d, B runs=%0d)", a_runs - ra, b_runs - rb);
        if (a_last != A_MAXG || b_last != B_MAXG)
            $fatal(1, "MAX DENSITY: green lengths A=%0d B=%0d, expected %0d / %0d", a_last, b_last, A_MAXG, B_MAXG);
        cov[24]=1;
        stamp();
        $display("PASS: BOTH JUNCTIONS AT MAX DENSITY (A green=%0d, B green=%0d, NS and EW both served)", a_last, b_last);

        // Density changed mid-green is ignored (monitor expects start-sampled length)
        @(negedge clk); dens_A = 3'd0; dens_B = 3'd0;
        wait_runs_A(a_runs + 2);
        wait_a_ns_green();
        @(negedge clk); dens_A = 3'd7; dens_B = 3'd7;
        wait_wave(2);
        cov[25]=1;
        stamp();
        $display("PASS: DENSITY CHANGE DURING GREEN IGNORED UNTIL NEXT GREEN");

        // Green wave under 8 different density combinations
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk); dens_A = comboA[i]; dens_B = comboB[i];
            wait_wave(3);
        end
        cov[26]=1;
        stamp();
        $display("PASS: GREEN-WAVE under 8 density combinations (offset min=%0d max=%0d)", wave_min, wave_max);

        // Constrained-random: density, pedestrian requests, emergency pulses, rare reset
        emg_left = 0; rst_left = 0;
        for (i = 0; i < RAND_CYCLES; i = i + 1) begin
            @(negedge clk);
            dens_A    = $urandom_range(7, 0);
            dens_B    = $urandom_range(7, 0);
            ped_req_A = ($urandom_range(19, 0) == 0);
            ped_req_B = ($urandom_range(19, 0) == 0);
            if (emg_left > 0) begin
                emergency_override = 1'b1;
                emg_left = emg_left - 1;
            end else begin
                emergency_override = 1'b0;
                if ($urandom_range(149, 0) == 0) emg_left = $urandom_range(4, 1);
            end
            if (rst_left > 0) begin
                rst = 1'b1;
                rst_left = rst_left - 1;
            end else begin
                rst = 1'b0;
                if ($urandom_range(2999, 0) == 0) rst_left = $urandom_range(3, 1);
            end
        end
        @(negedge clk);
        ped_req_A = 1'b0; ped_req_B = 1'b0; emergency_override = 1'b0; rst = 1'b0;
        dens_A = 3'd0; dens_B = 3'd0;
        wait_wave(3);
        cov[27] = 1;
        stamp();
        $display("PASS: CONSTRAINED-RANDOM (%0d cycles: density, pedestrian, emergency, reset)", RAND_CYCLES);

        // timer scenarios (T05 zero target, T06 reset while counting)
        wait (tf0 && tf1 && tf2);
        cov[5] = 1; cov[6] = 1;

        // emergency-phase coverage bins
        cov[28] = 1;
        for (ph = 0; ph < 6; ph = ph + 1) begin
            if (!emg_cov_a[ph]) begin cov[28] = 0; $display("COVERAGE HOLE: emergency never hit junction A phase %0d", ph); end
            if (!emg_cov_b[ph]) begin cov[28] = 0; $display("COVERAGE HOLE: emergency never hit junction B phase %0d", ph); end
        end
        if (!cov[28]) $fatal(1, "emergency phase coverage incomplete");
        cov[29] = 1;   // starvation watchdog never fired (it $fatals otherwise)

        $display("");
        $display("================= COVERAGE vs TASK 1 PLAN =================");
        show("T01", "Reset at startup (All-Red during reset, NS restart)",        cov[1]);
        show("T02", "Normal NS sequence NS G -> Y -> All-Red",                    cov[2]);
        show("T03", "Normal EW sequence All-Red -> EW G -> Y -> All-Red",         cov[3]);
        show("T04", "All-Red safety gap (no conflicting greens back-to-back)",    cov[4]);
        show("T05", "Timer target = 0",                                           cov[5]);
        show("T06", "Timer reset while counting",                                 cov[6]);
        show("T07", "Pedestrian A request serviced",                              cov[7]);
        show("T08", "Pedestrian B request serviced",                              cov[8]);
        show("T09", "Simultaneous pedestrian requests (round-robin)",             cov[9]);
        show("T10", "Repeated simultaneous requests, alternate, no starvation",   cov[10]);
        show("T11", "Pedestrian request during yellow retained, serviced once",   cov[11]);
        show("T12", "Emergency during NS green",                                  cov[12]);
        show("T13", "Emergency during EW green",                                  cov[13]);
        show("T14", "Emergency during pedestrian phase",                          cov[14]);
        show("T15", "Emergency held active, both stay All-Red",                   cov[15]);
        show("T16", "Emergency release, resume from valid safe phase",            cov[16]);
        show("T17", "Green-wave offset measured (3..5 cycles)",                   cov[17]);
        show("T18", "Minimum density: green never below minimum",                 cov[18]);
        show("T19", "Maximum density: green never above maximum",                 cov[19]);
        show("T20", "Density sweep 0..7",                                         cov[20]);
        $display("  ---- additional Task 5 / corner-case tests ----");
        show("X21", "Emergency sweep over 24 phase offsets",                      cov[21]);
        show("X22", "Repeated emergency assert/deassert, no idle cycle",          cov[22]);
        show("X23", "Reset during active operation",                              cov[23]);
        show("X24", "Both junctions at max density, neither starved",             cov[24]);
        show("X25", "Density change during green ignored",                        cov[25]);
        show("X26", "Green wave under 8 density combinations",                    cov[26]);
        show("X27", "Constrained-random (density/ped/emergency/reset)",           cov[27]);
        show("X28", "Emergency hit every phase of both junctions (bins)",         cov[28]);
        show("X29", "Pedestrian starvation watchdog never fired",                 cov[29]);
        $display("===========================================================");

        $display("SUMMARY: green-wave measurements=%0d (offset %0d..%0d), A ped=%0d, B ped=%0d",
                 wave_count, wave_min, wave_max, a_ped_cnt, b_ped_cnt);
        $display("============================================");
        $display("AMTGC FULL VERIFICATION: ALL PASS");
        $display("============================================");
        $finish;
    end

    initial begin
        #100000000;
        $fatal(1, "AMTGC FULL VERIFICATION: global timeout");
    end

endmodule

`timescale 1ns/1ps

// ---------------------------------------------------------------------
// Checks that a signal stays high for exactly EXPECT consecutive cycles.
// Runs that overlap an emergency/reset (abort=1) are not checked.
// ---------------------------------------------------------------------
module run_len_checker #(
    parameter string OWNER = "J",
    parameter string TAG   = "X"
) (
    input logic clk,
    input logic sig,
    input logic abort,
    input int   expect_len      // latched on the first cycle of each run
);
    int   len     = 0;
    int   exp_l   = 0;
    bit   prev    = 1'b0;
    bit   aborted = 1'b0;

    always @(posedge clk) begin
        if (sig === 1'b1) begin
            if (!prev) exp_l = expect_len;
            len = len + 1;
            if (abort === 1'b1) aborted = 1'b1;
        end else begin
            if (prev && !aborted && (len != exp_l))
                $fatal(1, "[%s] %s duration FAIL: expected %0d cycles, observed %0d",
                       OWNER, TAG, exp_l, len);
            len     = 0;
            aborted = 1'b0;
        end
        prev = (sig === 1'b1);
    end
endmodule

// ---------------------------------------------------------------------
// Passive safety / protocol monitor for one junction.
// ---------------------------------------------------------------------
module junction_monitor #(
    parameter int    GREEN_TIME     = 1,
    parameter int    GREEN_EXT_STEP = 0,
    parameter int    MIN_GREEN_TIME = 1,
    parameter int    MAX_GREEN_TIME = 1000,
    parameter int    YELLOW_TIME    = 1,
    parameter int    PED_TIME       = 1,
    parameter int    DENSITY_WIDTH  = 3,
    parameter string OWNER          = "J"
) (
    input  logic clk,
    input  logic rst,
    input  logic emergency_override,
    input  logic ns_red,
    input  logic ns_yellow,
    input  logic ns_green,
    input  logic ew_red,
    input  logic ew_yellow,
    input  logic ew_green,
    input  logic ped_active,
    input  logic [DENSITY_WIDTH-1:0] traffic_density,
    output int   ped_count,
    output int   ns_green_count,
    output int   last_green_len,
    output int   green_runs
);

    // phase codes: 0 all-red/wait, 1 NS green, 2 NS yellow, 3 EW green,
    //              4 EW yellow, 5 pedestrian
    localparam int CODE_RED = 0, CODE_NSG = 1, CODE_NSY = 2,
                   CODE_EWG = 3, CODE_EWY = 4, CODE_PED = 5;

    wire abort_w = emergency_override | rst;

    // Scoreboard model of the adaptive green: density sampled at green start.
    function automatic int exp_green(input int d);
        int t;
        begin
            t = GREEN_TIME + d * GREEN_EXT_STEP;
            if (t < MIN_GREEN_TIME) t = MIN_GREEN_TIME;
            if (t > MAX_GREEN_TIME) t = MAX_GREEN_TIME;
            exp_green = t;
        end
    endfunction

    logic [DENSITY_WIDTH-1:0] dens_q;
    always @(posedge clk) dens_q <= traffic_density;   // value the DUT saw last edge

    int exp_green_now;
    assign exp_green_now = exp_green(int'(dens_q));

    run_len_checker #(.OWNER(OWNER), .TAG("NS_GREEN"))
        chk_nsg (.clk(clk), .sig(ns_green),   .abort(abort_w), .expect_len(exp_green_now));
    run_len_checker #(.OWNER(OWNER), .TAG("EW_GREEN"))
        chk_ewg (.clk(clk), .sig(ew_green),   .abort(abort_w), .expect_len(exp_green_now));
    run_len_checker #(.OWNER(OWNER), .TAG("NS_YELLOW"))
        chk_nsy (.clk(clk), .sig(ns_yellow),  .abort(abort_w), .expect_len(YELLOW_TIME));
    run_len_checker #(.OWNER(OWNER), .TAG("EW_YELLOW"))
        chk_ewy (.clk(clk), .sig(ew_yellow),  .abort(abort_w), .expect_len(YELLOW_TIME));
    run_len_checker #(.OWNER(OWNER), .TAG("PED_PHASE"))
        chk_ped (.clk(clk), .sig(ped_active), .abort(abort_w), .expect_len(PED_TIME));

    function automatic bit legal_step(input int p, input int n);
        case (p)
            CODE_RED: legal_step = (n == CODE_NSG) || (n == CODE_EWG) || (n == CODE_PED);
            CODE_NSG: legal_step = (n == CODE_NSY) || (n == CODE_RED);
            CODE_NSY: legal_step = (n == CODE_RED);
            CODE_EWG: legal_step = (n == CODE_EWY) || (n == CODE_RED);
            CODE_EWY: legal_step = (n == CODE_RED);
            CODE_PED: legal_step = (n == CODE_RED) || (n == CODE_NSG) || (n == CODE_EWG);
            default:  legal_step = 1'b0;
        endcase
    endfunction

    int  code, code_p, exp_dir;
    bit  started, arm, emg_p, rst_p;
    bit  ns_any_p, ew_any_p;
    int  glen;

    initial begin
        ped_count      = 0;
        ns_green_count = 0;
        last_green_len = 0;
        green_runs     = 0;
        glen           = 0;
        code_p   = 0;
        exp_dir  = 0;
        started  = 1'b0;
        arm      = 1'b1;
        emg_p    = 1'b0;
        rst_p    = 1'b0;
        ns_any_p = 1'b0;
        ew_any_p = 1'b0;
    end

    always @(posedge clk) begin
        code = (ped_active === 1'b1) ? CODE_PED :
               (ns_green   === 1'b1) ? CODE_NSG :
               (ns_yellow  === 1'b1) ? CODE_NSY :
               (ew_green   === 1'b1) ? CODE_EWG :
               (ew_yellow  === 1'b1) ? CODE_EWY : CODE_RED;

        if (started) begin
            // ---- static safety ----
            if ($countones({ns_red, ns_yellow, ns_green}) != 1)
                $fatal(1, "[%s] SAFETY: NS lights not one-hot", OWNER);
            if ($countones({ew_red, ew_yellow, ew_green}) != 1)
                $fatal(1, "[%s] SAFETY: EW lights not one-hot", OWNER);
            if ((ns_green || ns_yellow) && (ew_green || ew_yellow))
                $fatal(1, "[%s] SAFETY: NS and EW both non-red", OWNER);
            if (ped_active && !(ns_red && ew_red))
                $fatal(1, "[%s] SAFETY: pedestrian phase without both directions red", OWNER);

            // ---- no direct NS<->EW change (All-Red gap) ----
            if ((ns_green && ew_any_p) || (ew_green && ns_any_p))
                $fatal(1, "[%s] SAFETY: conflicting green without All-Red gap", OWNER);

            // ---- emergency / reset: All-Red one sample after assertion ----
            if ((emg_p || rst_p) && !(ns_red && ew_red && !ped_active))
                $fatal(1, "[%s] EMERGENCY/RESET: not All-Red one clock after assertion", OWNER);

            // ---- phase order ----
            if (emg_p || rst_p) exp_dir = 0;

            if (code != code_p) begin
                if (!legal_step(code_p, code))
                    $fatal(1, "[%s] FSM: illegal phase step %0d -> %0d", OWNER, code_p, code);
                if ((code_p == CODE_NSG || code_p == CODE_EWG) && code == CODE_RED
                    && !(emg_p || rst_p))
                    $fatal(1, "[%s] FSM: green ended without yellow and no emergency/reset", OWNER);
                if (code == CODE_NSY) exp_dir = CODE_EWG;
                if (code == CODE_EWY) exp_dir = CODE_NSG;
                if (code == CODE_PED) ped_count = ped_count + 1;
                if (code == CODE_NSG) ns_green_count = ns_green_count + 1;
            end

            if (code == CODE_NSG || code == CODE_EWG) begin
                if (exp_dir != 0 && code != exp_dir)
                    $fatal(1, "[%s] FSM: wrong green direction (expected %0d got %0d)",
                           OWNER, exp_dir, code);
                exp_dir = 0;
            end

            // ---- safe restart after emergency / reset ----
            if ((emg_p && !emergency_override) || (rst_p && !rst)) arm = 1'b1;
            if (arm && (code == CODE_NSG || code == CODE_EWG)) begin
                if (code != CODE_NSG)
                    $fatal(1, "[%s] RECOVERY: first green after emergency/reset is not NS", OWNER);
                arm = 1'b0;
            end
        end

        // completed green-run length (for density sweeps)
        if (code == CODE_NSG || code == CODE_EWG) begin
            if (code == code_p) glen = glen + 1;
            else                glen = 1;
        end else if (code_p == CODE_NSG || code_p == CODE_EWG) begin
            last_green_len = glen;
            green_runs     = green_runs + 1;
            glen           = 0;
        end

        emg_p    = emergency_override;
        rst_p    = rst;
        code_p   = code;
        ns_any_p = (ns_green === 1'b1) || (ns_yellow === 1'b1);
        ew_any_p = (ew_green === 1'b1) || (ew_yellow === 1'b1);
        started  = 1'b1;
    end

endmodule

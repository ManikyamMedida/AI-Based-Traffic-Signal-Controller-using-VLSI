`timescale 1ns/1ps

// Adaptive Multi-Junction Traffic Grid Controller - top level (Task 3).
//
// Hierarchy: amtgc_top
//              |- ped_arbiter          (shared, round-robin)
//              |- junction_controller A (-> generic_timer)
//              |- junction_controller B (-> generic_timer)
//              |- generic_timer         (green-wave offset timer)
//
// GREEN WAVE
//   A is the reference. When A starts NS_GREEN, a generic_timer counts the
//   offset and then releases B's NS_GREEN (B parks in NS_WAIT until then).
//   A in turn waits for B to be parked (b_ns_wait) before starting its next
//   NS_GREEN, so the offset is constant for any green/ped timing.
//   Measured offset = WAVE_OFFSET clock cycles between the first NS-green
//   cycle of A and the first NS-green cycle of B.
//   (generic_timer done lags by WAVE_TIMER_LATENCY cycles; compensated.)
//
// EMERGENCY
//   Broadcast to both junctions; each reaches All-Red 1 clock after the
//   override is sampled (requirement: <= 2). Pending wave releases are
//   cancelled so recovery re-synchronizes through the same gate.

module amtgc_top #(
    parameter int unsigned COUNTER_WIDTH = 8,

    parameter int unsigned DENSITY_WIDTH = 3,

    parameter int unsigned A_GREEN_TIME  = 4,
    parameter int unsigned A_GREEN_EXT_STEP = 2,
    parameter int unsigned A_MIN_GREEN_TIME = 3,
    parameter int unsigned A_MAX_GREEN_TIME = 12,
    parameter int unsigned A_YELLOW_TIME = 2,
    parameter int unsigned A_RED_TIME    = 2,
    parameter int unsigned A_PED_TIME    = 3,

    parameter int unsigned B_GREEN_TIME  = 3,
    parameter int unsigned B_GREEN_EXT_STEP = 1,
    parameter int unsigned B_MIN_GREEN_TIME = 3,
    parameter int unsigned B_MAX_GREEN_TIME = 8,
    parameter int unsigned B_YELLOW_TIME = 2,
    parameter int unsigned B_RED_TIME    = 3,
    parameter int unsigned B_PED_TIME    = 2,

    parameter int unsigned WAVE_OFFSET   = 4
) (
    input  logic clk,
    input  logic rst,
    input  logic emergency_override,

    input  logic ped_req_A,
    input  logic ped_req_B,

    input  logic [DENSITY_WIDTH-1:0] traffic_density_A,
    input  logic [DENSITY_WIDTH-1:0] traffic_density_B,

    output logic a_ns_red,
    output logic a_ns_yellow,
    output logic a_ns_green,
    output logic a_ew_red,
    output logic a_ew_yellow,
    output logic a_ew_green,

    output logic b_ns_red,
    output logic b_ns_yellow,
    output logic b_ns_green,
    output logic b_ew_red,
    output logic b_ew_yellow,
    output logic b_ew_green,

    output logic ped_grant_A,
    output logic ped_grant_B,
    output logic ped_active_A,
    output logic ped_active_B,
    output logic ped_pending_A,
    output logic ped_pending_B,

    output logic a_ns_green_start,
    output logic b_ns_green_start,
    output logic wave_release
);

    localparam int unsigned WAVE_TIMER_LATENCY = 2;
    localparam logic [COUNTER_WIDTH-1:0] WAVE_TARGET =
        COUNTER_WIDTH'(WAVE_OFFSET - WAVE_TIMER_LATENCY);

    logic a_ns_wait, b_ns_wait;
    logic wave_done;
    logic wave_active_q;

    // ---------------- shared pedestrian arbiter ----------------
    ped_arbiter u_ped_arbiter (
        .clk        (clk),
        .rst        (rst),
        .ped_req_A  (ped_pending_A),
        .ped_req_B  (ped_pending_B),
        .ped_grant_A(ped_grant_A),
        .ped_grant_B(ped_grant_B)
    );

    // ---------------- junction A (reference) ----------------
    junction_controller #(
        .COUNTER_WIDTH(COUNTER_WIDTH),
        .GREEN_TIME   (A_GREEN_TIME),
        .GREEN_EXT_STEP(A_GREEN_EXT_STEP),
        .MIN_GREEN_TIME(A_MIN_GREEN_TIME),
        .MAX_GREEN_TIME(A_MAX_GREEN_TIME),
        .DENSITY_WIDTH(DENSITY_WIDTH),
        .YELLOW_TIME  (A_YELLOW_TIME),
        .RED_TIME     (A_RED_TIME),
        .PED_TIME     (A_PED_TIME)
    ) u_junction_a (
        .clk               (clk),
        .rst               (rst),
        .emergency_override(emergency_override),
        .ped_req           (ped_req_A),
        .ped_grant         (ped_grant_A),
        .traffic_density   (traffic_density_A),
        .ns_go             (b_ns_wait),
        .ped_req_pending   (ped_pending_A),
        .ns_green_start    (a_ns_green_start),
        .ns_wait           (a_ns_wait),
        .ped_active        (ped_active_A),
        .ns_red            (a_ns_red),
        .ns_yellow         (a_ns_yellow),
        .ns_green          (a_ns_green),
        .ew_red            (a_ew_red),
        .ew_yellow         (a_ew_yellow),
        .ew_green          (a_ew_green)
    );

    // ---------------- junction B (follower) ----------------
    junction_controller #(
        .COUNTER_WIDTH(COUNTER_WIDTH),
        .GREEN_TIME   (B_GREEN_TIME),
        .GREEN_EXT_STEP(B_GREEN_EXT_STEP),
        .MIN_GREEN_TIME(B_MIN_GREEN_TIME),
        .MAX_GREEN_TIME(B_MAX_GREEN_TIME),
        .DENSITY_WIDTH(DENSITY_WIDTH),
        .YELLOW_TIME  (B_YELLOW_TIME),
        .RED_TIME     (B_RED_TIME),
        .PED_TIME     (B_PED_TIME)
    ) u_junction_b (
        .clk               (clk),
        .rst               (rst),
        .emergency_override(emergency_override),
        .ped_req           (ped_req_B),
        .ped_grant         (ped_grant_B),
        .traffic_density   (traffic_density_B),
        .ns_go             (wave_release),
        .ped_req_pending   (ped_pending_B),
        .ns_green_start    (b_ns_green_start),
        .ns_wait           (b_ns_wait),
        .ped_active        (ped_active_B),
        .ns_red            (b_ns_red),
        .ns_yellow         (b_ns_yellow),
        .ns_green          (b_ns_green),
        .ew_red            (b_ew_red),
        .ew_yellow         (b_ew_yellow),
        .ew_green          (b_ew_green)
    );

    // ---------------- green-wave offset ----------------
    generic_timer #(
        .COUNTER_WIDTH(COUNTER_WIDTH)
    ) u_wave_timer (
        .clk         (clk),
        .rst         (rst),
        .start       (a_ns_green_start),
        .count_target(WAVE_TARGET),
        .done        (wave_done)
    );

    // A release is only valid for the A start that armed it, and never
    // during an emergency.
    always_ff @(posedge clk) begin
        if (rst) begin
            wave_active_q <= 1'b0;
        end else if (emergency_override) begin
            wave_active_q <= 1'b0;
        end else if (a_ns_green_start) begin
            wave_active_q <= 1'b1;
        end else if (wave_done) begin
            wave_active_q <= 1'b0;
        end
    end

    assign wave_release = wave_done && wave_active_q && !emergency_override;

    initial begin
        if (WAVE_OFFSET < WAVE_TIMER_LATENCY)
            $fatal(1, "WAVE_OFFSET must be >= %0d", WAVE_TIMER_LATENCY);
    end

endmodule
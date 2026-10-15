`timescale 1ns/1ps

// Parameterized Moore traffic-junction controller (Tasks 2/3).
//
// Extends the training project's traffic_fsm_final (GREEN/YELLOW/RED/PEDESTRIAN)
// to a 4-way junction with an All-Red safety gap, shared-arbiter pedestrian
// handling, emergency override and a green-wave gate (ns_go / ns_wait).
//
// Timing is delegated to the standalone generic_timer (instantiated here).
// The FSM contains no counter.
//
// PHASE LENGTH CONVENTION
//   generic_timer asserts done (target + 1) cycles after the cycle in which
//   the FSM requests a start, so the controller loads (TIME - TIMER_LATENCY).
//   Every phase therefore lasts exactly TIME clock cycles.
//
// GREEN-WAVE GATE
//   Every entry into NS_GREEN is gated by ns_go. If ns_go is low when the
//   junction is ready, it parks in NS_WAIT (all red, ns_wait=1) until ns_go.
//
// ADAPTIVE GREEN (Task 4)
//   green = clamp(GREEN_TIME + traffic_density*GREEN_EXT_STEP,
//                 MIN_GREEN_TIME, MAX_GREEN_TIME)
//   traffic_density is sampled ONCE, in the cycle the green phase is
//   requested; changes during the green are ignored until the next green.
//   The computation lives here (not in generic_timer): the timer only
//   counts to the count_target it is given and stays traffic-agnostic.
//
// EMERGENCY
//   While emergency_override is high the FSM is forced to ALL_RED and the
//   phase timer is restarted every cycle. All-Red is reached one clock after
//   the override is sampled. After release a full RED_TIME All-Red interval
//   completes, then operation resumes through NS_GREEN (valid safe phase).
//   An active pedestrian phase is aborted; its request is not re-queued.

module junction_controller #(
    parameter int unsigned COUNTER_WIDTH = 8,
    parameter int unsigned GREEN_TIME    = 5,   // base green at density 0
    parameter int unsigned GREEN_EXT_STEP = 1,  // extra green cycles per density level
    parameter int unsigned MIN_GREEN_TIME = 3,  // guaranteed minimum green
    parameter int unsigned MAX_GREEN_TIME = 12, // safety cap
    parameter int unsigned DENSITY_WIDTH  = 3,
    parameter int unsigned YELLOW_TIME   = 2,
    parameter int unsigned RED_TIME      = 2,
    parameter int unsigned PED_TIME      = 3
) (
    input  logic clk,
    input  logic rst,                 // active-high synchronous
    input  logic emergency_override,

    input  logic ped_req,             // pedestrian button (rising edge = 1 request)
    input  logic ped_grant,           // from shared arbiter

    input  logic [DENSITY_WIDTH-1:0] traffic_density, // sampled at each green start
    input  logic ns_go,               // permission to start NS_GREEN

    output logic ped_req_pending,     // request to arbiter
    output logic ns_green_start,      // 1-cycle pulse, first cycle of NS_GREEN
    output logic ns_wait,             // parked, waiting for ns_go
    output logic ped_active,

    output logic ns_red,
    output logic ns_yellow,
    output logic ns_green,
    output logic ew_red,
    output logic ew_yellow,
    output logic ew_green
);

    localparam int unsigned STATE_BITS    = 3;
    localparam int unsigned TIMER_LATENCY = 1;
    localparam longint unsigned MAX_TARGET = (64'd1 << COUNTER_WIDTH) - 64'd1;

    typedef enum logic [STATE_BITS-1:0] {
        S_NS_GREEN,
        S_NS_YELLOW,
        S_ALL_RED,
        S_EW_GREEN,
        S_EW_YELLOW,
        S_PED_PHASE,
        S_NS_WAIT
    } state_t;

    state_t state_q, state_d;
    state_t ns_dest, ret_dest;

    logic ret_ew_q, ret_ew_d;           // 1: next green after All-Red is EW
    logic ped_req_q, ped_req_rise;
    logic ped_pending_q, ped_pending_d;
    logic init_done_q;

    logic                     timer_start;
    logic                     timer_done;
    logic [COUNTER_WIDTH-1:0] timer_target;

    generic_timer #(
        .COUNTER_WIDTH(COUNTER_WIDTH)
    ) u_timer (
        .clk         (clk),
        .rst         (rst),
        .start       (timer_start),
        .count_target(timer_target),
        .done        (timer_done)
    );

    // Adaptive green: base + density*step, clamped to [MIN, MAX].
    function automatic logic [COUNTER_WIDTH-1:0] green_target(
        input logic [DENSITY_WIDTH-1:0] dens
    );
        longint unsigned t;
        begin
            t = GREEN_TIME + (dens * GREEN_EXT_STEP);
            if (t < MIN_GREEN_TIME) t = MIN_GREEN_TIME;
            if (t > MAX_GREEN_TIME) t = MAX_GREEN_TIME;
            green_target = COUNTER_WIDTH'(t - TIMER_LATENCY);
        end
    endfunction

    function automatic logic [COUNTER_WIDTH-1:0] phase_target(
        input state_t                   phase,
        input logic [DENSITY_WIDTH-1:0] dens
    );
        case (phase)
            S_NS_GREEN:  phase_target = green_target(dens);
            S_NS_YELLOW: phase_target = COUNTER_WIDTH'(YELLOW_TIME - TIMER_LATENCY);
            S_ALL_RED:   phase_target = COUNTER_WIDTH'(RED_TIME    - TIMER_LATENCY);
            S_EW_GREEN:  phase_target = green_target(dens);
            S_EW_YELLOW: phase_target = COUNTER_WIDTH'(YELLOW_TIME - TIMER_LATENCY);
            S_PED_PHASE: phase_target = COUNTER_WIDTH'(PED_TIME    - TIMER_LATENCY);
            S_NS_WAIT:   phase_target = COUNTER_WIDTH'(RED_TIME    - TIMER_LATENCY);
            default:     phase_target = COUNTER_WIDTH'(RED_TIME    - TIMER_LATENCY);
        endcase
    endfunction

    // ------------------------------------------------------------------
    // Next-state logic (combinational, blocking assignments)
    // ------------------------------------------------------------------
    always_comb begin
        ped_req_rise = ped_req & ~ped_req_q;

        ns_dest  = ns_go     ? S_NS_GREEN : S_NS_WAIT;
        ret_dest = ret_ew_q  ? S_EW_GREEN : ns_dest;

        state_d  = state_q;
        ret_ew_d = ret_ew_q;

        if (emergency_override) begin
            state_d  = S_ALL_RED;
            ret_ew_d = 1'b0;
        end else begin
            case (state_q)
                S_NS_GREEN: begin
                    if (timer_done)
                        state_d = S_NS_YELLOW;
                end

                S_NS_YELLOW: begin
                    if (timer_done) begin
                        state_d  = S_ALL_RED;
                        ret_ew_d = 1'b1;
                    end
                end

                S_ALL_RED: begin
                    if (timer_done) begin
                        if (ped_pending_q && ped_grant)
                            state_d = S_PED_PHASE;
                        else
                            state_d = ret_dest;
                    end
                end

                S_EW_GREEN: begin
                    if (timer_done)
                        state_d = S_EW_YELLOW;
                end

                S_EW_YELLOW: begin
                    if (timer_done) begin
                        state_d  = S_ALL_RED;
                        ret_ew_d = 1'b0;
                    end
                end

                S_PED_PHASE: begin
                    if (timer_done)
                        state_d = ret_dest;
                end

                S_NS_WAIT: begin
                    if (ns_go)
                        state_d = S_NS_GREEN;
                end

                default: begin
                    state_d  = S_ALL_RED;
                    ret_ew_d = 1'b0;
                end
            endcase
        end
    end

    // Pedestrian pending flag: set by a request edge, cleared when the
    // pedestrian phase is entered (one request -> at most one service).
    always_comb begin
        ped_pending_d = ped_pending_q;

        if (ped_req_rise)
            ped_pending_d = 1'b1;
        else if ((state_q != S_PED_PHASE) && (state_d == S_PED_PHASE))
            ped_pending_d = 1'b0;
    end

    // Timer control: restart on every state change, during emergency
    // (keeps the All-Red interval fresh) and once after reset.
    always_comb begin
        timer_start  = 1'b0;
        timer_target = phase_target(state_d, traffic_density);

        if (!init_done_q || emergency_override || (state_d != state_q))
            timer_start = 1'b1;
    end

    // ------------------------------------------------------------------
    // Sequential logic (non-blocking assignments, synchronous reset)
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state_q       <= S_ALL_RED;
            ret_ew_q      <= 1'b0;
            ped_req_q     <= 1'b0;
            ped_pending_q <= 1'b0;
            init_done_q   <= 1'b0;
            ns_green_start <= 1'b0;
        end else begin
            state_q       <= state_d;
            ret_ew_q      <= ret_ew_d;
            ped_req_q     <= ped_req;
            ped_pending_q <= ped_pending_d;
            init_done_q   <= 1'b1;
            ns_green_start <= (state_d == S_NS_GREEN) && (state_q != S_NS_GREEN);
        end
    end

    // ------------------------------------------------------------------
    // Moore output decode
    // ------------------------------------------------------------------
    always_comb begin
        ns_red     = 1'b0;
        ns_yellow  = 1'b0;
        ns_green   = 1'b0;
        ew_red     = 1'b0;
        ew_yellow  = 1'b0;
        ew_green   = 1'b0;
        ped_active = 1'b0;
        ns_wait    = 1'b0;

        case (state_q)
            S_NS_GREEN: begin
                ns_green = 1'b1;
                ew_red   = 1'b1;
            end

            S_NS_YELLOW: begin
                ns_yellow = 1'b1;
                ew_red    = 1'b1;
            end

            S_ALL_RED: begin
                ns_red = 1'b1;
                ew_red = 1'b1;
            end

            S_EW_GREEN: begin
                ns_red   = 1'b1;
                ew_green = 1'b1;
            end

            S_EW_YELLOW: begin
                ns_red    = 1'b1;
                ew_yellow = 1'b1;
            end

            S_PED_PHASE: begin
                ns_red     = 1'b1;
                ew_red     = 1'b1;
                ped_active = 1'b1;
            end

            S_NS_WAIT: begin
                ns_red  = 1'b1;
                ew_red  = 1'b1;
                ns_wait = 1'b1;
            end

            default: begin
                ns_red = 1'b1;
                ew_red = 1'b1;
            end
        endcase
    end

    // The request is hidden during the pedestrian phase so the arbiter always
    // sees it drop once serviced (releases the grant, prevents starvation).
    assign ped_req_pending = ped_pending_q && (state_q != S_PED_PHASE);

    // ------------------------------------------------------------------
    // Parameter sanity checks (simulation)
    // ------------------------------------------------------------------
    initial begin
        if (COUNTER_WIDTH == 0)  $fatal(1, "COUNTER_WIDTH must be > 0");
        if (GREEN_TIME  == 0)    $fatal(1, "GREEN_TIME must be > 0");
        if (MIN_GREEN_TIME == 0) $fatal(1, "MIN_GREEN_TIME must be > 0");
        if (MIN_GREEN_TIME > MAX_GREEN_TIME) $fatal(1, "MIN_GREEN_TIME must be <= MAX_GREEN_TIME");
        if (YELLOW_TIME == 0)    $fatal(1, "YELLOW_TIME must be > 0");
        if (RED_TIME    == 0)    $fatal(1, "RED_TIME must be > 0 (All-Red safety gap)");
        if (PED_TIME    == 0)    $fatal(1, "PED_TIME must be > 0");
        if (MAX_GREEN_TIME > MAX_TARGET + TIMER_LATENCY) $fatal(1, "MAX_GREEN_TIME does not fit COUNTER_WIDTH");
        if (YELLOW_TIME > MAX_TARGET + TIMER_LATENCY) $fatal(1, "YELLOW_TIME does not fit COUNTER_WIDTH");
        if (RED_TIME    > MAX_TARGET + TIMER_LATENCY) $fatal(1, "RED_TIME does not fit COUNTER_WIDTH");
        if (PED_TIME    > MAX_TARGET + TIMER_LATENCY) $fatal(1, "PED_TIME does not fit COUNTER_WIDTH");
    end

endmodule

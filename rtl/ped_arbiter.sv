`timescale 1ns/1ps

// Shared pedestrian arbiter (Task 3) - round-robin with held grant.
//
// Interacts ONLY through request/grant signals (no junction internals).
//
// Policy
//   * A grant, once given, is held while the owner's request stays high, so a
//     junction never loses its grant before it reaches its pedestrian slot.
//   * When the arbiter is free and BOTH junctions request, the winner is the
//     one that did NOT win the previous contested decision (alternation).
//     Reset preference is A.
//   * Uncontested grants do not move the pointer, so contested decisions
//     strictly alternate A, B, A, B ...
//   * Starvation-free: a requester waits for at most one competing grant.

module ped_arbiter (
    input  logic clk,
    input  logic rst,           // active-high synchronous
    input  logic ped_req_A,
    input  logic ped_req_B,
    output logic ped_grant_A,
    output logic ped_grant_B
);

    logic last_b_q, last_b_d;   // 1: B won the last contested decision
    logic grant_a_d, grant_b_d;

    always_comb begin
        grant_a_d = 1'b0;
        grant_b_d = 1'b0;
        last_b_d  = last_b_q;

        if (ped_grant_A && ped_req_A) begin
            grant_a_d = 1'b1;                       // hold A
        end else if (ped_grant_B && ped_req_B) begin
            grant_b_d = 1'b1;                       // hold B
        end else if (ped_req_A && ped_req_B) begin  // contested decision
            if (last_b_q) begin
                grant_a_d = 1'b1;
                last_b_d  = 1'b0;
            end else begin
                grant_b_d = 1'b1;
                last_b_d  = 1'b1;
            end
        end else if (ped_req_A) begin
            grant_a_d = 1'b1;
        end else if (ped_req_B) begin
            grant_b_d = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            ped_grant_A <= 1'b0;
            ped_grant_B <= 1'b0;
            last_b_q    <= 1'b1;    // reset preference: A
        end else begin
            ped_grant_A <= grant_a_d;
            ped_grant_B <= grant_b_d;
            last_b_q    <= last_b_d;
        end
    end

endmodule
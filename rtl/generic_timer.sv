`timescale 1ns/1ps

// Task 2 - Reusable parameterized timer
module generic_timer #(
    parameter int unsigned COUNTER_WIDTH = 8
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     start,
    input  logic [COUNTER_WIDTH-1:0] count_target,
    output logic                     done
);

    logic [COUNTER_WIDTH-1:0] counter_q;
    logic [COUNTER_WIDTH-1:0] target_q;
    logic                     active_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            counter_q <= '0;
            target_q  <= '0;
            active_q  <= 1'b0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start) begin
                counter_q <= '0;
                target_q  <= count_target;

                if (count_target == '0) begin
                    active_q <= 1'b0;
                    done     <= 1'b1;
                end else begin
                    active_q <= 1'b1;
                end
            end else if (active_q) begin
                if (counter_q + 1'b1 >= target_q) begin
                    counter_q <= target_q;
                    active_q  <= 1'b0;
                    done      <= 1'b1;
                end else begin
                    counter_q <= counter_q + 1'b1;
                end
            end
        end
    end

endmodule

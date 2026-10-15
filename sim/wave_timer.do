# wave_timer.do  -  generic_timer testbench (use: do sim/wave_timer.do  BEFORE  run -all)
# Shows the 8-bit instance (target 5); u_t1 = 4-bit/target 3, u_t3 = 16-bit/target 8 are identical in structure.
onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {CLOCK}
add wave -noupdate -label clk                /tb_generic_timer/clk
add wave -noupdate -divider {TIMER u_t2 (COUNTER_WIDTH=8)}
add wave -noupdate -label rst                /tb_generic_timer/u_t2/rst
add wave -noupdate -label start              /tb_generic_timer/u_t2/start
add wave -noupdate -label count_target -radix unsigned /tb_generic_timer/u_t2/count_target
add wave -noupdate -label active             /tb_generic_timer/u_t2/dut/active_q
add wave -noupdate -label counter      -radix unsigned /tb_generic_timer/u_t2/dut/counter_q
add wave -noupdate -label target_latched -radix unsigned /tb_generic_timer/u_t2/dut/target_q
add wave -noupdate -label done               /tb_generic_timer/u_t2/done
add wave -noupdate -divider {OTHER WIDTHS: done only}
add wave -noupdate -label done_W4_t3         /tb_generic_timer/u_t1/done
add wave -noupdate -label done_W16_t8        /tb_generic_timer/u_t3/done
configure wave -signalnamewidth 1
update

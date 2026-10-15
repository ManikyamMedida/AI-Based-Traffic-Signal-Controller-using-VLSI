# wave_full.do  -  AMTGC system (use BEFORE run -all)
onerror {resume}
add wave -noupdate -divider {CLOCK / SYSTEM INPUTS}
add wave -noupdate -label clk                /tb_amtgc_full/clk
add wave -noupdate -label rst                /tb_amtgc_full/rst
add wave -noupdate -label emergency_override /tb_amtgc_full/emergency_override
add wave -noupdate -divider {PEDESTRIAN ARBITER}
add wave -noupdate -label ped_req_A          /tb_amtgc_full/ped_req_A
add wave -noupdate -label ped_req_B          /tb_amtgc_full/ped_req_B
add wave -noupdate -label pending_A          /tb_amtgc_full/ped_pending_A
add wave -noupdate -label pending_B          /tb_amtgc_full/ped_pending_B
add wave -noupdate -label grant_A            /tb_amtgc_full/ped_grant_A
add wave -noupdate -label grant_B            /tb_amtgc_full/ped_grant_B
add wave -noupdate -label ped_active_A       /tb_amtgc_full/ped_active_A
add wave -noupdate -label ped_active_B       /tb_amtgc_full/ped_active_B
add wave -noupdate -divider {JUNCTION A}
add wave -noupdate -label density_A  -radix unsigned /tb_amtgc_full/dens_A
add wave -noupdate -label A_state            /tb_amtgc_full/dut/u_junction_a/state_q
add wave -noupdate -label A_timer_target -radix unsigned /tb_amtgc_full/dut/u_junction_a/timer_target
add wave -noupdate -label A_timer_count  -radix unsigned /tb_amtgc_full/dut/u_junction_a/u_timer/counter_q
add wave -noupdate -label A_NS_green         /tb_amtgc_full/a_ns_green
add wave -noupdate -label A_NS_yellow        /tb_amtgc_full/a_ns_yellow
add wave -noupdate -label A_EW_green         /tb_amtgc_full/a_ew_green
add wave -noupdate -label A_EW_yellow        /tb_amtgc_full/a_ew_yellow
add wave -noupdate -label A_green_len -radix unsigned /tb_amtgc_full/a_last
add wave -noupdate -divider {JUNCTION B}
add wave -noupdate -label density_B  -radix unsigned /tb_amtgc_full/dens_B
add wave -noupdate -label B_state            /tb_amtgc_full/dut/u_junction_b/state_q
add wave -noupdate -label B_timer_target -radix unsigned /tb_amtgc_full/dut/u_junction_b/timer_target
add wave -noupdate -label B_timer_count  -radix unsigned /tb_amtgc_full/dut/u_junction_b/u_timer/counter_q
add wave -noupdate -label B_NS_green         /tb_amtgc_full/b_ns_green
add wave -noupdate -label B_NS_yellow        /tb_amtgc_full/b_ns_yellow
add wave -noupdate -label B_EW_green         /tb_amtgc_full/b_ew_green
add wave -noupdate -label B_EW_yellow        /tb_amtgc_full/b_ew_yellow
add wave -noupdate -label B_green_len -radix unsigned /tb_amtgc_full/b_last
add wave -noupdate -divider {GREEN WAVE}
add wave -noupdate -label A_ns_green_start   /tb_amtgc_full/a_ns_green_start
add wave -noupdate -label B_ns_wait          /tb_amtgc_full/dut/b_ns_wait
add wave -noupdate -label wave_timer_count -radix unsigned /tb_amtgc_full/dut/u_wave_timer/counter_q
add wave -noupdate -label wave_release       /tb_amtgc_full/wave_release
add wave -noupdate -label B_ns_green_start   /tb_amtgc_full/b_ns_green_start
add wave -noupdate -label offset_cycles -radix unsigned /tb_amtgc_full/off
configure wave -signalnamewidth 1
update

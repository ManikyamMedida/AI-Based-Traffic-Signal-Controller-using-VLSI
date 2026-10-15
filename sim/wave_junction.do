# wave_junction.do  -  junction_controller testbench (use BEFORE run -all)
onerror {resume}
add wave -noupdate -divider {CLOCK / CONTROL}
add wave -noupdate -label clk                /tb_junction_controller/clk
add wave -noupdate -label rst                /tb_junction_controller/rst
add wave -noupdate -label emergency          /tb_junction_controller/emergency_override
add wave -noupdate -divider {JUNCTION A inputs}
add wave -noupdate -label density_A  -radix unsigned /tb_junction_controller/dens_A
add wave -noupdate -label ped_req_A          /tb_junction_controller/ped_req_A
add wave -noupdate -label ped_pending_A      /tb_junction_controller/ped_pending_A
add wave -noupdate -label ped_grant_A        /tb_junction_controller/ped_grant_A
add wave -noupdate -divider {JUNCTION A timer}
add wave -noupdate -label timer_target -radix unsigned /tb_junction_controller/dut_A/timer_target
add wave -noupdate -label timer_counter -radix unsigned /tb_junction_controller/dut_A/u_timer/counter_q
add wave -noupdate -label timer_done         /tb_junction_controller/dut_A/timer_done
add wave -noupdate -divider {JUNCTION A FSM}
add wave -noupdate -label state              /tb_junction_controller/dut_A/state_q
add wave -noupdate -label next_state         /tb_junction_controller/dut_A/state_d
add wave -noupdate -label NS_green           /tb_junction_controller/ns_green_A
add wave -noupdate -label NS_yellow          /tb_junction_controller/ns_yellow_A
add wave -noupdate -label NS_red             /tb_junction_controller/ns_red_A
add wave -noupdate -label EW_green           /tb_junction_controller/ew_green_A
add wave -noupdate -label EW_yellow          /tb_junction_controller/ew_yellow_A
add wave -noupdate -label EW_red             /tb_junction_controller/ew_red_A
add wave -noupdate -label ped_active         /tb_junction_controller/ped_active_A
add wave -noupdate -divider {JUNCTION B (same RTL, different parameters)}
add wave -noupdate -label density_B  -radix unsigned /tb_junction_controller/dens_B
add wave -noupdate -label state_B            /tb_junction_controller/dut_B/state_q
add wave -noupdate -label NS_green_B         /tb_junction_controller/ns_green_B
add wave -noupdate -label NS_yellow_B        /tb_junction_controller/ns_yellow_B
add wave -noupdate -label EW_green_B         /tb_junction_controller/ew_green_B
add wave -noupdate -label EW_yellow_B        /tb_junction_controller/ew_yellow_B
add wave -noupdate -label ped_active_B       /tb_junction_controller/ped_active_B
configure wave -signalnamewidth 1
update

@echo off
REM Run from the project root (the folder that contains rtl\ tb\ sim\).
REM Requires ModelSim/Questa (vlib, vlog, vsim) on PATH. Logs go to sim\logs\.
if exist work rmdir /s /q work
vlib work
vmap work work

echo ===== Task 2: generic_timer =====
vlog -sv rtl/generic_timer.sv tb/tb_generic_timer.sv
vsim -c -l sim/logs/task2_timer_console.log work.tb_generic_timer -do "run -all; quit -f"

echo ===== Task 2/4: junction_controller =====
vlog -sv rtl/generic_timer.sv rtl/junction_controller.sv tb/tb_monitors.sv tb/tb_junction_controller.sv
vsim -c -l sim/logs/junction_console.log work.tb_junction_controller -do "run -all; quit -f"

echo ===== Task 3/4: amtgc_top integration =====
vlog -sv rtl/generic_timer.sv rtl/junction_controller.sv rtl/ped_arbiter.sv rtl/amtgc_top.sv tb/tb_monitors.sv tb/tb_amtgc_top.sv
vsim -c -l sim/logs/amtgc_console.log work.tb_amtgc_top -do "run -all; quit -f"

echo ===== Task 5: unified verification =====
vlog -sv rtl/generic_timer.sv rtl/junction_controller.sv rtl/ped_arbiter.sv rtl/amtgc_top.sv tb/tb_monitors.sv tb/tb_generic_timer.sv tb/tb_amtgc_full.sv
vsim -c -l sim/logs/task5_full_verification_rerun.log work.tb_amtgc_full -do "run -all; quit -f"

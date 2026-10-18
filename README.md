# AI-Based Traffic Signal Controller using VLSI

Two coordinated 4-way traffic junctions in SystemVerilog with a shared pedestrian
arbiter, system-wide emergency override, green-wave coordination and
traffic-adaptive green timing. Built as an extension of the Elevance Skills
training traffic-controller project (see "Training project lineage").

## Features
- Reusable, parameterized `junction_controller` (Moore FSM: NS Green, NS Yellow, All-Red, EW Green, EW Yellow, Pedestrian, plus a parked `NS_WAIT` state); the same RTL is instantiated twice with different parameters.
- Standalone `generic_timer` (parameter `COUNTER_WIDTH`, `start` / `count_target` / `done`), unchanged since Task 2, also reused for the green-wave offset.
- `ped_arbiter`: round-robin with held grant, starvation-free, request/grant signals only.
- `emergency_override`: both junctions reach All-Red 1 clock after it is sampled (requirement: <= 2); restart through a valid safe phase.
- Green wave: junction B's NS Green starts exactly 4 cycles after junction A's (accepted window 3..5), independent of green/pedestrian durations.
- Adaptive green: `green = clamp(GREEN_TIME + density x GREEN_EXT_STEP, MIN_GREEN_TIME, MAX_GREEN_TIME)`, density sampled once at green start.
- Single clock domain, active-high synchronous reset, named port connections only, no magic numbers in FSM logic.

## Repository layout
```
rtl/            generic_timer.sv  junction_controller.sv  ped_arbiter.sv  amtgc_top.sv
tb/             tb_monitors.sv  tb_generic_timer.sv  tb_junction_controller.sv
                tb_amtgc_top.sv (Tasks 3/4)  tb_amtgc_full.sv (Task 5 unified, self-checking)
sim/            run_all.bat  wave_*.do  logs/  screenshots/
docs/           report, per-task documentation, diagrams/, assumptions, bug log, coverage statement, checksums
```

## Tools
ModelSim Intel FPGA Edition 2020.1 (also tested with QuestaSim 2021.1). No other dependencies.

## How to run (from the project root, i.e. the folder containing rtl/ tb/ sim/)
Option 1 - everything (Windows, ModelSim on PATH):
```
sim\run_all.bat
```
Option 2 - from the ModelSim transcript (use forward slashes):
```tcl
vlib work
vmap work work

# Task 2: timer
vlog -sv rtl/generic_timer.sv tb/tb_generic_timer.sv
vsim -voptargs=+acc work.tb_generic_timer
do sim/wave_timer.do
run -all
quit -sim

# Task 2/4: junction controller
vlog -sv rtl/generic_timer.sv rtl/junction_controller.sv tb/tb_monitors.sv tb/tb_junction_controller.sv
vsim -voptargs=+acc work.tb_junction_controller
do sim/wave_junction.do
run -all
quit -sim

# Task 3/4: system integration
vlog -sv rtl/generic_timer.sv rtl/junction_controller.sv rtl/ped_arbiter.sv rtl/amtgc_top.sv tb/tb_monitors.sv tb/tb_amtgc_top.sv
vsim -voptargs=+acc work.tb_amtgc_top
do sim/wave_system.do
run -all
quit -sim

# Task 5: unified self-checking verification (about 242 us simulated)
vlog -sv rtl/generic_timer.sv rtl/junction_controller.sv rtl/ped_arbiter.sv rtl/amtgc_top.sv tb/tb_monitors.sv tb/tb_generic_timer.sv tb/tb_amtgc_full.sv
vsim -voptargs=+acc work.tb_amtgc_full
do sim/wave_full.do
run -all
```
Expected result of the unified bench: a coverage table with every item `COVERED`, then
`AMTGC FULL VERIFICATION: ALL PASS`. Any failed check stops the run with a `** Fatal:` line.

## Key parameters (verification configuration)
| | Junction A | Junction B |
|---|---|---|
| base green / step / min / max | 4 / 2 / 3 / 12 | 2 / 1 / 3 / 8 |
| yellow / red / pedestrian | 2 / 2 / 3 | 2 / 3 / 2 |
Green-wave offset target: 4 cycles. `COUNTER_WIDTH` = 8.

## Results (from sim/logs)
- Timer: 12/12 checks (widths 4, 8, 16; zero target; reset while counting).
- Green-wave offset: exactly 40 ns (4 cycles) between the two junctions' NS-green starts (`sim/Screenshots/Task3_03_green_wave_offset_4_cycles.png`).
- Unified bench: 20 plan scenarios + 9 extra tests covered (29/29, A ped 684, B ped 657); 835 green-wave measurements, all exactly 4 cycles; 60 simultaneous-request rounds (120 requests) alternate A/B 30/30; 20000-cycle constrained-random run (density, pedestrian, emergency, reset).
- Mutation tests (restored RTL passes afterwards):

| Mutation | Caught by | Log |
|---|---|---|
| All-Red skipped | `conflicting green without All-Red gap` | `sim/logs/task5_mutation_tests.log`, lines 4-46 |
| Emergency disabled | `not All-Red one clock after assertion` | `sim/logs/task5_mutation_tests.log`, lines 47-107 |
| Fixed-priority arbiter | `ARBITER FAIRNESS FAIL` | `sim/logs/task5_mutation_tests.log`, lines 108-164 |
| Minimum-green clamp removed | `NS_GREEN duration FAIL: expected 3 cycles, observed 2` | `sim/logs/task5_mutation_tests.log`, lines 165-207 (restored clean run: lines 208-335) |

## Documentation
| File | Purpose |
|---|---|
| `docs/Technical_Report.md` | technical report (8 sections + appendices) |
| `docs/Task1-4_AsBuilt_Documentation.md` | per-task design, results and evidence |
| `docs/diagrams/` | as-built block diagram, FSM diagram, Task 1 plan diagram |
| `docs/ASSUMPTIONS.md` | assumptions and conventions |
| `docs/BUG_LOG.md` | defects found, causes, fixes (BUG-01..07) |
| `docs/Task5_Coverage_Statement.md` | plan vs executed tests, mutation results, limitations |
| `docs/SCREENSHOT_MANIFEST.md` | index of screenshots and logs |
| `docs/Self_Attestation_Checklist.md`, `docs/Demo_Video_Script.md` | delivery items |
| `docs/RTL_CHECKSUMS.txt` | SHA-256 of the frozen RTL |

## Training project lineage
The design extends the course training project (`traffic_timer`, `traffic_fsm_final`, `density_logic`, `traffic_system_top_final`): timer -> `generic_timer`, single-road FSM -> 4-way `junction_controller`, three fixed density levels -> clamped adaptive green, single pedestrian latch -> shared round-robin arbiter, manual waveform testbench -> self-checking verification.

## Frozen RTL
`docs/RTL_CHECKSUMS.txt` records SHA-256 hashes of the RTL that passed the final Task 5 run (Oct 8 2026); the delivered RTL must match. On Windows: `certutil -hashfile rtl\junction_controller.sv SHA256`.

## Author and disclosure
MANIKYAM MEDIDA, Elevance Skills VLSI internship. 
AI Transparency Notice: Parts of the conceptual explanations and analogies in this documentation were generated with the assistance of [AI Tool, e.g., ChatGPT]. All AI-generated content has been human-reviewed, edited, and verified for technical accuracy.

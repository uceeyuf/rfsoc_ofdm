# Program the RFSoC4x2 over JTAG and start the application on A53 #0.
#   xsct run_jtag.tcl
# Copyright (c) 2026, Yijie Yu. BSD-3-Clause.

set here [file normalize [file dirname [info script]]]
set pf   $here/vitis_ws/ofdm_video_pf/export/ofdm_video_pf/hw
set xsa  [lindex [glob $pf/*.xsa] 0]
set bit  [lindex [glob $pf/*.bit] 0]
set init $here/vitis_ws/ofdm_video_pf/export/ofdm_video_pf/hw/psu_init.tcl
if {![file exists $init]} { set init [lindex [glob $here/vitis_ws/ofdm_video_pf/hw/psu_init.tcl] 0] }
set elf  $here/vitis_ws/ofdm_video/Debug/ofdm_video.elf

connect
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 3000
targets -set -nocase -filter {name =~ "PSU*"}
fpga -file $bit
targets -set -nocase -filter {name =~ "APU*"}
loadhw -hw $xsa -mem-ranges [list {0x80000000 0xbfffffff} {0x400000000 0x5ffffffff} {0x1000000000 0x7fffffffff}] -regs
configparams force-mem-access 1
source $init
psu_init
after 1000
psu_ps_pl_isolation_removal
after 1000
psu_ps_pl_reset_config
catch {psu_protection}
targets -set -nocase -filter {name =~ "*A53*#0"}
rst -processor
dow $elf
configparams force-mem-access 0
con
puts "running $elf"

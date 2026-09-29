# Vitis 2020.2 workspace for the OFDM video link.
#   xsct create_vitis.tcl [path/to/design_1_wrapper.xsa]
# Copyright (c) 2026, Yijie Yu. BSD-3-Clause.

set here [file normalize [file dirname [info script]]]
set xsa  [expr {[llength $argv] > 0 ? [file normalize [lindex $argv 0]] : "$here/../design_1_wrapper.xsa"}]
set ws   $here/vitis_ws

file delete -force $ws
setws $ws

platform create -name ofdm_video_pf -hw $xsa -proc psu_cortexa53_0 -os standalone -out $ws
bsp setlib -name lwip211
bsp config api_mode RAW_API
bsp config lwip_dhcp false
bsp config mem_size 1048576
bsp config memp_n_pbuf 1024
bsp config pbuf_pool_size 4096
bsp config n_rx_descriptors 256
bsp config n_tx_descriptors 256
bsp config stdin psu_uart_1
bsp config stdout psu_uart_1
platform generate

app create -name ofdm_video -platform ofdm_video_pf -domain standalone_domain -template "Empty Application"
importsources -name ofdm_video -path $here/src
app config -name ofdm_video -add libraries lwip4
app config -name ofdm_video -add libraries metal
# app build generates Debug/makefile; in batch mode it may drop the xsct channel before
# linking, so finish with make
catch {app build -name ofdm_video}
set elf $ws/ofdm_video/Debug/ofdm_video.elf
if {![file exists $elf]} {
    set vitis $::env(XILINX_VITIS)
    set ::env(PATH) "$vitis/gnu/aarch64/nt/aarch64-none/bin;$vitis/gnuwin/bin;$::env(PATH)"
    exec make -C $ws/ofdm_video/Debug all >@ stdout 2>@ stderr
}
puts "ELF: $elf"

# Capture the ofdm_rx output symbols (ILA slot 0, valid beats only) to ila_rx.csv.
#   vivado -mode batch -source ila_capture.tcl
# Copyright (c) 2026, Yijie Yu. BSD-3-Clause.

set here [file normalize [file dirname [info script]]]
set ltx  $here/../ofdm_video/ofdm_video.runs/impl_1/design_1_wrapper.ltx

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xczu48dr*] 0]
current_hw_device $dev
set_property PROBES.FILE $ltx $dev
set_property FULL_PROBES.FILE $ltx $dev
refresh_hw_device $dev

set ila [lindex [get_hw_ilas] 0]
set tvalid [get_hw_probes -of_objects $ila -filter {NAME =~ "*net_slot_0_axis_tvalid"}]

set_property CONTROL.CAPTURE_MODE BASIC $ila
set_property CAPTURE_COMPARE_VALUE eq1'b1 $tvalid
set_property CONTROL.TRIGGER_POSITION 0 $ila
set_property CONTROL.DATA_DEPTH 8192 $ila
run_hw_ila $ila
wait_on_hw_ila -timeout 1 $ila
write_hw_ila_data -csv_file -force $here/ila_rx.csv [upload_hw_ila_data $ila]
puts "wrote $here/ila_rx.csv"

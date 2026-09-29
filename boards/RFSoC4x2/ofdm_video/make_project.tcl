# RFSoC4x2 OFDM video link, Vivado 2020.2
#
#   vivado -mode batch -source make_project.tcl                 (project + block design)
#   vivado -mode batch -source make_project.tcl -tclargs build  (+ bitstream + .xsa)
#
# DAC_B = DAC tile 228 ch0, ADC_B = ADC tile 226 ch0, 3.93216 GSPS, refclk 491.52 MHz
# (LMK04828 245.76 MHz + LMX2594 491.52 MHz, programmed by the bare-metal app over PS SPI0).
# Copyright (c) 2026, Yijie Yu. BSD-3-Clause.

set build [expr {[llength $argv] > 0 && [lindex $argv 0] eq "build"}]

set here      [file normalize [file dirname [info script]]]
set proj_name ofdm_video
set proj_dir  $here/$proj_name
set bd_name   design_1
set iprepo    [file normalize $here/../../ip/iprepo]
set use_ila   1

# board files: installed ones first, then the RealDigital download next to the repo
if {[llength [get_board_parts -quiet realdigital.org:rfsoc4x2:*]] == 0} {
    set_param board.repoPaths [list [file normalize $here/../../../../rfsoc4x2_board_files]]
}

create_project $proj_name $proj_dir -part xczu48dr-ffvg1517-2-e -force
set_property board_part realdigital.org:rfsoc4x2:part0:1.0 [current_project]
set_property target_language Verilog [current_project]
set_property ip_repo_paths $iprepo [current_project]
update_ip_catalog

# RTL: strath-sdr ofdm_tx sources + modified top chain + our wrappers
add_files -norecurse [glob $iprepo/ofdm_tx_v0_5/hdl/vhdl/*.vhd]
add_files -norecurse [glob $here/rtl/ofdm_txs/*.vhd]
add_files -norecurse [list $here/rtl/axil_regs.v $here/rtl/ofdm_tx_stream.v $here/rtl/ofdm_rx_demap.v]
add_files -fileset constrs_1 -norecurse $here/constraints.xdc
update_compile_order -fileset sources_1

create_bd_design $bd_name

# ---------------------------------------------------------------- PS
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e zynq_ultra_ps_e_0]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $ps
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__USE__IRQ0 {1} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__DDRC__ROW_ADDR_COUNT {16} \
] $ps

# ---------------------------------------------------------------- RF data converter
set rfdc [create_bd_cell -type ip -vlnv xilinx.com:ip:usp_rf_data_converter usp_rf_data_converter_0]
set_property -dict [list \
    CONFIG.ADC0_Enable {0} \
    CONFIG.ADC_Slice00_Enable {false} \
    CONFIG.ADC_Slice01_Enable {false} \
    CONFIG.ADC2_Enable {1} \
    CONFIG.ADC2_PLL_Enable {true} \
    CONFIG.ADC2_Refclk_Freq {491.520} \
    CONFIG.ADC2_Sampling_Rate {3.93216} \
    CONFIG.ADC2_Fabric_Freq {245.760} \
    CONFIG.ADC2_Outclk_Freq {245.760} \
    CONFIG.ADC_Slice20_Enable {true} \
    CONFIG.ADC_Slice21_Enable {true} \
    CONFIG.ADC_Data_Type20 {1} \
    CONFIG.ADC_Data_Type21 {1} \
    CONFIG.ADC_Data_Width20 {2} \
    CONFIG.ADC_Data_Width21 {2} \
    CONFIG.ADC_Decimation_Mode20 {8} \
    CONFIG.ADC_Decimation_Mode21 {8} \
    CONFIG.ADC_Mixer_Type20 {2} \
    CONFIG.ADC_Mixer_Type21 {2} \
    CONFIG.ADC_Mixer_Mode20 {0} \
    CONFIG.ADC_Mixer_Mode21 {0} \
    CONFIG.ADC_NCO_Freq20 {-0.6} \
    CONFIG.ADC_Nyquist20 {1} \
    CONFIG.ADC_Nyquist21 {1} \
    CONFIG.DAC0_Enable {1} \
    CONFIG.DAC0_PLL_Enable {true} \
    CONFIG.DAC0_Refclk_Freq {491.520} \
    CONFIG.DAC0_Sampling_Rate {3.93216} \
    CONFIG.DAC0_Fabric_Freq {245.760} \
    CONFIG.DAC0_Outclk_Freq {245.760} \
    CONFIG.DAC_Slice00_Enable {true} \
    CONFIG.DAC_Data_Width00 {4} \
    CONFIG.DAC_Interpolation_Mode00 {8} \
    CONFIG.DAC_Mixer_Type00 {2} \
    CONFIG.DAC_Mixer_Mode00 {0} \
    CONFIG.DAC_NCO_Freq00 {0.6} \
    CONFIG.DAC_Nyquist00 {1} \
] $rfdc

foreach p {dac0_clk adc2_clk sysref_in vout00 vin2_01} {
    make_bd_intf_pins_external [get_bd_intf_pins usp_rf_data_converter_0/$p]
}

set clk_ps  [get_bd_pins zynq_ultra_ps_e_0/pl_clk0]
set clk_dac [get_bd_pins usp_rf_data_converter_0/clk_dac0]
set clk_adc [get_bd_pins usp_rf_data_converter_0/clk_adc2]

# ---------------------------------------------------------------- resets
foreach {name clk} [list rst_ps $clk_ps rst_dac $clk_dac rst_adc $clk_adc] {
    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset $name
    connect_bd_net $clk [get_bd_pins $name/slowest_sync_clk]
    connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins $name/ext_reset_in]
}
set rstn_ps  [get_bd_pins rst_ps/peripheral_aresetn]
set rstn_dac [get_bd_pins rst_dac/peripheral_aresetn]
set rstn_adc [get_bd_pins rst_adc/peripheral_aresetn]

# ---------------------------------------------------------------- transmit chain (clk_dac0)
create_bd_cell -type module -reference ofdm_tx_stream ofdm_tx_stream_0
create_bd_cell -type ip -vlnv strathsdr.org:PYNQ-SDR:ofdm_interpolator ofdm_interpolator_0

set tx_fifo [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo tx_fifo]
set_property -dict [list CONFIG.FIFO_DEPTH {8192} CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.TDATA_NUM_BYTES {4} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}] $tx_fifo

connect_bd_intf_net [get_bd_intf_pins tx_fifo/M_AXIS] [get_bd_intf_pins ofdm_tx_stream_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins ofdm_tx_stream_0/m_axis] [get_bd_intf_pins ofdm_interpolator_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins ofdm_interpolator_0/M_AXIS] [get_bd_intf_pins usp_rf_data_converter_0/s00_axis]

connect_bd_net $clk_dac [get_bd_pins ofdm_tx_stream_0/aclk] [get_bd_pins ofdm_interpolator_0/aclk] \
    [get_bd_pins tx_fifo/m_axis_aclk] [get_bd_pins usp_rf_data_converter_0/s0_axis_aclk]
connect_bd_net $rstn_dac [get_bd_pins ofdm_tx_stream_0/aresetn] [get_bd_pins ofdm_interpolator_0/aresetn] \
    [get_bd_pins usp_rf_data_converter_0/s0_axis_aresetn]

# ---------------------------------------------------------------- receive chain (clk_adc2)
create_bd_cell -type ip -vlnv strathsdr.org:PYNQ-SDR:ofdm_decimator ofdm_decimator_0
create_bd_cell -type ip -vlnv strathsdr.org:PYNQ-SDR:ofdm_rx ofdm_rx_0
create_bd_cell -type module -reference ofdm_rx_demap ofdm_rx_demap_0

set rx_fifo [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo rx_fifo]
set_property -dict [list CONFIG.FIFO_DEPTH {8192} CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.TDATA_NUM_BYTES {4} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}] $rx_fifo

connect_bd_intf_net [get_bd_intf_pins usp_rf_data_converter_0/m20_axis] [get_bd_intf_pins ofdm_decimator_0/S_REAL_AXIS]
connect_bd_intf_net [get_bd_intf_pins usp_rf_data_converter_0/m21_axis] [get_bd_intf_pins ofdm_decimator_0/S_IMAG_AXIS]
connect_bd_intf_net [get_bd_intf_pins ofdm_decimator_0/M_AXIS] [get_bd_intf_pins ofdm_rx_0/AXI4_Stream_Slave]
connect_bd_intf_net [get_bd_intf_pins ofdm_rx_0/AXI4_Stream_Master] [get_bd_intf_pins ofdm_rx_demap_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins ofdm_rx_demap_0/m_axis] [get_bd_intf_pins rx_fifo/S_AXIS]

connect_bd_net $clk_adc [get_bd_pins ofdm_decimator_0/aclk] [get_bd_pins ofdm_rx_0/IPCORE_CLK] \
    [get_bd_pins ofdm_rx_0/AXI4_Lite_ACLK] [get_bd_pins ofdm_rx_demap_0/aclk] \
    [get_bd_pins rx_fifo/s_axis_aclk] [get_bd_pins usp_rf_data_converter_0/m2_axis_aclk]
connect_bd_net $rstn_adc [get_bd_pins ofdm_decimator_0/aresetn] [get_bd_pins ofdm_rx_0/IPCORE_RESETN] \
    [get_bd_pins ofdm_rx_0/AXI4_Lite_ARESETN] [get_bd_pins ofdm_rx_demap_0/aresetn] \
    [get_bd_pins rx_fifo/s_axis_aresetn] [get_bd_pins usp_rf_data_converter_0/m2_axis_aresetn]

# ---------------------------------------------------------------- DMA (pl_clk0)
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_length_width {23} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_m_axi_s2mm_data_width {32} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_mm2s_burst_size {64} \
    CONFIG.c_s2mm_burst_size {64} \
] $dma

connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins tx_fifo/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins rx_fifo/M_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]
connect_bd_net $clk_ps [get_bd_pins tx_fifo/s_axis_aclk] [get_bd_pins rx_fifo/m_axis_aclk] \
    [get_bd_pins axi_dma_0/s_axi_lite_aclk] [get_bd_pins axi_dma_0/m_axi_mm2s_aclk] \
    [get_bd_pins axi_dma_0/m_axi_s2mm_aclk]
connect_bd_net $rstn_ps [get_bd_pins tx_fifo/s_axis_aresetn] [get_bd_pins axi_dma_0/axi_resetn]

set hp0_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect hp0_interconnect]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] $hp0_ic
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins hp0_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins hp0_interconnect/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins hp0_interconnect/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]
connect_bd_net $clk_ps [get_bd_pins hp0_interconnect/ACLK] [get_bd_pins hp0_interconnect/S00_ACLK] \
    [get_bd_pins hp0_interconnect/S01_ACLK] [get_bd_pins hp0_interconnect/M00_ACLK] \
    [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk]
connect_bd_net [get_bd_pins rst_ps/interconnect_aresetn] [get_bd_pins hp0_interconnect/ARESETN]
connect_bd_net $rstn_ps [get_bd_pins hp0_interconnect/S00_ARESETN] [get_bd_pins hp0_interconnect/S01_ARESETN] \
    [get_bd_pins hp0_interconnect/M00_ARESETN]

set irq [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat irq_concat]
set_property CONFIG.NUM_PORTS {2} $irq
connect_bd_net [get_bd_pins axi_dma_0/mm2s_introut] [get_bd_pins irq_concat/In0]
connect_bd_net [get_bd_pins axi_dma_0/s2mm_introut] [get_bd_pins irq_concat/In1]
connect_bd_net [get_bd_pins irq_concat/dout] [get_bd_pins zynq_ultra_ps_e_0/pl_ps_irq0]

# ---------------------------------------------------------------- AXI-Lite control
set lite_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect lite_interconnect]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {6}] $lite_ic
connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] [get_bd_intf_pins lite_interconnect/S00_AXI]
connect_bd_net $clk_ps [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] [get_bd_pins lite_interconnect/ACLK] \
    [get_bd_pins lite_interconnect/S00_ACLK]
connect_bd_net [get_bd_pins rst_ps/interconnect_aresetn] [get_bd_pins lite_interconnect/ARESETN]
connect_bd_net $rstn_ps [get_bd_pins lite_interconnect/S00_ARESETN]

set lite_slaves [list \
    M00 usp_rf_data_converter_0/s_axi   $clk_ps  $rstn_ps \
    M01 axi_dma_0/S_AXI_LITE            $clk_ps  $rstn_ps \
    M02 ofdm_tx_stream_0/s_axi          $clk_dac $rstn_dac \
    M03 ofdm_tx_stream_0/s_axi_ctl      $clk_dac $rstn_dac \
    M04 ofdm_rx_0/AXI4_Lite             $clk_adc $rstn_adc \
    M05 ofdm_rx_demap_0/s_axi           $clk_adc $rstn_adc \
]
foreach {m slave clk rstn} $lite_slaves {
    connect_bd_intf_net [get_bd_intf_pins lite_interconnect/${m}_AXI] [get_bd_intf_pins $slave]
    connect_bd_net $clk  [get_bd_pins lite_interconnect/${m}_ACLK]
    connect_bd_net $rstn [get_bd_pins lite_interconnect/${m}_ARESETN]
}
connect_bd_net $clk_ps  [get_bd_pins usp_rf_data_converter_0/s_axi_aclk]
connect_bd_net $rstn_ps [get_bd_pins usp_rf_data_converter_0/s_axi_aresetn]

# ---------------------------------------------------------------- ILA on the receive side
if {$use_ila} {
    set ila [create_bd_cell -type ip -vlnv xilinx.com:ip:system_ila system_ila_0]
    set_property -dict [list CONFIG.C_NUM_MONITOR_SLOTS {2} CONFIG.C_SLOT_0_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} \
        CONFIG.C_SLOT_1_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} CONFIG.C_DATA_DEPTH {8192} \
        CONFIG.C_EN_STRG_QUAL {1}] $ila
    connect_bd_intf_net [get_bd_intf_pins system_ila_0/SLOT_0_AXIS] [get_bd_intf_pins ofdm_rx_0/AXI4_Stream_Master]
    connect_bd_intf_net [get_bd_intf_pins system_ila_0/SLOT_1_AXIS] [get_bd_intf_pins ofdm_rx_demap_0/m_axis]
    connect_bd_net $clk_adc  [get_bd_pins system_ila_0/clk]
    connect_bd_net $rstn_adc [get_bd_pins system_ila_0/resetn]
}

# ---------------------------------------------------------------- address map
set addr_map {
    usp_rf_data_converter_0/s_axi   0xA0000000 256K
    axi_dma_0/S_AXI_LITE            0xA0040000 64K
    ofdm_tx_stream_0/s_axi          0xA0050000 64K
    ofdm_tx_stream_0/s_axi_ctl      0xA0060000 4K
    ofdm_rx_0/AXI4_Lite             0xA0070000 64K
    ofdm_rx_demap_0/s_axi           0xA0080000 4K
}
foreach {pin base range} $addr_map {
    assign_bd_address -offset $base -range $range \
        -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
        [get_bd_addr_segs -of_objects [get_bd_intf_pins $pin]]
}
# DMA masters -> DDR
assign_bd_address

validate_bd_design
save_bd_design

make_wrapper -files [get_files $bd_name.bd] -top -import
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

if {$build} {
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
        error "implementation failed"
    }
    open_run impl_1
    report_timing_summary -file $here/timing_summary.rpt
    write_hw_platform -fixed -include_bit -force -file $here/${bd_name}_wrapper.xsa
}

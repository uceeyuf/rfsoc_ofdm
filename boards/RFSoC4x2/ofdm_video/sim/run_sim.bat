@echo off
rem Baseband loopback simulation with the Vivado simulator.
rem Usage: set SIM_DEFINES=-d MOD=3 -d NFRAMES=4 & run_sim.bat
setlocal
if "%XILINX_VIVADO%"=="" set XILINX_VIVADO=C:\Xilinx\Vivado\2020.2
set PATH=%XILINX_VIVADO%\bin;%PATH%
cd /d %~dp0

call xvhdl --nolog -f vhdl_files.f || exit /b 1
call xvlog --nolog ../rtl/axil_regs.v ../rtl/ofdm_tx_stream.v ../rtl/ofdm_rx_demap.v || exit /b 1
call xvlog --nolog -sv %SIM_DEFINES% tb_ofdm_loop.v || exit /b 1
call xelab --nolog -debug off -timescale 1ns/1ps tb_ofdm_loop -s tb_ofdm_loop || exit /b 1
call xsim --nolog tb_ofdm_loop -R || exit /b 1

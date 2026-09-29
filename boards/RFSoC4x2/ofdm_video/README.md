![语言](https://img.shields.io/badge/语言-Verilog_+_VHDL-9A90FD.svg) ![仿真](https://img.shields.io/badge/仿真-xsim-green.svg) ![部署](https://img.shields.io/badge/部署-vivado_2020.2-FF1010.svg) ![板卡](https://img.shields.io/badge/板卡-RFSoC_4x2-blue.svg)

[English](#en) | [中文](#cn)

　

<span id="en">RFSoC 4x2 OFDM compressed video link</span>
===========================

Compressed video (H.264 in MPEG-TS) sent over the air interface of the Strathclyde [rfsoc_ofdm](https://github.com/strath-sdr/rfsoc_ofdm) transceiver on the RFSoC 4x2: **DAC_B (tile 228 ch0) → SMA loop → ADC_B (tile 226 ch0)**, bare metal, no PYNQ.

The PC streams video to the board over UDP, the PS packs it into CRC-protected link packets, the PL modulates them onto the OFDM carrier, and the received packets go back to the PC for playback.

　

| ![arch](./docs/arch.svg) |
| :----------------------: |
| **Figure1** : data path  |

　

## Technical Features

* **User data on the strath-sdr PHY**: the HDL Coder `ofdm_tx` only transmits PRBS. `rtl/ofdm_txs/` is the same core with the PRBS source replaced by an external symbol port; `ofdm_tx_stream` feeds it from an AXI4-Stream FIFO. `ofdm_rx` is used unchanged; `ofdm_rx_demap` slices its equalised sub-carriers (BPSK / QPSK / 16-QAM, same bit mapping as the TX generators) and packs bytes.
* **Bit-exact framing found in simulation**: the TX pipeline never sends the symbol requested at position 45 of each 48-carrier OFDM symbol, and the receiver repeats one symbol at position 0, with a 3-symbol offset. The TX bit source skips that slot, the RX packer drops the repeat, so each OFDM frame carries exactly **5960 data symbols**, byte aligned for all three modulations.
* **Self-synchronising byte stream**: every OFDM frame is one DMA packet. Link packets (`1A CF FC 1D`, length, sequence, payload, CRC32) may span frames; a lost frame only loses the packets inside it. Empty FIFO slots are filled with PRBS words, so the spectrum is the same with or without traffic.
* **Clocks without PYNQ**: LMK04828 (245.76 MHz) and two LMX2594 (491.52 MHz) programmed over PS SPI0 (`LMK_LMX.c`), instead of the I2C-to-SPI bridge of the ZCU208 CLK104. Both tiles use their own PLL at 3.93216 GSPS, ×8 interpolation / decimation, 245.76 MHz fabric clock, carrier 600 MHz (runtime adjustable).
* **Debug**: System ILA on the receiver symbols and on the demapper output; TX / RX frame and symbol counters over AXI-Lite; UART self-test mode that saturates the link and checks every payload byte.

　

## Performance results

| modulation | payload per OFDM frame | link payload rate |
| :--------: | :--------------------: | :---------------: |
| BPSK       | 745 B                  | 5.9 Mb/s          |
| QPSK       | 1490 B                 | 11.8 Mb/s         |
| 16-QAM     | 2980 B                 | 23.7 Mb/s         |

OFDM frame: 320-sample preamble + 127 data symbols + equal idle time, 20640 samples at 20.48 MSPS = 1.008 ms.

**Simulation** (`sim/`, TX core → RX core at baseband, random payload): every received frame matches the transmitted byte stream, contiguous from the first frame, for BPSK, QPSK and 16-QAM.

**Implementation** (Vivado 2020.2, XCZU48DR-2, with the ILA): 27.1 k LUT (6.4 %), 40.5 k FF (4.8 %), 41 BRAM, 191 DSP, all constraints met (WNS +0.251 ns). Bitstream + XSA in about 15 min.

**On the board** (DAC_B → SMA cable → ADC_B, 600 MHz carrier, UART self-test, 1316-byte packets):

| modulation | measured payload rate | CRC errors |
| :--------: | :-------------------: | :--------: |
| BPSK       | 5.86 Mb/s             | 0 / 5 000 packets |
| QPSK       | 11.71 Mb/s            | 0 / 15 000 packets |
| 16-QAM     | 23.44 Mb/s            | 1 / 20 000 packets |

Switching the modulation at run time costs one or two packets.

**End to end** (PC → UDP → board → OFDM → board → UDP → PC, `pc/link_test.py`): throughput saturates at **5.98 / 11.83 / 23.55 Mb/s** (BPSK / QPSK / 16-QAM), below that the loss is 0.01–0.04 %; above it the extra load is dropped at the board TX queue, never corrupted. Over 940 k packets the CRC error rate was 1.6 × 10⁻⁴, including modulation changes. A 20 s 720p H.264 stream at 2 Mb/s (QPSK): 593/600 frames decoded, PSNR 40.2 dB average, error-free frames bit-identical to the source.
If the link shows periodic error bursts right after power-on, reload the design (LMK PLL1 settling).

　

## Usage

**Hardware** (Vivado 2020.2, RFSoC 4x2 board files installed):

```
cd boards/RFSoC4x2/ofdm_video
vivado -mode batch -source make_project.tcl -tclargs build
```

produces `design_1_wrapper.xsa` (bitstream included).

**Software** (Vitis 2020.2, standalone + lwIP 2.1.1 raw API):

```
xsct sw/create_vitis.tcl
```

builds `sw/vitis_ws/ofdm_video/Debug/ofdm_video.elf`. `xsct sw/run_jtag.tcl` loads bitstream + ELF over JTAG (UART1, 115200); `vivado -mode batch -source sw/ila_capture.tcl` dumps the receiver constellation to `ila_rx.csv`.

**Link test**: connect DAC_B to ADC_B with an SMA cable and a 10–20 dB attenuator. On the UART press `t` for the self-test; the 1 s status line shows the payload rate, CRC errors and lost packets. `1` / `2` / `4` select BPSK / QPSK / 16-QAM, `+` / `-` move the carrier, `s` prints the PL counters.

**Video**: PC on `192.168.1.x`, board is `192.168.1.10`. Install [ffmpeg](https://ffmpeg.org/), then

```
pc\play.bat
pc\send_video.bat input.mp4 2M
```

(`pc\send_camera.bat "camera name"` for a webcam, `python pc\link_test.py --rate 8` for a UDP throughput test). If the firewall blocks ffplay, record with `python pcecv_ts.py rx.ts --relay 5002` and play `udp://127.0.0.1:5002`.

　

## Directory

| path | content |
| :--- | :------ |
| `rtl/ofdm_txs/` | strath-sdr `ofdm_tx` top levels with the external data port (generated from `ofdm_tx_v0_5`) |
| `rtl/ofdm_tx_stream.v` | AXI4-Stream bit source + `ofdm_txs` wrapper |
| `rtl/ofdm_rx_demap.v` | slicer, frame alignment, byte packer |
| `sim/` | xsim loopback testbench (`run_sim.bat`, `check_loop.py`) |
| `make_project.tcl` | block design, bitstream, XSA |
| `sw/src/` | bare-metal application |
| `pc/` | ffmpeg / ffplay scripts and UDP link test |

　

## Credits

* OFDM transceiver, interpolator and decimator: [strath-sdr/rfsoc_ofdm](https://github.com/strath-sdr/rfsoc_ofdm), BSD-3-Clause, University of Strathclyde.
* RFDC startup flow: Xilinx ZCU208 `dds_ila` example.
* Clock register values: PYNQ RFSoC4x2 `LMK04828_245.76` / `LMX2594_491.52`.

　

　

<span id="cn">RFSoC 4x2 OFDM 压缩视频传输</span>
===========================

在 RFSoC 4x2 上用 Strathclyde 的 [rfsoc_ofdm](https://github.com/strath-sdr/rfsoc_ofdm) 收发机传输压缩视频（H.264 / MPEG-TS）：**DAC_B（tile 228 ch0）→ SMA 环回 → ADC_B（tile 226 ch0）**，裸机运行，不依赖 PYNQ。

PC 通过 UDP 把视频流发给板卡，PS 封装成带 CRC 的链路包，PL 调制到 OFDM 载波上发射，接收到的包再发回 PC 播放。

　

| ![arch](./docs/arch.svg) |
| :----------------------: |
| **图1** : 数据通路        |

　

## 技术特点

* **在 strath-sdr PHY 上传用户数据**：原 HDL Coder 生成的 `ofdm_tx` 只能发 PRBS。`rtl/ofdm_txs/` 是同一个核，只把 PRBS 源换成外部符号端口，由 `ofdm_tx_stream` 从 AXI4-Stream FIFO 取数。`ofdm_rx` 原样使用，`ofdm_rx_demap` 对均衡后的子载波做硬判决（BPSK / QPSK / 16-QAM，比特映射与 TX 生成器一致）并打包成字节。
* **仿真确定的逐比特对齐**：TX 流水线在每个 48 子载波 OFDM 符号的第 45 个位置请求的数据永远发不出去，接收端在第 0 个位置重复一个符号，整体偏移 3 个符号。TX 比特源跳过该位置，RX 丢掉重复符号，每个 OFDM 帧正好承载 **5960 个数据符号**，三种调制下都字节对齐。
* **自同步字节流**：每个 OFDM 帧对应一个 DMA 包。链路包（`1A CF FC 1D`、长度、序号、载荷、CRC32）可以跨帧，丢一帧只丢该帧内的包。FIFO 空时填 PRBS 字，有无业务时频谱相同。
* **不依赖 PYNQ 的时钟配置**：LMK04828（245.76 MHz）和两片 LMX2594（491.52 MHz）通过 PS SPI0 配置（`LMK_LMX.c`），不同于 ZCU208 CLK104 的 I2C 转 SPI。两个 tile 都用内部 PLL，3.93216 GSPS，8 倍插值/抽取，fabric 时钟 245.76 MHz，载波 600 MHz（可运行时修改）。
* **调试**：System ILA 抓接收符号和解映射输出；AXI-Lite 可读 TX/RX 帧和符号计数；串口自测模式把链路跑满并逐字节校验载荷。

　

## 性能结果

| 调制 | 每 OFDM 帧载荷 | 链路载荷速率 |
| :--: | :------------: | :----------: |
| BPSK | 745 B | 5.9 Mb/s |
| QPSK | 1490 B | 11.8 Mb/s |
| 16-QAM | 2980 B | 23.7 Mb/s |

OFDM 帧：320 点前导 + 127 个数据符号 + 等长空闲，共 20640 点，20.48 MSPS 下 1.008 ms。

**仿真**（`sim/`，基带 TX 核直连 RX 核，随机载荷）：BPSK、QPSK、16-QAM 下每一帧收到的字节都与发送字节流一致，从第一帧起连续。

**实现**（Vivado 2020.2，XCZU48DR-2，含 ILA）：27.1 k LUT（6.4 %）、40.5 k FF（4.8 %）、41 BRAM、191 DSP，时序全部满足（WNS +0.251 ns），bitstream + XSA 约 15 分钟。

**上板结果**（DAC_B → SMA 线 → ADC_B，载波 600 MHz，串口自测，1316 字节包）：

| 调制 | 实测载荷速率 | CRC 错误 |
| :--: | :----------: | :------: |
| BPSK | 5.86 Mb/s | 0 / 5 000 包 |
| QPSK | 11.71 Mb/s | 0 / 15 000 包 |
| 16-QAM | 23.44 Mb/s | 1 / 20 000 包 |

运行时切换调制只丢一两个包。

**端到端**（PC → UDP → 板卡 → OFDM → 板卡 → UDP → PC，`pc/link_test.py`）：吞吐饱和于 **5.98 / 11.83 / 23.55 Mb/s**（BPSK / QPSK / 16-QAM），未饱和时丢包 0.01–0.04 %；超出部分在板卡 TX 队列丢弃，不会出错包。94 万包累计 CRC 错误率 1.6 × 10⁻⁴（含调制切换）。20 秒 720p H.264 2 Mb/s 视频（QPSK）：600 帧解出 593 帧，平均 PSNR 40.2 dB，无错帧与源逐比特一致。上电后如果出现周期性误码突发，重新加载一次设计即可（LMK PLL1 稳定问题）。

　

## 使用方法

**硬件**（Vivado 2020.2，已安装 RFSoC 4x2 board files）：

```
cd boards/RFSoC4x2/ofdm_video
vivado -mode batch -source make_project.tcl -tclargs build
```

生成 `design_1_wrapper.xsa`（含 bitstream）。

**软件**（Vitis 2020.2，standalone + lwIP 2.1.1 raw API）：

```
xsct sw/create_vitis.tcl
```

生成 `sw/vitis_ws/ofdm_video/Debug/ofdm_video.elf`。`xsct sw/run_jtag.tcl` 通过 JTAG 下载 bitstream 和 ELF（UART1，115200）；`vivado -mode batch -source sw/ila_capture.tcl` 把接收星座点导出到 `ila_rx.csv`。

**链路测试**：DAC_B 通过 SMA 线和 10–20 dB 衰减器接 ADC_B。串口按 `t` 进入自测，每秒状态行显示载荷速率、CRC 错误和丢包。`1` / `2` / `4` 切换 BPSK / QPSK / 16-QAM，`+` / `-` 调载波，`s` 打印 PL 计数器。

**视频**：PC 设为 `192.168.1.x`，板卡是 `192.168.1.10`。安装 [ffmpeg](https://ffmpeg.org/) 后运行

```
pc\play.bat
pc\send_video.bat input.mp4 2M
```

（摄像头用 `pc\send_camera.bat "摄像头名"`，UDP 吞吐测试用 `python pc\link_test.py --rate 8`）。防火墙拦 ffplay 时，可用 `python pcecv_ts.py rx.ts --relay 5002` 录制并转发，再播放 `udp://127.0.0.1:5002`。

　

## 目录

| 路径 | 内容 |
| :--- | :--- |
| `rtl/ofdm_txs/` | 带外部数据口的 strath-sdr `ofdm_tx` 顶层（由 `ofdm_tx_v0_5` 生成） |
| `rtl/ofdm_tx_stream.v` | AXI4-Stream 比特源 + `ofdm_txs` 封装 |
| `rtl/ofdm_rx_demap.v` | 判决、帧对齐、字节打包 |
| `sim/` | xsim 环回仿真（`run_sim.bat`、`check_loop.py`） |
| `make_project.tcl` | block design、bitstream、XSA |
| `sw/src/` | 裸机程序 |
| `pc/` | ffmpeg / ffplay 脚本和 UDP 链路测试 |

　

## 致谢

* OFDM 收发机、插值器、抽取器：[strath-sdr/rfsoc_ofdm](https://github.com/strath-sdr/rfsoc_ofdm)，BSD-3-Clause，University of Strathclyde。
* RFDC 启动流程：Xilinx ZCU208 `dds_ila` 例程。
* 时钟寄存器值：PYNQ RFSoC4x2 `LMK04828_245.76` / `LMX2594_491.52`。

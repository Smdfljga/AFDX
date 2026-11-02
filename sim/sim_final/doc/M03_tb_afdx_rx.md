# M03 tb_afdx_rx —— afdx_rx 接收链路波形观察

- **类别**：单独模块仿真（**纯波形用例，不做自检**）
- **源文件**：`tb_afdx_rx.v`
- **DUT**：`afdx_rx`

## 1. 这个仿真在测什么

把 `afdx_rx` 单独拉出来，注入一整帧合法 AFDX 报文，方便你**用波形看清接收解析全过程**：
从 `ff_rx_*` 字节流进来，到帧头解析（DA/SA/类型/IP/UDP）、长度校验、CRC 校验、
提交到应用端口 `port_wr_*`，以及 MIB 计数脉冲。

它不打印 PASS/FAIL，靠人看波形；套件里它只要跑到 `$finish` 且无 Error 就算通过。

## 2. 激励怎么造的

- `clk` 10 ns（100MHz 仿真节奏，与实机 25MHz 不影响功能判读）；
- VLID = `0x0001`，UDP 目的端口 = `0x0BB8`(3000)，应用数据 32 字节；
- TB 内部用 `cfg_mem`/`st_mem` 数组当 VL 配置表和状态表（同步读，1 拍出数据），
  预先填好这条 VL 的 tag/端口类型/UDP 端口/BAG/Lmax/RM/IC 使能；
- `port_wr_full` 置 0（端口缓冲永远有空位），`rx_ready_*` 按端口类型放行；
- 按字节推 `ff_rx_data` 并在首尾字节给 `ff_rx_sop`/`ff_rx_eop`，`ff_rx_err` 恒 0。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {MAC 字节流}
add wave -noupdate -radix hex /tb_afdx_rx/ff_rx_data
add wave -noupdate /tb_afdx_rx/ff_rx_data_vld
add wave -noupdate /tb_afdx_rx/ff_rx_sop
add wave -noupdate /tb_afdx_rx/ff_rx_eop
add wave -noupdate /tb_afdx_rx/ff_rx_err
add wave -noupdate -divider {内部解析计数}
add wave -noupdate /tb_afdx_rx/dut/state
add wave -noupdate -radix unsigned /tb_afdx_rx/dut/da_cnt
add wave -noupdate -radix unsigned /tb_afdx_rx/dut/ip_cnt
add wave -noupdate -radix unsigned /tb_afdx_rx/dut/udp_cnt
add wave -noupdate -radix unsigned /tb_afdx_rx/dut/pay_cnt
add wave -noupdate /tb_afdx_rx/dut/sn_r
add wave -noupdate -divider {提交到端口与 MIB}
add wave -noupdate /tb_afdx_rx/port_wr_en
add wave -noupdate -radix hex /tb_afdx_rx/port_wr_vl_index
add wave -noupdate -radix unsigned /tb_afdx_rx/port_wr_byte_offset
add wave -noupdate -radix hex /tb_afdx_rx/port_wr_data
add wave -noupdate /tb_afdx_rx/port_wr_frame_done
add wave -noupdate /tb_afdx_rx/mib_rx_frame_inc
add wave -noupdate /tb_afdx_rx/mib_rx_byte_inc
add wave -noupdate /tb_afdx_rx/irq_rx_frame
```

## 4. 波形上应该看到什么

1. `ff_rx_sop` 一拍高之后，`dut/state` 依次走过“找 DA → 找 SA → 类型 → IP → UDP → 载荷”几个状态；
2. `da_cnt`/`ip_cnt`/`udp_cnt`/`pay_cnt` 依次递增，`pay_cnt` 数到 32 结束；
3. 校验通过后 `port_wr_en` 在载荷期间连续为高，`port_wr_byte_offset` 从 0 递增，
   `port_wr_data` 就是应用载荷字节；
4. `ff_rx_eop` 那拍出现 `port_wr_frame_done` 单拍脉冲，同时 `mib_rx_frame_inc` 脉冲；
5. `sn_r` 等于帧里那个 SN 字节（用于 IC 判据），`irq_rx_frame` 打一个中断脉冲；
6. 全程 `ff_rx_rdy` 为 1（RX 永远跟得上 MAC 的字节流）。

反过来看：如果帧头不对/长度不符，`state` 会提前回空闲，`port_wr_frame_done` 不出现，
而 `mib_rx_error_inc` / `irq_error` 会有脉冲——这就是“丢弃”的样子。

## 5. 判据

跑到 `$finish`、日志无 `Error`/`Fatal`（本用例不打印 PASS）。

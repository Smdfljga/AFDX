# tb_afdx_tx —— afdx_tx 发送链路波形观察

- **类别**：单独模块仿真（**纯波形用例，不做自检**）
- **源文件**：`tb_afdx_tx.v`
- **DUT**：`afdx_tx`

## 1. 这个仿真在测什么

把 `afdx_tx` 单独拉出来，给它一帧待发数据，看清**发送组帧全过程**：
读端口缓冲 → 拼以太网头/IP 头/UDP 头 → 填 SN → 算 IP 校验和 → 不足最小帧长补 0 →
`ff_tx_*` 逐字节吐出并等待 MAC 的 `ff_tx_rdy`。

TB 内部用简单 RAM + 长度寄存器**代替 tx_port_buf**，所以波形里能清楚看到
`port_rd_*`（缓冲读）与 `ff_tx_*`（MAC 写）两条流的关系。

## 2. 激励怎么造的

- `clk` 10 ns；VLID = `0x0004`（低 4 位映射到槽位 4），UDP 目的端口 `0x4001`，32 字节待发；
- TB 内 `payload_mem` / `tx_len_mem` 就是“端口缓冲”，同步读 1 拍出数据；
- 配置表 `cfg_mem`、状态表 `st_mem` 预填好这条 VL（BAG=1、Lmax=512、RM 关闭）；
- `sys_ts` 递增模拟系统时间戳；
- 应用侧 `tx_valid_app` 拉一个脉冲触发发送，`ff_tx_rdy` 常置 1 让字节尽快出。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {触发与缓冲读}
add wave -noupdate /tb_afdx_tx/tx_valid_app
add wave -noupdate -radix hex /tb_afdx_tx/slot_vlid
add wave -noupdate /tb_afdx_tx/port_rd_en
add wave -noupdate -radix unsigned /tb_afdx_tx/port_rd_byte_offset
add wave -noupdate -radix hex /tb_afdx_tx/port_rd_data
add wave -noupdate /tb_afdx_tx/port_rd_valid
add wave -noupdate -divider {组帧状态}
add wave -noupdate /tb_afdx_tx/dut/state
add wave -noupdate -radix unsigned /tb_afdx_tx/dut/sn_r
add wave -noupdate -radix unsigned /tb_afdx_tx/dut/ip_id_cnt
add wave -noupdate -radix unsigned /tb_afdx_tx/dut/wait_cnt
add wave -noupdate -radix unsigned /tb_afdx_tx/sys_ts
add wave -noupdate -divider {MAC 输出}
add wave -noupdate /tb_afdx_tx/ff_tx_wren
add wave -noupdate /tb_afdx_tx/ff_tx_sop
add wave -noupdate /tb_afdx_tx/ff_tx_eop
add wave -noupdate /tb_afdx_tx/ff_tx_err
add wave -noupdate -radix hex /tb_afdx_tx/ff_tx_data
add wave -noupdate /tb_afdx_tx/ff_tx_rdy
add wave -noupdate -divider {MIB 与中断}
add wave -noupdate /tb_afdx_tx/mib_tx_frame_inc
add wave -noupdate /tb_afdx_tx/mib_tx_byte_inc
add wave -noupdate /tb_afdx_tx/irq_tx_done
```

## 4. 波形上应该看到什么

1. `tx_valid_app` 脉冲后 1~2 拍出现 `port_rd_en`，`port_rd_data` 依次是 32 个载荷字节；
2. `ff_tx_sop` 高起那一帧，前 14 个字节是 **DA(6) + SA(6) + 类型 0800**；
   接着 IPv4 头（版本/IHL=45、TOS、总长、标识递增、TTL、协议 11=UDP、**校验和**）、
   UDP 头（源端口、目的端口 0x4001、长度）、然后载荷；
3. **SN 字节在载荷之后**（`afdx_tx.v` 里 `tx_byte_pos == 42 + data_len` 才输出 `sn_r`），
   位置是字节 `42 + 补齐后载荷长度`；本实现把 SN 当“UDP 载荷的最后一个字节”，
   接收侧 `afdx_rx` 也按这个约定解析（这一点与 ARINC 664 原文“SN 在载荷首位”不同，需与对端协议对齐）；
4. `port_rd_byte_offset` 数到 31 后停止，`ff_tx_data` 之后出现 **0x00 填充**
   直到整帧达到最小帧长（18 字节载荷以下都要补）；
5. `ff_tx_eop` 那拍后 1~2 拍 `mib_tx_frame_inc` 脉冲、`irq_tx_done` 脉冲；
6. 若把 `ff_tx_rdy` 拉低，`ff_tx_wren` 立刻停住但**数据字节不丢**（`ff_tx_data` 保持），
   拉高后从原字节继续——这是等 MAC 的握手行为。

## 5. 判据

跑到 `$finish`，日志里 `TX captured bytes: N` 非 0，无 `Error`/`Fatal`（不打印 PASS）。

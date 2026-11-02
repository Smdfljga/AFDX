# M02 tb_afdx_rxtx —— RX/TX 端到端（AFDX_top 级）

- **类别**：单独模块仿真（DUT = `AFDX_top`，收发两条链路一起走）
- **源文件**：`tb_afdx_rxtx.v`
- **DUT**：`AFDX_top`

## 1. 这个仿真在测什么

一条 VL（`VLID = 0x0004`、17 字节应用数据）把两个方向都打通：

1. **收**：MAC 侧注入一帧 17 字节 AFDX 报文，应用端口读回来的数据必须是应用载荷
   （**不含 SN 字节**，SN 是 AFDX 层加的）；
2. **发**：应用写 17 字节到槽位 4 并触发 `app_tx_req`，MAC 输出帧必须带正确帧头、
   正确的 SN、并且载荷不足最小帧长时补填充。

## 2. 激励怎么造的

- `clk_sys` 40 ns，复位后先写 VL 配置（含 UDP 端口、Lmax、BAG），等 `cfg_done`；
- 收方向：用 `send_frame` 类任务按字节推 `ff_rx_data/ff_rx_data_vld/ff_rx_sop/ff_rx_eop`，
  帧头按要求拼（DA/SA/IP/UDP），随后用 `app_rd_*` 逐字节读回比对；
- 发方向：`app_wr_en` 逐字节写 17 字节到槽位 4，然后拉 `app_tx_req` 等 `app_wr_gnt`，
  在 `ff_tx_*` 上逐字节抓输出帧做断言。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {时钟/配置}
add wave -noupdate /tb_afdx_rxtx/clk_sys
add wave -noupdate /tb_afdx_rxtx/rst_b
add wave -noupdate /tb_afdx_rxtx/cfg_done
add wave -noupdate -divider {接收方向}
add wave -noupdate -radix hex /tb_afdx_rxtx/ff_rx_data
add wave -noupdate /tb_afdx_rxtx/ff_rx_data_vld
add wave -noupdate /tb_afdx_rxtx/ff_rx_sop
add wave -noupdate /tb_afdx_rxtx/ff_rx_eop
add wave -noupdate -radix hex /tb_afdx_rxtx/app_rd_vl_index
add wave -noupdate -radix unsigned /tb_afdx_rxtx/app_rd_byte_offset
add wave -noupdate -radix hex /tb_afdx_rxtx/app_rd_data
add wave -noupdate /tb_afdx_rxtx/app_rd_valid
add wave -noupdate -divider {发送方向}
add wave -noupdate /tb_afdx_rxtx/app_tx_req
add wave -noupdate /tb_afdx_rxtx/app_wr_gnt
add wave -noupdate -radix hex /tb_afdx_rxtx/ff_tx_data
add wave -noupdate /tb_afdx_rxtx/ff_tx_wren
add wave -noupdate /tb_afdx_rxtx/ff_tx_sop
add wave -noupdate /tb_afdx_rxtx/ff_tx_eop
add wave -r /tb_afdx_rxtx/dut/*
```

## 4. 波形上应该看到什么

**接收侧**

| 观察点 | 期望现象 |
|---|---|
| `ff_rx_data_vld` | 注入期间连续为高，`ff_rx_sop` 只在首字节高、`ff_rx_eop` 只在末字节高 |
| 应用读回 | `app_rd_valid` 每字节一个脉冲，`app_rd_frame_len` = 17 |
| 载荷内容 | 逐字节等于注入的应用数据；**SN 那一个字节不出现在应用侧** |

**发送侧**

| 观察点 | 期望现象 |
|---|---|
| `app_wr_gnt` | 写 17 字节期间为高，写完 1~2 拍后 `app_tx_req` 可撤 |
| `ff_tx_sop` 到 `ff_tx_eop` | 一帧完整输出；前导码 **不计入** `ff_tx_*`（IP 内部补） |
| 帧内容 | DA/SA/类型 0800 + IPv4 头 + UDP 头，SN 从 0 开始；末尾有 0x00 填充到最小帧长 |
| `ff_tx_rdy` | 常置 1 时应能连续出字节（1 拍 1 字节） |

## 5. 通过判据

日志出现 `[PASS] RX 17B payload`、`[PASS] TX frame assembly`，且 `result: 0 failures`。

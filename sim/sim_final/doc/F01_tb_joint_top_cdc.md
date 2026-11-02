# F01 tb_joint_top_cdc —— 顶层收发胶合缓冲（MAC 侧 ↔ 核心侧）

- **类别**：全链路仿真（**接口级**，DUT = `afdx_net_rx` + `afdx_tx_buf` 一起）
- **源文件**：`tb_joint_top_cdc.v`
- **DUT**：`afdx_net_rx`（收）+ `afdx_tx_buf`（发）

## 1. 这个仿真在测什么

板级顶层把“MAC 字节流”和“AFDX 核心字节流”接起来的那对缓冲，两个方向都测：

1. **收方向**：两片 MAC 各 3 帧经 `afdx_net_rx` 的帧缓存送核心，逐字节正确、帧长/帧首帧尾正确、
   两网轮流不丢帧；
2. **发方向**：核心写 3 帧进 `afdx_tx_buf`，MAC 侧逐字节收，**MAC 帧内反压**（`mac_tx_rdy` 拉低）
   时一个字节都不能丢、也不能卡死；
3. 两路时钟独立（本 TB 用 MAC 125MHz / 核心 25MHz 的**异步极端情况**；
   当前 `top.v` 把两侧都接成 25MHz，同频只是这条用例的子集）。

## 2. 激励怎么造的

- `clk_mac` 8ns、`clk_core` 40ns；
- `mac_send(net, base, 64)` 在 MAC 时钟域推 `a_rx_*` / `b_rx_*`；
- `core_send(base, 64)` 在核心时钟域推 `core_tx_*`，每字节等 `core_tx_rdy`；
- 发方向的背压用 fork 实现：**等第一个字节真的开始往 MAC 送（`mac_tx_wren` 拉高）**后，
  再在帧中间拉低 `mac_tx_rdy` 37 拍，放开 11 拍，再拉低 23 拍；
- 收/发两个方向都有逐字节比对（`base + 序号`），并检查帧长 = 64。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {双时钟}
add wave -noupdate /tb_joint_top_cdc/clk_mac
add wave -noupdate /tb_joint_top_cdc/clk_core
add wave -noupdate /tb_joint_top_cdc/rst_b
add wave -noupdate -divider {收：MAC -> 核心}
add wave -noupdate /tb_joint_top_cdc/a_rx_data_vld
add wave -noupdate -radix hex /tb_joint_top_cdc/a_rx_data
add wave -noupdate /tb_joint_top_cdc/a_rx_sop
add wave -noupdate /tb_joint_top_cdc/a_rx_eop
add wave -noupdate /tb_joint_top_cdc/ff_rx_rdy
add wave -noupdate /tb_joint_top_cdc/ff_rx_data_vld
add wave -noupdate -radix hex /tb_joint_top_cdc/ff_rx_data
add wave -noupdate /tb_joint_top_cdc/ff_rx_sop
add wave -noupdate /tb_joint_top_cdc/ff_rx_eop
add wave -noupdate /tb_joint_top_cdc/frame_net
add wave -noupdate -divider {发：核心 -> MAC}
add wave -noupdate /tb_joint_top_cdc/core_tx_rdy
add wave -noupdate /tb_joint_top_cdc/core_tx_wren
add wave -noupdate -radix hex /tb_joint_top_cdc/core_tx_data
add wave -noupdate /tb_joint_top_cdc/mac_tx_rdy
add wave -noupdate /tb_joint_top_cdc/mac_tx_wren
add wave -noupdate -radix hex /tb_joint_top_cdc/mac_tx_data
add wave -noupdate /tb_joint_top_cdc/mac_tx_sop
add wave -noupdate /tb_joint_top_cdc/mac_tx_eop
add wave -noupdate -divider {内部(收)}
add wave -noupdate /tb_joint_top_cdc/dut/state
add wave -noupdate /tb_joint_top_cdc/dut/pick_slot
add wave -noupdate -radix binary /tb_joint_top_cdc/dut/a_avail_slot
add wave -noupdate -radix binary /tb_joint_top_cdc/dut/b_avail_slot
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| 收方向 | `a_rx_*` 写满一帧后，跨到核心时钟域才出现 `ff_rx_data_vld`（能看到 2~3 拍同步延迟） |
| `frame_net` | A 网帧 0、B 网帧 1，与激励一致 |
| 收方向字节 | `ff_rx_data` 从 base 起逐字节 +1，`sop`/`eop` 只在首/末拍 |
| `mac_tx_rdy` 拉低期间 | `mac_tx_wren` 立刻为 0，`mac_tx_data` **保持当前字节**（不丢、不重复） |
| 放开后 | 从被挡住的字节继续，帧尾 `mac_tx_eop` 正常出现，帧长仍是 64 |
| `core_tx_rdy` | 缓冲还有空槽时为 1；写完两帧占满两槽时短暂变 0（核心自然等待） |

## 5. 通过判据

日志出现 `[PASS] rx 3 frames across clock`、`[PASS] tx 3 frames across clock`，
末尾 `PASS: joint top cdc chain`。

# tb_joint_dualnet —— 双网胶合全链路（afdx_net_rx + AFDX_top）

- **类别**：全链路仿真（DUT = `afdx_net_rx` + `AFDX_top` 串起来）
- **源文件**：`tb_joint_dualnet.v`
- **DUT**：`afdx_net_rx`（双网胶合）+ `AFDX_top`（端系统核心）

## 1. 这个仿真在测什么

板级顶层的**双网拓扑**在端系统里的实际效果，五组用例：

1. A 网单帧 → 提交应用，`frame_net = 0`；
2. B 网单帧 → 提交应用，`frame_net = 1`；
3. **A/B 同帧副本**（同 VL、同 SN，两张网各来一份）→ RM 使能时只收一份，另一份计 `rm_drop`；
4. **A/B 不同 SN** → 两帧都收（不是副本）；
5. 应用发送 → 经核心组帧后从 `core_tx_*` 输出（发方向链路在胶合层也通）。

## 2. 激励怎么造的

- `clk` 40 ns；先配 VL（含 RM 使能），等 `cfg_done`；
- `build_frame` 生成报文，`inject(net, ...)` 把字节流推到 `a_rx_*` 或 `b_rx_*`
  （经 `afdx_net_rx` 才进核心），`core_frame_net` 由胶合层给出；
- 用例 3 用完全相同的 SN 在两网各注入一次；用例 4 让 SN 不同；
- 发方向：应用写 17 字节 + `app_tx_req`，`core_tx_rdy` 常置 1，收集 `core_tx_*` 字节到 `tx_mem`。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {A/B 网注入}
add wave -noupdate /tb_joint_dualnet/a_rx_data_vld
add wave -noupdate -radix hex /tb_joint_dualnet/a_rx_data
add wave -noupdate /tb_joint_dualnet/b_rx_data_vld
add wave -noupdate -radix hex /tb_joint_dualnet/b_rx_data
add wave -noupdate -divider {胶合输出(进核心)}
add wave -noupdate /tb_joint_dualnet/core_rx_data_vld
add wave -noupdate -radix hex /tb_joint_dualnet/core_rx_data
add wave -noupdate /tb_joint_dualnet/core_rx_sop
add wave -noupdate /tb_joint_dualnet/core_rx_eop
add wave -noupdate /tb_joint_dualnet/core_frame_net
add wave -noupdate -divider {应用侧}
add wave -noupdate /tb_joint_dualnet/app_rd_valid
add wave -noupdate -radix hex /tb_joint_dualnet/app_rd_data
add wave -noupdate -radix unsigned /tb_joint_dualnet/app_rd_frame_len
add wave -noupdate /tb_joint_dualnet/irq_error
add wave -noupdate -divider {发方向}
add wave -noupdate /tb_joint_dualnet/core_tx_wren
add wave -noupdate -radix hex /tb_joint_dualnet/core_tx_data
add wave -noupdate /tb_joint_dualnet/core_tx_sop
add wave -noupdate /tb_joint_dualnet/core_tx_eop
add wave -noupdate -radix hex /tb_joint_dualnet/tx_mem
```

## 4. 波形上应该看到什么

| 用例 | 波形特征 |
|---|---|
| A 网单帧 | `core_frame_net = 0`，应用读回一帧 |
| B 网单帧 | `core_frame_net = 1`，应用读回一帧 |
| A/B 同帧副本 | **只出现一次** `app_rd_frame_len` 有效 / 提交；`irq_error` 或 `rm_drop` 计数出现一次 |
| A/B 不同 SN | 两次提交，帧内容不同 |
| 发方向 | `core_tx_sop...eop` 一帧，帧头与载荷正确 |
| 胶合层选路 | 两网同时有待读帧时，`afdx_net_rx` 按上一次服务记录轮转（`core_frame_net` 交替） |

## 5. 通过判据

五组 `[PASS]` 全部出现，末尾 `PASS: joint dualnet chain`。

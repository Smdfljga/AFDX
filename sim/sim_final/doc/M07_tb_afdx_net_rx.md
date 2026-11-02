# M07 tb_afdx_net_rx —— 双网接收帧缓存（跨时钟 + 槽位乒乓 + 满槽丢帧）

- **类别**：单独模块仿真（**自检**，DUT = `afdx_net_rx`）
- **源文件**：`tb_afdx_net_rx.v`
- **DUT**：`afdx_net_rx`（内含两片 `rx_frame_buf` 和两个 `afdx_net_rx_wr`）

## 1. 这个仿真在测什么

板级顶层的“双网胶合”前半段，六个检查点：

1. 两网帧都能独立进缓存，并带出正确的 `frame_net`；
2. 核心没就绪（`ff_rx_rdy = 0`）时**一个字节都不送**；
3. 每张网 2 个 2KB 槽位**乒乓**使用（槽 0 读完切槽 1）；
4. 两槽都占满时第 3 帧**整帧丢弃**，且不破坏已有帧；
5. 丢弃后槽位能重新投入使用；
6. MAC 侧 `a_rx_rdy`/`b_rx_rdy` 恒为 1（整帧入缓存，不反压 MAC）。

**双时钟**：MAC 侧 125MHz（8ns）写，核心侧 25MHz（40ns）读，跨时钟只靠“每槽 1bit 翻转标志 + 两级同步”。

## 2. 激励怎么造的

- 两路时钟：`clk_mac` 8ns、`clk_core` 40ns，异步；
- `mac_send(net, base, len)` 任务在 MAC 时钟域逐字节推 `a_rx_*` 或 `b_rx_*`，
  数据基值 `base` 递增，帧长 64 字节（`FRAME_LEN`）；
- 核心侧 `negedge clk_core` 采样 `ff_rx_*`，逐字节比对 `base + 序号`；
- 用例 1：`ff_rx_rdy = 0` 先灌 A、B 各一帧 → 检查 0 帧吐出；再放开 → 等 2 帧；
- 用例 2：`ff_rx_rdy = 0` 连灌 A 网三帧（0x20/0x30/0x40）→ 只该出 2 帧，第三帧被丢；
- 用例 3：再灌一帧 0x50 → 槽位应可复用，帧数到 5。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {双时钟}
add wave -noupdate /tb_afdx_net_rx/clk_mac
add wave -noupdate /tb_afdx_net_rx/clk_core
add wave -noupdate /tb_afdx_net_rx/rst_b
add wave -noupdate -divider {A 网写入侧(125M)}
add wave -noupdate -radix hex /tb_afdx_net_rx/a_rx_data
add wave -noupdate /tb_afdx_net_rx/a_rx_data_vld
add wave -noupdate /tb_afdx_net_rx/a_rx_sop
add wave -noupdate /tb_afdx_net_rx/a_rx_eop
add wave -noupdate -radix binary /tb_afdx_net_rx/dut/a_wr_tog
add wave -noupdate -radix binary /tb_afdx_net_rx/dut/a_ack_tog
add wave -noupdate -divider {读侧选路(25M)}
add wave -noupdate /tb_afdx_net_rx/dut/state
add wave -noupdate /tb_afdx_net_rx/dut/net_sel
add wave -noupdate /tb_afdx_net_rx/dut/slot_sel
add wave -noupdate -radix binary /tb_afdx_net_rx/dut/a_rd_tog
add wave -noupdate -radix binary /tb_afdx_net_rx/dut/a_avail_slot
add wave -noupdate -radix unsigned /tb_afdx_net_rx/dut/cur_len
add wave -noupdate -divider {送给核心}
add wave -noupdate /tb_afdx_net_rx/ff_rx_rdy
add wave -noupdate /tb_afdx_net_rx/ff_rx_data_vld
add wave -noupdate -radix hex /tb_afdx_net_rx/ff_rx_data
add wave -noupdate /tb_afdx_net_rx/ff_rx_sop
add wave -noupdate /tb_afdx_net_rx/ff_rx_eop
add wave -noupdate /tb_afdx_net_rx/frame_net
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| 写侧 `a_wr_tog` | 每写完一整帧翻转一次对应槽位（00→01→10 交替） |
| `a_ack_tog` | 读侧读完整帧后翻转，再经两级同步回到写域，**比 `a_rd_tog` 晚 2~3 个 MAC 拍** |
| `a_avail_slot` | `a_wr_tog_d1 ^ a_rd_tog`，某位为 1 表示该槽有整帧待读 |
| 槽位乒乓 | 用例 2 里先读槽 0（`slot_sel=0`），读完后 `slot_sel` 变 1 接着读槽 1 |
| 满槽丢帧 | 第 3 帧期间写侧 `slot_free0/1` 都为 0 → 整帧丢弃，**`a_wr_tog` 不翻转** |
| `ff_rx_rdy = 0` | `ff_rx_data_vld` 全程为 0，读侧 `state` 停在空闲，一旦放开立刻按 `cur_len` 连发 |
| `frame_net` | A 网帧为 0、B 网帧为 1 |
| 帧内字节 | `ff_rx_data` 从 `base` 开始逐字节 +1，`ff_rx_sop` 只在首字节、`ff_rx_eop` 只在末字节 |

判读小技巧：把 `clk_mac` 与 `clk_core` 放一起看，能直观看到“写侧翻标志 → 两级同步 → 读侧见到”这三段延迟。

## 5. 通过判据

三组用例都打印 `[PASS]`，最后 `PASS: afdx_net_rx dual clock chain`。

# tb_joint_latency —— 时延与抖动（变长帧，客户口口径）

- **类别**：全链路仿真（**DUT = `AFDX_top`**，收发双向）
- **源文件**：`tb_joint_latency.v`
- **DUT**：`AFDX_top`

## 1. 这个仿真在测什么

把赛题“端到端时延 < 1–2 ms、抖动 ≤ 几十 µs”变成可打印的数字，并按老师口径测量：

- **时延口径**：统一用**客户口**（应用侧 ↔ MAC 客户接口 `ff_tx_*` / `ff_rx_*`）打点。
  老师的 GMII SFD→SFD 口径在 RTL 里观测不到（SFD 在 MAC IP 内部），
  两者差 MAC 内部 FIFO + 前导/SFD 串行化（约 0.1 µs 量级）。
- **抖动定义**：按老师确认的“**同一 VL 多帧端到端时延的最大值减小值**”，
  不再用“相邻帧间隔的极差”。
- **变长帧**：按老师要求覆盖最小帧、最大帧和两种中间帧长。

四组发送测量（25 MHz，1 拍 = 40 ns）：

| 组 | 帧长 | 说明 |
|---|---|---|
| 1 | 64 B（载荷 21） | 以太网最小帧 |
| 2 | 512 B（载荷 469） | 中间帧 |
| 3 | 1024 B（载荷 981） | 中间帧 |
| 4 | 1514 B（载荷 1471） | 本实现可发送的最大帧（payload 硬限 1471） |

接收侧另测 64 / 512 / 1024 / **1518** B（收侧允许到 1518，IP 总长 ≤1504）。

## 2. 激励怎么造的

- `clk_sys` 40 ns，全局拍计数 `cyc`；
- 配一条应用 VL（`VLID=0x0004`、UDP 4000、队列端口、**BAG = 1 ms**）；
- **每组测前先等 `BAG + 2000` 拍**，让 BAG 窗口过期，这样量到的是**纯处理时延**（不含整形等待）；
- 每组用同一 VL 连发 4 帧（`send_frame(vl, plen, expected_frames)`），
  打点：`app_wr_gnt && app_wr_off==0` → `t_app0`；`ff_tx_eop` → `t_wire`；`ff_tx_sop` → `t_sop`；
- 抖动 = 这 4 帧时延的 `max − min`；
- 另有一组**专门演示带 BAG 等待**的时延（连发两帧，第二帧要等 1 ms），说明 BAG 等待不计入 2 ms 指标；
- 接收侧：`build_frame` 造帧 → `inject_frame` 注入 → 应用读第一个字节打点 `t_rx_app`
  （用 `rx_pending` 标志保证只记本帧），随后 `drain_app` 把整帧读空出队。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {计时基}
add wave -noupdate -radix unsigned /tb_joint_latency/cyc
add wave -noupdate -divider {发送打点}
add wave -noupdate /tb_joint_latency/app_wr_en
add wave -noupdate /tb_joint_latency/app_wr_gnt
add wave -noupdate -radix unsigned /tb_joint_latency/app_wr_off
add wave -noupdate /tb_joint_latency/app_tx_req
add wave -noupdate /tb_joint_latency/ff_tx_sop
add wave -noupdate /tb_joint_latency/ff_tx_eop
add wave -noupdate -radix unsigned /tb_joint_latency/t_app0
add wave -noupdate -radix unsigned /tb_joint_latency/t_wire
add wave -noupdate -radix unsigned /tb_joint_latency/lat_tx
add wave -noupdate -divider {BAG 整形内部}
add wave -noupdate /tb_joint_latency/dut/u_afdx/u_afdx_tx/state
add wave -noupdate -radix unsigned /tb_joint_latency/dut/u_afdx/u_afdx_tx/wait_cnt
add wave -noupdate -radix unsigned /tb_joint_latency/dut/u_afdx/sys_ts
add wave -noupdate -divider {接收打点}
add wave -noupdate /tb_joint_latency/rx_data_vld
add wave -noupdate /tb_joint_latency/rx_eop
add wave -noupdate /tb_joint_latency/app_rd_valid
add wave -noupdate -radix unsigned /tb_joint_latency/t_rx_eop
add wave -noupdate -radix unsigned /tb_joint_latency/t_rx_app
```

## 4. 波形上应该看到什么 + 实测结果

| 帧长 | 波形特征 | 实测时延 | 抖动 |
|---|---|---|---|
| 64 B | `app_wr_gnt` 首字节到 `ff_tx_eop` 约 120 拍 | **123 拍 = 4.92 µs** | 0 |
| 512 B | 约 1000 拍 | **1019 拍 = 40.76 µs** | 0 |
| 1024 B | 约 2000 拍 | **2043 拍 = 81.72 µs** | 0 |
| 1514 B | 约 3000 拍 | **3023 拍 = 120.92 µs** | 0 |

- 抖动：每组 4 帧时延完全一致 → **max−min = 0 拍 = 0.0 µs**（远优于“几十 µs”）。
- 带 BAG 等待那一组：第 2 帧时延 **24986 拍 = 999.44 µs**，这是 BAG 整形等待，
  按老师口径**不计入 2 ms 单帧指标**（日志单独打印，方便写报告时区分）。
- 线上帧长检查：`ff_tx` 上实际帧长 64 / 512 / 1024 / 1514 字节，与配置一致。
- 接收侧：4 种帧长的 `rx_eop → app_rd_valid` 都是 **203 拍 = 8.12 µs**
  （帧尾到应用首字节，因打点都在帧尾之后，所以不随帧长变化）。

判读要点：把 `app_wr_gnt`（首字节）与 `ff_tx_eop`（末字节）两个光标一卡，差值就是“单帧处理时延”；
`wait_cnt` 递增说明这帧在等 BAG，此时量到的是整形等待而不是处理时延。

## 5. 通过判据

每组都出现 `[PASS] tx latency ... <= 2ms` 与 `[PASS] tx jitter ... <= 100us`；
BAG 演示组 `[PASS] second frame waits for BAG as designed`；
接收侧 4 种帧长都 `[PASS] rx latency ... <= 200us`；末尾 `PASS: variable-length latency and jitter measured`。

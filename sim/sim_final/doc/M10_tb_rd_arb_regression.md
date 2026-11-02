# M10 tb_rd_arb_regression —— 接收读口仲裁（应用 / SNMP / 615A / RTC）

- **类别**：单独模块仿真（**自检**，DUT = `rx_rd_arb`）
- **源文件**：`tb_rd_arb_regression.v`
- **DUT**：`rx_rd_arb`

## 1. 这个仿真在测什么

接收缓冲只有**一个读口**，四个消费方（应用、SNMP、615A、RTC）要分享它。
这条用例验证固定优先级仲裁与握手：

1. 应用连续流水读（`app_req` 一直拉高）时，地址按 `app_offset` 每拍前进；
2. SNMP / 615A / RTC 三个协议代理同时发起读请求时会**轮到自己**读到数据；
3. 仲裁切换时 `buf_en`/`buf_vl`/`buf_offset` 不串台（不会把 A 代理的地址给 B 代理）。

## 2. 激励怎么造的

- `clk` 10 ns，复位后让应用先跑；
- `run_agents` 拉高后，三个代理各自在 `negedge clk` 上保持自己的 `*_offset` 并等 `*_valid`；
- TB 用 `ram_q` 模拟缓冲出数（数据 = 地址相关值，便于判断是谁在读）；
- `rd_data` / `buf_en` 被连续采样，出现不配对就记一次失败。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {应用读}
add wave -noupdate /tb_rd_arb_regression/app_req
add wave -noupdate -radix unsigned /tb_rd_arb_regression/app_offset
add wave -noupdate /tb_rd_arb_regression/app_valid
add wave -noupdate -divider {代理请求}
add wave -noupdate /tb_rd_arb_regression/run_agents
add wave -noupdate -radix unsigned /tb_rd_arb_regression/snmp_offset
add wave -noupdate -radix unsigned /tb_rd_arb_regression/dl_offset
add wave -noupdate -radix unsigned /tb_rd_arb_regression/rtc_offset
add wave -noupdate -divider {仲裁输出}
add wave -noupdate /tb_rd_arb_regression/buf_en
add wave -noupdate -radix hex /tb_rd_arb_regression/buf_vl
add wave -noupdate -radix unsigned /tb_rd_arb_regression/buf_offset
add wave -noupdate -radix hex /tb_rd_arb_regression/ram_q
add wave -noupdate -radix hex /tb_rd_arb_regression/rd_data
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| 应用单独跑 | `buf_en` 每拍为 1，`buf_offset` 每拍 +1（流水不中断） |
| 代理插入 | 应用让出一拍，`buf_en` 仍为 1 但 `buf_offset` 是**代理的地址**，下一拍回到应用地址 |
| 同一拍只选一个 | `buf_en=1` 时 `buf_offset` 只能来自一个源，不会出现两个源混用 |
| `rd_data` | 与 `buf_offset` 对应的 RAM 内容一致（`buf_en` 后 1 拍有效） |
| 优先级 | 应用优先级最低，代理请求期间应用会被插入等待，但**不丢请求** |

## 5. 通过判据

日志打印 `PASS ... checks=N failures=0`（`failures` 必须为 0）。

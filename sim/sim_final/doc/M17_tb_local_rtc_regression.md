# M17 tb_local_rtc_regression —— 25MHz 下的微秒计数与毫秒广播节拍

- **类别**：单独模块仿真（**自检**，DUT = `local_rtc`）
- **源文件**：`tb_local_rtc_regression.v`
- **DUT**：`local_rtc`

## 1. 这个仿真在测什么

AFDX 核心降到 25MHz 之后，本地时钟的分频系数从 125 改成 25，这条用例就是守这个：

1. **微秒计数**：25 拍 = 1 µs（1000 拍 = 40 µs）；
2. **毫秒广播节拍**：1 ms = 25000 拍，检查多个周期的**间隔精确**；
3. **同步校正**：`sync_en` 装载 `sync_value` 后，微秒计数和节拍相位都从头对齐；
4. **零周期关闭广播**：`sync_period_ms = 0` 时 `rtc_tick` 一个都不许出，但 µs 计数继续自由走；
5. **校正优先于广播**：同一拍既要广播又有校正时，必须校正生效且抑制广播。

## 2. 激励怎么造的

- `clk` 40 ns（25MHz，`always #20`）；
- `align_clock(v)` 任务：在 `negedge` 上给 `sync_value` + `sync_en` 脉冲，用接口装载而不是强改内部寄存器；
- `check_period(period_ms, repetitions)` 任务：设周期 → 对齐 → 逐拍观察 `rtc_tick`，
  每次脉冲检查与上一次的间隔是否正好 `period_ms × 25000` 拍，并核对
  `rtc_value` 是否等于 `period_ms × repetitions × 1000` µs；
- 用例覆盖：1ms×3、2ms×2、零周期跑 30000 拍（1200µs）、恢复 1ms×1、边界处同时校正。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {时钟与接口}
add wave -noupdate /tb_local_rtc_regression/clk
add wave -noupdate /tb_local_rtc_regression/rst_b
add wave -noupdate /tb_local_rtc_regression/sync_en
add wave -noupdate -radix hex /tb_local_rtc_regression/sync_value
add wave -noupdate -radix unsigned /tb_local_rtc_regression/sync_period_ms
add wave -noupdate -divider {输出}
add wave -noupdate -radix unsigned /tb_local_rtc_regression/rtc_value
add wave -noupdate /tb_local_rtc_regression/rtc_tick
add wave -noupdate -divider {内部分频}
add wave -noupdate -radix unsigned /tb_local_rtc_regression/dut/us_cnt
add wave -noupdate -radix unsigned /tb_local_rtc_regression/dut/ms_cnt
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| `us_cnt` | 0→24 循环，每到 24 归零并让 `rtc_value` +1（**25 拍一个微秒**） |
| `rtc_value` | 每 25 拍 +1；对齐后从装载值开始重新计数 |
| `rtc_tick` | `period_ms = 1` 时每 25000 拍一个单拍脉冲；`period_ms = 2` 时 50000 拍一个 |
| 零周期段 | `rtc_tick` **全程为 0**，而 `rtc_value` 照常每 25 拍 +1 |
| 同时校正那拍 | `sync_en` 为高时 `rtc_tick` 被抑制（波形上看到 tick 少了那一拍），`rtc_value` 直接跳到装载值 |

判读要点：把 `rtc_tick` 的相邻上升沿用光标量一下间距，25MHz 下应当正好是 25000 拍（1µs 标尺下 1ms）。

## 5. 通过判据

日志打印 `PASS: RTC real25MHz us counter, 1ms/2ms periods, correction and zero-period restart`。

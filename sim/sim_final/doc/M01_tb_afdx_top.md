# M01 tb_afdx_top —— 顶层最小冒烟（配置 + RTC 框架）

- **类别**：单独模块仿真（DUT = 顶层 `AFDX_top`，只做框架级检查）
- **源文件**：`tb_afdx_top.v`
- **DUT**：`AFDX_top`

## 1. 这个仿真在测什么

不跑业务数据，只确认三件最基础的事：

1. 工程能编译、时钟与复位正常（`rst_b` 释放后内部时序跑得起来）；
2. VL 配置写接口通顺：写若干条配置 + 一条哨兵数据后 `cfg_done` 会拉高；
3. `local_rtc` 在走时：注入 8 个时钟后 RTC 值应该只涨 8 µs（25MHz 下 1µs = 25 拍）；
4. 空闲时 `ff_tx_wren` 不应该有意外流量。

## 2. 激励怎么造的

- 时钟 `clk_sys` 周期 40 ns（25MHz），复位保持 10 拍后释放；
- 用 `cfg_write` 任务逐条写 VL 配置（地址/VLID/UDP 端口/端口类型/BAG/Lmax/RM/IC），
  最后写一条 `cfg_wr_vlid = 16'hFFFF` 的哨兵让状态机收尾；
- 复位释放后 `cfg_done` 必须为 1；
- 然后放跑 8 个时钟（`repeat(8) @(posedge clk_sys)`），比较 `local_rtc` 与初值 `rtc_t0` 的差；
- 全程 `ff_rx_*` 空闲、`ff_tx_rdy` 常置 1，观察是否出现 `ff_tx_wren`。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {时钟/复位}
add wave -noupdate /tb_afdx_top/clk_sys
add wave -noupdate /tb_afdx_top/rst_b
add wave -noupdate -divider {配置写}
add wave -noupdate -radix hex /tb_afdx_top/cfg_wr_addr
add wave -noupdate -radix hex /tb_afdx_top/cfg_wr_vlid
add wave -noupdate /tb_afdx_top/cfg_wr_en
add wave -noupdate /tb_afdx_top/cfg_done
add wave -noupdate -divider {RTC}
add wave -noupdate -radix unsigned /tb_afdx_top/local_rtc
add wave -noupdate /tb_afdx_top/rtc_sync_valid
add wave -noupdate -divider {空闲检查}
add wave -noupdate /tb_afdx_top/ff_tx_wren
add wave -noupdate -radix hex /tb_afdx_top/ff_tx_data
# 想看内部细节
add wave -r /tb_afdx_top/dut/*
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| `cfg_wr_en` | 每条配置出现一个宽度 1 拍的高脉冲，`cfg_wr_addr` 跟着跳 |
| `cfg_done` | 写完哨兵后 2~6 拍内拉高并保持；`cfg_done = 0` 之前下游不接受帧 |
| `local_rtc` | 每 25 个 `clk_sys` 涨 1（微秒计数）；总增量正好 8 |
| `ff_tx_wren` | 全程为 0（空闲不应有发送） |
| 复位期间 | 内部 `state` 停在空闲，`cfg_done=0`，无毛刺 |

判读要点：这条用例是“体检”，只要 `cfg_done` 按时拉高、RTC 每 25 拍 +1，就说明顶层连线与配置链路没接错。

## 5. 通过判据

日志末尾出现 `PASS: afdx_top smoke test`，且没有 `[FAIL]`。

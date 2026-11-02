# tb_joint_rtc —— RTC 主从全链路（两个端系统对接）

- **类别**：全链路仿真（**DUT = 两个 `AFDX_top` 实例**：主时钟 + 从时钟）
- **源文件**：`tb_joint_rtc.v`
- **DUT**：`AFDX_top`（`RTC_MASTER_MODE=1`）×1 + `AFDX_top`（`RTC_MASTER_MODE=0`）×1

## 1. 这个仿真在测什么

时间同步的完整闭环，用**两个真实端系统**互相喂数据：

1. **主模式广播**：主实例按 1 ms 周期在 RTC VL（槽位 3）上广播同步帧，
   载荷格式正确、周期精确（25MHz 下 1 ms = **25000 拍**）；
2. 主帧里的**延迟补偿字段 = 0**（主侧不填链路延迟）；
3. **从模式接收**：从实例收到同步帧 → 解析主时间戳与延迟 → `delay_comp` 补偿 →
   `rtc_sync_valid` 脉冲，`local_rtc` 被校正到 `主时间戳 + 延迟值`。

## 2. 激励怎么造的

- `clk` 40 ns，两个实例共用；
- 配置写同时广播给主从两个实例（同样的 VL 表）；
- 主实例不需要外部激励：它自己按 `RTC_SYNC_PERIOD=1ms` 广播，TB 只负责收字节
  （`m_tx_wren` 采样到 `tx_mem`，并记录每帧首字节的时钟序号 `tx_cyc[]`）；
- 从实例侧由 TB **注入一帧手工构造的同步报文**：
  主时间戳 `0x112233445566`、延迟补偿 `0x00000102`，
  用来验证 `rtc_sync_valid` 与 `local_rtc = master_ts + delay`（并允许少量走时误差）。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {时钟}
add wave -noupdate /tb_joint_rtc/clk
add wave -noupdate /tb_joint_rtc/rst_b
add wave -noupdate -divider {主实例广播(m_tx)}
add wave -noupdate /tb_joint_rtc/m_tx_wren
add wave -noupdate -radix hex /tb_joint_rtc/m_tx_data
add wave -noupdate /tb_joint_rtc/m_tx_sop
add wave -noupdate /tb_joint_rtc/m_tx_eop
add wave -noupdate -radix unsigned /tb_joint_rtc/tx_cyc[0]
add wave -noupdate -radix unsigned /tb_joint_rtc/tx_cyc[1]
add wave -noupdate -radix unsigned /tb_joint_rtc/m_local_rtc
add wave -noupdate -divider {从实例接收(s_rx)}
add wave -noupdate /tb_joint_rtc/s_rx_data_vld
add wave -noupdate -radix hex /tb_joint_rtc/s_rx_data
add wave -noupdate /tb_joint_rtc/s_rx_sop
add wave -noupdate /tb_joint_rtc/s_rx_eop
add wave -noupdate -divider {校正结果}
add wave -noupdate /tb_joint_rtc/s_local_rtc
add wave -noupdate /tb_joint_rtc/s_rtc_sync_valid
add wave -noupdate -radix hex /tb_joint_rtc/master_ts_exp
add wave -noupdate -radix hex /tb_joint_rtc/delay_exp
add wave -noupdate -divider {内部}
add wave -noupdate /tb_joint_rtc/dut_s/u_afdx/u_rtc_sync/u_local_rtc/us_cnt
add wave -noupdate /tb_joint_rtc/dut_s/u_afdx/u_rtc_sync/u_rtc_rx/state
add wave -noupdate /tb_joint_rtc/dut_m/u_afdx/u_rtc_sync/u_rtc_tx/state
add wave -noupdate -radix hex /tb_joint_rtc/tx_mem
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| `m_tx_sop` 周期 | 相邻两次 `m_tx_sop` 间隔 **25000 拍**（1 ms @25MHz）；日志也会打印实测值 |
| 主帧载荷 | 10 字节同步字段：主时间戳 + 延迟字段，**延迟字段为 0x00000000** |
| 从实例收到帧 | `s_rx_data_vld` 一串，帧尾后 `u_rtc_rx` 内部取出 `master_ts`/`delay` |
| `s_rtc_sync_valid` | 校正完成时**一个脉冲**，此后 `s_local_rtc` 被装载 |
| `s_local_rtc` 装载瞬间 | 从当前值**跳到** `0x112233445566 + 0x102`（波形上是明显的一次跳变） |
| 跳变后走时 | 之后每 25 拍 +1（微秒计数继续走） |
| `m_local_rtc` | 主实例自由走时，不受从实例影响 |

## 5. 通过判据

日志出现：
`[PASS] master frame sent`、`[PASS] master delay field = 0`、
`[PASS] master period ~1ms (25000 cycles)`、`[PASS] rtc_sync_valid`、`[PASS] local_rtc corrected`，
末尾 `PASS: joint rtc chain`。

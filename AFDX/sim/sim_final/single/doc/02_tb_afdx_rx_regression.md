# tb_afdx_rx_regression —— afdx_rx 完整性检查(IC)/冗余管理(RM) 自检

- **类别**：单独模块仿真（**自检**，DUT = `afdx_rx` + `vl_state_ram`）
- **源文件**：`tb_afdx_rx_regression.v`
- **DUT**：`afdx_rx`（配 `vl_state_ram` 当 PSN/状态表）

## 1. 这个仿真在测什么

AFDX 接收侧最关键的两套判据，按序列号行为分四组用例：

| 用例 | 测什么 |
|---|---|
| 1 `SN = 0/1/1/5/6` | 首帧接受 → 正常递增接受 → **同网重复丢弃** → **SN 跳跃丢弃并重同步 PSN** → 重同步后下一帧恢复正常 |
| 2 `SN = 255 → 1` | 序列号在 8 位环上**回绕**的判据（255 的下一帧应是 1） |
| 3 非首帧收到 `SN = 0` | 判为非法并丢弃，**且不更新 PSN** |
| 4 跨网副本（`frame_net` 不同） | RM 使能时计 `rm_drop_count`，**不重复提交**；载荷不发给应用 |

另外这条用例用了 **源 IP = 04FFFFFF**（超长头部累加）来验证 IPv4 校验和的累加器
是逐字回卷的，不会在 17 位处溢出后算错。

## 2. 激励怎么造的

- `clk` 10 ns；复位后先把 VL 配置写进 TB 内的 `cfg_mem`（或者用 `cfg_wr_*` 写接口），
  并把 `cfg_rm_en` 配成 1；
- 用 `build_frame` 任务按 `SN` 拼一整帧（以太网头 + IP 头 + UDP 头 + SN + 载荷），
  校验和现场算好写进 IP 头；
- `inject` 任务按字节推 `ff_rx_*`，`frame_net` 指定来自 A 网还是 B 网；
- 每注入一帧后用检查任务比对：`mib_rx_frame_inc`（接受）、`mib_sn_error_inc`（SN 错）、
  `mib_rm_drop_inc`（冗余副本）、`irq_error`、`port_wr_frame_done`（是否提交应用）。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {注入帧头}
add wave -noupdate -radix hex /tb_afdx_rx_regression/g_frame_buf
add wave -noupdate /tb_afdx_rx_regression/frame_net
add wave -noupdate /tb_afdx_rx_regression/ff_rx_data_vld
add wave -noupdate /tb_afdx_rx_regression/ff_rx_sop
add wave -noupdate /tb_afdx_rx_regression/ff_rx_eop
add wave -noupdate -divider {IC/RM 判据}
add wave -noupdate /tb_afdx_rx_regression/dut/sn_r
add wave -noupdate /tb_afdx_rx_regression/dut/psn_write_en
add wave -noupdate -radix hex /tb_afdx_rx_regression/dut/psn_write_val
add wave -noupdate /tb_afdx_rx_regression/dut/last_net_valid
add wave -noupdate /tb_afdx_rx_regression/dut/state
add wave -noupdate -radix unsigned /tb_afdx_rx_regression/g_cksum
add wave -noupdate -divider {结果与计数}
add wave -noupdate /tb_afdx_rx_regression/mib_rx_frame_inc
add wave -noupdate /tb_afdx_rx_regression/mib_rm_drop_inc
add wave -noupdate /tb_afdx_rx_regression/port_wr_frame_done
add wave -noupdate /tb_afdx_rx_regression/irq_error
```

## 4. 波形上应该看到什么

| 场景 | 波形特征 |
|---|---|
| 首帧 SN=0 | `psn_write_en` 脉冲，`port_wr_frame_done` 出现 → 接受 |
| SN=1（+1） | 同上，PSN 更新为 1 |
| SN=1 再来一次（重复） | **无** `port_wr_frame_done`、**无** `psn_write_en`，`irq_error` 有脉冲 → 丢弃 |
| SN=5（跳跃） | 丢弃，但 `psn_write_en` **会**脉冲并把 PSN 重同步到 5；下一帧 SN=6 恢复接受 |
| SN=255 → 1 | 1 被判为合法下一帧（环回），接受 |
| 非首帧 SN=0 | 丢弃且 PSN 不动（`psn_write_en` 无脉冲） |
| 跨网副本 RM 使能 | `mib_rm_drop_inc` 脉冲，应用侧**不重复**出现 `port_wr_frame_done` |

## 5. 通过判据

日志 `result: 0 failures`。四组用例每组都会打印 `[PASS] xxx = 值`。

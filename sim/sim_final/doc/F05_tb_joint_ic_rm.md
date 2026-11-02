# F05 tb_joint_ic_rm —— 完整性检查(IC)/冗余管理(RM) 全链路

- **类别**：全链路仿真（**DUT = `AFDX_top`**，MAC 侧注入 → 判据 → 应用提交）
- **源文件**：`tb_joint_ic_rm.v`
- **DUT**：`AFDX_top`

## 1. 这个仿真在测什么

在**完整端系统里**验证 IC/RM 判据（比 M04 的模块级版本更贴近真实链路，
因为帧先经过双网胶合的 `rx_frame_net` 标记）：

1. SN 递增 → 接受；
2. 同网重复 → 丢弃；
3. SN 跳跃 → 丢弃并重同步 PSN，下一帧恢复；
4. SN 回绕（255 → 1）→ 接受；
5. 跨网副本、RM 使能 → 计 `rm_drop`，不重复提交；
6. 跨网副本、RM 关闭 → 按 SN 错误处理（也算丢弃，但计数走 SN 错误）；
7. A/B 网交替收同一 VL（**故障切换**）→ 都按正常序列接受。

## 2. 激励怎么造的

- `clk` 40 ns；配 VL 时 `cfg_wr_rm_en` 按用例切换（先 1 后 0）；
- `build_frame` + `inject(net, sn, ...)` 在指定网注入，`rx_frame_net` 跟 `net` 一致；
- 通过观察 `irq_error`、MIB 的 `rm_drop`/`sn_error` 计数、以及应用侧是否有帧提交来判定；
- 交替用例按 A、B、A、B 顺序注入同 VL 的连续 SN。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {注入与网络标记}
add wave -noupdate /tb_joint_ic_rm/ff_rx_data_vld
add wave -noupdate -radix hex /tb_joint_ic_rm/ff_rx_data
add wave -noupdate /tb_joint_ic_rm/ff_rx_sop
add wave -noupdate /tb_joint_ic_rm/ff_rx_eop
add wave -noupdate /tb_joint_ic_rm/rx_frame_net
add wave -noupdate -radix hex /tb_joint_ic_rm/g_net
add wave -noupdate -divider {判据内部}
add wave -noupdate /tb_joint_ic_rm/dut/u_afdx/u_afdx_rx/state
add wave -noupdate /tb_joint_ic_rm/dut/u_afdx/u_afdx_rx/sn_r
add wave -noupdate /tb_joint_ic_rm/dut/u_afdx/u_afdx_rx/psn_write_en
add wave -noupdate -radix hex /tb_joint_ic_rm/dut/u_afdx/u_afdx_rx/psn_write_val
add wave -noupdate /tb_joint_ic_rm/dut/u_afdx/u_afdx_rx/last_net_valid
add wave -noupdate -divider {结果}
add wave -noupdate /tb_joint_ic_rm/app_rd_valid
add wave -noupdate -radix unsigned /tb_joint_ic_rm/app_rd_frame_len
add wave -noupdate /tb_joint_ic_rm/irq_error
add wave -noupdate /tb_joint_ic_rm/irq_rx_frame
```

## 4. 波形上应该看到什么

| 场景 | 波形特征 |
|---|---|
| SN 递增 | `app_rd_valid` 出现，`psn_write_en` 脉冲，`irq_rx_frame` 脉冲 |
| 同网重复 | 无 `app_rd_valid`，`psn_write_en` **无**脉冲，`irq_error` 有脉冲 |
| SN 跳跃 | 无提交，但 `psn_write_en` 会脉冲（PSN 重同步），下一帧正常 |
| SN 回绕 | 255 之后收 1 仍提交 |
| 跨网副本 + RM 使能 | 无重复提交；`rm_drop` 计数 +1（RM 路径），`irq_error` 可能不出 |
| 跨网副本 + RM 关闭 | 无提交，走 SN 错误路径（`irq_error` 脉冲） |
| A/B 交替（故障切换） | 每帧都提交，`rx_frame_net` 在 0/1 之间交替 |

## 5. 通过判据

所有用例的 `[PASS]` 都出现，末尾 `PASS: joint ic rm chain`。

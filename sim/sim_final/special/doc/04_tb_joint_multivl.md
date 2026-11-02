# tb_joint_multivl —— 多 VL 并发与独立 BAG 整形

- **类别**：全链路仿真（**DUT = `AFDX_top`**，发送链路）
- **源文件**：`tb_joint_multivl.v`
- **DUT**：`AFDX_top`

## 1. 这个仿真在测什么

赛题要求“实现多 VL 并发能力”，这条用例把它拆成两件事：

1. **并发**：8 条发送 VL（VLID 0x04–0x0B）同时挂起一帧，逐个触发后 8 帧都要上线，
   每帧 DA 最后两字节必须是自己的 VLID，并统计整批上线的跨度与客户口突发吞吐；
2. **独立整形**：VL4(BAG=1ms) / VL5(BAG=2ms) / VL6(BAG=0ms) 同时触发，
   观察三条 VL 各自的等待时间；
3. **顺带暴露一个设计行为**：发送调度器目前是“轮到就等 BAG”，一条 VL 等 BAG 会**阻塞**其他 VL
   （队头阻塞）。本用例把该现象显式测出来并校验其规律（`d6 ≈ d5`，即 VL6 被压到最后一个 BAG 等待结束）。

## 2. 激励怎么造的

- `clk_sys` 40 ns（25MHz）；先配 6 条 VL：VL4(BAG 1ms)、VL5(BAG 2ms)、VL6–VL11(BAG 0)；
- `write_byte(vl, off, data)` 任务按字节写并等授权；**并发写**用“按字节轮流访问 8 条 VL”实现
  （第 0 字节写到 VL4…VL11，再写第 1 字节…），保证 8 条 VL 同时有半帧数据；
- 写完逐个 `trigger_vl(vl)`（把 `app_wr_vl_index` 指向该 VL 再打 `app_tx_req` 脉冲）；
- TB 侧 `always` 采集 `ff_tx_*`：记录每帧的 `tx_sop` 时刻、`tx_eop` 时刻，
  并在第 6 个字节（`tx_cnt==5`）抓 `tx_data` 作为该帧的 VLID 低字节；
- 第二轮写 VL4/VL5/VL6 各一帧后同时触发，统计各自“触发到上链路”的拍数。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {应用写（多 VL 交替）}
add wave -noupdate -radix unsigned /tb_joint_multivl/app_wr_vl
add wave -noupdate -radix unsigned /tb_joint_multivl/app_wr_off
add wave -noupdate -radix hex /tb_joint_multivl/app_wr_data
add wave -noupdate /tb_joint_multivl/app_wr_en
add wave -noupdate /tb_joint_multivl/app_wr_gnt
add wave -noupdate /tb_joint_multivl/app_tx_req
add wave -noupdate -divider {线上帧}
add wave -noupdate /tb_joint_multivl/ff_tx_wren
add wave -noupdate /tb_joint_multivl/ff_tx_sop
add wave -noupdate /tb_joint_multivl/ff_tx_eop
add wave -noupdate -radix hex /tb_joint_multivl/ff_tx_data
add wave -noupdate /tb_joint_multivl/ff_tx_rdy
add wave -noupdate -divider {调度器内部}
add wave -noupdate /tb_joint_multivl/dut/u_afdx/u_afdx_tx/state
add wave -noupdate -radix unsigned /tb_joint_multivl/dut/u_afdx/u_afdx_tx/sched_idx
add wave -noupdate -radix unsigned /tb_joint_multivl/dut/u_afdx/u_afdx_tx/wait_cnt
add wave -noupdate -radix hex /tb_joint_multivl/dut/u_afdx/abort_vl
add wave -noupdate -divider {计时}
add wave -noupdate -radix unsigned /tb_joint_multivl/cyc
add wave -noupdate -radix unsigned /tb_joint_multivl/t_sop
add wave -noupdate -radix unsigned /tb_joint_multivl/t_eop
```

## 4. 波形上应该看到什么 + 实测结果

| 观察点 | 波形特征 | 实测 |
|---|---|---|
| 并发写阶段 | `app_wr_vl` 在 4…11 之间快速轮转，8 条 VL 的偏移同步推进 | — |
| 触发后 | 8 帧 `ff_tx_sop…eop` 连续出现，帧间几乎无空隙 | 整批 8 帧跨度 **1225 拍 = 49 µs** |
| 客户口突发吞吐 | 8×(43+100) 字节 / 49 µs | **186 Mbps**（≥ 赛题 100 Mbps） |
| 每帧 DA | 第 6 个字节 = 0x04…0x0B，各出现一次 | 8 个 VLID 全命中 |
| VL4 等 BAG | 触发后约 1ms 才出现 `sop` | 等待 **21715 拍 ≈ 0.87 ms** |
| VL5 等 BAG | 触发后约 2ms 才出现 `sop` | 等待 **46865 拍 ≈ 1.87 ms** |
| VL6(BAG 0) | 修复后立刻发出（修复前被压到最后） | 等待 **48 拍 = 1.92 µs**（修复前 47014 拍） |

**结论（重要）**：8 路并发发送能力成立、VLID/载荷正确、突发吞吐 186 Mbps；
但调度器存在**队头阻塞**——一条 VL 在等 BAG 时，整条发送流水都被占住，别的 VL 只能等。
影响：多 VL 并发时，一条大 BAG 的 VL 会把其他 VL 的发送时延抬到“前面所有 BAG 等待之和”，
这与“单帧处理 11 µs 级别”无关，但会影响多 VL 场景下的时延上界。
改进方向：`S_DECIDE` 里 BAG 未到期时不要进 `S_WAIT` 死等，而是把这个槽位跳过、继续扫描下一个
已到期的槽位，等所有槽位都未到期再等。这是一次调度器 FSM 改动，需要单独评审。

## 5. 通过判据

日志出现 `[PASS] 8 concurrent VL frames on the wire`、`[PASS] all 8 VLIDs appear exactly once`、
`[PASS] client burst throughput >= 100 Mbps`、`[PASS] VL4 waited ~1ms (BAG)`、
`[PASS] VL5 waited ~2ms (BAG)`，以及队头阻塞的一致性检查
（修复后走 `[PASS] VL6 (BAG 0) went out immediately` 分支；若又变回阻塞，会走
`[PASS] head-of-line blocking observed ...` 提示回归），
末尾 `PASS: multi-VL concurrent transmit + independent BAG`。

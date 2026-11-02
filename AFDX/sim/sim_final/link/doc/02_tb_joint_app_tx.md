# tb_joint_app_tx —— 发送全链路（应用写 → 组帧 → MAC 输出）

- **类别**：全链路仿真（**DUT = `AFDX_top`**，从应用写口一直到 `ff_tx_*`）
- **源文件**：`tb_joint_app_tx.v`
- **DUT**：`AFDX_top`

## 1. 这个仿真在测什么

发送方向的完整业务链路，四组用例：

1. **超长帧拒绝**：超过 `Lmax` 的帧不发送，并计发送错误；
2. **正常发帧**：应用写 17 字节 + `app_tx_req` → 输出帧的 DA/SA/类型/IP/UDP/SN/填充全部正确；
3. **SN 与 BAG**：第二帧 SN = 1，且与第一帧的起始间隔 ≥ BAG（本用例配 1 ms = 25000 拍）；
4. **不重复发**：不写新帧、只再拉一次 `app_tx_req`，不应该把旧帧再发出去。

## 2. 激励怎么造的

- `clk_sys` 40 ns；先配 VL 4（UDP 端口、Lmax、BAG=1ms、RM 关闭）；
- `ff_tx_rdy` **常置 1**，这样能直接观察核心输出的字节流节奏；
- 应用侧 `app_wr_*` 逐字节写入，`app_tx_req` 打脉冲等 `app_wr_gnt`；
- 超长用例写 `Lmax+X` 字节再触发；
- TB 把 `ff_tx_*` 字节收集到 `tx_mem`，逐字段断言（含 SN 与帧间隔的拍数统计）。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {应用写}
add wave -noupdate /tb_joint_app_tx/app_wr_en
add wave -noupdate -radix hex /tb_joint_app_tx/app_wr_vl_index
add wave -noupdate -radix unsigned /tb_joint_app_tx/app_wr_byte_offset
add wave -noupdate -radix hex /tb_joint_app_tx/app_wr_data
add wave -noupdate /tb_joint_app_tx/app_tx_req
add wave -noupdate /tb_joint_app_tx/app_wr_gnt
add wave -noupdate -divider {MAC 输出}
add wave -noupdate /tb_joint_app_tx/ff_tx_wren
add wave -noupdate -radix hex /tb_joint_app_tx/ff_tx_data
add wave -noupdate /tb_joint_app_tx/ff_tx_sop
add wave -noupdate /tb_joint_app_tx/ff_tx_eop
add wave -noupdate /tb_joint_app_tx/ff_tx_rdy
add wave -noupdate -divider {内部}
add wave -noupdate /tb_joint_app_tx/dut/u_afdx/u_afdx_tx/state
add wave -noupdate -radix unsigned /tb_joint_app_tx/dut/u_afdx/u_afdx_tx/sn_r
add wave -noupdate -radix unsigned /tb_joint_app_tx/dut/u_afdx/u_afdx_tx/wait_cnt
add wave -noupdate -divider {抓包}
add wave -noupdate -radix hex /tb_joint_app_tx/tx_mem
```

## 4. 波形上应该看到什么

| 用例 | 波形特征 |
|---|---|
| 超长帧 | `app_tx_req` 之后**没有** `ff_tx_sop`，`irq_error` 有脉冲 |
| 正常帧 | `ff_tx_sop` 起 14 字节是 DA/SA/类型 0800，接着 IP 头（协议 11=UDP）、UDP 头（端口一致）、SN、载荷、0x00 填充 |
| SN | 第 1 帧为 0、第 2 帧为 1（`sn_r` 波形上直接看到） |
| BAG 间隔 | 两帧 `ff_tx_sop` 之间 ≥ 25000 拍；`wait_cnt` 在等 BAG 时递增，等够才发 |
| 重复触发 | 第二次 `app_tx_req` 后 `ff_tx_wren` 保持 0（旧帧不再发） |
| 帧长 | 17 字节载荷 + 填充，整帧满足以太网最小帧长 |

## 5. 通过判据

四组 `[PASS]` 全部出现，末尾 `PASS: joint app tx chain`。

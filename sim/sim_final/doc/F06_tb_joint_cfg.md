# F06 tb_joint_cfg —— VL 配置全链路（配置写 → 表生效 → 收帧门控）

- **类别**：全链路仿真（**DUT = `AFDX_top`**）
- **源文件**：`tb_joint_cfg.v`
- **DUT**：`AFDX_top`

## 1. 这个仿真在测什么

配置面到业务面的完整传导：

1. 逐条写 4 个 VL（SNMP / 615A / RTC / 应用各一条）+ 一条哨兵 → `cfg_done` 拉高；
2. 已配置 VL 的帧能**正常提交**到对应应用端口；
3. **未配置 VL** 的帧被丢弃并计错误；
4. 已配置但 **UDP 目的端口不符**的帧被丢弃并计错误。

## 2. 激励怎么造的

- `clk` 40 ns；复位后用 `cfg_write` 任务按顺序写配置
  （地址、VLID、UDP 端口、端口类型、BAG、Lmax、RM、IC），最后写 `0xFFFF` 哨兵；
- 等 `cfg_done` 为 1 后再注入帧；
- `build_frame(vlid, udp, len, sn)` 造帧，`inject` 推到 `ff_rx_*`；
- 三组帧：合法的、VLID 未配置的、UDP 端口错的；分别看应用侧是否有提交、`irq_error` 是否脉冲。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {配置写}
add wave -noupdate /tb_joint_cfg/cfg_wr_en
add wave -noupdate -radix hex /tb_joint_cfg/cfg_wr_addr
add wave -noupdate -radix hex /tb_joint_cfg/cfg_wr_vlid
add wave -noupdate -radix hex /tb_joint_cfg/cfg_wr_udp_port
add wave -noupdate -radix hex /tb_joint_cfg/cfg_wr_port_type
add wave -noupdate /tb_joint_cfg/cfg_done
add wave -noupdate -divider {注入}
add wave -noupdate /tb_joint_cfg/ff_rx_data_vld
add wave -noupdate -radix hex /tb_joint_cfg/ff_rx_data
add wave -noupdate /tb_joint_cfg/ff_rx_sop
add wave -noupdate /tb_joint_cfg/ff_rx_eop
add wave -noupdate -divider {结果}
add wave -noupdate /tb_joint_cfg/app_rd_valid
add wave -noupdate -radix hex /tb_joint_cfg/app_rd_vl_index
add wave -noupdate -radix unsigned /tb_joint_cfg/app_rd_frame_len
add wave -noupdate /tb_joint_cfg/irq_error
add wave -noupdate /tb_joint_cfg/irq_rx_frame
add wave -noupdate -divider {内部表}
add wave -noupdate /tb_joint_cfg/dut/u_afdx/u_afdx_vl_cfg/u_config_wr/state
add wave -noupdate /tb_joint_cfg/dut/u_afdx/u_afdx_rx/state
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| `cfg_wr_en` | 每次写一个 1 拍脉冲，`cfg_wr_addr` 跟 VLID 对应 |
| `cfg_done` | 哨兵写完后拉高并保持（配置完成标志） |
| 合法帧 | `app_rd_valid` 出现，`app_rd_vl_index` = 配置的槽位号，帧长度正确 |
| 未配置 VL | **无** `app_rd_valid`，`irq_error` 有脉冲 |
| UDP 端口不符 | 同上：丢弃 + 错误脉冲 |
| `irq_rx_frame` | 只在合法帧提交时脉冲 |

## 5. 通过判据

四组用例 `[PASS]` 全出现，末尾 `PASS: joint cfg chain`。

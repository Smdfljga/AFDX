# tb_joint_snmp —— SNMP 管理全链路（业务帧产生计数 → GetRequest → 响应）

- **类别**：全链路仿真（**DUT = `AFDX_top`**，收发都走端系统）
- **源文件**：`tb_joint_snmp.v`
- **DUT**：`AFDX_top`

## 1. 这个仿真在测什么

管理面闭环，而且**先造业务流量再查询**，这样验的是真实的计数链路：

1. 先在应用 VL（槽位 4）上注入一帧 → MIB 的 RX 表该 VL 的计数器 +1；
2. 再在 SNMP VL（槽位 1）上注入一个 **GetRequest**，请求的正是“RX 表 VL4 的计数器 0”；
3. 响应帧从 `ff_tx_*` 发出，**载荷字节 47..50 就是被查的计数值**，必须等于 1（前面那一帧贡献的）。

## 2. 激励怎么造的

- `clk` 40 ns；配两条 VL（应用槽位 4、SNMP 槽位 1）；
- 第一帧：合法业务帧注入 → 应用端口提交 → MIB `rx_frame`/`rx_byte` 计数增加；
- 第二帧：复用模块级用例的固定 GetRequest 模板（SNMP 端口），注入后等响应；
- 响应字节收集到 `tx_mem`，定位到载荷 47..50 做断言。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {业务帧(产生计数)}
add wave -noupdate /tb_joint_snmp/ff_rx_data_vld
add wave -noupdate -radix hex /tb_joint_snmp/ff_rx_data
add wave -noupdate /tb_joint_snmp/ff_rx_sop
add wave -noupdate /tb_joint_snmp/ff_rx_eop
add wave -noupdate -divider {应用侧提交}
add wave -noupdate /tb_joint_snmp/app_rd_valid
add wave -noupdate -radix hex /tb_joint_snmp/app_rd_vl_index
add wave -noupdate /tb_joint_snmp/irq_rx_frame
add wave -noupdate -divider {SNMP 响应}
add wave -noupdate /tb_joint_snmp/ff_tx_wren
add wave -noupdate -radix hex /tb_joint_snmp/ff_tx_data
add wave -noupdate /tb_joint_snmp/ff_tx_sop
add wave -noupdate /tb_joint_snmp/ff_tx_eop
add wave -noupdate /tb_joint_snmp/irq_tx_done
add wave -noupdate -divider {内部}
add wave -noupdate /tb_joint_snmp/dut/u_afdx/u_snmp_agent/u_snmp_decoder/phase
add wave -noupdate -radix hex /tb_joint_snmp/tx_mem
```

## 4. 波形上应该看到什么

| 阶段 | 波形特征 |
|---|---|
| 业务帧 | `app_rd_valid` 出现一帧；MIB 计数路径被触发 |
| GetRequest 注入 | `u_snmp_decoder` 的 `phase` 走过 TLV 解析，识别出 GetRequest |
| MIB 查询 | 内部 `mib_rd_en` 脉冲（在 `snmp_agent` 里），选中 RX 表、VL4/cnt0 |
| 响应帧 | `ff_tx_sop...eop` 一帧，UDP 目的端口是 SNMP 端口；**载荷 47..50 = 0x00000001** |
| `irq_tx_done` | 响应帧末尾一个脉冲 |
| `irq_error` | 全程 0 |

## 5. 通过判据

日志 `[PASS]` 全部出现，末尾 `PASS: joint snmp chain`。

# tb_afdx_tx_regression —— afdx_tx 发送链路自检

- **类别**：单独模块仿真（**自检**，DUT = `afdx_tx`）
- **源文件**：`tb_afdx_tx_regression.v`
- **DUT**：`afdx_tx`

## 1. 这个仿真在测什么

在“同步 RAM 两拍出数（与厂商 M4K IP 一致）”的模型下**连续发三帧**，中间穿插让 MAC 连续停顿，逐字节检查：

1. 第一帧 SN = 0，第二帧 SN = 1（同一条 VL 递增）；
2. **255 回卷到 1** 的边界；
3. **IPv4 校验和的二次回卷**边界（累加后高 16 位再加回低 16 位）；
4. MAC 停顿（`ff_tx_rdy` 拉低）期间字节不丢、恢复后从断点继续。

## 2. 激励怎么造的

- `clk` 10 ns，VLID = `0x0004`（槽位 4），UDP 端口 `0x4001`，每帧 32 字节载荷；
- `payload_mem` + `tx_len_mem` 当端口缓冲（同步读），`cfg_mem`/`st_mem` 填 VL 属性；
- `sys_ts` 递增；BAG 配 1，所以三帧之间只受 `ff_tx_rdy` 影响；
- 第二帧触发后**主动把 `ff_tx_rdy` 拉低若干拍**再放开，模拟 MAC 反压；
- TB 侧 `tx_cap` 数组抓 `ff_tx_*` 输出的每一个字节，帧尾后用检查任务逐字段比对
  （DA/SA/类型/长度/标识/校验和/SN/载荷/填充）。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {触发}
add wave -noupdate /tb_afdx_tx_regression/tx_valid_app
add wave -noupdate -radix unsigned /tb_afdx_tx_regression/sys_ts
add wave -noupdate -divider {组帧状态}
add wave -noupdate /tb_afdx_tx_regression/dut/state
add wave -noupdate -radix unsigned /tb_afdx_tx_regression/dut/sn_r
add wave -noupdate -radix unsigned /tb_afdx_tx_regression/dut/next_sn_r
add wave -noupdate -radix unsigned /tb_afdx_tx_regression/dut/ip_id_cnt
add wave -noupdate -divider {MAC 输出与反压}
add wave -noupdate /tb_afdx_tx_regression/ff_tx_wren
add wave -noupdate /tb_afdx_tx_regression/ff_tx_rdy
add wave -noupdate /tb_afdx_tx_regression/ff_tx_sop
add wave -noupdate /tb_afdx_tx_regression/ff_tx_eop
add wave -noupdate -radix hex /tb_afdx_tx_regression/ff_tx_data
add wave -noupdate -divider {抓包缓存与校验}
add wave -noupdate -radix hex /tb_afdx_tx_regression/tx_cap
add wave -noupdate -radix hex /tb_afdx_tx_regression/check_sum
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| 三帧 `ff_tx_sop...eop` | 帧与帧之间有间隔（不是背靠背贴死），每帧字节数 = 表头 + 载荷 + 填充 |
| `sn_r` | 第 1 帧 0、第 2 帧 1、第 3 帧 2；单独的回卷用例里 255 之后是 1 |
| `ff_tx_rdy` 拉低期间 | `ff_tx_wren` 立刻为 0，`ff_tx_data` **保持当前字节不动** |
| `ff_tx_rdy` 恢复 | 从被挡住的那个字节继续，**不重复、不跳字节** |
| IPv4 校验和 | 帧头 `check_sum` 与 TB 独立算出的值一致（含二次回卷边界） |
| `ff_tx_err` | 全程为 0（合法帧不该置错误） |

## 5. 通过判据

日志无 `[FAIL]`、`result: 0 failures`，最后打印 `PASS`。

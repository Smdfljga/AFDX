# tb_mib_query_regression —— MIB 查询引擎（双表 / 连续查询 / 非法编号）

- **类别**：单独模块仿真（**自检**，DUT = `mib_query`）
- **源文件**：`tb_mib_query_regression.v`
- **DUT**：`mib_query`

## 1. 这个仿真在测什么

SNMP 侧要按 OID 去 MIB 里取计数器的值，这条用例覆盖：

1. **同步双表**：RX 表和 TX 表分别查询，`mib_sel` 选中正确的表；
2. **连续查询**：背靠背两个查询请求，结果不能串（前一个的值不能被后一个覆盖）；
3. **OID 撤销**：`query_req` 撤掉后状态机要干净回到空闲，不挂住；
4. **非法计数器编号**：给一个超出范围的编号，必须返回错误/0，而不是乱指地址。

## 2. 激励怎么造的

- `clk` 10 ns；`oid` 里编码“表选择 + 计数器编号”；
- `query_req` 打脉冲触发查询，等 `query_done`；
- TB 侧 `rx_q` / `tx_q` 两个数组当两张表的模型，`mib_rd_data` 按 `mib_addr` 返回；
- 每次查完比对 `query_value` 与 TB 模型里的期望值。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {查询请求}
add wave -noupdate /tb_mib_query_regression/query_req
add wave -noupdate -radix hex /tb_mib_query_regression/oid
add wave -noupdate -divider {访问 MIB}
add wave -noupdate /tb_mib_query_regression/mib_sel
add wave -noupdate -radix hex /tb_mib_query_regression/mib_addr
add wave -noupdate /tb_mib_query_regression/mib_rd_en
add wave -noupdate -radix unsigned /tb_mib_query_regression/mib_rd_data
add wave -noupdate -divider {结果}
add wave -noupdate /tb_mib_query_regression/query_done
add wave -noupdate -radix unsigned /tb_mib_query_regression/query_value
add wave -noupdate -divider {内部}
add wave -noupdate -radix unsigned /tb_mib_query_regression/dut/cnt_d2
add wave -noupdate /tb_mib_query_regression/dut/tbl_d2
add wave -noupdate /tb_mib_query_regression/dut/rq_d2
add wave -noupdate /tb_mib_query_regression/dut/rq_d3
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| `query_req` 脉冲 | 当拍 `mib_rd_en` 拉高、`mib_addr` 指向该计数器；两拍后 `mib_rd_data` 才有效 |
| `mib_sel` | RX 查询为 0、TX 查询为 1（跟 OID 里的表位一致，但比请求晚两拍） |
| `query_done` | `mib_rd_data` 回来的那一拍（请求后第 3 拍）拉一个脉冲，`query_value` 同时有效 |
| 连续查询 | 两次 `query_done` 之间的 `query_value` 分别是两个不同的值，**不串** |
| 撤销请求 | 状态机回空闲，`mib_rd_en` 不再有脉冲 |
| 非法编号 | `query_done` 仍会给出（或给 0/错误），但 `mib_addr` 不会指到别的计数器 |

## 5. 通过判据

日志打印 `PASS: mib_query dual table / pipeline / oid revoke`，无 `[FAIL]`。

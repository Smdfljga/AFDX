# M08 tb_buffers_regression —— 端口缓冲 + VL 状态表联合自检

- **类别**：单独模块仿真（**自检**，DUT = `tx_wr_arb` + `rx_port_buf` + `vl_state_ram`）
- **源文件**：`tb_buffers_regression.v`
- **DUT**：`tx_wr_arb`、`rx_port_buf`、`vl_state_ram`

## 1. 这个仿真在测什么

三个“搬数据”的模块凑在一起的行为：

1. `tx_wr_arb`：把四路帧尾事件（应用/SNMP/615A/RTC）仲裁成“长度登记”脉冲；
2. `rx_port_buf`：写一帧进缓冲，再按字节偏移读回，校验数据与帧长；
3. `vl_state_ram`：双口状态表读写（A/B 两个口同时读写不同地址）；
4. 四路帧尾事件必须**各登记一次且只一次**（`done_seen` 位图覆盖）。

## 2. 激励怎么造的

- `clk` 10 ns（`always #5`）；
- 用 `done[3:0]` 依次拉四路帧尾事件，检查 `len_en` / `len_vl` / `len_off` 对应的
  “长度登记”是否只出现在被选中的槽位；
- 对 `rx_port_buf` 逐字节写一帧（`wr_en` + `wr_byte_offset` + `wr_data` + `wr_frame_done`），
  然后用 `rd_en` 从偏移 0 读回，比对 `rd_data` 与 `lengths[vl]`；
- 对 `vl_state_ram` 用 A 口写、B 口读，验证双口独立。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {时钟/复位}
add wave -noupdate /tb_buffers_regression/clk
add wave -noupdate /tb_buffers_regression/rst_b
add wave -noupdate -divider {帧尾仲裁}
add wave -noupdate -radix binary /tb_buffers_regression/done
add wave -noupdate /tb_buffers_regression/len_en
add wave -noupdate -radix hex /tb_buffers_regression/len_vl
add wave -noupdate -radix unsigned /tb_buffers_regression/len_off
add wave -noupdate -radix binary /tb_buffers_regression/done_seen
add wave -noupdate -divider {接收端口缓冲}
add wave -noupdate /tb_buffers_regression/wr_en
add wave -noupdate -radix hex /tb_buffers_regression/wr_vl
add wave -noupdate -radix unsigned /tb_buffers_regression/wr_off
add wave -noupdate -radix hex /tb_buffers_regression/wr_data
add wave -noupdate /tb_buffers_regression/frame_done
add wave -noupdate /tb_buffers_regression/rd_en
add wave -noupdate -radix hex /tb_buffers_regression/rd_data
add wave -noupdate /tb_buffers_regression/rd_valid
add wave -noupdate -radix unsigned /tb_buffers_regression/full
add wave -noupdate -divider {状态表}
add wave -noupdate /tb_buffers_regression/st_wr_en
add wave -noupdate -radix hex /tb_buffers_regression/st_addr_a
add wave -noupdate -radix hex /tb_buffers_regression/st_da
add wave -noupdate /tb_buffers_regression/st_qb
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| `done` 四路依次拉高 | 每一路对应一次 `len_en` 脉冲，`len_vl` 等于该路槽位、`len_off` 等于末字节偏移 |
| `done_seen` | 四位最终全 1，说明四路都登记过、没有漏也没有重复 |
| 写缓冲 | `wr_en` 连续、`wr_off` 从 0 递增，`frame_done` 在末字节那拍脉冲 |
| 读回 | `rd_valid` 每字节一个脉冲，`rd_data` 与写入序列一致，读到 `lengths[vl]` 为止 |
| `full` | 单帧写入期间保持 0（不溢出） |
| 状态表 | A 口写、B 口读互不影响；`st_qb` 能读到刚写的数据 |

## 5. 通过判据

日志打印 `PASS ... checks=N failures=0`（`failures` 必须为 0）。

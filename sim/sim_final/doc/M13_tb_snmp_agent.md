# M13 tb_snmp_agent —— SNMP GetRequest → MIB 查询 → GetResponse

- **类别**：单独模块仿真（**自检**，DUT = `snmp_agent`，内含 `snmp_decoder` + `snmp_encoder`）
- **源文件**：`tb_snmp_agent.v`
- **DUT**：`snmp_agent`

## 1. 这个仿真在测什么

管理面最小闭环：**收到一个 SNMP GetRequest → 解析 OID → 查 MIB → 生成 GetResponse 发出去**。
请求对象是 “RX 表里 VL=4 的 cnt0 计数器”。要验证：

1. `snmp_decoder` 能正确解析请求 PDU（`pdu_type`、OID 字段）；
2. `mib_query` 查到的值被正确填进响应载荷；
3. `snmp_encoder` 按固定模板把响应逐字节写进发送端口缓冲（`tx_wr_*`）；
4. 三个外部访问（`rx_rd` / `mib_rd` / `tx_wr_gnt`）都是**一拍延时应答**也能正常工作。

## 2. 激励怎么造的

- `clk` 10 ns；`req_mem` 里预先放好一个 GetRequest 字节流；
- `rx_ready_snmp` 拉高，模块按 `rx_rd_byte_offset` 逐字节读 `rx_rd_data`；
- TB 用 `rx_rd_valid` / `mib_rd_data` / `tx_wr_gnt` 三个“一拍后应答”的信号模拟外部环境；
- 响应字节被 `tx_mem` 收集，帧尾后检查关键字段（版本、community、PDU 类型、
  响应里的计数值）。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {请求读取}
add wave -noupdate /tb_snmp_agent/rx_ready_snmp
add wave -noupdate /tb_snmp_agent/rx_rd_req
add wave -noupdate -radix unsigned /tb_snmp_agent/rx_rd_byte_offset
add wave -noupdate -radix hex /tb_snmp_agent/rx_rd_data
add wave -noupdate /tb_snmp_agent/rx_rd_valid
add wave -noupdate -divider {MIB 查询}
add wave -noupdate /tb_snmp_agent/mib_sel
add wave -noupdate -radix hex /tb_snmp_agent/mib_addr
add wave -noupdate /tb_snmp_agent/mib_rd_en
add wave -noupdate -radix unsigned /tb_snmp_agent/mib_rd_data
add wave -noupdate -divider {响应写出}
add wave -noupdate /tb_snmp_agent/tx_wr_en
add wave -noupdate -radix unsigned /tb_snmp_agent/tx_wr_byte_offset
add wave -noupdate -radix hex /tb_snmp_agent/tx_wr_data
add wave -noupdate /tb_snmp_agent/tx_frame_done
add wave -noupdate /tb_snmp_agent/tx_wr_gnt
add wave -noupdate -divider {内部}
add wave -noupdate /tb_snmp_agent/dut/decoder_phase
add wave -noupdate /tb_snmp_agent/dut/encoder_state_r
add wave -noupdate -radix hex /tb_snmp_agent/tx_mem
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| `rx_rd_req` | 与 `rx_rd_valid` 交替握手，`rx_rd_byte_offset` 从 0 走到请求帧长度 |
| 解码完成 | 内部 phase 走过“TLV 长度 → community → PDU 类型 → OID”，`pdu_type` 识别为 GetRequest |
| `mib_rd_en` | 解码结束后打一拍，`mib_sel=0`（RX 表）、`mib_addr` 指向 VL4/cnt0 |
| `tx_wr_en` | 响应期间连续有效，`tx_wr_byte_offset` 从 0 递增到帧尾 |
| `tx_frame_done` | 最后一个字节那拍脉冲 |
| `tx_wr_gnt` 拉低 | `tx_wr_en` 停住但字节不丢，`tx_wr_data` 保持，恢复后继续 |
| 响应内容 | 版本号 1、community 一致、PDU 为 GetResponse(0xA2)、值段等于 MIB 里的计数值 |

## 5. 通过判据

日志打印 `PASS: snmp_agent get request/response`，且 `tx_mem` 关键字段检查无失败。

# M14 tb_snmp_encoder_regression —— SNMP 固定模板编码器（位段 + 背压）

- **类别**：单独模块仿真（**自检**，DUT = `snmp_encoder`）
- **源文件**：`tb_snmp_encoder_regression.v`
- **DUT**：`snmp_encoder`

## 1. 这个仿真在测什么

`snmp_encoder` 用**固定模板**拼 GetResponse，把三样东西填进去：OID 对应的对象索引、
32 位计数值、以及各个 TLV 的长度字段。这条用例只验证数据通路：

1. 模板里每个**位段**（版本、community、PDU 类型、OID 段、整数字段）位置正确；
2. `value` 32 位被正确拆成 4 个字节写进去（大端）；
3. **背压**：`grant` 被按 `grant_phase` 周期性地拉低时，输出字节不丢、不缺、不重。

## 2. 激励怎么造的

- `clk` 10 ns；给一组 `oid` / `value`，`enc_req` 打脉冲启动；
- TB 用 `grant_phase` 计数器实现“每 N 拍才给一次 `grant`”的节流，模拟发送端口缓冲忙；
- `captured` 数组收集 `data`（`tx_en` 有效时），帧尾后逐字节与期望模板比对。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {启动与输入}
add wave -noupdate /tb_snmp_encoder_regression/enc_req
add wave -noupdate -radix hex /tb_snmp_encoder_regression/oid
add wave -noupdate -radix hex /tb_snmp_encoder_regression/value
add wave -noupdate -divider {输出与背压}
add wave -noupdate /tb_snmp_encoder_regression/grant
add wave -noupdate -radix unsigned /tb_snmp_encoder_regression/grant_phase
add wave -noupdate /tb_snmp_encoder_regression/tx_en
add wave -noupdate -radix unsigned /tb_snmp_encoder_regression/offset
add wave -noupdate -radix hex /tb_snmp_encoder_regression/data
add wave -noupdate /tb_snmp_encoder_regression/done
add wave -noupdate -divider {内部状态}
add wave -noupdate /tb_snmp_encoder_regression/dut/state_r
add wave -noupdate -radix unsigned /tb_snmp_encoder_regression/dut/byte_cnt
add wave -noupdate /tb_snmp_encoder_regression/dut/done_r
add wave -noupdate -radix hex /tb_snmp_encoder_regression/captured
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| `enc_req` 之后 | `tx_en` 开始按 `grant` 逐字节有效，`offset` 从 0 递增 |
| `grant` 拉低期间 | `tx_en` 立刻为 0，`data`/`offset` **保持**，恢复后从同一字节继续 |
| `done` | 最后一个字节写出后一个脉冲，`state_r` 回空闲 |
| 字节内容 | 依次是 0x30(SEQUENCE) 长度、版本 0x02 0x01 0x00、community、0xA2(GetResponse)、
OID 编码段、值段 0x02 0x04 + 4 字节大端 `value` |
| `byte_cnt` | 与 `offset` 同步，不出现跳字节或回头 |

## 5. 通过判据

日志打印 `PASS: snmp_encoder fixed template + backpressure`，`captured` 与期望模板逐字节一致。

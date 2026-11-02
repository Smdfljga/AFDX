# tb_tftp —— TFTP DATA 解析 → 文件 FIFO → Flash 写 → 回 ACK

- **类别**：单独模块仿真（**自检**，DUT = `tftp`）
- **源文件**：`tb_tftp.v`
- **DUT**：`tftp`（内含 `file_buffer` 与 `flash_ctrl`）

## 1. 这个仿真在测什么

615A 加载的核心协议层，一条 DATA 报文的完整消化过程：

1. **解析**：从接收帧里取出 opcode / block number / 数据段；
2. **搬数据**：数据段写进文件 FIFO（`buf_wr_*`），再读出给 Flash（`flash_wr_*`）；
3. **写 Flash**：`flash_wr_req/addr/done` 握手；
4. **回 ACK**：按模板拼 ACK(block N) 写进发送端口缓冲（`tx_wr_*`），`tx_frame_done` 收尾；
5. 写完置 `load_busy`/`load_done` 状态位。

激励是“注入 100 字节 DATA#1”，期望 Flash 写入 100 字节、回 ACK#1、`load_done` 拉高。

## 2. 激励怎么造的

- `clk` 10 ns；`rx_frame_len` 给 100+协议开销；
- `req_mem` 里放好一整帧 DATA 报文（含 2 字节 opcode、2 字节块号、数据段）；
- `start` 打脉冲启动，模块按 `rx_rd_byte_offset` 逐字节读 `rx_rd_data`；
- TB 用 `buf_rd_data` / `flash_wr_done` / `tx_wr_gnt` 一拍应答模拟 FIFO/Flash/端口缓冲；
- `ack_mem` 收集 ACK 输出字节。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {启动与接收读}
add wave -noupdate /tb_tftp/start
add wave -noupdate -radix unsigned /tb_tftp/rx_frame_len
add wave -noupdate /tb_tftp/rx_rd_req
add wave -noupdate -radix unsigned /tb_tftp/rx_rd_byte_offset
add wave -noupdate -radix hex /tb_tftp/rx_rd_data
add wave -noupdate -divider {解析结果}
add wave -noupdate /tb_tftp/tftp_op_valid
add wave -noupdate -radix hex /tb_tftp/tftp_op_type
add wave -noupdate -radix unsigned /tb_tftp/tftp_block_num
add wave -noupdate -divider {文件 FIFO 与 Flash}
add wave -noupdate /tb_tftp/buf_wr_en
add wave -noupdate -radix hex /tb_tftp/buf_wr_data
add wave -noupdate /tb_tftp/fifo_wr
add wave -noupdate /tb_tftp/flash_wr_req
add wave -noupdate -radix hex /tb_tftp/flash_wr_addr
add wave -noupdate /tb_tftp/flash_wr_done
add wave -noupdate -divider {ACK 输出}
add wave -noupdate /tb_tftp/tx_wr_en
add wave -noupdate -radix unsigned /tb_tftp/tx_wr_byte_offset
add wave -noupdate -radix hex /tb_tftp/tx_wr_data
add wave -noupdate /tb_tftp/tx_frame_done
add wave -noupdate -divider {状态}
add wave -noupdate /tb_tftp/load_busy
add wave -noupdate /tb_tftp/load_done
add wave -noupdate /tb_tftp/dut/state
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| `rx_rd_byte_offset` | 从 0 递增，走完 DATA 报文的头部（opcode + 块号） |
| `tftp_op_type` | 识别为 DATA（0x0003），`tftp_block_num` = 1 |
| `buf_wr_en` / `buf_wr_data` | 数据段逐字节写入 FIFO，共 100 字节 |
| `flash_wr_req` → `flash_wr_done` | 每次写一字节地址递增，握手不丢字节 |
| `tx_wr_byte_offset` | 从 0 开始写 ACK：opcode 0x0004 + 块号 1 + 填充 |
| `tx_frame_done` | ACK 最后一字节那拍脉冲 |
| `load_busy` / `load_done` | 处理期间 `load_busy=1`，结束后 `load_done` 拉高并保持 |
| `fifo_mem` | 100 个字节与注入数据段一致（内容比对最直接） |

## 5. 通过判据

日志打印 `PASS: tftp data -> flash -> ack`，且 Flash 写入字节数 = 100、ACK 块号 = 1。

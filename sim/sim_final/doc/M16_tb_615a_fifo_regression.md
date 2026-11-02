# M16 tb_615a_fifo_regression —— 615A 包装层 + 同步 FIFO 集成

- **类别**：单独模块仿真（**自检**，DUT = `data_loader_615a` 的数据读写包装层）
- **源文件**：`tb_615a_fifo_regression.v`
- **DUT**：`data_loader_615a`（+ `file_buffer_ip` 同步 FIFO）

## 1. 这个仿真在测什么

`tftp` 只测协议，这一条测**包装层与 FIFO 的接线**：

1. 接收侧：外部把一整帧放进 `request_mem`，包装层按 `rx_req` / `rx_offset` 逐字节取出；
2. 发送侧：包装层把响应字节按 `tx_en` / `tx_offset` 逐字节写出，`frame_done` 收尾；
3. 同步 FIFO 的读写时序（1 拍出数）与包装层的 `read_pending` 握手配合是否对；
4. `load_busy` / `load_done` / `load_error` 状态位在正常流程下的取值；
5. `tx_grant` 被节流（`grant_phase`）时响应字节不丢。

## 2. 激励怎么造的

- `clk` 10 ns；`request_mem[0:1023]` 预放一整帧 TFTP 请求；
- `frame_len` 给帧长，`start` 打脉冲；
- TB 用 `read_pending` 表示“上次读请求还没被应答”，按需驱动 `rx_data`/`rx_valid`；
- `grant_phase` 周期性拉低 `tx_grant` 做背压；
- `tx_data` 被 `ack_capture` 收集，帧尾后与期望响应比对。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {接收侧}
add wave -noupdate /tb_615a_fifo_regression/start
add wave -noupdate -radix unsigned /tb_615a_fifo_regression/frame_len
add wave -noupdate /tb_615a_fifo_regression/rx_req
add wave -noupdate -radix unsigned /tb_615a_fifo_regression/rx_offset
add wave -noupdate -radix hex /tb_615a_fifo_regression/rx_data
add wave -noupdate /tb_615a_fifo_regression/rx_valid
add wave -noupdate /tb_615a_fifo_regression/read_pending
add wave -noupdate -divider {发送侧与背压}
add wave -noupdate /tb_615a_fifo_regression/tx_en
add wave -noupdate -radix unsigned /tb_615a_fifo_regression/tx_offset
add wave -noupdate -radix hex /tb_615a_fifo_regression/tx_data
add wave -noupdate /tb_615a_fifo_regression/tx_grant
add wave -noupdate -radix unsigned /tb_615a_fifo_regression/grant_phase
add wave -noupdate /tb_615a_fifo_regression/frame_done
add wave -noupdate -divider {状态}
add wave -noupdate /tb_615a_fifo_regression/load_busy
add wave -noupdate /tb_615a_fifo_regression/load_done
add wave -noupdate /tb_615a_fifo_regression/load_error
add wave -noupdate -radix hex /tb_615a_fifo_regression/ack_capture
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| `rx_req` ↔ `rx_valid` | 交替握手，`rx_offset` 从 0 递增到帧长；`read_pending` 在请求未应答时为 1 |
| `tx_en` | 响应期间有效，`tx_offset` 从 0 递增 |
| `tx_grant` 拉低 | `tx_en` 立刻停，`tx_data` 保持，恢复后从同一字节继续 |
| `frame_done` | 响应最后一字节那拍脉冲 |
| `load_busy` / `load_done` | 处理中 busy=1；正常结束 done 拉高、error 保持 0 |
| `ack_capture` | 与期望 ACK 字节流一致（含 2 字节 opcode + 块号 + 填充） |

## 5. 通过判据

日志打印 `PASS: 615a wrapper + fifo`，无 `[FAIL]`。

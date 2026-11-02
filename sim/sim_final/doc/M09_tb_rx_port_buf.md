# M09 tb_rx_port_buf —— 接收端口缓冲的“队列/采样”两种语义

- **类别**：单独模块仿真（**自检**，DUT = `rx_port_buf`）
- **源文件**：`tb_rx_port_buf.v`
- **DUT**：`rx_port_buf`

## 1. 这个仿真在测什么

每个 VL 的接收端口有两种用法，这条用例分别验证：

1. **队列模式**（`wr_queue_mode = 1`）：连写 3 帧，读端必须**按顺序**读出 3 帧，
   `frame_cnt` 依次为 3 → 2 → 1；
2. **采样模式**（`wr_queue_mode = 0`）：新帧覆盖旧帧，`frame_cnt` **恒为 1**，
   读端永远拿到最新那一帧；
3. 读写指针、`frame_len` 集合、`full` 标志都要跟着对。

## 2. 激励怎么造的

- `clk` 10 ns，复位后先把 `wr_queue_mode` 置 1；
- 用 `wr_en` + `wr_byte_offset` + `wr_data` 连写 3 帧（每帧长度不同，便于区分），
  每帧末尾给一个 `wr_frame_done`；
- 然后逐帧 `rd_en` 读回，检查每帧长度与首字节；
- 再把 `wr_queue_mode` 清 0，连写 3 帧（内容不同），读回只应得到最后一帧，
  `rd_frame_cnt_all` 应为 1。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {写侧}
add wave -noupdate /tb_rx_port_buf/wr_en
add wave -noupdate -radix hex /tb_rx_port_buf/wr_vl_index
add wave -noupdate -radix unsigned /tb_rx_port_buf/wr_byte_offset
add wave -noupdate -radix hex /tb_rx_port_buf/wr_data
add wave -noupdate /tb_rx_port_buf/wr_frame_done
add wave -noupdate /tb_rx_port_buf/wr_queue_mode
add wave -noupdate -radix unsigned /tb_rx_port_buf/wr_frame_len
add wave -noupdate /tb_rx_port_buf/wr_full
add wave -noupdate -divider {读侧}
add wave -noupdate /tb_rx_port_buf/rd_en
add wave -noupdate -radix hex /tb_rx_port_buf/rd_vl_index
add wave -noupdate -radix unsigned /tb_rx_port_buf/rd_byte_offset
add wave -noupdate -radix hex /tb_rx_port_buf/rd_data
add wave -noupdate /tb_rx_port_buf/rd_valid
add wave -noupdate -radix unsigned /tb_rx_port_buf/rd_frame_len_all
add wave -noupdate -radix unsigned /tb_rx_port_buf/rd_frame_cnt_all
add wave -noupdate -divider {内部指针}
add wave -noupdate -radix unsigned /tb_rx_port_buf/dut/wr_ptr
add wave -noupdate -radix unsigned /tb_rx_port_buf/dut/rd_ptr
add wave -noupdate -radix unsigned /tb_rx_port_buf/dut/frame_cnt
add wave -noupdate -radix unsigned /tb_rx_port_buf/dut/fifo_wr_ptr
add wave -noupdate -radix unsigned /tb_rx_port_buf/dut/fifo_rd_ptr
```

## 4. 波形上应该看到什么

**队列模式**

| 观察点 | 期望现象 |
|---|---|
| `wr_frame_done` | 每帧末尾一个脉冲，`frame_cnt` 从 0 加到 3 |
| `rd_frame_cnt_all` | 读到第 1 帧时 = 3，读完减为 2 → 1 → 0 |
| `rd_data` | 三帧内容依次出现，**顺序不颠倒、不丢帧** |
| `fifo_wr_ptr` / `fifo_rd_ptr` | 写指针一路递增，读指针随后追上 |

**采样模式**

| 观察点 | 期望现象 |
|---|---|
| `rd_frame_cnt_all` | **始终为 1**（旧帧被覆盖） |
| `rd_frame_len_all` | 等于最后一帧长度 |
| 读回内容 | 只有最后一帧的数据，前两帧读不到 |
| `fifo_wr_ptr` | 不递增（采样模式不走 FIFO） |

## 5. 通过判据

日志打印 `PASS: rx_port_buf queue/sample semantics`，无 `[FAIL]`。

# tb_rtc_sync —— RTC 收发四个模块（local_rtc / rtc_rx / rtc_tx / delay_comp）

- **类别**：单独模块仿真（**自检**，DUT = `local_rtc` + `rtc_tx` + `rtc_rx` + `delay_comp`）
- **源文件**：`tb_rtc_sync.v`
- **DUT**：`local_rtc`、`rtc_tx`、`rtc_rx`、`delay_comp`

## 1. 这个仿真在测什么

RTC 同步报文的收发与延迟补偿四件事：

1. `local_rtc` 的 1 µs 计数（与 M17 呼应，这里只做基本计数）；
2. `rtc_tx` 按 10 字节同步报文格式**大端**组帧（主时间戳 + 链路延迟字段）；
3. `rtc_rx` 解析收到的同步报文，取出主时间戳与延迟值；
4. `delay_comp` 按公式算出校正时间戳：`corrected_ts = master_ts + delay`，
   `calc_done` 与 `corrected_ts` **同拍有效**。

## 2. 激励怎么造的

- `clk` 40 ns；`sync_period_ms` 给 1，让 `rtc_tick` 每 1ms 出现一次；
- `tx_req` 打脉冲触发 `rtc_tx` 组帧，TB 用 `tx_wr_gnt` 常 1 收下输出字节到 `tx_mem`；
- 再把 `tx_mem` 里的字节流灌给 `rtc_rx`（`rx_start` + `rx_frame_len` + 逐字节 `rx_rd_data`），
  观察解析出的 `master_ts` / `delay_val`；
- 把这两个值喂给 `delay_comp`，检查 `corrected_ts` 与 `calc_done`。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {本地时钟}
add wave -noupdate -radix unsigned /tb_rtc_sync/rtc_value
add wave -noupdate /tb_rtc_sync/rtc_tick
add wave -noupdate /tb_rtc_sync/sync_en
add wave -noupdate -radix hex /tb_rtc_sync/sync_value
add wave -noupdate -divider {组帧(rtc_tx)}
add wave -noupdate /tb_rtc_sync/tx_req
add wave -noupdate -radix hex /tb_rtc_sync/local_ts
add wave -noupdate /tb_rtc_sync/tx_wr_en
add wave -noupdate -radix unsigned /tb_rtc_sync/tx_wr_byte_offset
add wave -noupdate -radix hex /tb_rtc_sync/tx_wr_data
add wave -noupdate /tb_rtc_sync/tx_frame_done
add wave -noupdate -divider {解析(rtc_rx)}
add wave -noupdate /tb_rtc_sync/rx_start
add wave -noupdate /tb_rtc_sync/rx_rd_req
add wave -noupdate -radix hex /tb_rtc_sync/rx_rd_data
add wave -noupdate /tb_rtc_sync/rx_rd_valid
add wave -noupdate -radix hex /tb_rtc_sync/master_ts
add wave -noupdate -radix hex /tb_rtc_sync/delay_val
add wave -noupdate -divider {延迟补偿}
add wave -noupdate -radix hex /tb_rtc_sync/corrected_ts
add wave -noupdate /tb_rtc_sync/calc_done
add wave -noupdate -radix hex /tb_rtc_sync/tx_mem
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| `tx_wr_frame` 字节流 | 正好 10 字节（载荷 10B：主时间戳 6B + 延迟 4B 之类的大端排列） |
| `tx_wr_byte_offset` | 0→9，`tx_frame_done` 在第 10 个字节那拍脉冲 |
| 大端顺序 | 先高字节后低字节（把 `tx_mem` 按十六进制看，与 `local_ts` 对得上） |
| `rx_*` 逐字节 | `rx_rd_req`/`rx_rd_valid` 交替，`master_ts`/`delay_val` 在末字节后稳定 |
| `calc_done` | 与 `corrected_ts` **同一拍**有效（这是模块约定，波形上要能看到对齐） |
| `corrected_ts` | 等于 `master_ts + delay_val`（按 48 位对齐看） |

## 5. 通过判据

日志打印 `PASS: rtc sync chain`，无 `[FAIL]`。

# tb_joint_frag —— IP 分片发送与分片重组

## 测什么

对应赛题的分片要求，一次跑通两个方向：

1. **发送方向**：应用写入超过 Lmax 的消息时，`afdx_tx` 按 `Lmax-43` 切片发送（43 = 14 B 以太网 + 20 B IP + 8 B UDP + 1 B SN），
   非末片数据取 `8n+7` 字节，使“8 B UDP + 数据 + 1 B SN”恰好是 8 的整数倍，IP 片偏移字段才能是整数。
2. **接收方向**：`afdx_rx` 不再丢弃分片帧，按片偏移把各片写入端口缓冲的消息内偏移，
   端口缓冲累计字节数、检查片偏移连续性，**末片到达时整条消息一次性提交**，上层读到的永远是完整消息。
3. **异常与恢复**：只有后续片没有首片的残片、缺末片的半条消息都不提交，且不破坏已有消息；随后再送完整分片仍能重组。

## 激励

- 配置两条采样端口 VL：`VLID 0x0004`（UDP 4001，Lmax 512，BAG 1 ms）用于主用例，
  `VLID 0x0006`（UDP 4006，Lmax 512）用于异常用例。
- 主用例应用侧一次写入 1200 字节（数据按 `0x00+k` 递增），拉一次 `app_tx_req`：
  Lmax=512 → 每片 463 字节（`463 = 8×57+7`），1200 = 463 + 463 + 274 → 3 片。
- 采集 `ff_tx_*` 三个分片的字节流，核对其帧长、IP 总长度、MF/片偏移字段与每片序列号；
  然后把这三帧原样从 `ff_rx_*` 回灌给同一端系统，检查提交时机、重组后长度与应用逐字节读回内容。
- 异常用例用 `build_frame` 手工构造分片帧：单独发“第二片”（`片偏移 59`）、只发首片（缺末片），
  再发一组完整的两片（63 + 57 字节，末片偏移 `(63+9)/8 = 9`）。

## 建议抓的波形

```
ff_tx_sop ff_tx_eop ff_tx_wren ff_tx_data /tb_joint_frag/*
mib_tx_frag_inc mib_tx_error_inc
ff_rx_* 端口（回灌阶段）
app_rd_frame_cnt app_rd_frame_len app_rd_valid app_rd_data
dut.u_afdx_rx.reasm_wait dut.u_afdx_rx.reasm_seen dut.u_afdx_rx.frag_orphan
dut.u_afdx_port_buf.u_rx_port_buf.reasm_bytes
dut.u_afdx_port_buf.u_rx_port_buf.reasm_next
```

## 波形上应看到什么

- 3 个 `ff_tx_sop`…`ff_tx_eop`，帧长 506 / 506 / 317 字节（43 + 463、43 + 463、43 + 274）；
  相邻两片之间至少间隔一个 BAG（25000 拍），因为每片都写回时间戳、各自参与整形。
- IP 首部第 20/21 字节（帧内偏移 20、21）：片 0 为 `0x20 0x00`（MF=1、偏移 0）、
  片 1 为 `0x20 0x3B`（偏移 59）、片 2 为 `0x00 0x76`（偏移 118、MF=0）。
- 每片的 SN 在 `42 + 片内数据长度` 处，取值 0 / 1 / 2；`mib_tx_error_inc` 全程为 0。
- 回灌阶段前两片到达时 `app_rd_frame_cnt` 保持 0；第 3 片提交后变成 1、`app_rd_frame_len` 为 1200。
- `reasm_bytes` 在片 0 结束后为 463、片 1 结束后为 926，片 2 提交后回到 0；
  `reasm_next` 依次为 472、944，与下一片的片偏移×8 一致。
- 异常用例：残片到达时 `frag_orphan` 脉冲一次（计一次接收错误）、`app_rd_frame_cnt` 不增加；
  只发首片时 `reasm_wait` 拉高但消息始终不提交。

## 通过判据

仿真日志出现 `PASS: joint fragmentation chain`，且以下全为 `[PASS]`：

```
3 fragments sent / fragment lengths 506/506/317 / fragment 0..2 header
fragment 0 ip total length / per-fragment SN 0/1/2 / no tx error counted
partial fragments not committed / reassembled message length 1200
reassembled payload byte-exact / orphan fragment discarded
2-fragment message reassembled / 2-fragment payload byte-exact
missing last fragment not committed
```

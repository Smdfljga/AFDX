# tb_tx_vl128 —— 发送 VL 容量验证（128 个发送 VL）

- **类别**：单独模块仿真（**自检**，DUT = `AFDX_top`，只走发送链路）
- **源文件**：`tb_tx_vl128.v`
- **DUT**：`AFDX_top`

## 1. 这个仿真在测什么

赛题要求“最多 128 个发送 VL”。发送链路的应用写索引已从 4 位加宽到 **7 位**（VL 索引 0–127），
这条用例验证四件事：

1. 连续配置 **128 条发送 VL**（VLID 0x00–0x7F），哨兵收尾后 `cfg_done` 必须拉高；
2. 对 VLID `0x70`–`0x7F` 这 16 个 VL 各发一帧：每帧 **DA 的最后两字节必须等于自己的 VLID**；
3. 同样的 16 个 VL 再发一轮：**SN 按 VL 独立递增**（首帧 0 → 第二帧 1）；
4. **已知限制显式化**：数据缓冲仍是 16 槽 × 2KB，槽位按 `VLID` 低 4 位映射（与接收侧一致）。
   所以用索引 0 发送时，实际会用槽位 0 上“最后被配置”的那个 VLID（0x70），SN 也接着该 VL 继续。

> 也就是说：**VL 可寻址/可配置 128 个，SN、BAG、Lmax 各自独立；同一时刻最多 16 个 VL 有在途帧；
> VLID 低 4 位相同的 VL 不能同时在途**（要同时支持任意 128 个 VL 并发，得把数据槽也扩到 128 个，
> 那是把 32KB 缓冲扩到 256KB 的改动）。

## 2. 激励怎么造的

- `clk_sys` 40 ns（25MHz），复位后先写 **128 条 VL 配置**（`VLID = 0..127`，
  UDP 端口顺带区分 `0x4000+i`，BAG 配 0 免等待，Lmax 512）；
- 写一条 `VLID = 0xFFFF` 的哨兵收尾 → 等 `cfg_done`；
- `send_frame(vl_idx)` 任务：`app_wr_en` 逐字节写 17 字节载荷（图案 `0xA0+n`）到指定 VL 索引，
  然后 `app_tx_req` 触发；等到该帧 `ff_tx_eop` 上链路再发下一帧；
- TB 侧 `tx_mem` 缓存每个帧的字节，帧尾检查：帧长 64、`tx_mem[5] == VLID 低字节`、
  `tx_mem[59] == SN`、`tx_err == 0`。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {配置写 128 条}
add wave -noupdate -radix hex /tb_tx_vl128/cfg_wr_vlid
add wave -noupdate /tb_tx_vl128/cfg_wr_en
add wave -noupdate /tb_tx_vl128/cfg_done
add wave -noupdate -divider {应用写（7 位 VL 索引）}
add wave -noupdate -radix unsigned /tb_tx_vl128/app_wr_vl
add wave -noupdate -radix unsigned /tb_tx_vl128/app_wr_off
add wave -noupdate -radix hex /tb_tx_vl128/app_wr_data
add wave -noupdate /tb_tx_vl128/app_wr_en
add wave -noupdate /tb_tx_vl128/app_wr_gnt
add wave -noupdate /tb_tx_vl128/app_tx_req
add wave -noupdate -divider {MAC 发送流}
add wave -noupdate /tb_tx_vl128/ff_tx_wren
add wave -noupdate -radix hex /tb_tx_vl128/ff_tx_data
add wave -noupdate /tb_tx_vl128/ff_tx_sop
add wave -noupdate /tb_tx_vl128/ff_tx_eop
add wave -noupdate -divider {内部：槽位复用与 SN}
add wave -noupdate -radix hex /tb_tx_vl128/dut/slot_vlid
add wave -noupdate -radix unsigned /tb_tx_vl128/dut/u_afdx_tx/sn_r
add wave -noupdate -radix hex /tb_tx_vl128/tx_mem
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| `cfg_wr_en` | 128 个写脉冲依次出现，`cfg_wr_vlid` 从 0x00 走到 0x7F，之后哨兵 0xFFFF |
| `cfg_done` | 哨兵后拉高并保持 |
| `app_wr_vl` | 依次出现 112…127 的 7 位索引（最高位为 0，说明只用了低 7 位） |
| `ff_tx_sop…eop` | 每帧 64 字节；**字节 4/5 = 0x00 / VLID 低字节** |
| SN 位置 | 字节 **59**（= 42 + 补齐后载荷 17）；第一轮全 0，第二轮全 1 |
| `slot_vlid`（内部） | 16×16 位寄存器组；低 4 位相同的 VL 共用同一段（最后配置生效） |
| 索引 0 的帧 | DA 实际是 `0x00 0x70`，SN 是 2 —— 这就是“槽位复用”的表现 |

## 5. 通过判据

日志：`[PASS] 128 config entries accepted`、`[PASS] 16 VL frames on the wire`、
`[PASS] 32 frames total, SN per VL incremented`、`[PASS] slot sharing behaves as documented`，
末尾 `PASS: 128 transmit VL addressing + per-VL SN`。

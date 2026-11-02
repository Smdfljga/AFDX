# tb_joint_app_rx —— 接收全链路（MAC 帧 → 端系统 → 应用端口）

- **类别**：全链路仿真（**DUT = `AFDX_top`**，从 MAC 字节流一直到应用读口）
- **源文件**：`tb_joint_app_rx.v`
- **DUT**：`AFDX_top`

## 1. 这个仿真在测什么

接收方向的完整业务链路，四组用例：

1. **采样端口单帧**：注入一帧 → 应用侧读回同一帧，长度与内容一致；
2. **采样端口覆盖**：再注入一帧 → 应用读到的是新帧（旧帧被覆盖，`frame_cnt` 恒 1）；
3. **队列端口**：连注入两帧 → 应用按顺序读回两帧并出队；
4. **异常帧丢弃**：UDP 目的端口不符 / 帧太短 / MAC 报错（`ff_rx_err`）→ 都不提交应用，
   并计入错误计数（`irq_error` / MIB error 计数）。

## 2. 激励怎么造的

- `clk_sys` 40 ns（25MHz）；先写 VL 配置（应用 VL 4 配成队列/采样各一条，UDP 端口固定）；
- `build_frame` 拼合法报文（以太网头 + IP 头 + UDP 头 + SN + 载荷），
  `inject` 按字节推 `ff_rx_*`，`rx_frame_net` 指定来源网络；
- 异常用例分别造：改 UDP 目的端口、截短帧长、把 `ff_rx_err` 拉高；
- 应用侧用 `app_rd_*` 逐字节读回并比对，读够帧长后撤 `app_rd_en` 完成出队。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {MAC 侧注入}
add wave -noupdate /tb_joint_app_rx/ff_rx_data_vld
add wave -noupdate -radix hex /tb_joint_app_rx/ff_rx_data
add wave -noupdate /tb_joint_app_rx/ff_rx_sop
add wave -noupdate /tb_joint_app_rx/ff_rx_eop
add wave -noupdate /tb_joint_app_rx/ff_rx_err
add wave -noupdate /tb_joint_app_rx/rx_frame_net
add wave -noupdate -divider {应用读口}
add wave -noupdate -radix hex /tb_joint_app_rx/app_rd_vl_index
add wave -noupdate -radix unsigned /tb_joint_app_rx/app_rd_byte_offset
add wave -noupdate /tb_joint_app_rx/app_rd_en
add wave -noupdate -radix hex /tb_joint_app_rx/app_rd_data
add wave -noupdate /tb_joint_app_rx/app_rd_valid
add wave -noupdate -radix unsigned /tb_joint_app_rx/app_rd_frame_len
add wave -noupdate -radix unsigned /tb_joint_app_rx/app_rd_frame_cnt
add wave -noupdate -divider {错误侧}
add wave -noupdate /tb_joint_app_rx/irq_error
add wave -noupdate /tb_joint_app_rx/irq_rx_frame
add wave -noupdate -divider {内部}
add wave -noupdate /tb_joint_app_rx/dut/u_afdx/u_afdx_rx/state
add wave -noupdate /tb_joint_app_rx/dut/u_afdx/u_afdx_port_buf/u_rx_port_buf/frame_cnt
```

## 4. 波形上应该看到什么

| 用例 | 波形特征 |
|---|---|
| 采样端口单帧 | `app_rd_valid` 每字节一个脉冲，`app_rd_frame_len` = 载荷长，内容与注入一致 |
| 采样端口第二帧 | `app_rd_frame_cnt` **始终为 1**，读回的是新帧字节 |
| 队列端口两帧 | `app_rd_frame_cnt` 先 2 后 1；两帧**顺序**读出，第二帧在读第一帧期间已排好队 |
| UDP 端口不符 | 没有 `app_rd_valid`，`irq_error` 有脉冲 |
| 短帧 / `ff_rx_err` | 同上：不提交应用，错误计数增加 |
| `irq_rx_frame` | 每提交一帧一个脉冲 |

## 5. 通过判据

日志里四组 `[PASS]` 全部出现，末尾 `PASS: joint app rx chain`。

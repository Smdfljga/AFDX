# F07 tb_joint_615a —— 615A 加载全链路（WRQ/DATA → 回 ACK）

- **类别**：全链路仿真（**DUT = `AFDX_top`**，收方向进核心 + 发方向出核心）
- **源文件**：`tb_joint_615a.v`
- **DUT**：`AFDX_top`

## 1. 这个仿真在测什么

615A 加载协议的**闭环**（请求进来、应答出去都走同一条端系统）：

1. 在 615A VL（槽位 2）上注入 **WRQ** → 应答 **ACK#0** 从 `ff_tx_*` 发出；
2. 注入 **DATA(块 1)** → 应答 **ACK#1**，且加载完成标志置位；
3. 应答报文经发送端口缓冲 + TX 组帧输出，载荷按 17 字节补齐（不足补 0）。

## 2. 激励怎么造的

- `clk` 40 ns；配 615A VL（槽位 2、UDP 端口、Lmax、BAG）；
- `build_frame` 拼 615A 报文（以太网/IP/UDP + TFTP opcode + 载荷），`inject` 推到 `ff_rx_*`；
- 先用 WRQ（opcode 2），等应答；再用 DATA（opcode 3、块号 1、若干数据字节），等第二个应答；
- 应答从 `ff_tx_*` 逐字节收到 `tx_mem`，帧尾后解析 opcode / 块号做断言。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {请求注入}
add wave -noupdate /tb_joint_615a/ff_rx_data_vld
add wave -noupdate -radix hex /tb_joint_615a/ff_rx_data
add wave -noupdate /tb_joint_615a/ff_rx_sop
add wave -noupdate /tb_joint_615a/ff_rx_eop
add wave -noupdate -divider {内部加载状态}
add wave -noupdate /tb_joint_615a/dut/u_afdx/u_afdx_rx/state
add wave -noupdate /tb_joint_615a/dut/u_afdx/u_afdx_tx/state
add wave -noupdate -divider {应答输出}
add wave -noupdate /tb_joint_615a/ff_tx_wren
add wave -noupdate -radix hex /tb_joint_615a/ff_tx_data
add wave -noupdate /tb_joint_615a/ff_tx_sop
add wave -noupdate /tb_joint_615a/ff_tx_eop
add wave -noupdate /tb_joint_615a/ff_tx_rdy
add wave -noupdate -divider {中断}
add wave -noupdate /tb_joint_615a/irq_rx_frame
add wave -noupdate /tb_joint_615a/irq_tx_done
add wave -noupdate /tb_joint_615a/irq_error
add wave -noupdate -radix hex /tb_joint_615a/tx_mem
```

## 4. 波形上应该看到什么

| 阶段 | 波形特征 |
|---|---|
| WRQ 注入 | `ff_rx_data_vld` 连续，帧尾后核心内部产生一次加载请求 |
| ACK#0 | `ff_tx_sop` 起一帧：以太网头 + IP + UDP（615A 端口）+ TFTP opcode 0x0004 + **块号 0** + 填充 |
| DATA 注入 | 数据段进入文件 FIFO / Flash 写路径（可在 `u_data_loader_615a` 内部看到 `flash_wr_req`） |
| ACK#1 | 第二帧应答，块号 = **1** |
| 加载完成 | 615A 内部 `load_done` 置位（可在 `u_data_loader_615a` 内观察） |
| `irq_tx_done` | 每个应答帧发完一个脉冲 |
| `irq_error` | 全程应为 0（正常流程不该报错） |

## 5. 通过判据

日志 `[PASS]` 全部出现，末尾 `PASS: joint 615a chain`。

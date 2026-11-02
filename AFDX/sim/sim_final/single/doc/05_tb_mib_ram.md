# tb_mib_ram —— MIB 计数器读-改-写累加

- **类别**：单独模块仿真（**自检**，DUT = `mib_ram`，RX/TX 各一份）
- **源文件**：`tb_mib_ram.v`
- **DUT**：`mib_ram`（内含 `mib_rx_ip` / `mib_tx_ip` 两个双口 RAM）

## 1. 这个仿真在测什么

MIB 计数器是“读出来 +1 再写回”的结构，最怕两件事：**连拍累加丢数**、**RX/TX 两套表串到一块**。
这条用例：

1. 连续注入 3 次 `cnt0` 事件 → 计数器必须是 **+3**；
2. 连续注入 20 次 `cnt4` 事件 → 计数器必须是 **+20**；
3. RX 与 TX 两份 `mib_ram` 例化都要正确：各自 `inc_addr` 与 `op_addr` 接对自己的 IP。

## 2. 激励怎么造的

- `clk` 10 ns，复位后先用 `inc_addr` 选中某个计数器地址；
- 用 `cnt0`/`cnt4` 事件脉冲连续触发（间隔按模块的读-改-写节奏）；
- 之后用 `rd_addr` + `rd_en` 把该计数器读回来，和期望值比对；
- 对 TX 那份例化做同样的读回（`rd_data_tx`），确认两边互不干扰。

## 3. 建议抓的波形

```tcl
add wave -noupdate -divider {事件输入}
add wave -noupdate -radix hex /tb_mib_ram/inc_addr
add wave -noupdate /tb_mib_ram/cnt0
add wave -noupdate /tb_mib_ram/cnt1
add wave -noupdate /tb_mib_ram/cnt2
add wave -noupdate /tb_mib_ram/cnt3
add wave -noupdate /tb_mib_ram/cnt4
add wave -noupdate -divider {读回}
add wave -noupdate -radix hex /tb_mib_ram/rd_addr
add wave -noupdate /tb_mib_ram/rd_en
add wave -noupdate -radix unsigned /tb_mib_ram/rd_data
add wave -noupdate -radix unsigned /tb_mib_ram/rd_data_tx
add wave -noupdate -divider {内部状态}
add wave -noupdate -radix unsigned /tb_mib_ram/dut/state
add wave -noupdate /tb_mib_ram/dut/bin_valid
add wave -noupdate -radix hex /tb_mib_ram/dut/sel_idx
```

## 4. 波形上应该看到什么

| 观察点 | 期望现象 |
|---|---|
| `cnt0` 三个脉冲 | 每次触发后内部 `state` 走一遍“读 → 加 1 → 写回”，三次后该计数 = 3 |
| `cnt4` 二十个脉冲 | 中途**不丢脉冲**（关键：读-改-写必须握手上锁，不能连拍覆盖） |
| 读回 `rd_data` | `rd_en` 后 1 拍有效，值等于 3 / 20 |
| `rd_data_tx` | 与 RX 表互不影响（各自独立累加） |

## 5. 通过判据

日志打印 `PASS: mib_ram read-modify-write`，且两个计数器读回值分别为 3 和 20。

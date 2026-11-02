# Quartus 版：只看 RTL View 的接口骨架工程

这个工程**不实现任何功能**，只用来看层次结构和模块间的连线：

- 每个模块保留**真实的参数表与端口列表**（与原 RTL 逐字节一致）；
- 保留**真实的子模块例化**（含原代码里的 generate 分支）；
- 删掉了所有 `always` / `initial` / `function` / `task` 以及零散的 `assign`，所以每个模块在 RTL View 里就是一个只有端口的空盒子，父模块里能看到盒子之间怎么连；
- 例外：3 处 `generate` 块（`mib_ram` 2 处、`rx_port_buf` 1 处）原样保留，因为例化嵌在里面；块内几条 `assign` 是纯连线，也一并留着；
- 厂商 IP（PLL、两片 MAC、9 个 M4K 类存储器）只保留端口列表，模块体为空。

## 怎么用

```
File → Open Project → 选 afdx_rtlview.qpf
（Quartus 可能提示版本转换，直接确认即可）
Processing → Start → Start Analysis & Synthesis
Tools → Netlist Viewers → RTL Viewer
```

顶层实体是 `top`，展开后能看到：

```
top
├─ pll                         （锁相环，端口桩）
├─ eth_1 / eth_2               （两片三速以太网 MAC，端口桩）
├─ afdx_net_rx                 （双网接收胶合）
│   ├─ rx_frame_buf  ×2        （端口桩）
│   └─ afdx_net_rx_wr ×2
├─ afdx_tx_buf                 （发送缓冲）
│   └─ rx_frame_buf            （端口桩）
└─ AFDX_top                    （AFDX 核心）
    ├─ afdx_rx                 （接收）
    ├─ afdx_tx                 （发送）
    ├─ afdx_vl_cfg             （VL 配置）
    │   ├─ config_wr
    │   ├─ vl_config_ram → vl_config_ip
    │   ├─ vl_state_ram  → vl_state_ip ×2
    │   └─ mib_ram ×2    → mib_rx_ip / mib_tx_ip
    ├─ afdx_port_buf           （输入输出缓冲）
    │   ├─ rx_port_buf  → rx_port_buf_ip
    │   ├─ rx_rd_arb
    │   ├─ tx_port_buf  → tx_port_buf_ip
    │   └─ tx_wr_arb
    ├─ snmp_agent              （SNMP 代理）
    │   ├─ snmp_decoder
    │   ├─ mib_query
    │   └─ snmp_encoder
    ├─ data_loader_615a        （615A 加载）
    │   ├─ tftp
    │   ├─ file_buffer → file_buffer_ip
    │   ├─ flash_ctrl
    │   └─ file_table  → file_table_ip
    └─ rtc_sync                （RTC 时钟同步）
        ├─ local_rtc
        ├─ rtc_rx
        ├─ delay_comp
        └─ rtc_tx
```

## 注意

1. **器件只是占位**：本体是 EQ6HL130（eLinx），Quartus 里没有这个器件，所以 `.qsf` 里填的是 Cyclone IV E `EP4CE115F29C7`，仅用于跑综合出网表看结构。要换器件在 `Assignments → Device` 里改，`.qsf` 的 FAMILY/DEVICE 两行也可以直接改。
2. **会有一些“悬空”告警**：因为逻辑被删掉，很多 `wire`/`reg` 没有驱动、很多输出没有赋值，综合时会报 undriven/unconnected 一类警告，这是预期现象，不影响 RTL Viewer 看结构。
3. 顶层 `top.v` 连到 `AFDX_top` 的 `app_wr_vl_index` 是 4 位对 7 位（原设计里就是故意的加宽），Quartus 会给一条位宽 warning，属正常。
4. 这个目录是**从 `elinx/rtl` 自动生成**的只读副本；改了原 RTL 之后重新生成即可：

```powershell
cd F:\bigfatfish\AFDX\quartus
python .\tools\gen_skeleton.py     # 重新生成 rtl\ 下的 43 个骨架文件
python .\tools\gen_project.py      # 重新生成 afdx_rtlview.qsf（文件清单）
```
5. 想看带功能实现的完整工程，仍用 `elinx`（eLinx 3.0）那一套；这个 Quartus 工程不参与任何仿真和综合交付。

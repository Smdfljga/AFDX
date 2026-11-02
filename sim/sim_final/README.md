# sim_final —— 交付用仿真套件（27 个，全部通过）

这是从 `sim/` 和 `sim/jointsim/` 里筛出来的一套**可交付仿真**：18 个单独模块仿真 + 9 个全链路仿真。
每个仿真的说明文档在 `doc/` 下（功能 / 激励 / 该抓哪些波形 / 波形上该看到什么）。

## 1. 怎么跑

```powershell
cd F:\bigfatfish\AFDX\sim\sim_final
powershell -File .\run_final.ps1 -ModelSimBin 'D:\Program Files\ModelSim\win64'
```

- 编译：`sim/ip_sim_models.v` + `elinx/rtl/*.v`（**不含** `top.v`，它要做板级顶层，需要厂商 MAC/PLL 仿真模型）
  + 本目录全部 `tb*.v`；
- 逐个跑，每个 TB 30 ms 仿真上限，日志写在 `_build\<tb>.log`；
- 汇总结果写到 `report.json`，脚本 exit code 0 = 全通过。

**只跑一个（看波形）**：

```powershell
cd F:\bigfatfish\AFDX\sim\sim_final\_build
& 'D:\Program Files\ModelSim\win64\vsim.exe' -voptargs=+acc work.tb_afdx_rxtx -do "add wave -r /tb_afdx_rxtx/*; run -all"
```

## 2. 当前状态

| 项 | 结果 |
|---|---|
| 编译 | **Errors: 0, Warnings: 0** |
| 用例 | **27 / 27 PASS**（25 个自检 + 2 个纯波形用例） |
| 脚本 exit code | 0 |

两个纯波形用例（`tb_afdx_rx`、`tb_afdx_tx`）不打印 PASS，判据是“跑到 `$finish` 且无 Error”。

## 3. 分类清单

### 3.1 单独模块仿真（18 个）

| # | 测试台 | DUT | 测什么 | 文档 |
|---|---|---|---|---|
| 1 | `tb_afdx_top` | `AFDX_top` | 顶层体检：配置写通、`cfg_done`、RTC 走时、空闲无发送 | [M01](doc/M01_tb_afdx_top.md) |
| 2 | `tb_afdx_rxtx` | `AFDX_top` | 同一 VL 收发两端：应用读回不含 SN、发送帧头/SN/填充 | [M02](doc/M02_tb_afdx_rxtx.md) |
| 3 | `tb_afdx_rx` | `afdx_rx` | **纯波形**：看接收解析全过程 | [M03](doc/M03_tb_afdx_rx.md) |
| 4 | `tb_afdx_rx_regression` | `afdx_rx`+`vl_state_ram` | IC/RM 自检：SN 递增/重复/跳跃重同步/回绕/跨网副本 | [M04](doc/M04_tb_afdx_rx_regression.md) |
| 5 | `tb_afdx_tx` | `afdx_tx` | **纯波形**：看发送组帧全过程 | [M05](doc/M05_tb_afdx_tx.md) |
| 6 | `tb_afdx_tx_regression` | `afdx_tx` | 发送自检：SN 递增/回卷、IP 校验和二次回卷、MAC 反压不丢字节 | [M06](doc/M06_tb_afdx_tx_regression.md) |
| 7 | `tb_afdx_net_rx` | `afdx_net_rx` | 双网帧缓存：跨时钟、2 槽乒乓、满槽丢帧、槽位复用 | [M07](doc/M07_tb_afdx_net_rx.md) |
| 8 | `tb_buffers_regression` | `tx_wr_arb`+`rx_port_buf`+`vl_state_ram` | 帧尾仲裁、缓冲写读、双口状态表 | [M08](doc/M08_tb_buffers_regression.md) |
| 9 | `tb_rx_port_buf` | `rx_port_buf` | 队列模式（3 帧顺序出）vs 采样模式（覆盖） | [M09](doc/M09_tb_rx_port_buf.md) |
| 10 | `tb_rd_arb_regression` | `rx_rd_arb` | 读口仲裁：应用/SNMP/615A/RTC 优先级与握手 | [M10](doc/M10_tb_rd_arb_regression.md) |
| 11 | `tb_mib_ram` | `mib_ram` | 计数器读-改-写：+3 / +20，RX/TX 两表不串 | [M11](doc/M11_tb_mib_ram.md) |
| 12 | `tb_mib_query_regression` | `mib_query` | 双表查询、连续查询、OID 撤销、非法编号 | [M12](doc/M12_tb_mib_query_regression.md) |
| 13 | `tb_snmp_agent` | `snmp_agent` | GetRequest → 查 MIB → GetResponse | [M13](doc/M13_tb_snmp_agent.md) |
| 14 | `tb_snmp_encoder_regression` | `snmp_encoder` | 固定模板位段 + 背压不丢字节 | [M14](doc/M14_tb_snmp_encoder_regression.md) |
| 15 | `tb_tftp` | `tftp` | DATA#1 → Flash 100 字节 → ACK#1 → load_done | [M15](doc/M15_tb_tftp.md) |
| 16 | `tb_615a_fifo_regression` | `data_loader_615a` | 615A 包装层 + 同步 FIFO 接线与背压 | [M16](doc/M16_tb_615a_fifo_regression.md) |
| 17 | `tb_local_rtc_regression` | `local_rtc` | **25MHz** 下 1µs=25 拍、1ms=25000 拍、校正、零周期关广播 | [M17](doc/M17_tb_local_rtc_regression.md) |
| 18 | `tb_rtc_sync` | `local_rtc`+`rtc_tx`+`rtc_rx`+`delay_comp` | 10 字节同步报文大端收发 + 延迟补偿公式 | [M18](doc/M18_tb_rtc_sync.md) |

### 3.2 全链路仿真（9 个）

| # | 测试台 | DUT | 链路 | 文档 |
|---|---|---|---|---|
| 1 | `tb_joint_top_cdc` | `afdx_net_rx`+`afdx_tx_buf` | **接口级**：MAC 字节流 ↔ 核心字节流（收发两个缓冲，含 MAC 帧内反压） | [F01](doc/F01_tb_joint_top_cdc.md) |
| 2 | `tb_joint_app_rx` | `AFDX_top` | MAC 帧 → 端系统 → 应用端口（含采样/队列、异常帧丢弃） | [F02](doc/F02_tb_joint_app_rx.md) |
| 3 | `tb_joint_app_tx` | `AFDX_top` | 应用写 → 组帧 → MAC 输出（含 Lmax、BAG、SN、不重复发） | [F03](doc/F03_tb_joint_app_tx.md) |
| 4 | `tb_joint_dualnet` | `afdx_net_rx`+`AFDX_top` | 双网接收胶合 + A/B 副本 RM + 发方向 | [F04](doc/F04_tb_joint_dualnet.md) |
| 5 | `tb_joint_ic_rm` | `AFDX_top` | 完整性检查/冗余管理全链路（含 A/B 故障切换） | [F05](doc/F05_tb_joint_ic_rm.md) |
| 6 | `tb_joint_cfg` | `AFDX_top` | VL 配置写 → 表生效 → 收帧门控 | [F06](doc/F06_tb_joint_cfg.md) |
| 7 | `tb_joint_615a` | `AFDX_top` | 615A：WRQ→ACK#0、DATA→ACK#1+加载完成 | [F07](doc/F07_tb_joint_615a.md) |
| 8 | `tb_joint_snmp` | `AFDX_top` | 业务帧产生计数 → GetRequest → 响应带回计数值 | [F08](doc/F08_tb_joint_snmp.md) |
| 9 | `tb_joint_rtc` | 两个 `AFDX_top` | RTC 主从：1ms 广播 → 从侧延迟补偿 → 本地时钟校正 | [F09](doc/F09_tb_joint_rtc.md) |

## 4. 相比原始目录做了哪些取舍

| 处理 | 说明 |
|---|---|
| **删除** `tb_rx_ic_rm.v` | 与 `tb_afdx_rx_regression.v` 的 4 组用例完全相同，后者是超集（多了源 IP=04FFFFFF 的高头部校验和用例），保留后者 |
| **保留全部 9 个 joint** | 它们都是**完整协议链路**（每个都从 `ff_rx` 注入走到应用/协议侧，或从应用/协议侧走到 `ff_tx` 输出），没有“只接了两个模块、链路断开”的用例。唯一没有 `AFDX_top` 的 `tb_joint_top_cdc` 是**顶层接口级**用例，单独标注 |
| **保留 2 个纯波形用例** | `tb_afdx_rx`/`tb_afdx_tx` 不打印 PASS（靠人看波形），套件里按“跑到 `$finish` 且无 Error”判通过；它们就是给“抓波形”用的 |
| 不带 `top.v` | 板级顶层需要厂商 MAC/PLL 的仿真模型（`eth_1/eth_2/pll`），本套件不编译它；顶层胶合由 `tb_joint_top_cdc` 覆盖 |

## 5. 时钟说明（和最终 RTL 对应）

最终 `top.v` 里：两片 MAC 的 `clk_sys` = **125MHz**（GMII 必须），
两片 MAC 的 `ff_tx_clk`/`ff_rx_clk`、`afdx_net_rx` 的两个时钟、`afdx_tx_buf` 的两个时钟、AFDX 核心 = **全部 25MHz**。

- `tb_afdx_net_rx` / `tb_joint_top_cdc` 用的是 **125MHz 写 / 25MHz 读**（异步），
  这是最终接法的**超集**：同频只是它的特例，所以这两条仍然有效且更严格；
- 其余用例都用 25MHz 单时钟；
- 想看“1µs = 25 拍 / 1ms = 25000 拍”这类时钟相关的判据，看 M17 和 F09。

## 6. 抓波形的通用做法

1. 每个 md 的“建议抓的波形”里给了现成的 `add wave` 命令，直接粘到 ModelSim 命令行即可；
2. 想看内部信号就把 TB 顶层换成 `-r /tb_xxx/dut/*`（更细的层级也可以，比如
   `/tb_joint_dualnet/dut/u_afdx/u_afdx_rx/*`）；
3. 建议都把 `clk` / `rst_b` / 各级 `sop` `eop` `vld` 固定放在第一屏，
   数据总线用 `-radix hex`，计数器用 `-radix unsigned`（md 里已按此给出）；
4. 每个 md 的“波形上应该看到什么”是判读基准：先看握手（sop/eop/vld/rdy），
   再看数据内容，最后看状态机与计数脉冲。

## 7. 目录结构

```
sim/sim_final/
├─ README.md          ← 本文件
├─ run_final.ps1      ← 一键编译 + 跑完 27 个用例
├─ report.json        ← 最近一次运行结果
├─ tb_*.v             ← 27 个测试台（模块级 18 + 全链路 9）
├─ doc/               ← 27 个说明文档（M01..M18 / F01..F09）
└─ _build/            ← 编译库、每个用例的仿真日志（可随时删，重跑会重建）
```

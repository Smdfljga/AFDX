# AFDX 端系统仿真套件（20 个用例）

为写报告整理过的一套仿真：按「单模块 / 全链路 / 特殊」三类归档，每个用例都有一份说明文档（怎么抓波形、成功现象）。
每个分类目录下的 `doc/` 里是对应用例的详细说明。

## 目录结构

```
sim_final/
├─ README.md            ← 本文件（每个用例一句话）
├─ run_final.ps1        ← 一键编译 + 跑完 20 个用例，结果写 report.json
├─ report.json          ← 最近一次运行结果
├─ 单模块仿真/          ← 10 个：单个 RTL 模块的功能自检
│  ├─ tb_*.v
│  └─ doc/              ← 每个 TB 一份 md
├─ 全链路仿真/          ← 5 个：从 MAC 字节流进到应用/协议侧出去（app / 615A / SNMP / RTC）
│  ├─ tb_*.v
│  └─ doc/
└─ 特殊仿真/            ← 5 个：双网冗余、VL 并发、变长帧、时延抖动
   ├─ tb_*.v
   └─ doc/
```

## 怎么跑

```powershell
cd F:\bigfatfish\AFDX\sim\sim_final
powershell -File .\run_final.ps1 -ModelSimBin 'D:\Program Files\ModelSim\win64'
```

- 编译：`sim/ip_sim_models.v` + `elinx/rtl/*.v`（不含板级 `top.v`）+ 三个分类目录里全部 `tb*.v`；
- 逐个跑（每个上限 30 ms 仿真时间），日志在 `_build\<tb>.log`；
- 汇总 `report.json`，脚本 exit code 0 表示全过。

单个用例看波形：

```powershell
cd F:\bigfatfish\AFDX\sim\sim_final\_build
& 'D:\Program Files\ModelSim\win64\vsim.exe' -voptargs=+acc work.tb_joint_latency -do "add wave -r /tb_joint_latency/*; run -all"
```

## 一、单模块仿真（10 个）

| # | 测试台 | 一句话说明 | 文档 |
|---|---|---|---|
| 1 | `tb_afdx_rx` | 注入一整帧合法报文，观察 `afdx_rx` 从帧头解析到提交应用的全过程（纯波形用例） | [01](单模块仿真/doc/01_tb_afdx_rx.md) |
| 2 | `tb_afdx_rx_regression` | 接收侧完整性检查/冗余管理自检：SN 递增、同网重复丢弃、跳跃重同步、255→1 回绕、跨网副本 | [02](单模块仿真/doc/02_tb_afdx_rx_regression.md) |
| 3 | `tb_afdx_tx` | 给 `afdx_tx` 一帧待发数据，观察组帧、SN 插入、IP 校验和与最小帧填充（纯波形用例） | [03](单模块仿真/doc/03_tb_afdx_tx.md) |
| 4 | `tb_afdx_tx_regression` | 发送自检：连续三帧 SN 递增/回卷、IP 校验和二次回卷、MAC 反压时不丢字节 | [04](单模块仿真/doc/04_tb_afdx_tx_regression.md) |
| 5 | `tb_mib_ram` | MIB 计数器读-改-写累加：连续 3 次 cnt0 → +3、20 次 cnt4 → +20，RX/TX 两表互不干扰 | [05](单模块仿真/doc/05_tb_mib_ram.md) |
| 6 | `tb_mib_query_regression` | MIB 查询引擎：双表查询、连续查询不串值、OID 撤销、非法计数器编号 | [06](单模块仿真/doc/06_tb_mib_query_regression.md) |
| 7 | `tb_snmp_encoder_regression` | SNMP 固定模板编码器：各 TLV 位段位置正确、32 位值大端拆分、背压下不丢字节 | [07](单模块仿真/doc/07_tb_snmp_encoder_regression.md) |
| 8 | `tb_tftp` | TFTP DATA#1 → 文件 FIFO → Flash 写入 100 字节 → 回 ACK#1 并置加载完成 | [08](单模块仿真/doc/08_tb_tftp.md) |
| 9 | `tb_local_rtc_regression` | 25 MHz 下 1 µs = 25 拍、1 ms = 25000 拍，同步校正装载与零周期关广播 | [09](单模块仿真/doc/09_tb_local_rtc_regression.md) |
| 10 | `tb_rtc_sync` | RTC 同步报文 10 字节大端收发 + 延迟补偿公式 `corrected = master_ts + delay` | [10](单模块仿真/doc/10_tb_rtc_sync.md) |

## 二、全链路仿真（5 个）

| # | 测试台 | 一句话说明 | 文档 |
|---|---|---|---|
| 1 | `tb_joint_app_rx` | 应用接收全链路：采样端口覆盖 / 队列端口顺序出队、UDP 端口不符与短帧/错帧被丢弃计错 | [01](全链路仿真/doc/01_tb_joint_app_rx.md) |
| 2 | `tb_joint_app_tx` | 应用发送全链路：超 Lmax 拒发、17 字节组帧头正确、SN 递增、BAG 间隔、重复请求不重发 | [02](全链路仿真/doc/02_tb_joint_app_tx.md) |
| 3 | `tb_joint_615a` | 615A 加载闭环：WRQ → ACK#0、DATA(块1) → ACK#1 并置加载完成 | [03](全链路仿真/doc/03_tb_joint_615a.md) |
| 4 | `tb_joint_snmp` | SNMP 闭环：业务帧先产生 MIB 计数，再发 GetRequest，响应帧载荷 47..50 带回该计数值 | [04](全链路仿真/doc/04_tb_joint_snmp.md) |
| 5 | `tb_joint_rtc` | RTC 主从全链路：主实例 1 ms 广播，从实例解析+延迟补偿后校正本地时钟 | [05](全链路仿真/doc/05_tb_joint_rtc.md) |

## 三、特殊仿真（5 个）

| # | 测试台 | 一句话说明 | 文档 |
|---|---|---|---|
| 1 | `tb_joint_dualnet` | 双网冗余：A 网单帧 / B 网单帧 / A、B 同帧副本只收一份 / A、B 不同 SN 两帧都收 | [01](特殊仿真/doc/01_tb_joint_dualnet.md) |
| 2 | `tb_joint_ic_rm` | 双网完整性检查与冗余管理：同帧副本 RM 丢弃、RM 关闭按 SN 错处理、A/B 交替故障切换 | [02](特殊仿真/doc/02_tb_joint_ic_rm.md) |
| 3 | `tb_tx_vl128` | VL 容量：128 条发送 VL 全部可配置可寻址，每帧 DA 携带自己的 VLID，SN 按 VL 独立递增 | [03](特殊仿真/doc/03_tb_tx_vl128.md) |
| 4 | `tb_joint_multivl` | VL 并发：8 条 VL 同时挂起全部上线（突发 186 Mbps），各 VL 的 BAG 独立整形互不阻塞 | [04](特殊仿真/doc/04_tb_joint_multivl.md) |
| 5 | `tb_joint_latency` | 变长帧时延与抖动：64/512/1024/1514 B 发送时延 4.92/40.76/81.72/120.92 µs，抖动 0；接收 64~1518 B 均 8.08 µs | [05](特殊仿真/doc/05_tb_joint_latency.md) |

## 四、相对上一版（30 个）剔除的 10 个用例

为了让报告写得动，把「缓冲模块本身」和「与新分类不符」的用例从交付集移出（RTL 里仍然保留，`sim/`、`sim/jointsim/` 可查）：

| 剔除的测试台 | 原因 |
|---|---|
| `tb_buffers_regression`、`tb_rx_port_buf` | 缓冲模块自身的仿真，按你的要求不做 |
| `tb_afdx_net_rx` | 双网帧缓存（缓冲）模块，同上 |
| `tb_rd_arb_regression` | 接收读口仲裁，属缓冲读写细节 |
| `tb_afdx_top` | 顶层冒烟（配置 + RTC 走时），功能已被全链路的 `tb_joint_rtc`/`tb_joint_app_rx` 覆盖 |
| `tb_afdx_rxtx` | `AFDX_top` 级收发小用例，功能已被全链路 app 收发两条取代 |
| `tb_snmp_agent` | SNMP 模块级用例，已被全链路 `tb_joint_snmp` 覆盖 |
| `tb_615a_fifo_regression` | 615A 包装层 + FIFO 细节，已被全链路 `tb_joint_615a` 覆盖 |
| `tb_joint_cfg` | VL 配置链路，属配置面，不在 app/615A/SNMP/RTC 四条业务链里 |
| `tb_joint_top_cdc` | MAC↔核心跨时钟缓冲，属缓冲类接口用例 |

## 五、当前状态

| 项 | 结果 |
|---|---|
| 用例 | **20 / 20 PASS**（18 个自检 + 2 个纯波形） |
| 编译 | Errors: 0, Warnings: 0 |
| 脚本 exit code | 0 |

详见 `report.json`。

// top : AFDX 双网端系统板级顶层
// 封装 PLL（输入 50MHz，输出 125MHz 与 25MHz）、A/B 两片三速以太网 MAC（eth_1/eth_2）与 AFDX_top，
// 并把 AFDX 预留的双网冗余打通：
//   接收：两片 MAC 的字节流各自整帧进 afdx_net_rx 的帧缓存，再串行送 AFDX 接收核心，
//         同时给出 frame_net，让 afdx_rx 的完整性检查/冗余管理能看到 A/B 两份副本；
//   发送：AFDX 核心只有一路发送字节流，这里同时写进两片 MAC，两网发送内容完全一致。
// 时钟：clk_50m 经 PLL 得到 125MHz 与 25MHz。
//       两片 MAC 的 clk_sys 走 125MHz（GMII 必须），而用户侧 ff_tx_clk / ff_rx_clk 走 25MHz：
//       MAC 的 ff_rx_* 是组合输出（FIFO RAM 读 + 7 级 LUT），实测要 9.2ns，125MHz 的 8ns 关不掉；
//       这两个口在 IP 里本来就是独立的异步客户端时钟（两侧各一个 dcfifo + 两级复位同步），
//       降到 25MHz 后时序轻松满足，客户端字节率约 25MB/s（200Mbps），对赛题 100Mbps 有 2 倍余量。
//       AFDX 核心同样 25MHz，afdx_net_rx / afdx_tx_buf 的跨时钟握手结构保留（同频下依然正确）。
//       PHY 的 p0_rxc 由外部 PHY 提供，GMII 模式下 p0_txc 不参与 MAC 内部逻辑。
// 复位：内部复位 = 外部复位 & PLL 锁定，PLL 未锁定时各模块保持复位。
module top (                                                // 声明模块及其端口
    // ==================== 板级时钟与复位 ====================
    input  wire                          clk_50m,               // 板载 50MHz 时钟，送 PLL
    input  wire                          rst_b,                  // 板级复位，低电平有效

    // ==================== A 网 PHY 接口 ====================
    inout  wire                          mdio_a,                 // A 网 MDIO
    output wire                          mdc_a,                  // A 网 MDC
    output wire                          phy_rstb_a,             // A 网 PHY 复位
    output wire                          p0_gtxc_a,              // A 网 GMII 发送时钟
    output wire [7:0]                    p0_txd_a,               // A 网 GMII 发送数据
    output wire                          p0_txen_a,              // A 网 GMII 发送使能
    output wire                          p0_txer_a,              // A 网 GMII 发送错误
    input  wire                          p0_txc_a,               // A 网发送时钟（GMII 模式下未用）
    input  wire                          p0_rxc_a,               // A 网 GMII/MII 接收时钟
    input  wire [7:0]                    p0_rxd_a,               // A 网 GMII 接收数据
    input  wire                          p0_rxdv_a,              // A 网 GMII 接收有效
    input  wire                          p0_rxer_a,              // A 网 GMII 接收错误
    input  wire                          p0_col_a,               // A 网碰撞检测
    input  wire                          p0_crs_a,               // A 网载波检测

    // ==================== B 网 PHY 接口 ====================
    inout  wire                          mdio_b,                 // B 网 MDIO
    output wire                          mdc_b,                  // B 网 MDC
    output wire                          phy_rstb_b,             // B 网 PHY 复位
    output wire                          p0_gtxc_b,              // B 网 GMII 发送时钟
    output wire [7:0]                    p0_txd_b,               // B 网 GMII 发送数据
    output wire                          p0_txen_b,              // B 网 GMII 发送使能
    output wire                          p0_txer_b,              // B 网 GMII 发送错误
    input  wire                          p0_txc_b,               // B 网发送时钟（GMII 模式下未用）
    input  wire                          p0_rxc_b,               // B 网 GMII/MII 接收时钟
    input  wire [7:0]                    p0_rxd_b,               // B 网 GMII 接收数据
    input  wire                          p0_rxdv_b,              // B 网 GMII 接收有效
    input  wire                          p0_rxer_b,              // B 网 GMII 接收错误
    input  wire                          p0_col_b,               // B 网碰撞检测
    input  wire                          p0_crs_b,               // B 网载波检测

    // ==================== VL 配置写入接口（CPU/上位机侧） ====================
    input  wire                          cfg_wr_en,              // 配置写使能，单拍有效写一条 VL
    input  wire [11:0]                   cfg_wr_addr,            // 配置写地址，VL 表条目索引
    input  wire [15:0]                   cfg_wr_vlid,            // 配置写入的 VLID
    input  wire [15:0]                   cfg_wr_udp_port,        // 配置项：UDP 目的端口
    input  wire [1:0]                    cfg_wr_port_type,       // 配置项：端口类型（0=采样 1=队列）
    input  wire [15:0]                   cfg_wr_bag,             // 配置项：BAG，带宽分配间隔
    input  wire [15:0]                   cfg_wr_lmax,            // 配置项：Lmax，最大帧长（字节）
    input  wire                          cfg_wr_rm_en,           // 配置项：冗余管理使能
    input  wire                          cfg_wr_ic_mode,         // 配置项：完整性检查模式
    output wire                          cfg_done,               // 配置完成，全部条目写完后拉高

    // ==================== 应用数据接口 ====================
    input  wire [3:0]                    app_rd_vl_index,        // 应用读 VL 索引
    input  wire [10:0]                   app_rd_byte_offset,     // 应用读字节偏移
    input  wire                          app_rd_en,              // 应用读使能
    output wire [7:0]                    app_rd_data,            // 应用读数据
    output wire                          app_rd_valid,           // 应用读数据有效
    output wire [15:0]                   app_rd_frame_len,       // 应用当前读槽位的待读帧长度
    output wire [3:0]                    app_rd_frame_cnt,       // 应用当前读槽位的待读帧数
    input  wire                          app_wr_en,              // 应用写使能，写入发送端口缓冲
    input  wire [3:0]                    app_wr_vl_index,        // 应用写 VL 索引
    input  wire [10:0]                   app_wr_byte_offset,     // 应用写字节偏移
    input  wire [7:0]                    app_wr_data,            // 应用写数据
    input  wire                          app_tx_req,             // 应用发送请求：写完一帧后拉高一拍
    output wire                          app_wr_gnt,             // 应用写请求已被接受

    // ==================== RTC 时钟同步状态 ====================
    output wire [47:0]                   local_rtc,              // 本地 RTC 当前值
    output wire                          rtc_sync_valid,         // 一次时钟同步校正完成

    // ==================== 中断 ====================
    output wire                          irq_rx_frame,           // 中断：有效接收帧到达
    output wire                          irq_tx_done,            // 中断：一帧发送完成
    output wire                          irq_error               // 中断：链路/完整性/RM 等错误
);                                                          // 端口声明或模块例化结束

    // ==================== PLL 与内部时钟复位 ====================
    wire                                 clk_125m;               // PLL 输出 125MHz 系统时钟
	wire                                 clk_25m;               // PLL 输出 25MHz AFDX时钟
    wire                                 pll_locked;             // PLL 锁定指示
    wire                                 rst_n;                  // 内部复位 = 外部复位 & PLL 锁定

    pll u_pll (                                             // 50MHz→125MHz 时钟锁相环
        .inclk0 (clk_50m),                                  // 板载 50MHz 输入
        .c0     (clk_125m),                                 // 125MHz 输出
		.c1		(clk_25m),                                  // 25MHz 输出
        .locked (pll_locked)                                // 锁定指示
    );                                                      // PLL 例化结束

    assign rst_n = rst_b & pll_locked;                      // PLL 未锁定时各模块保持复位

    // ==================== AFDX 核心 ?? 双网胶合：接收 ====================
    wire [7:0]                           core_rx_data;           // 胶合模块送核心的接收数据
    wire                                 core_rx_data_vld;       // 胶合模块送核心的数据有效
    wire                                 core_rx_sop;            // 胶合模块送核心的包起始
    wire                                 core_rx_eop;            // 胶合模块送核心的包结束
    wire                                 core_rx_err;            // 胶合模块送核心的接收错误
    wire                                 core_rx_rdy;            // 核心接收准备
    wire                                 core_frame_net;         // 本帧来源网络：0=A 1=B

    // ==================== AFDX 核心 ?? 双网胶合：发送 ====================
    wire [7:0]                           core_tx_data;           // 核心发送数据
    wire                                 core_tx_wren;           // 核心发送数据写使能
    wire                                 core_tx_sop;            // 核心发送包起始
    wire                                 core_tx_eop;            // 核心发送包结束
    wire                                 core_tx_err;            // 核心发送错误
    wire                                 core_tx_rdy;            // 缓冲可接收核心出字节
    wire                                 mac_a_tx_rdy;           // A 网 MAC 发送就绪
    wire                                 mac_b_tx_rdy;           // B 网 MAC 发送就绪
    wire [7:0]                           mac_tx_data;            // 缓冲送两片 MAC 的发送数据
    wire                                 mac_tx_wren;            // 缓冲送两片 MAC 的写使能
    wire                                 mac_tx_sop;             // 缓冲送两片 MAC 的帧首
    wire                                 mac_tx_eop;             // 缓冲送两片 MAC 的帧尾
    wire                                 mac_tx_err;             // 缓冲送两片 MAC 的错误标记
    wire                                 mac_tx_rdy;             // 两片 MAC 都就绪

    // ==================== A 网 MAC 接收侧字节流 ====================
    wire [7:0]                           mac_a_rx_data;          // A 网 MAC 接收数据
    wire                                 mac_a_rx_data_vld;      // A 网 MAC 接收数据有效
    wire                                 mac_a_rx_sop;           // A 网 MAC 接收包起始
    wire                                 mac_a_rx_eop;           // A 网 MAC 接收包结束
    wire                                 mac_a_rx_err;           // A 网 MAC 接收错误
    wire                                 mac_a_rx_rdy;           // A 网 MAC 接收准备

    // ==================== B 网 MAC 接收侧字节流 ====================
    wire [7:0]                           mac_b_rx_data;          // B 网 MAC 接收数据
    wire                                 mac_b_rx_data_vld;      // B 网 MAC 接收数据有效
    wire                                 mac_b_rx_sop;           // B 网 MAC 接收包起始
    wire                                 mac_b_rx_eop;           // B 网 MAC 接收包结束
    wire                                 mac_b_rx_err;           // B 网 MAC 接收错误
    wire                                 mac_b_rx_rdy;           // B 网 MAC 接收准备

    // ==================== 发送侧两网都就绪才出字节 ====================
    assign mac_tx_rdy = mac_a_tx_rdy & mac_b_tx_rdy;        // 同一字节流写两片 MAC，需两网同时就绪

    // ==================== A 网 MAC ====================
    eth_1 u_eth_1 (                                         // A 网三速以太网 MAC IP
        .mdc            (mdc_a),                            // 输出：MDC
        .phy_rstb0      (phy_rstb_a),                       // 输出：PHY 复位
        .p0_gtxc        (p0_gtxc_a),                        // 输出：GMII 发送时钟
        .p0_txd         (p0_txd_a),                         // 输出：GMII 发送数据
        .p0_txen        (p0_txen_a),                        // 输出：GMII 发送使能
        .p0_txer        (p0_txer_a),                        // 输出：GMII 发送错误
        .ff_tx_rdy      (mac_a_tx_rdy),                     // 输出：发送 FIFO 就绪
        .ff_tx_al_full  (),                                 // 输出：发送 FIFO 将满（未使用）
        .ff_rx_data_vld (mac_a_rx_data_vld),                // 输出：接收数据有效
        .ff_rx_data     (mac_a_rx_data),                    // 输出：接收数据
        .ff_rx_sop      (mac_a_rx_sop),                     // 输出：接收包起始
        .ff_rx_eop      (mac_a_rx_eop),                     // 输出：接收包结束
        .ff_rx_err      (mac_a_rx_err),                     // 输出：接收错误
        .reg_data_out   (),                                 // 输出：寄存器读数据（未使用）
        .reg_acc_bsy    (),                                 // 输出：寄存器访问忙（未使用）
        .mdio           (mdio_a),                           // 双向：MDIO
        .clk_sys        (clk_125m),                         // 输入：系统时钟 125MHz
        .rst_b          (rst_n),                            // 输入：复位
        .p0_txc         (p0_txc_a),                         // 输入：发送时钟（GMII 未用）
        .p0_rxc         (p0_rxc_a),                         // 输入：接收时钟
        .p0_rxd         (p0_rxd_a),                         // 输入：GMII 接收数据
        .p0_rxdv        (p0_rxdv_a),                        // 输入：GMII 接收有效
        .p0_rxer        (p0_rxer_a),                        // 输入：GMII 接收错误
        .p0_col         (p0_col_a),                         // 输入：碰撞检测
        .p0_crs         (p0_crs_a),                         // 输入：载波检测
        .ff_tx_clk      (clk_25m),                          // 输入：用户发送 FIFO 时钟 25MHz（客户端异步口）
        .ff_tx_data     (mac_tx_data),                      // 输入：用户发送数据（缓冲输出）
        .ff_tx_sop      (mac_tx_sop),                       // 输入：用户发送包起始
        .ff_tx_eop      (mac_tx_eop),                       // 输入：用户发送包结束
        .ff_tx_err      (mac_tx_err),                       // 输入：用户发送错误
        .ff_tx_wren     (mac_tx_wren),                      // 输入：用户发送写使能
        .ff_rx_clk      (clk_25m),                          // 输入：用户接收 FIFO 时钟 25MHz（客户端异步口）
        .ff_rx_rdy      (mac_a_rx_rdy),                     // 输入：用户接收准备
        .reg_wr         (1'b0),                             // 输入：寄存器写（未使用）
        .reg_rd         (1'b0),                             // 输入：寄存器读（未使用）
        .reg_addr       (4'd0),                             // 输入：寄存器地址（未使用）
        .reg_data_in    (32'd0)                             // 输入：寄存器写数据（未使用）
    );                                                      // A 网 MAC 例化结束

    // ==================== B 网 MAC ====================
    eth_2 u_eth_2 (                                         // B 网三速以太网 MAC IP
        .mdc            (mdc_b),                            // 输出：MDC
        .phy_rstb0      (phy_rstb_b),                       // 输出：PHY 复位
        .p0_gtxc        (p0_gtxc_b),                        // 输出：GMII 发送时钟
        .p0_txd         (p0_txd_b),                         // 输出：GMII 发送数据
        .p0_txen        (p0_txen_b),                        // 输出：GMII 发送使能
        .p0_txer        (p0_txer_b),                        // 输出：GMII 发送错误
        .ff_tx_rdy      (mac_b_tx_rdy),                     // 输出：发送 FIFO 就绪
        .ff_tx_al_full  (),                                 // 输出：发送 FIFO 将满（未使用）
        .ff_rx_data_vld (mac_b_rx_data_vld),                // 输出：接收数据有效
        .ff_rx_data     (mac_b_rx_data),                    // 输出：接收数据
        .ff_rx_sop      (mac_b_rx_sop),                     // 输出：接收包起始
        .ff_rx_eop      (mac_b_rx_eop),                     // 输出：接收包结束
        .ff_rx_err      (mac_b_rx_err),                     // 输出：接收错误
        .reg_data_out   (),                                 // 输出：寄存器读数据（未使用）
        .reg_acc_bsy    (),                                 // 输出：寄存器访问忙（未使用）
        .mdio           (mdio_b),                           // 双向：MDIO
        .clk_sys        (clk_125m),                         // 输入：系统时钟 125MHz
        .rst_b          (rst_n),                            // 输入：复位
        .p0_txc         (p0_txc_b),                         // 输入：发送时钟（GMII 未用）
        .p0_rxc         (p0_rxc_b),                         // 输入：接收时钟
        .p0_rxd         (p0_rxd_b),                         // 输入：GMII 接收数据
        .p0_rxdv        (p0_rxdv_b),                        // 输入：GMII 接收有效
        .p0_rxer        (p0_rxer_b),                        // 输入：GMII 接收错误
        .p0_col         (p0_col_b),                         // 输入：碰撞检测
        .p0_crs         (p0_crs_b),                         // 输入：载波检测
        .ff_tx_clk      (clk_25m),                          // 输入：用户发送 FIFO 时钟 25MHz（客户端异步口）
        .ff_tx_data     (mac_tx_data),                      // 输入：用户发送数据（缓冲输出）
        .ff_tx_sop      (mac_tx_sop),                       // 输入：用户发送包起始
        .ff_tx_eop      (mac_tx_eop),                       // 输入：用户发送包结束
        .ff_tx_err      (mac_tx_err),                       // 输入：用户发送错误
        .ff_tx_wren     (mac_tx_wren),                      // 输入：用户发送写使能
        .ff_rx_clk      (clk_25m),                          // 输入：用户接收 FIFO 时钟 25MHz（客户端异步口）
        .ff_rx_rdy      (mac_b_rx_rdy),                     // 输入：用户接收准备
        .reg_wr         (1'b0),                             // 输入：寄存器写（未使用）
        .reg_rd         (1'b0),                             // 输入：寄存器读（未使用）
        .reg_addr       (4'd0),                             // 输入：寄存器地址（未使用）
        .reg_data_in    (32'd0)                             // 输入：寄存器写数据（未使用）
    );                                                      // B 网 MAC 例化结束

    // ==================== 核心发送 → 双网 MAC 的跨时钟缓冲 ====================
    afdx_tx_buf u_afdx_tx_buf (                             // 核心 25MHz 写、MAC 客户端 25MHz 读（握手结构保留）
        .wr_clk        (clk_25m),                           // 输入：核心侧时钟
        .rd_clk        (clk_25m),                           // 输入：MAC 客户端时钟（两片 MAC 的 ff_tx_clk 同源）
        .rst_b         (rst_n),                             // 输入：复位
        .core_tx_data  (core_tx_data),                      // 输入：核心发送数据
        .core_tx_wren  (core_tx_wren),                      // 输入：核心发送写使能
        .core_tx_sop   (core_tx_sop),                       // 输入：核心发送包起始
        .core_tx_eop   (core_tx_eop),                       // 输入：核心发送包结束
        .core_tx_err   (core_tx_err),                       // 输入：核心发送错误标记
        .core_tx_rdy   (core_tx_rdy),                       // 输出：缓冲可接收
        .mac_tx_data   (mac_tx_data),                       // 输出：送往 MAC 的数据
        .mac_tx_wren   (mac_tx_wren),                       // 输出：送往 MAC 的写使能
        .mac_tx_sop    (mac_tx_sop),                        // 输出：帧首
        .mac_tx_eop    (mac_tx_eop),                        // 输出：帧尾
        .mac_tx_err    (mac_tx_err),                        // 输出：帧错误标记
        .mac_tx_rdy    (mac_tx_rdy)                         // 输入：两片 MAC 都就绪
    );                                                      // 发送缓冲例化结束

    // ==================== 双网接收缓存与整帧选路 ====================
    afdx_net_rx u_afdx_net_rx (                             // A/B 两网帧缓存与整帧轮流送核心
        .wr_clk           (clk_25m),                        // 输入：MAC 客户端时钟 25MHz（两片 MAC 的 ff_rx_clk 同源）
        .rd_clk           (clk_25m),                        // 输入：核心侧时钟 25MHz
        .rst_b            (rst_n),                          // 输入：复位
        .a_rx_data        (mac_a_rx_data),                  // 输入：A 网接收数据
        .a_rx_data_vld    (mac_a_rx_data_vld),              // 输入：A 网接收数据有效
        .a_rx_sop         (mac_a_rx_sop),                   // 输入：A 网接收包起始
        .a_rx_eop         (mac_a_rx_eop),                   // 输入：A 网接收包结束
        .a_rx_err         (mac_a_rx_err),                   // 输入：A 网接收错误
        .a_rx_rdy         (mac_a_rx_rdy),                   // 输出：A 网接收准备
        .b_rx_data        (mac_b_rx_data),                  // 输入：B 网接收数据
        .b_rx_data_vld    (mac_b_rx_data_vld),              // 输入：B 网接收数据有效
        .b_rx_sop         (mac_b_rx_sop),                   // 输入：B 网接收包起始
        .b_rx_eop         (mac_b_rx_eop),                   // 输入：B 网接收包结束
        .b_rx_err         (mac_b_rx_err),                   // 输入：B 网接收错误
        .b_rx_rdy         (mac_b_rx_rdy),                   // 输出：B 网接收准备
        .ff_rx_data       (core_rx_data),                   // 输出：送核心的接收数据
        .ff_rx_data_vld   (core_rx_data_vld),               // 输出：送核心的数据有效
        .ff_rx_sop        (core_rx_sop),                    // 输出：送核心的包起始
        .ff_rx_eop        (core_rx_eop),                    // 输出：送核心的包结束
        .ff_rx_err        (core_rx_err),                    // 输出：送核心的接收错误
        .ff_rx_rdy        (core_rx_rdy),                    // 输入：核心接收准备
        .frame_net        (core_frame_net)                  // 输出：本帧来源网络
    );                                                      // 双网接收胶合例化结束

    // ==================== AFDX 核心 ====================
    AFDX_top #(                                             // 双网配置的 AFDX 端系统顶层
        .DATA_WIDTH        (8),                             // MAC 侧数据位宽
        .VLID_WIDTH        (16),                            // VLID 位宽
        .VL_ADDR_WIDTH     (12),                            // VL 表地址位宽
        .CNT_WIDTH         (32),                            // MIB 计数器位宽
        .VL_INDEX_WIDTH    (4),                             // 端口缓冲槽位号位宽
        .BYTE_OFFSET_WIDTH (11),                            // 端口缓冲字节偏移位宽
        .RTC_WIDTH         (48),                            // 本地 RTC 位宽
        .STATE_WIDTH       (64),                            // VL 运行期状态字位宽
        .REDUNDANCY_EN     (1'b1),                          // 双网冗余使能
        .VL_INDEX_SNMP     (4'd1),                          // SNMP 代理 VL 索引
        .VL_INDEX_615A     (4'd2),                          // 615A 代理 VL 索引
        .VL_INDEX_RTC      (4'd3),                          // RTC 代理 VL 索引
        .RTC_MASTER_MODE   (1'b0),                          // RTC 角色：从时钟
        .RTC_SYNC_PERIOD   (16'd10),                        // 主时钟广播周期（ms）
        .RTC_PROC_DELAY    (32'd100)                        // 本地接收处理延迟（ns）
    ) u_afdx (                                              // 参数绑定结束，开始连接实例端口
        .clk_sys             (clk_25m),                     // 输入：核心系统时钟 25MHz
        .rst_b               (rst_n),                       // 输入：复位
        .ff_rx_data          (core_rx_data),                // 输入：接收数据
        .ff_rx_data_vld      (core_rx_data_vld),            // 输入：接收数据有效
        .ff_rx_sop           (core_rx_sop),                 // 输入：接收包起始
        .ff_rx_eop           (core_rx_eop),                 // 输入：接收包结束
        .ff_rx_err           (core_rx_err),                 // 输入：接收错误
        .ff_rx_rdy           (core_rx_rdy),                 // 输出：接收准备
        .rx_frame_net        (core_frame_net),              // 输入：本帧来源网络
        .ff_tx_data          (core_tx_data),                // 输出：发送数据
        .ff_tx_wren          (core_tx_wren),                // 输出：发送数据写使能
        .ff_tx_sop           (core_tx_sop),                 // 输出：发送包起始
        .ff_tx_eop           (core_tx_eop),                 // 输出：发送包结束
        .ff_tx_err           (core_tx_err),                 // 输出：发送错误
        .ff_tx_rdy           (core_tx_rdy),                 // 输入：发送准备（缓冲有空槽）
        .cfg_wr_en           (cfg_wr_en),                   // 输入：配置写使能
        .cfg_wr_addr         (cfg_wr_addr),                 // 输入：配置写地址
        .cfg_wr_vlid         (cfg_wr_vlid),                 // 输入：配置写 VLID
        .cfg_wr_udp_port     (cfg_wr_udp_port),             // 输入：配置 UDP 端口
        .cfg_wr_port_type    (cfg_wr_port_type),            // 输入：端口类型
        .cfg_wr_bag          (cfg_wr_bag),                  // 输入：BAG
        .cfg_wr_lmax         (cfg_wr_lmax),                 // 输入：Lmax
        .cfg_wr_rm_en        (cfg_wr_rm_en),                // 输入：RM 使能
        .cfg_wr_ic_mode      (cfg_wr_ic_mode),              // 输入：IC 模式
        .cfg_done            (cfg_done),                    // 输出：配置完成
        .app_rd_vl_index     (app_rd_vl_index),             // 输入：应用读 VL 索引
        .app_rd_byte_offset  (app_rd_byte_offset),          // 输入：应用读字节偏移
        .app_rd_en           (app_rd_en),                   // 输入：应用读使能
        .app_rd_data         (app_rd_data),                 // 输出：应用读数据
        .app_rd_valid        (app_rd_valid),                // 输出：应用读数据有效
        .app_rd_frame_len    (app_rd_frame_len),            // 输出：应用待读帧长度
        .app_rd_frame_cnt    (app_rd_frame_cnt),            // 输出：应用待读帧数
        .app_wr_en           (app_wr_en),                   // 输入：应用写使能
        .app_wr_vl_index     (app_wr_vl_index),             // 输入：应用写 VL 索引
        .app_wr_byte_offset  (app_wr_byte_offset),          // 输入：应用写字节偏移
        .app_wr_data         (app_wr_data),                 // 输入：应用写数据
        .app_tx_req          (app_tx_req),                  // 输入：应用发送请求
        .app_wr_gnt          (app_wr_gnt),                  // 输出：应用写请求已被接受
        .local_rtc           (local_rtc),                   // 输出：本地 RTC
        .rtc_sync_valid      (rtc_sync_valid),              // 输出：RTC 同步校正完成
        .irq_rx_frame        (irq_rx_frame),                // 输出：接收帧中断
        .irq_tx_done         (irq_tx_done),                 // 输出：发送完成中断
        .irq_error           (irq_error)                    // 输出：错误中断
    );                                                      // AFDX 核心例化结束

endmodule                                                   // 模块定义结束

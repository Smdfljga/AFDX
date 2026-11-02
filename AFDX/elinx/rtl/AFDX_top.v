// AFDX_top : AFDX 端系统顶层
// 顶层只挂 7 个功能模块，内部细节都收在各自模块里：
// u_afdx_rx         接收模块：帧解析 / 完整性检查 / 冗余管理 / 写缓冲 / 计数
// u_afdx_tx         输出模块：BAG 整形 / 组帧 / 分片 / 驱动 MAC / 计数
// u_afdx_vl_cfg     VL 配置模块：配置写入 + 配置表 + 状态表 + MIB 计数表
// u_afdx_port_buf   输入输出缓冲模块：收发端口缓冲 + 两个读写仲裁器
// u_snmp_agent      SNMP 模块：PDU 解码 / MIB 查询 / 响应编码
// u_data_loader_615a 615A 模块：TFTP 数据加载 + Flash 写 + 文件表
// u_rtc_sync        RTC 模块：时钟同步（本地 RTC / 延迟补偿 / 同步报文收发）
// 双网冗余由 REDUNDANCY_EN 常量开关控制：0=单网（本板），1=双网；
// 双网时接收帧的网络来源由外层网络选路模块经 rx_frame_net 送入冗余管理，
// 发送侧仍是一路 MAC 接口，由外层包装层复制到两张网。
// 注：各模块内部逻辑已补全，顶层新增 rx_frame_net 以打通双网冗余
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module AFDX_top #(                                          // 声明模块及其参数接口
    parameter VLID_WIDTH        = 16,       // VLID 位宽，AFDX 虚拟链路标识
    parameter VL_ADDR_WIDTH     = 12,       // VL 表地址位宽（按 afdx.xlsx Sheet6：地址 = vlid[11:0]，4096 条）
    parameter DATA_WIDTH        = 8,        // MAC 侧数据位宽，1 字节/拍
    parameter CNT_WIDTH         = 32,       // MIB 计数器位宽
    parameter VL_INDEX_WIDTH    = 4,        // 端口缓冲槽位号位宽（16 个槽位，槽位号 = vlid 低位）
    parameter BYTE_OFFSET_WIDTH = 11,       // 端口缓冲字节偏移位宽（2KB/VL）
    parameter RTC_WIDTH         = 48,       // 本地 RTC 位宽
    parameter STATE_WIDTH       = 64,       // VL 运行期状态字位宽
    parameter REDUNDANCY_EN     = 1'b1,     // 冗余管理常量开关：0=单网 1=双网
    parameter VL_INDEX_SNMP     = 4'd1,     // SNMP 代理占用的 VL 索引（设计期分配）
    parameter VL_INDEX_615A     = 4'd2,     // 615A 代理占用的 VL 索引
    parameter VL_INDEX_RTC      = 4'd3,     // RTC 代理占用的 VL 索引
    parameter RTC_MASTER_MODE   = 1'b0,     // RTC 角色：1=主时钟（主动广播）0=从时钟
    parameter RTC_SYNC_PERIOD   = 16'd10,   // 主时钟广播周期（ms）
    parameter RTC_PROC_DELAY    = 32'd100   // 本地接收处理延迟（ns），用于延迟补偿
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk_sys,                // 系统时钟（125MHz），全模块单一时钟域
    input  wire                          rst_b,                  // 全局复位，低电平有效

    // ==================== MAC 接收接口（client 侧） ====================
    input  wire [DATA_WIDTH-1:0]         ff_rx_data,             // MAC 接收数据，1 字节/拍
    input  wire                          ff_rx_data_vld,         // MAC 接收数据有效
    input  wire                          ff_rx_sop,              // MAC 接收包起始
    input  wire                          ff_rx_eop,              // MAC 接收包结束
    input  wire                          ff_rx_err,              // MAC 接收错误
    output wire                          ff_rx_rdy,              // MAC 接收准备
    input  wire                          rx_frame_net,           // 本帧来源网络：0=网络 A 1=网络 B

    // ==================== MAC 发送接口（client 侧） ====================
    output wire [DATA_WIDTH-1:0]         ff_tx_data,             // MAC 发送数据，1 字节/拍
    output wire                          ff_tx_wren,             // MAC 发送数据写使能
    output wire                          ff_tx_sop,              // MAC 发送包起始
    output wire                          ff_tx_eop,              // MAC 发送包结束
    output wire                          ff_tx_err,              // MAC 发送错误
    input  wire                          ff_tx_rdy,              // MAC 发送准备

    // ==================== VL 配置写入接口（CPU/上位机侧） ====================
    input  wire                          cfg_wr_en,              // 配置写使能，单拍有效写一条 VL
    input  wire [VL_ADDR_WIDTH-1:0]      cfg_wr_addr,            // 配置写地址，VL 表条目索引
    input  wire [VLID_WIDTH-1:0]         cfg_wr_vlid,            // 配置写入的 VLID
    input  wire [15:0]                   cfg_wr_udp_port,        // 配置项：UDP 目的端口
    input  wire [1:0]                    cfg_wr_port_type,       // 配置项：端口类型（0=采样 1=队列）
    input  wire [15:0]                   cfg_wr_bag,             // 配置项：BAG，带宽分配间隔
    input  wire [15:0]                   cfg_wr_lmax,            // 配置项：Lmax，最大帧长（字节）
    input  wire                          cfg_wr_rm_en,           // 配置项：冗余管理使能
    input  wire                          cfg_wr_ic_mode,         // 配置项：完整性检查模式
    output wire                          cfg_done,               // 配置完成，全部条目写完后拉高

    // ==================== 应用数据接口 ====================
    input  wire [VL_INDEX_WIDTH-1:0]     app_rd_vl_index,        // 应用读 VL 索引
    input  wire [BYTE_OFFSET_WIDTH-1:0]  app_rd_byte_offset,     // 应用读字节偏移
    input  wire                          app_rd_en,              // 应用读使能（= 读请求）
    output wire [DATA_WIDTH-1:0]         app_rd_data,            // 应用读数据
    output wire                          app_rd_valid,           // 应用读数据有效（仲裁授权后拉高）
    output wire [15:0]                   app_rd_frame_len,       // 应用当前读槽位的待读帧长度（按 app_rd_vl_index 查）
    output wire [3:0]                    app_rd_frame_cnt,       // 应用当前读槽位的待读帧数（0=无数据可读）
    input  wire                          app_wr_en,              // 应用写使能，写入发送端口缓冲
    input  wire [6:0]                    app_wr_vl_index,        // 应用写 VL 索引（7 位，最多 128 个发送 VL）
    input  wire [BYTE_OFFSET_WIDTH-1:0]  app_wr_byte_offset,     // 应用写字节偏移（从 0 连续递增）
    input  wire [DATA_WIDTH-1:0]         app_wr_data,            // 应用写数据
    input  wire                          app_tx_req,             // 应用发送请求：写完一帧后拉高一拍
    output wire                          app_wr_gnt,             // 应用写请求已被接受（每写一字节需等此回执）

    // ==================== RTC 时钟同步状态 ====================
    output wire [RTC_WIDTH-1:0]          local_rtc,              // 本地 RTC 当前值（同时是 TX 的 BAG 时间基准）
    output wire                          rtc_sync_valid,         // 一次时钟同步校正完成

    // ==================== 中断 ====================
    output wire                          irq_rx_frame,           // 中断：有效接收帧到达
    output wire                          irq_tx_done,            // 中断：一帧发送完成
    output wire                          irq_error               // 中断：链路/完整性/RM 等错误
);                                                          // 端口声明或模块例化结束

    // ==================== 接收模块 ↔ VL 配置模块：配置表读 ====================
    wire [VL_ADDR_WIDTH-1:0]  rx_cfg_addr;                    // RX 查表地址
    wire                      rx_cfg_rd_en;                   // RX 查表读使能
    wire [VLID_WIDTH-1:0]     rx_cfg_tag;                     // 读回 VLID，判断查表命中
    wire                      rx_cfg_valid;                   // 条目有效标志
    wire [1:0]                rx_cfg_port_type;               // 端口类型
    wire [15:0]               rx_cfg_udp_port;                // UDP 目的端口
    wire [15:0]               rx_cfg_bag;                     // BAG
    wire [15:0]               rx_cfg_lmax;                    // Lmax
    wire                      rx_cfg_rm_en;                   // RM 使能
    wire                      rx_cfg_ic_mode;                 // IC 模式

    // ==================== 输出模块 ↔ VL 配置模块：配置表读 ====================
    wire [VL_ADDR_WIDTH-1:0]  tx_cfg_addr;                    // TX 查表地址
    wire                      tx_cfg_rd_en;                   // TX 查表读使能
    wire [VLID_WIDTH-1:0]     tx_cfg_tag;                     // 读回 VLID
    wire                      tx_cfg_valid;                   // 条目有效标志
    wire [1:0]                tx_cfg_port_type;               // 端口类型
    wire [15:0]               tx_cfg_udp_port;                // UDP 目的端口
    wire [15:0]               tx_cfg_bag;                     // BAG
    wire [15:0]               tx_cfg_lmax;                    // Lmax
    wire                      tx_cfg_rm_en;                   // RM 使能

    // ==================== 接收模块 ↔ VL 配置模块：状态表读写 ====================
    wire [VL_ADDR_WIDTH-1:0]  rx_st_addr;                     // 状态表地址
    wire                      rx_st_rd_en;                    // 状态读使能（帧首读 PSN）
    wire [STATE_WIDTH-1:0]    rx_st_rd_data;                  // 状态读数据
    wire                      rx_st_wr_en;                    // 状态写使能（帧尾写回）
    wire [STATE_WIDTH-1:0]    rx_st_wr_data;                  // 状态写数据

    // ==================== 输出模块 ↔ VL 配置模块：状态表读写 ====================
    wire [VL_ADDR_WIDTH-1:0]  tx_st_addr;                     // 状态表地址
    wire                      tx_st_rd_en;                    // 状态读使能
    wire [STATE_WIDTH-1:0]    tx_st_rd_data;                  // 状态读数据
    wire                      tx_st_wr_en;                    // 状态写使能
    wire [STATE_WIDTH-1:0]    tx_st_wr_data;                  // 状态写数据

    // ==================== 接收模块 → VL 配置模块：MIB 计数事件 ====================
    wire [VL_ADDR_WIDTH-1:0]  rx_mib_addr;                    // 计数事件所属 VL 索引
    wire                      mib_rx_frame_inc;               // 接收成功帧数 +1
    wire                      mib_rx_error_inc;               // 接收错误帧数 +1
    wire                      mib_sn_error_inc;               // SN 错误帧数 +1
    wire                      mib_rm_drop_inc;                // RM 重复帧丢弃数 +1
    wire                      mib_rx_byte_inc;                // 接收字节数 +1

    // ==================== 输出模块 → VL 配置模块：MIB 计数事件 ====================
    wire [VL_ADDR_WIDTH-1:0]  tx_mib_addr;                    // 计数事件所属 VL 索引
    wire                      mib_tx_frame_inc;               // 发送成功帧数 +1
    wire                      mib_tx_byte_inc;                // 发送字节数 +1
    wire                      mib_tx_error_inc;               // 发送错误帧数 +1
    wire                      mib_tx_frag_inc;                // 超 Lmax 被丢弃帧数 +1（原"分片次数"）
    wire                      mib_tx_bag_inc;                 // BAG 违反次数 +1

    // ==================== VL 配置模块 → 输出模块：槽位到 VLID 映射 ====================
    wire [(1<<VL_INDEX_WIDTH)*VLID_WIDTH-1:0] slot_vlid;       // 每槽位对应的完整 VLID

    // ==================== SNMP 模块 ↔ VL 配置模块：MIB 读口 ====================
    wire                      mib_sel;                        // 0=读 RX 计数表 1=读 TX 计数表
    wire [VL_ADDR_WIDTH-1:0]  mib_rd_addr;                    // 要查询的 VL 条目索引
    wire                      mib_rd_en;                      // MIB 读使能
    wire [5*CNT_WIDTH-1:0]    mib_rd_data;                    // 读回的 5 个计数器

    // ==================== 接收模块 → 各消费者：就绪通知 ====================
    wire                      rx_ready_app;                   // 应用端口一帧接收完成
    wire                      rx_ready_snmp;                  // SNMP 端口一帧接收完成
    wire                      rx_ready_615a;                  // 615A 端口一帧接收完成
    wire                      rx_ready_rtc;                   // RTC 端口一帧接收完成

    // ==================== 接收模块 → 缓冲模块：写口 ====================
    wire                      rx_port_wr_en;                  // 接收缓冲写使能
    wire [VL_INDEX_WIDTH-1:0] rx_port_wr_vl_index;            // 接收缓冲写 VL 索引
    wire [BYTE_OFFSET_WIDTH-1:0] rx_port_wr_byte_offset;      // 接收缓冲写字节偏移
    wire [DATA_WIDTH-1:0]     rx_port_wr_data;                // 接收缓冲写数据
    wire                      rx_port_wr_frame_done;          // 接收缓冲帧尾脉冲（提交本帧）
    wire                      rx_port_wr_frag_done;           // 接收缓冲每帧结束脉冲（含非末片）
    wire [15:0]               rx_port_wr_frag_off;            // 本帧在整条消息内的起始偏移
    wire                      rx_port_wr_more;                // 本帧之后还有分片
    wire [15:0]               rx_port_wr_frame_len;           // 本帧应用数据长度
    wire                      rx_port_queue_mode;             // 0=采样端口(覆盖) 1=队列/SAP端口(入队)
    wire                      rx_port_wr_full;                // 该槽位队列已满（RX 应丢弃并计错）

    // ==================== 缓冲模块 → 各消费者：读口 ====================
    wire [DATA_WIDTH-1:0]     rx_rd_data_bus;                 // 接收缓冲读数据（仲裁后共享）
    wire                      snmp_rx_rd_req;                 // SNMP 读请求
    wire [BYTE_OFFSET_WIDTH-1:0] snmp_rx_rd_byte_offset;      // SNMP 读字节偏移
    wire                      snmp_rx_rd_valid;               // SNMP 读数据有效
    wire [15:0]               snmp_rx_frame_len;             // SNMP 槽位当前待读帧长度
    wire [3:0]                snmp_rx_frame_cnt;             // SNMP 槽位待读帧数
    wire                      dl_rx_rd_req;                   // 615A 读请求
    wire [BYTE_OFFSET_WIDTH-1:0] dl_rx_rd_byte_offset;        // 615A 读字节偏移
    wire                      dl_rx_rd_valid;                 // 615A 读数据有效
    wire [15:0]               dl_rx_frame_len;               // 615A 槽位当前待读帧长度
    wire [3:0]                dl_rx_frame_cnt;               // 615A 槽位待读帧数
    wire                      rtc_rx_rd_req;                  // RTC 读请求
    wire [BYTE_OFFSET_WIDTH-1:0] rtc_rx_rd_byte_offset;       // RTC 读字节偏移
    wire                      rtc_rx_rd_valid;                // RTC 读数据有效
    wire [15:0]               rtc_rx_frame_len;              // RTC 槽位当前待读帧长度
    wire [3:0]                rtc_rx_frame_cnt;              // RTC 槽位待读帧数

    // ==================== 输出模块 → 缓冲模块：读口 ====================
    wire                      tx_port_rd_en;                  // 发送缓冲读使能
    wire [VL_INDEX_WIDTH-1:0] tx_port_rd_vl_index;            // 发送缓冲读 VL 索引
    wire [BYTE_OFFSET_WIDTH-1:0] tx_port_rd_byte_offset;      // 发送缓冲读字节偏移
    wire [DATA_WIDTH-1:0]     tx_port_rd_data;                // 发送缓冲读数据
    wire                      tx_port_rd_valid;               // 发送缓冲读数据有效
    wire [15:0]               tx_port_payload_len;            // 该 VL 待发载荷长度
    wire [15:0]               tx_abort_vl;                    // 丢弃待发帧的槽位（TX → 发送缓冲，撤销槽位）

    // ==================== 各发送方 → 缓冲模块：写口 ====================
    wire                      snmp_tx_wr_en;                  // SNMP 写发送缓冲使能
    wire [BYTE_OFFSET_WIDTH-1:0] snmp_tx_wr_byte_offset;      // SNMP 写字节偏移
    wire [DATA_WIDTH-1:0]     snmp_tx_wr_data;                // SNMP 写数据
    wire                      snmp_tx_frame_done;             // SNMP 帧尾
    wire                      dl_tx_wr_en;                    // 615A 写发送缓冲使能
    wire [BYTE_OFFSET_WIDTH-1:0] dl_tx_wr_byte_offset;        // 615A 写字节偏移
    wire [DATA_WIDTH-1:0]     dl_tx_wr_data;                  // 615A 写数据
    wire                      dl_tx_frame_done;               // 615A 帧尾
    wire                      rtc_tx_wr_en;                   // RTC 写发送缓冲使能
    wire [BYTE_OFFSET_WIDTH-1:0] rtc_tx_wr_byte_offset;       // RTC 写字节偏移
    wire [DATA_WIDTH-1:0]     rtc_tx_wr_data;                 // RTC 写数据
    wire                      rtc_tx_frame_done;              // RTC 帧尾
    wire                      snmp_tx_wr_gnt;                 // SNMP 写请求已被接受
    wire                      dl_tx_wr_gnt;                   // 615A 写请求已被接受
    wire                      rtc_tx_wr_gnt;                  // RTC 写请求已被接受

    // ==================== 615A 加载状态（预留，可引出到顶层做状态指示） ====================
    wire                      load_busy;                      // 615A 加载进行中
    wire                      load_done;                      // 615A 加载完成
    wire                      load_error;                     // 615A 加载失败

    // ==================== 网络标记（冗余开关） ====================
    // 双网时由外层网络选路模块给出本帧来源；单网时恒按 A 网处理
    wire rx_frame_net_sel = REDUNDANCY_EN ? rx_frame_net : 1'b0; // 0=网络 A 1=网络 B

    // ==================== 1) 接收模块 ====================
    afdx_rx #(                                              // 例化子模块并连接数据通路
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .VLID_WIDTH        (VLID_WIDTH),                    // 连接子模块对应端口
        .VL_ADDR_WIDTH     (VL_ADDR_WIDTH),                 // 连接子模块对应端口
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             // 连接子模块对应端口
        .CNT_WIDTH         (CNT_WIDTH),                     // 连接子模块对应端口
        .STATE_WIDTH       (STATE_WIDTH),                   // 连接子模块对应端口
        .VL_INDEX_SNMP     (VL_INDEX_SNMP),                 // 连接子模块对应端口
        .VL_INDEX_615A     (VL_INDEX_615A),                 // 连接子模块对应端口
        .VL_INDEX_RTC      (VL_INDEX_RTC)                   // 连接子模块对应端口
    ) u_afdx_rx (                                           // 参数绑定结束，开始连接实例端口
        .clk                  (clk_sys),                      // input  [0:0]
        .rst_b                (rst_b),                        // input  [0:0]
        .ff_rx_data           (ff_rx_data),                   // input  [7:0]
        .ff_rx_data_vld       (ff_rx_data_vld),               // input  [0:0]
        .ff_rx_sop            (ff_rx_sop),                    // input  [0:0]
        .ff_rx_eop            (ff_rx_eop),                    // input  [0:0]
        .ff_rx_err            (ff_rx_err),                    // input  [0:0]
        .ff_rx_rdy            (ff_rx_rdy),                    // output [0:0]
        .frame_net            (rx_frame_net_sel),             // input  [0:0]
        .cfg_addr             (rx_cfg_addr),                  // output [11:0]
        .cfg_rd_en            (rx_cfg_rd_en),                 // output [0:0]
        .cfg_tag              (rx_cfg_tag),                   // input  [15:0]
        .cfg_valid            (rx_cfg_valid),                 // input  [0:0]
        .cfg_port_type        (rx_cfg_port_type),             // input  [1:0]
        .cfg_udp_port         (rx_cfg_udp_port),              // input  [15:0]
        .cfg_bag              (rx_cfg_bag),                   // input  [15:0]
        .cfg_lmax             (rx_cfg_lmax),                  // input  [15:0]
        .cfg_rm_en            (rx_cfg_rm_en),                 // input  [0:0]
        .cfg_ic_mode          (rx_cfg_ic_mode),               // input  [0:0]
        .st_addr              (rx_st_addr),                   // output [11:0]
        .st_rd_en             (rx_st_rd_en),                  // output [0:0]
        .st_rd_data           (rx_st_rd_data),                // input  [63:0]
        .st_wr_en             (rx_st_wr_en),                  // output [0:0]
        .st_wr_data           (rx_st_wr_data),                // output [63:0]
        .port_wr_en           (rx_port_wr_en),                // output [0:0]
        .port_wr_vl_index     (rx_port_wr_vl_index),          // output [3:0]
        .port_wr_byte_offset  (rx_port_wr_byte_offset),       // output [10:0]
        .port_wr_data         (rx_port_wr_data),              // output [7:0]
        .port_wr_frame_done   (rx_port_wr_frame_done),        // output [0:0]
        .port_wr_frag_done    (rx_port_wr_frag_done),         // output [0:0]
        .port_wr_frag_off     (rx_port_wr_frag_off),          // output [15:0]
        .port_wr_more         (rx_port_wr_more),              // output [0:0]
        .port_wr_frame_len    (rx_port_wr_frame_len),         // output [15:0]
        .port_wr_queue_mode   (rx_port_queue_mode),           // output [0:0]
        .port_wr_full         (rx_port_wr_full),              // input  [0:0]
        .port_type            (),                             // output [1:0]  端口类型仅接收侧内部使用
        .rx_ready_app         (rx_ready_app),                 // output [0:0]
        .rx_ready_snmp        (rx_ready_snmp),                // output [0:0]
        .rx_ready_615a        (rx_ready_615a),                // output [0:0]
        .rx_ready_rtc         (rx_ready_rtc),                 // output [0:0]
        .mib_addr             (rx_mib_addr),                  // output [11:0]
        .mib_rx_frame_inc     (mib_rx_frame_inc),             // output [0:0]
        .mib_rx_error_inc     (mib_rx_error_inc),             // output [0:0]
        .mib_sn_error_inc     (mib_sn_error_inc),             // output [0:0]
        .mib_rm_drop_inc      (mib_rm_drop_inc),              // output [0:0]
        .mib_rx_byte_inc      (mib_rx_byte_inc),              // output [0:0]
        .irq_rx_frame         (irq_rx_frame),                 // output [0:0]
        .irq_error            (irq_error)                     // output [0:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== 2) 输出模块 ====================
    afdx_tx #(                                              // 例化子模块并连接数据通路
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .VLID_WIDTH        (VLID_WIDTH),                    // 连接子模块对应端口
        .VL_ADDR_WIDTH     (VL_ADDR_WIDTH),                 // 连接子模块对应端口
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             // 连接子模块对应端口
        .CNT_WIDTH         (CNT_WIDTH),                     // 连接子模块对应端口
        .STATE_WIDTH       (STATE_WIDTH),                   // 连接子模块对应端口
        .VL_INDEX_SNMP     (VL_INDEX_SNMP),                 // 连接子模块对应端口
        .VL_INDEX_615A     (VL_INDEX_615A),                 // 连接子模块对应端口
        .VL_INDEX_RTC      (VL_INDEX_RTC)                   // 连接子模块对应端口
    ) u_afdx_tx (                                           // 参数绑定结束，开始连接实例端口
        .clk                  (clk_sys),                      // input  [0:0]
        .rst_b                (rst_b),                        // input  [0:0]
        .sys_ts               (local_rtc[31:0]),              // input  [31:0] BAG 整形用的时间基准
        .ff_tx_data           (ff_tx_data),                   // output [7:0]
        .ff_tx_wren           (ff_tx_wren),                   // output [0:0]
        .ff_tx_sop            (ff_tx_sop),                    // output [0:0]
        .ff_tx_eop            (ff_tx_eop),                    // output [0:0]
        .ff_tx_err            (ff_tx_err),                    // output [0:0]
        .ff_tx_rdy            (ff_tx_rdy),                    // input  [0:0]
        .slot_vlid            (slot_vlid),                    // input  [255:0] 槽位→VLID 映射
        .cfg_addr             (tx_cfg_addr),                  // output [11:0]
        .cfg_rd_en            (tx_cfg_rd_en),                 // output [0:0]
        .cfg_tag              (tx_cfg_tag),                   // input  [15:0]
        .cfg_valid            (tx_cfg_valid),                 // input  [0:0]
        .cfg_port_type        (tx_cfg_port_type),             // input  [1:0]
        .cfg_udp_port         (tx_cfg_udp_port),              // input  [15:0]
        .cfg_bag              (tx_cfg_bag),                   // input  [15:0]
        .cfg_lmax             (tx_cfg_lmax),                  // input  [15:0]
        .cfg_rm_en            (tx_cfg_rm_en),                 // input  [0:0]
        .st_addr              (tx_st_addr),                   // output [11:0]
        .st_rd_en             (tx_st_rd_en),                  // output [0:0]
        .st_rd_data           (tx_st_rd_data),                // input  [63:0]
        .st_wr_en             (tx_st_wr_en),                  // output [0:0]
        .st_wr_data           (tx_st_wr_data),                // output [63:0]
        .port_rd_en           (tx_port_rd_en),                // output [0:0]
        .port_rd_vl_index     (tx_port_rd_vl_index),          // output [3:0]
        .port_rd_byte_offset  (tx_port_rd_byte_offset),       // output [10:0]
        .port_rd_data         (tx_port_rd_data),              // input  [7:0]
        .port_rd_valid        (tx_port_rd_valid),             // input  [0:0]
        .port_payload_len     (tx_port_payload_len),          // input  [15:0]
        .abort_vl             (tx_abort_vl),                  // output [15:0]
        .tx_valid_app         (app_tx_req),                   // input  [0:0]
        .tx_valid_snmp        (snmp_tx_frame_done),           // input  [0:0]
        .tx_valid_615a        (dl_tx_frame_done),             // input  [0:0]
        .tx_valid_rtc         (rtc_tx_frame_done),            // input  [0:0]
        .mib_addr             (tx_mib_addr),                  // output [11:0]
        .mib_tx_frame_inc     (mib_tx_frame_inc),             // output [0:0]
        .mib_tx_byte_inc      (mib_tx_byte_inc),              // output [0:0]
        .mib_tx_error_inc     (mib_tx_error_inc),             // output [0:0]
        .mib_tx_frag_inc      (mib_tx_frag_inc),              // output [0:0]
        .mib_tx_bag_inc       (mib_tx_bag_inc),               // output [0:0]
        .irq_tx_done          (irq_tx_done)                   // output [0:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== 3) VL 配置模块 ====================
    afdx_vl_cfg #(                                          // 例化子模块并连接数据通路
        .VLID_WIDTH    (VLID_WIDTH),                        // 连接子模块对应端口
        .VL_ADDR_WIDTH (VL_ADDR_WIDTH),                     // 连接子模块对应端口
        .VL_INDEX_WIDTH (VL_INDEX_WIDTH),                   // 连接子模块对应端口
        .CNT_WIDTH     (CNT_WIDTH),                         // 连接子模块对应端口
        .STATE_WIDTH   (STATE_WIDTH)                        // 连接子模块对应端口
    ) u_afdx_vl_cfg (                                       // 参数绑定结束，开始连接实例端口
        .clk                  (clk_sys),                      // input  [0:0]
        .rst_b                (rst_b),                        // input  [0:0]
        .cfg_wr_en            (cfg_wr_en),                    // input  [0:0]
        .cfg_wr_addr          (cfg_wr_addr),                  // input  [11:0]
        .cfg_wr_vlid          (cfg_wr_vlid),                  // input  [15:0]
        .cfg_wr_udp_port      (cfg_wr_udp_port),              // input  [15:0]
        .cfg_wr_port_type     (cfg_wr_port_type),             // input  [1:0]
        .cfg_wr_bag           (cfg_wr_bag),                   // input  [15:0]
        .cfg_wr_lmax          (cfg_wr_lmax),                  // input  [15:0]
        .cfg_wr_rm_en         (cfg_wr_rm_en),                 // input  [0:0]
        .cfg_wr_ic_mode       (cfg_wr_ic_mode),               // input  [0:0]
        .cfg_done             (cfg_done),                     // output [0:0]
        .rx_cfg_addr          (rx_cfg_addr),                  // input  [11:0]
        .rx_cfg_rd_en         (rx_cfg_rd_en),                 // input  [0:0]
        .rx_cfg_tag           (rx_cfg_tag),                   // output [15:0]
        .rx_cfg_valid         (rx_cfg_valid),                 // output [0:0]
        .rx_cfg_port_type     (rx_cfg_port_type),             // output [1:0]
        .rx_cfg_udp_port      (rx_cfg_udp_port),              // output [15:0]
        .rx_cfg_bag           (rx_cfg_bag),                   // output [15:0]
        .rx_cfg_lmax          (rx_cfg_lmax),                  // output [15:0]
        .rx_cfg_rm_en         (rx_cfg_rm_en),                 // output [0:0]
        .rx_cfg_ic_mode       (rx_cfg_ic_mode),               // output [0:0]
        .tx_cfg_addr          (tx_cfg_addr),                  // input  [11:0]
        .tx_cfg_rd_en         (tx_cfg_rd_en),                 // input  [0:0]
        .tx_cfg_tag           (tx_cfg_tag),                   // output [15:0]
        .tx_cfg_valid         (tx_cfg_valid),                 // output [0:0]
        .tx_cfg_port_type     (tx_cfg_port_type),             // output [1:0]
        .tx_cfg_udp_port      (tx_cfg_udp_port),              // output [15:0]
        .tx_cfg_bag           (tx_cfg_bag),                   // output [15:0]
        .tx_cfg_lmax          (tx_cfg_lmax),                  // output [15:0]
        .tx_cfg_rm_en         (tx_cfg_rm_en),                 // output [0:0]
        .rx_st_addr           (rx_st_addr),                   // input  [11:0]
        .rx_st_rd_en          (rx_st_rd_en),                  // input  [0:0]
        .rx_st_rd_data        (rx_st_rd_data),                // output [63:0]
        .rx_st_wr_en          (rx_st_wr_en),                  // input  [0:0]
        .rx_st_wr_data        (rx_st_wr_data),                // input  [63:0]
        .tx_st_addr           (tx_st_addr),                   // input  [11:0]
        .tx_st_rd_en          (tx_st_rd_en),                  // input  [0:0]
        .tx_st_rd_data        (tx_st_rd_data),                // output [63:0]
        .tx_st_wr_en          (tx_st_wr_en),                  // input  [0:0]
        .tx_st_wr_data        (tx_st_wr_data),                // input  [63:0]
        .rx_mib_addr          (rx_mib_addr),                  // input  [11:0]
        .mib_rx_frame_inc     (mib_rx_frame_inc),             // input  [0:0]
        .mib_rx_error_inc     (mib_rx_error_inc),             // input  [0:0]
        .mib_sn_error_inc     (mib_sn_error_inc),             // input  [0:0]
        .mib_rm_drop_inc      (mib_rm_drop_inc),              // input  [0:0]
        .mib_rx_byte_inc      (mib_rx_byte_inc),              // input  [0:0]
        .tx_mib_addr          (tx_mib_addr),                  // input  [11:0]
        .mib_tx_frame_inc     (mib_tx_frame_inc),             // input  [0:0]
        .mib_tx_byte_inc      (mib_tx_byte_inc),              // input  [0:0]
        .mib_tx_error_inc     (mib_tx_error_inc),             // input  [0:0]
        .mib_tx_frag_inc      (mib_tx_frag_inc),              // input  [0:0]
        .mib_tx_bag_inc       (mib_tx_bag_inc),               // input  [0:0]
        .mib_sel              (mib_sel),                      // input  [0:0]
        .mib_rd_addr          (mib_rd_addr),                  // input  [11:0]
        .mib_rd_en            (mib_rd_en),                    // input  [0:0]
        .mib_rd_data          (mib_rd_data),                  // output [159:0]
        .slot_vlid            (slot_vlid)                     // output [255:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== 应用帧尾筛选 ====================
    // 应用把 app_tx_req 同时当「帧尾」和「发送请求」，只有这一帧确实写了字节才算帧尾：
    // 只发请求不写数据时若照样登记长度，会把上一帧的长度再登记一次，TX 扫描就重复发送旧帧
    reg [127:0] app_data_written;                               // 每个发送 VL 是否有应用数据写进来还没登记长度
    integer     app_written_i;                                  // 复位遍历标志
    wire        app_frame_done = app_tx_req &&                  // 送 tx_wr_arb 的应用帧尾
                                 (app_data_written[app_wr_vl_index] || app_wr_gnt); // 已有未登记数据，或本拍同时写入

    always @(posedge clk_sys or negedge rst_b) begin        // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            for (app_written_i = 0; app_written_i < 128; app_written_i = app_written_i + 1)  // 依次处理 128 个发送 VL 的表项
                app_data_written[app_written_i] <= 1'b0;    // 时钟沿更新该槽位是否有未登记长度的数据
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            if (app_wr_gnt)                                 // 应用写入一字节被接受
                app_data_written[app_wr_vl_index] <= 1'b1;  // 该槽位有未登记长度的数据
            if (app_frame_done)                             // 帧尾被接受
                app_data_written[app_wr_vl_index] <= 1'b0;  // 长度已登记，清标志
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    // ==================== 4) 输入输出缓冲模块 ====================
    afdx_port_buf #(                                        // 例化子模块并连接数据通路
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                // 数据槽位位宽（4）
        .VL_IND_WIDTH      (7),                             // 逻辑发送 VL 索引位宽（128 个发送 VL）
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             // 连接子模块对应端口
        .VL_INDEX_SNMP     (VL_INDEX_SNMP),                 // 连接子模块对应端口
        .VL_INDEX_615A     (VL_INDEX_615A),                 // 连接子模块对应端口
        .VL_INDEX_RTC      (VL_INDEX_RTC)                   // 连接子模块对应端口
    ) u_afdx_port_buf (                                     // 参数绑定结束，开始连接实例端口
        .clk                  (clk_sys),                      // input  [0:0]
        .rst_b                (rst_b),                        // input  [0:0]
        .rx_wr_en             (rx_port_wr_en),                // input  [0:0]
        .rx_wr_vl_index       (rx_port_wr_vl_index),          // input  [3:0]
        .rx_wr_byte_offset    (rx_port_wr_byte_offset),       // input  [10:0]
        .rx_wr_data           (rx_port_wr_data),              // input  [7:0]
        .rx_wr_frame_done     (rx_port_wr_frame_done),        // input  [0:0]
        .rx_wr_frag_done      (rx_port_wr_frag_done),         // input  [0:0]
        .rx_wr_frag_off       (rx_port_wr_frag_off),          // input  [15:0]
        .rx_wr_more           (rx_port_wr_more),              // input  [0:0]
        .rx_wr_frame_len      (rx_port_wr_frame_len),         // input  [15:0]
        .rx_wr_queue_mode     (rx_port_queue_mode),           // input  [0:0]
        .rx_wr_full           (rx_port_wr_full),              // output [0:0]
        .app_rd_req           (app_rd_en),                    // input  [0:0]
        .app_rd_vl_index      (app_rd_vl_index),              // input  [3:0]
        .app_rd_byte_offset   (app_rd_byte_offset),           // input  [10:0]
        .app_rd_valid         (app_rd_valid),                 // output [0:0]
        .snmp_rd_req          (snmp_rx_rd_req),               // input  [0:0]
        .snmp_rd_byte_offset  (snmp_rx_rd_byte_offset),       // input  [10:0]
        .snmp_rd_valid        (snmp_rx_rd_valid),             // output [0:0]
        .dl_rd_req            (dl_rx_rd_req),                 // input  [0:0]
        .dl_rd_byte_offset    (dl_rx_rd_byte_offset),         // input  [10:0]
        .dl_rd_valid          (dl_rx_rd_valid),               // output [0:0]
        .rtc_rd_req           (rtc_rx_rd_req),                // input  [0:0]
        .rtc_rd_byte_offset   (rtc_rx_rd_byte_offset),        // input  [10:0]
        .rtc_rd_valid         (rtc_rx_rd_valid),              // output [0:0]
        .rx_rd_data           (rx_rd_data_bus),               // output [7:0]
        .app_rd_frame_len     (app_rd_frame_len),             // output [15:0]
        .app_rd_frame_cnt     (app_rd_frame_cnt),             // output [3:0]
        .snmp_rd_frame_len    (snmp_rx_frame_len),            // output [15:0]
        .snmp_rd_frame_cnt    (snmp_rx_frame_cnt),            // output [3:0]
        .dl_rd_frame_len      (dl_rx_frame_len),              // output [15:0]
        .dl_rd_frame_cnt      (dl_rx_frame_cnt),              // output [3:0]
        .rtc_rd_frame_len     (rtc_rx_frame_len),             // output [15:0]
        .rtc_rd_frame_cnt     (rtc_rx_frame_cnt),             // output [3:0]
        .app_wr_req           (app_wr_en),                    // input  [0:0]
        .app_wr_vl_index      (app_wr_vl_index),              // input  [6:0]：7 位发送 VL 索引
        .app_wr_byte_offset   (app_wr_byte_offset),           // input  [10:0]
        .app_wr_data          (app_wr_data),                  // input  [7:0]
        .app_frame_done       (app_frame_done),               // input  [0:0]
        .snmp_wr_req          (snmp_tx_wr_en),                // input  [0:0]
        .snmp_wr_byte_offset  (snmp_tx_wr_byte_offset),       // input  [10:0]
        .snmp_wr_data         (snmp_tx_wr_data),              // input  [7:0]
        .snmp_frame_done      (snmp_tx_frame_done),           // input  [0:0]
        .dl_wr_req            (dl_tx_wr_en),                  // input  [0:0]
        .dl_wr_byte_offset    (dl_tx_wr_byte_offset),         // input  [10:0]
        .dl_wr_data           (dl_tx_wr_data),                // input  [7:0]
        .dl_frame_done        (dl_tx_frame_done),             // input  [0:0]
        .rtc_wr_req           (rtc_tx_wr_en),                 // input  [0:0]
        .rtc_wr_byte_offset   (rtc_tx_wr_byte_offset),        // input  [10:0]
        .rtc_wr_data          (rtc_tx_wr_data),               // input  [7:0]
        .rtc_frame_done       (rtc_tx_frame_done),            // input  [0:0]
        .tx_rd_en             (tx_port_rd_en),                // input  [0:0]
        .tx_rd_vl_index       (tx_port_rd_vl_index),          // input  [3:0]
        .tx_rd_byte_offset    (tx_port_rd_byte_offset),       // input  [10:0]
        .tx_rd_data           (tx_port_rd_data),              // output [7:0]
        .tx_rd_valid          (tx_port_rd_valid),             // output [0:0]
        .tx_payload_len       (tx_port_payload_len),          // output [15:0]
        .abort_vl             (tx_abort_vl),                  // input  [15:0]
        .app_wr_gnt           (app_wr_gnt),                   // output [0:0]
        .snmp_wr_gnt          (snmp_tx_wr_gnt),               // output [0:0]
        .dl_wr_gnt            (dl_tx_wr_gnt),                 // output [0:0]
        .rtc_wr_gnt           (rtc_tx_wr_gnt)                 // output [0:0]
    );                                                      // 端口声明或模块例化结束

    // 四个消费者共用同一条读数据总线（rx_rd_arb 已保证同一拍只有一路被授权），
    // 应用读数据直接引出这根总线；缺这条连接时应用侧读回恒为高阻
    assign app_rd_data = rx_rd_data_bus;                        // output [7:0]：应用读数据

    // ==================== 5) SNMP 模块 ====================
    snmp_agent #(                                           // 例化子模块并连接数据通路
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             // 连接子模块对应端口
        .CNT_WIDTH         (CNT_WIDTH),                     // 连接子模块对应端口
        .VL_ADDR_WIDTH     (VL_ADDR_WIDTH),                 // 连接子模块对应端口
        .VL_INDEX_SELF     (VL_INDEX_SNMP)                  // 连接子模块对应端口
    ) u_snmp_agent (                                        // 参数绑定结束，开始连接实例端口
        .clk                (clk_sys),                        // input  [0:0]
        .rst_b              (rst_b),                          // input  [0:0]
        .rx_ready_snmp      (rx_ready_snmp),                  // input  [0:0]
        .rx_rd_req          (snmp_rx_rd_req),                 // output [0:0]
        .rx_rd_byte_offset  (snmp_rx_rd_byte_offset),         // output [10:0]
        .rx_rd_data         (rx_rd_data_bus),                 // input  [7:0]
        .rx_rd_valid        (snmp_rx_rd_valid),               // input  [0:0]
        .rx_frame_len       (snmp_rx_frame_len),              // input  [15:0]
        .tx_wr_en           (snmp_tx_wr_en),                  // output [0:0]
        .tx_wr_byte_offset  (snmp_tx_wr_byte_offset),         // output [10:0]
        .tx_wr_data         (snmp_tx_wr_data),                // output [7:0]
        .tx_frame_done      (snmp_tx_frame_done),             // output [0:0]
        .tx_wr_gnt          (snmp_tx_wr_gnt),                 // input  [0:0]
        .mib_sel            (mib_sel),                        // output [0:0]
        .mib_addr           (mib_rd_addr),                    // output [11:0]
        .mib_rd_en          (mib_rd_en),                      // output [0:0]
        .mib_rd_data        (mib_rd_data)                     // input  [159:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== 6) 615A 模块 ====================
    data_loader_615a #(                                     // 例化子模块并连接数据通路
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             // 连接子模块对应端口
        .VL_INDEX_SELF     (VL_INDEX_615A)                  // 连接子模块对应端口
    ) u_data_loader_615a (                                  // 参数绑定结束，开始连接实例端口
        .clk               (clk_sys),                         // input  [0:0]
        .rst_b             (rst_b),                           // input  [0:0]
        .rx_ready_615a     (rx_ready_615a),                   // input  [0:0]
        .rx_rd_req         (dl_rx_rd_req),                    // output [0:0]
        .rx_rd_byte_offset (dl_rx_rd_byte_offset),            // output [10:0]
        .rx_rd_data        (rx_rd_data_bus),                  // input  [7:0]
        .rx_rd_valid       (dl_rx_rd_valid),                  // input  [0:0]
        .rx_frame_len      (dl_rx_frame_len),                 // input  [15:0]
        .tx_wr_en          (dl_tx_wr_en),                     // output [0:0]
        .tx_wr_byte_offset (dl_tx_wr_byte_offset),            // output [10:0]
        .tx_wr_data        (dl_tx_wr_data),                   // output [7:0]
        .tx_frame_done     (dl_tx_frame_done),                // output [0:0]
        .tx_wr_gnt         (dl_tx_wr_gnt),                    // input  [0:0]
        .load_busy         (load_busy),                       // output [0:0]
        .load_done         (load_done),                       // output [0:0]
        .load_error        (load_error)                       // output [0:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== 7) RTC 模块 ====================
    rtc_sync #(                                             // 例化子模块并连接数据通路
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             // 连接子模块对应端口
        .RTC_WIDTH         (RTC_WIDTH),                     // 连接子模块对应端口
        .CNT_WIDTH         (CNT_WIDTH),                     // 连接子模块对应端口
        .VL_INDEX_SELF     (VL_INDEX_RTC)                   // 连接子模块对应端口
    ) u_rtc_sync (                                          // 参数绑定结束，开始连接实例端口
        .clk               (clk_sys),                         // input  [0:0]
        .rst_b             (rst_b),                           // input  [0:0]
        .rx_ready_rtc      (rx_ready_rtc),                    // input  [0:0]
        .rx_rd_req         (rtc_rx_rd_req),                   // output [0:0]
        .rx_rd_byte_offset (rtc_rx_rd_byte_offset),           // output [10:0]
        .rx_rd_data        (rx_rd_data_bus),                  // input  [7:0]
        .rx_rd_valid       (rtc_rx_rd_valid),                 // input  [0:0]
        .rx_frame_len      (rtc_rx_frame_len),                // input  [15:0]
        .tx_wr_en          (rtc_tx_wr_en),                    // output [0:0]
        .tx_wr_byte_offset (rtc_tx_wr_byte_offset),           // output [10:0]
        .tx_wr_data        (rtc_tx_wr_data),                  // output [7:0]
        .tx_frame_done     (rtc_tx_frame_done),               // output [0:0]
        .tx_wr_gnt         (rtc_tx_wr_gnt),                   // input  [0:0]
        .local_rtc         (local_rtc),                       // output [47:0]
        .rtc_sync_valid    (rtc_sync_valid),                  // output [0:0]
        .master_mode       (RTC_MASTER_MODE),                 // input  [0:0]  常量：主/从时钟
        .sync_period_ms    (RTC_SYNC_PERIOD),                 // input  [15:0] 常量：广播周期
        .rx_process_delay  (RTC_PROC_DELAY)                   // input  [31:0] 常量：接收处理延迟
    );                                                      // 端口声明或模块例化结束

endmodule                                                   // 模块定义结束

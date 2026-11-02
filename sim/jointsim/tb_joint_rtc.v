// tb_joint_rtc : 端系统联合仿真 —— RTC 全链路
// DUT：两个 AFDX_top。主时钟实例（RTC_MASTER_MODE=1）按 1ms 周期广播同步报文；
//       从时钟实例（RTC_MASTER_MODE=0）接收同步报文，经延迟补偿后校正 local_rtc。
// 用例：主模式广播帧的载荷格式与周期；从模式接收后 rtc_sync_valid 与本地时间校正值。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_joint_rtc;                                        // 声明模块及其参数接口

    localparam DATA_WIDTH        = 8;                       // 数据位宽
    localparam VLID_WIDTH        = 16;                      // VLID 位宽
    localparam VL_ADDR_WIDTH     = 12;                      // VL 表地址位宽
    localparam VL_INDEX_WIDTH    = 4;                       // 槽位号位宽
    localparam BYTE_OFFSET_WIDTH = 11;                      // 字节偏移位宽
    localparam RTC_WIDTH         = 48;                      // RTC 位宽
    localparam CLK_PERIOD        = 40;                      // 25MHz 核心时钟
    localparam BAG_CYCLES        = 25000;                   // 1ms 对应 25MHz 时钟数

    // ==================== 时钟与复位 ====================
    reg                       clk;                          // 系统时钟
    reg                       rst_b;                        // 复位

    // ==================== 主时钟实例端口 ====================
    reg  [DATA_WIDTH-1:0]     m_rx_data;                    // 主实例接收数据（未用）
    reg                       m_rx_data_vld;                // 主实例接收有效
    reg                       m_rx_sop;                     // 主实例接收帧首
    reg                       m_rx_eop;                     // 主实例接收帧尾
    reg                       m_rx_err;                     // 主实例接收错误
    wire                      m_rx_rdy;                     // 主实例接收准备
    reg                       m_frame_net;                  // 主实例网络标记
    wire [DATA_WIDTH-1:0]     m_tx_data;                    // 主实例发送数据
    wire                      m_tx_wren;                    // 主实例发送写使能
    wire                      m_tx_sop;                     // 主实例发送帧首
    wire                      m_tx_eop;                     // 主实例发送帧尾
    wire                      m_tx_err;                     // 主实例发送错误
    reg                       m_tx_rdy;                     // 主实例发送准备
    reg                       cfg_wr_en;                    // 配置写使能（两实例共用）
    reg  [VL_ADDR_WIDTH-1:0]  cfg_wr_addr;                  // 配置写地址
    reg  [VLID_WIDTH-1:0]     cfg_wr_vlid;                  // 配置写 VLID
    reg  [15:0]               cfg_wr_udp_port;              // 配置 UDP 端口
    reg  [1:0]                cfg_wr_port_type;             // 配置端口类型
    reg  [15:0]               cfg_wr_bag;                   // 配置 BAG
    reg  [15:0]               cfg_wr_lmax;                  // 配置 Lmax
    reg                       cfg_wr_rm_en;                 // 配置 RM 使能
    reg                       cfg_wr_ic_mode;               // 配置 IC 模式
    wire                      cfg_done_m;                   // 主实例配置完成
    // 主实例应用接口（未用）
    reg  [VL_INDEX_WIDTH-1:0] m_app_rd_vl;                  // 主实例应用读索引
    reg  [BYTE_OFFSET_WIDTH-1:0] m_app_rd_off;              // 主实例应用读偏移
    reg                       m_app_rd_en;                  // 主实例应用读使能
    wire [DATA_WIDTH-1:0]     m_app_rd_data;                // 主实例应用读数据
    wire                      m_app_rd_valid;               // 主实例应用读有效
    wire [15:0]               m_app_rd_len;                 // 主实例应用读长度
    wire [3:0]                m_app_rd_cnt;                 // 主实例应用读帧数
    reg                       m_app_wr_en;                  // 主实例应用写使能
    reg  [VL_INDEX_WIDTH-1:0] m_app_wr_vl;                  // 主实例应用写索引
    reg  [BYTE_OFFSET_WIDTH-1:0] m_app_wr_off;              // 主实例应用写偏移
    reg  [DATA_WIDTH-1:0]     m_app_wr_data;                // 主实例应用写数据
    reg                       m_app_tx_req;                 // 主实例应用发送请求
    wire                      m_app_wr_gnt;                 // 主实例应用写授权
    wire [RTC_WIDTH-1:0]      m_local_rtc;                  // 主实例本地 RTC
    wire                      m_rtc_sync_valid;             // 主实例同步校正完成
    wire                      m_irq_rx;                     // 主实例接收中断
    wire                      m_irq_tx;                     // 主实例发送完成中断
    wire                      m_irq_err;                    // 主实例错误中断

    // ==================== 从时钟实例端口 ====================
    reg  [DATA_WIDTH-1:0]     s_rx_data;                    // 从实例接收数据
    reg                       s_rx_data_vld;                // 从实例接收有效
    reg                       s_rx_sop;                     // 从实例接收帧首
    reg                       s_rx_eop;                     // 从实例接收帧尾
    reg                       s_rx_err;                     // 从实例接收错误
    wire                      s_rx_rdy;                     // 从实例接收准备
    reg                       s_frame_net;                  // 从实例网络标记
    wire [DATA_WIDTH-1:0]     s_tx_data;                    // 从实例发送数据
    wire                      s_tx_wren;                    // 从实例发送写使能
    wire                      s_tx_sop;                     // 从实例发送帧首
    wire                      s_tx_eop;                     // 从实例发送帧尾
    wire                      s_tx_err;                     // 从实例发送错误
    reg                       s_tx_rdy;                     // 从实例发送准备
    wire                      cfg_done_s;                   // 从实例配置完成
    reg  [VL_INDEX_WIDTH-1:0] s_app_rd_vl;                  // 从实例应用读索引
    reg  [BYTE_OFFSET_WIDTH-1:0] s_app_rd_off;              // 从实例应用读偏移
    reg                       s_app_rd_en;                  // 从实例应用读使能
    wire [DATA_WIDTH-1:0]     s_app_rd_data;                // 从实例应用读数据
    wire                      s_app_rd_valid;               // 从实例应用读有效
    wire [15:0]               s_app_rd_len;                 // 从实例应用读长度
    wire [3:0]                s_app_rd_cnt;                 // 从实例应用读帧数
    reg                       s_app_wr_en;                  // 从实例应用写使能
    reg  [VL_INDEX_WIDTH-1:0] s_app_wr_vl;                  // 从实例应用写索引
    reg  [BYTE_OFFSET_WIDTH-1:0] s_app_wr_off;              // 从实例应用写偏移
    reg  [DATA_WIDTH-1:0]     s_app_wr_data;                // 从实例应用写数据
    reg                       s_app_tx_req;                 // 从实例应用发送请求
    wire                      s_app_wr_gnt;                 // 从实例应用写授权
    wire [RTC_WIDTH-1:0]      s_local_rtc;                  // 从实例本地 RTC
    wire                      s_rtc_sync_valid;             // 从实例同步校正完成
    wire                      s_irq_rx;                     // 从实例接收中断
    wire                      s_irq_tx;                     // 从实例发送完成中断
    wire                      s_irq_err;                    // 从实例错误中断

    integer                   i;                            // 循环变量
    integer                   fail_cnt;                     // 失败计数
    integer                   tx_cnt;                       // 主实例发送字节数
    integer                   tx_frames;                    // 主实例发送帧数
    integer                   tx_cyc  [0:15];               // 主实例每帧首字节的时钟序号
    integer                   cyc;                          // 全局时钟序号
    reg  [7:0]                tx_mem [0:255];               // 主实例发送缓存
    reg  [7:0]                g_frame_buf [0:127];          // 注入帧字节
    reg  [31:0]               g_cksum;                      // IP 校验和累加器
    integer                   g_len;                        // 注入帧长度
    integer                   s_sync_cnt;                   // 从实例同步校正脉冲计数
    reg  [47:0]               master_ts_exp;                // 从实例期望的主时间戳
    reg  [31:0]               delay_exp;                    // 从实例期望的延迟补偿值

    // ==================== 从实例校正脉冲观测 ====================
    always @(posedge clk) begin                             // 每拍观测
        if (rst_b && s_rtc_sync_valid) s_sync_cnt = s_sync_cnt + 1; // 校正脉冲
    end                                                     // 观测结束

    // ==================== 时钟 ====================
    initial clk = 1'b0;                                     // 时钟初值
    always #(CLK_PERIOD/2) clk = ~clk;                      // 25MHz 核心时钟
    always @(posedge clk) cyc = cyc + 1;                    // 时钟序号

    // ==================== 主时钟实例 ====================
    AFDX_top #(                                             // 例化主时钟端系统
        .DATA_WIDTH(8), .VLID_WIDTH(16), .VL_ADDR_WIDTH(12), .CNT_WIDTH(32),  // 连接参数
        .VL_INDEX_WIDTH(4), .BYTE_OFFSET_WIDTH(11), .RTC_WIDTH(48), .STATE_WIDTH(64),  // 连接参数
        .REDUNDANCY_EN(1'b1), .VL_INDEX_SNMP(4'd1), .VL_INDEX_615A(4'd2),  // 连接参数
        .VL_INDEX_RTC(4'd3), .RTC_MASTER_MODE(1'b1), .RTC_SYNC_PERIOD(16'd1),  // 连接参数
        .RTC_PROC_DELAY(32'd0)                              // 连接参数
    ) dut_m (                                               // 实例化
        .clk_sys(clk), .rst_b(rst_b),                       // 时钟与复位
        .ff_rx_data(m_rx_data), .ff_rx_data_vld(m_rx_data_vld),  // 接收数据
        .ff_rx_sop(m_rx_sop), .ff_rx_eop(m_rx_eop), .ff_rx_err(m_rx_err),  // 接收控制
        .ff_rx_rdy(m_rx_rdy), .rx_frame_net(m_frame_net),   // 接收准备
        .ff_tx_data(m_tx_data), .ff_tx_wren(m_tx_wren),     // 发送数据
        .ff_tx_sop(m_tx_sop), .ff_tx_eop(m_tx_eop), .ff_tx_err(m_tx_err),  // 发送控制
        .ff_tx_rdy(m_tx_rdy),                               // 发送准备
        .cfg_wr_en(cfg_wr_en), .cfg_wr_addr(cfg_wr_addr),   // 配置写
        .cfg_wr_vlid(cfg_wr_vlid), .cfg_wr_udp_port(cfg_wr_udp_port),  // 配置写
        .cfg_wr_port_type(cfg_wr_port_type), .cfg_wr_bag(cfg_wr_bag),  // 配置写
        .cfg_wr_lmax(cfg_wr_lmax), .cfg_wr_rm_en(cfg_wr_rm_en),  // 配置写
        .cfg_wr_ic_mode(cfg_wr_ic_mode), .cfg_done(cfg_done_m),  // 配置写
        .app_rd_vl_index(m_app_rd_vl), .app_rd_byte_offset(m_app_rd_off),  // 应用读
        .app_rd_en(m_app_rd_en), .app_rd_data(m_app_rd_data), .app_rd_valid(m_app_rd_valid),  // 应用读
        .app_rd_frame_len(m_app_rd_len), .app_rd_frame_cnt(m_app_rd_cnt),  // 应用读
        .app_wr_en(m_app_wr_en), .app_wr_vl_index(m_app_wr_vl),  // 应用写
        .app_wr_byte_offset(m_app_wr_off), .app_wr_data(m_app_wr_data),  // 应用写
        .app_tx_req(m_app_tx_req), .app_wr_gnt(m_app_wr_gnt),  // 应用写
        .local_rtc(m_local_rtc), .rtc_sync_valid(m_rtc_sync_valid),  // RTC
        .irq_rx_frame(m_irq_rx), .irq_tx_done(m_irq_tx), .irq_error(m_irq_err)  // 中断
    );                                                      // 主实例结束

    // ==================== 从时钟实例 ====================
    AFDX_top #(                                             // 例化从时钟端系统
        .DATA_WIDTH(8), .VLID_WIDTH(16), .VL_ADDR_WIDTH(12), .CNT_WIDTH(32),  // 连接参数
        .VL_INDEX_WIDTH(4), .BYTE_OFFSET_WIDTH(11), .RTC_WIDTH(48), .STATE_WIDTH(64),  // 连接参数
        .REDUNDANCY_EN(1'b1), .VL_INDEX_SNMP(4'd1), .VL_INDEX_615A(4'd2),  // 连接参数
        .VL_INDEX_RTC(4'd3), .RTC_MASTER_MODE(1'b0), .RTC_SYNC_PERIOD(16'd1),  // 连接参数
        .RTC_PROC_DELAY(32'd0)                              // 连接参数
    ) dut_s (                                               // 实例化
        .clk_sys(clk), .rst_b(rst_b),                       // 时钟与复位
        .ff_rx_data(s_rx_data), .ff_rx_data_vld(s_rx_data_vld),  // 接收数据
        .ff_rx_sop(s_rx_sop), .ff_rx_eop(s_rx_eop), .ff_rx_err(s_rx_err),  // 接收控制
        .ff_rx_rdy(s_rx_rdy), .rx_frame_net(s_frame_net),   // 接收准备
        .ff_tx_data(s_tx_data), .ff_tx_wren(s_tx_wren),     // 发送数据
        .ff_tx_sop(s_tx_sop), .ff_tx_eop(s_tx_eop), .ff_tx_err(s_tx_err),  // 发送控制
        .ff_tx_rdy(s_tx_rdy),                               // 发送准备
        .cfg_wr_en(cfg_wr_en), .cfg_wr_addr(cfg_wr_addr),   // 配置写
        .cfg_wr_vlid(cfg_wr_vlid), .cfg_wr_udp_port(cfg_wr_udp_port),  // 配置写
        .cfg_wr_port_type(cfg_wr_port_type), .cfg_wr_bag(cfg_wr_bag),  // 配置写
        .cfg_wr_lmax(cfg_wr_lmax), .cfg_wr_rm_en(cfg_wr_rm_en),  // 配置写
        .cfg_wr_ic_mode(cfg_wr_ic_mode), .cfg_done(cfg_done_s),  // 配置写
        .app_rd_vl_index(s_app_rd_vl), .app_rd_byte_offset(s_app_rd_off),  // 应用读
        .app_rd_en(s_app_rd_en), .app_rd_data(s_app_rd_data), .app_rd_valid(s_app_rd_valid),  // 应用读
        .app_rd_frame_len(s_app_rd_len), .app_rd_frame_cnt(s_app_rd_cnt),  // 应用读
        .app_wr_en(s_app_wr_en), .app_wr_vl_index(s_app_wr_vl),  // 应用写
        .app_wr_byte_offset(s_app_wr_off), .app_wr_data(s_app_wr_data),  // 应用写
        .app_tx_req(s_app_tx_req), .app_wr_gnt(s_app_wr_gnt),  // 应用写
        .local_rtc(s_local_rtc), .rtc_sync_valid(s_rtc_sync_valid),  // RTC
        .irq_rx_frame(s_irq_rx), .irq_tx_done(s_irq_tx), .irq_error(s_irq_err)  // 中断
    );                                                      // 从实例结束

    // ==================== 主实例发送采集 ====================
    always @(posedge clk) begin                             // 每拍采集
        if (rst_b && m_tx_wren) begin                       // 有效发送拍
            if (m_tx_sop) tx_cyc[tx_frames] = cyc;          // 记录首字节时钟
            tx_mem[tx_cnt] = m_tx_data;                     // 缓存
            tx_cnt = tx_cnt + 1;                            // 计数
            if (m_tx_eop) tx_frames = tx_frames + 1;        // 帧数
        end                                                 // 采集结束
    end                                                     // 采集结束

    // ==================== 配置写任务 ====================
    task cfg_write;                                         // 写一条 VL 配置（两实例共用）
        input [15:0] vlid;                                  // VLID
        input [15:0] udp_port;                              // UDP 目的端口
        input [1:0]  ptype;                                 // 端口类型
        begin                                               // 任务主体
            @(posedge clk);                                 // 等采样沿
            cfg_wr_addr      <= vlid[VL_ADDR_WIDTH-1:0];    // 地址
            cfg_wr_vlid      <= vlid;                       // VLID
            cfg_wr_udp_port  <= udp_port;                   // UDP 端口
            cfg_wr_port_type <= ptype;                      // 端口类型
            cfg_wr_bag       <= 16'd1;                      // BAG
            cfg_wr_lmax      <= 16'd512;                    // Lmax
            cfg_wr_rm_en     <= 1'b0;                       // RM 使能
            cfg_wr_ic_mode   <= 1'b0;                       // IC 模式
            cfg_wr_en        <= 1'b1;                       // 写使能
            @(posedge clk);                                 // 等采样沿
            cfg_wr_en        <= 1'b0;                       // 撤销
            repeat (2) @(posedge clk);                      // 等落表
        end                                                 // 任务主体结束
    endtask                                                 // 配置写任务结束

    // ==================== 帧组装任务 ====================
    task build_frame;                                       // 组装一帧 AFDX 报文
        input [15:0] vlid;                                  // 目标 VLID
        input [15:0] udp_dst;                               // UDP 目的端口
        input integer dlen;                                 // 应用数据长度
        input [7:0]  sn;                                    // 序列号
        begin                                               // 任务主体
            g_frame_buf[0] = 8'h01; g_frame_buf[1] = 8'h00; // 目的 MAC 前缀
            g_frame_buf[2] = 8'h00; g_frame_buf[3] = 8'h00; // 目的 MAC 前缀
            g_frame_buf[4] = vlid[15:8]; g_frame_buf[5] = vlid[7:0]; // VLID
            g_frame_buf[6] = 8'h02; g_frame_buf[7] = 8'h00; // 源 MAC
            g_frame_buf[8] = 8'h00; g_frame_buf[9] = 8'h00; // 源 MAC
            g_frame_buf[10] = 8'h00; g_frame_buf[11] = 8'h01; // 源 MAC
            g_frame_buf[12] = 8'h08; g_frame_buf[13] = 8'h00; // IPv4
            g_frame_buf[14] = 8'h45; g_frame_buf[15] = 8'h00; // 版本/IHL、TOS
            g_frame_buf[16] = 8'h00; g_frame_buf[17] = (29 + dlen); // IP 总长度
            g_frame_buf[18] = 8'h00; g_frame_buf[19] = 8'h01; // 标识
            g_frame_buf[20] = 8'h40; g_frame_buf[21] = 8'h00; // DF、片偏移
            g_frame_buf[22] = 8'h01; g_frame_buf[23] = 8'h11; // TTL、UDP
            g_frame_buf[24] = 8'h00; g_frame_buf[25] = 8'h00; // 校验和占位
            g_frame_buf[26] = 8'h04; g_frame_buf[27] = 8'h00; // 源 IP
            g_frame_buf[28] = 8'h00; g_frame_buf[29] = 8'h01; // 源 IP
            g_frame_buf[30] = 8'hE0; g_frame_buf[31] = 8'hE0; // 目的 IP 前缀
            g_frame_buf[32] = vlid[15:8]; g_frame_buf[33] = vlid[7:0]; // 目的 IP 低位
            g_frame_buf[34] = 8'h00; g_frame_buf[35] = 8'hA1; // UDP 源端口
            g_frame_buf[36] = udp_dst[15:8]; g_frame_buf[37] = udp_dst[7:0]; // UDP 目的端口
            g_frame_buf[38] = 8'h00; g_frame_buf[39] = 9 + dlen; // UDP 长度
            g_frame_buf[40] = 8'h00; g_frame_buf[41] = 8'h00; // UDP 校验和
            g_frame_buf[42 + dlen] = sn;                    // 序列号
            g_cksum = 32'd0;                                // 校验和清零
            for (i = 0; i < 10; i = i + 1)                  // 逐 16bit 字累加
                g_cksum = g_cksum + {1'b0, g_frame_buf[14 + i*2], g_frame_buf[15 + i*2]}; // 累加
            g_cksum = (g_cksum & 32'hFFFF) + (g_cksum >> 16); // 回卷
            g_cksum = (g_cksum & 32'hFFFF) + (g_cksum >> 16); // 再回卷
            g_frame_buf[24] = ~g_cksum[15:8];               // 校验和高字节
            g_frame_buf[25] = ~g_cksum[7:0];                // 校验和低字节
            g_len = 14 + 20 + 8 + dlen + 1;                 // 整帧字节数
        end                                                 // 任务主体结束
    endtask                                                 // 帧组装任务结束

    // ==================== 帧注入任务（从实例） ====================
    task inject_slave;                                      // 向从实例注入同步帧
        begin                                               // 任务主体
            wait (s_rx_rdy === 1'b1);                       // 等就绪
            @(posedge clk);                                 // 等采样沿
            s_frame_net <= 1'b0;                            // 网络标记
            for (i = 0; i < g_len; i = i + 1) begin         // 逐字节注入
                s_rx_data     <= g_frame_buf[i];            // 数据
                s_rx_data_vld <= 1'b1;                      // 有效
                s_rx_sop      <= (i == 0);                  // 帧首
                s_rx_eop      <= (i == g_len-1);            // 帧尾
                @(posedge clk);                             // 等采样沿
            end                                             // 注入结束
            s_rx_data_vld <= 1'b0;                          // 撤销有效
            s_rx_sop      <= 1'b0;                          // 撤销帧首
            s_rx_eop      <= 1'b0;                          // 撤销帧尾
            repeat (60) @(posedge clk);                     // 等状态机走完
        end                                                 // 任务主体结束
    endtask                                                 // 注入任务结束

    // ==================== 失败记录任务 ====================
    task do_fail;                                           // 记录一次失败
        input [511:0] msg;                                  // 失败信息
        begin                                               // 任务主体
            $display("  [FAIL] %0s", msg);                  // 打印失败
            fail_cnt = fail_cnt + 1;                        // 失败计数
        end                                                 // 任务主体结束
    endtask                                                 // 失败记录任务结束

    // ==================== 主流程 ====================
    initial begin                                           // 激励流程
        clk = 1'b0; rst_b = 1'b0;                           // 初值
        m_rx_data = 8'h00; m_rx_data_vld = 1'b0; m_rx_sop = 1'b0; m_rx_eop = 1'b0; m_rx_err = 1'b0; // 主实例接收初值
        m_frame_net = 1'b0; m_tx_rdy = 1'b1;                // 主实例初值
        s_rx_data = 8'h00; s_rx_data_vld = 1'b0; s_rx_sop = 1'b0; s_rx_eop = 1'b0; s_rx_err = 1'b0; // 从实例接收初值
        s_frame_net = 1'b0; s_tx_rdy = 1'b1;                // 从实例初值
        cfg_wr_en = 1'b0; cfg_wr_addr = 12'd0; cfg_wr_vlid = 16'd0;  // 配置初值
        cfg_wr_udp_port = 16'd0; cfg_wr_port_type = 2'd0; cfg_wr_bag = 16'd0;  // 配置初值
        cfg_wr_lmax = 16'd0; cfg_wr_rm_en = 1'b0; cfg_wr_ic_mode = 1'b0;  // 配置初值
        m_app_rd_vl = 4'd0; m_app_rd_off = 11'd0; m_app_rd_en = 1'b0;  // 主实例应用读初值
        m_app_wr_en = 1'b0; m_app_wr_vl = 4'd0; m_app_wr_off = 11'd0;  // 主实例应用写初值
        m_app_wr_data = 8'h00; m_app_tx_req = 1'b0;         // 主实例应用写初值
        s_app_rd_vl = 4'd0; s_app_rd_off = 11'd0; s_app_rd_en = 1'b0;  // 从实例应用读初值
        s_app_wr_en = 1'b0; s_app_wr_vl = 4'd0; s_app_wr_off = 11'd0;  // 从实例应用写初值
        s_app_wr_data = 8'h00; s_app_tx_req = 1'b0;         // 从实例应用写初值
        cyc = 0; tx_cnt = 0; tx_frames = 0; fail_cnt = 0; s_sync_cnt = 0; // 计数初值
        repeat (10) @(posedge clk);                         // 保持复位
        rst_b = 1'b1;                                       // 释放复位
        repeat (5) @(posedge clk);                          // 等稳定

        cfg_write(16'h0003, 16'd4000, 2'b01);               // RTC VL（两实例都写）
        @(posedge clk); cfg_wr_vlid <= 16'hFFFF; cfg_wr_en <= 1'b1; // 哨兵
        @(posedge clk); cfg_wr_en <= 1'b0;                  // 撤销
        repeat (6) @(posedge clk);                          // 等 cfg_done

        $display("=== 主时钟广播 ===");                    // 用例标题
        wait (tx_frames >= 1);                              // 等第一帧
        repeat (8) @(posedge clk);                          // 等采集稳定
        if (tx_frames >= 1) $display("  [PASS] master frame sent"); // 有帧
        else do_fail("no master sync frame");               // 无帧
        if (tx_mem[48] == 8'h00 && tx_mem[49] == 8'h00 && tx_mem[50] == 8'h00 && tx_mem[51] == 8'h00) // 延迟字段
            $display("  [PASS] master delay field = 0");    // 通过
        else do_fail("master delay field");                 // 失败
        wait (tx_frames >= 2);                              // 等第二帧
        repeat (8) @(posedge clk);                          // 等采集稳定
        if ((tx_cyc[1] - tx_cyc[0]) >= (BAG_CYCLES - 400)) // 周期约 1ms
            $display("  [PASS] master period ~1ms (%0d cycles)", tx_cyc[1] - tx_cyc[0]); // 通过
        else begin                                          // 失败
            $display("  [FAIL] master period %0d cycles (exp %0d)", tx_cyc[1] - tx_cyc[0], BAG_CYCLES); // 打印实测
            fail_cnt = fail_cnt + 1;                        // 失败计数
        end                                                 // 失败结束

        $display("=== 从时钟接收与延迟补偿 ===");            // 用例标题
        master_ts_exp = 48'h112233445566;                   // 主时间戳
        delay_exp     = 32'h00000102;                       // 延迟补偿值
        build_frame(16'h0003, 16'd4000, 17, 8'd0);          // 组装同步帧
        g_frame_buf[42] = 8'h11; g_frame_buf[43] = 8'h22;   // 主时间戳高字节
        g_frame_buf[44] = 8'h33; g_frame_buf[45] = 8'h44;   // 主时间戳
        g_frame_buf[46] = 8'h55; g_frame_buf[47] = 8'h66;   // 主时间戳低字节
        g_frame_buf[48] = 8'h00; g_frame_buf[49] = 8'h00;   // 延迟高字节
        g_frame_buf[50] = 8'h01; g_frame_buf[51] = 8'h02;   // 延迟低字节
        inject_slave();                                     // 注入
        s_app_rd_vl <= 4'd3;                                // 观察 RTC 槽位
        repeat (600) @(posedge clk);                        // 等接收/校正处理
        if (s_sync_cnt >= 1) $display("  [PASS] rtc_sync_valid"); // 校正完成
        else do_fail("rtc_sync_valid not set");             // 未校正
        if (s_sync_cnt >= 1 && s_local_rtc >= (master_ts_exp + delay_exp) &&  // 校正值范围
            s_local_rtc <= (master_ts_exp + delay_exp + 48'd64))  // 允许少量走时
            $display("  [PASS] local_rtc corrected");       // 通过
        else begin                                          // 失败
            $display("  [FAIL] local_rtc = %0d (exp %0d)", s_local_rtc, master_ts_exp + delay_exp); // 打印
            fail_cnt = fail_cnt + 1;                        // 失败计数
        end                                                 // 失败结束

        if (fail_cnt == 0) $display("PASS: joint rtc chain"); // 汇总
        else $display("FAIL: joint rtc failures=%0d", fail_cnt); // 汇总
        $finish;                                            // 结束
    end                                                     // 激励结束

endmodule                                                   // 模块定义结束

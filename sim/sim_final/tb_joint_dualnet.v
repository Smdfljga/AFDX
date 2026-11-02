// tb_joint_dualnet : 端系统联合仿真 —— 双网接收胶合
// DUT：afdx_net_rx（双网帧缓存/选路）+ AFDX_top（端系统核心）。
// 用例：A 网单帧、B 网单帧、A/B 同帧副本（RM 使能丢一份）、A/B 不同 SN 两帧都收、
//       应用发送经核心输出到 ff_tx。
// 说明：MAC 侧直接用字节流激励；tx_rdy 常置 1。本文件只用于仿真。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_joint_dualnet;                                    // 声明模块及其参数接口

    localparam DATA_WIDTH        = 8;                       // 数据位宽
    localparam VLID_WIDTH        = 16;                      // VLID 位宽
    localparam VL_ADDR_WIDTH     = 12;                      // VL 表地址位宽
    localparam VL_INDEX_WIDTH    = 4;                       // 槽位号位宽
    localparam BYTE_OFFSET_WIDTH = 11;                      // 字节偏移位宽
    localparam RTC_WIDTH         = 48;                      // RTC 位宽
    localparam CLK_PERIOD        = 40;                      // 25MHz 核心时钟
    localparam FRAME_LEN         = 60;                      // 14+20+8+17 数据+1 SN

    // ==================== 双网 MAC 侧激励 ====================
    reg                       clk;                          // 系统时钟
    reg                       rst_b;                        // 复位
    reg  [DATA_WIDTH-1:0]     a_rx_data;                    // A 网接收数据
    reg                       a_rx_data_vld;                // A 网数据有效
    reg                       a_rx_sop;                     // A 网包起始
    reg                       a_rx_eop;                     // A 网包结束
    reg                       a_rx_err;                     // A 网错误
    wire                      a_rx_rdy;                     // A 网接收准备
    reg  [DATA_WIDTH-1:0]     b_rx_data;                    // B 网接收数据
    reg                       b_rx_data_vld;                // B 网数据有效
    reg                       b_rx_sop;                     // B 网包起始
    reg                       b_rx_eop;                     // B 网包结束
    reg                       b_rx_err;                     // B 网错误
    wire                      b_rx_rdy;                     // B 网接收准备

    // ==================== 核心 MAC 侧 ====================
    wire [DATA_WIDTH-1:0]     core_rx_data;                 // 核心接收数据
    wire                      core_rx_data_vld;             // 核心接收数据有效
    wire                      core_rx_sop;                  // 核心接收包起始
    wire                      core_rx_eop;                  // 核心接收包结束
    wire                      core_rx_err;                  // 核心接收错误
    wire                      core_rx_rdy;                  // 核心接收准备
    wire                      core_frame_net;               // 核心网络标记
    wire [DATA_WIDTH-1:0]     core_tx_data;                 // 核心发送数据
    wire                      core_tx_wren;                 // 核心发送写使能
    wire                      core_tx_sop;                  // 核心发送包起始
    wire                      core_tx_eop;                  // 核心发送包结束
    wire                      core_tx_err;                  // 核心发送错误
    reg                       core_tx_rdy;                  // 核心发送准备

    // ==================== 核心配置/应用接口 ====================
    reg                       cfg_wr_en;                    // 配置写使能
    reg  [VL_ADDR_WIDTH-1:0]  cfg_wr_addr;                  // 配置写地址
    reg  [VLID_WIDTH-1:0]     cfg_wr_vlid;                  // 配置写 VLID
    reg  [15:0]               cfg_wr_udp_port;              // 配置 UDP 端口
    reg  [1:0]                cfg_wr_port_type;             // 配置端口类型
    reg  [15:0]               cfg_wr_bag;                   // 配置 BAG
    reg  [15:0]               cfg_wr_lmax;                  // 配置 Lmax
    reg                       cfg_wr_rm_en;                 // 配置 RM 使能
    reg                       cfg_wr_ic_mode;               // 配置 IC 模式
    wire                      cfg_done;                     // 配置完成
    reg  [VL_INDEX_WIDTH-1:0] app_rd_vl_index;              // 应用读 VL 索引
    reg  [BYTE_OFFSET_WIDTH-1:0] app_rd_byte_offset;        // 应用读字节偏移
    reg                       app_rd_en;                    // 应用读使能
    wire [DATA_WIDTH-1:0]     app_rd_data;                  // 应用读数据
    wire                      app_rd_valid;                 // 应用读数据有效
    wire [15:0]               app_rd_frame_len;             // 应用待读帧长度
    wire [3:0]                app_rd_frame_cnt;             // 应用待读帧数
    reg                       app_wr_en;                    // 应用写使能
    reg  [VL_INDEX_WIDTH-1:0] app_wr_vl_index;              // 应用写 VL 索引
    reg  [BYTE_OFFSET_WIDTH-1:0] app_wr_byte_offset;        // 应用写字节偏移
    reg  [DATA_WIDTH-1:0]     app_wr_data;                  // 应用写数据
    reg                       app_tx_req;                   // 应用发送请求
    wire                      app_wr_gnt;                   // 应用写授权
    wire [RTC_WIDTH-1:0]      local_rtc;                    // 本地 RTC
    wire                      rtc_sync_valid;               // RTC 同步校正完成
    wire                      irq_rx_frame;                 // 接收帧中断
    wire                      irq_tx_done;                  // 发送完成中断
    wire                      irq_error;                    // 错误中断

    integer                   i;                            // 循环变量
    integer                   fail_cnt;                     // 失败计数
    integer                   g_commit;                     // 成功帧计数
    integer                   g_rm_drop;                    // RM 丢弃计数
    integer                   g_err;                        // 错误帧计数
    reg  [7:0]                g_frame_buf [0:FRAME_LEN-1];  // 注入帧字节
    reg  [31:0]               g_cksum;                      // IP 校验和累加器
    integer                   tx_cnt;                       // 发送字节数
    integer                   tx_frames;                    // 发送帧数
    reg  [7:0]                tx_mem [0:255];               // 发送字节缓存

    // ==================== 时钟 ====================
    initial clk = 1'b0;                                     // 时钟初值
    always #(CLK_PERIOD/2) clk = ~clk;                      // 25MHz 核心时钟

    // ==================== 双网接收胶合 ====================
    afdx_net_rx #(                                          // 双网帧缓存与整帧选路
        .DATA_WIDTH(8), .ADDR_WIDTH(12), .MAX_FRAME(1536)   // 参数
    ) u_net (                                               // 实例化
        .wr_clk(clk), .rd_clk(clk), .rst_b(rst_b),              // 时钟与复位
        .a_rx_data(a_rx_data), .a_rx_data_vld(a_rx_data_vld), // A 网数据
        .a_rx_sop(a_rx_sop), .a_rx_eop(a_rx_eop), .a_rx_err(a_rx_err), // A 网控制
        .a_rx_rdy(a_rx_rdy),                                // A 网准备
        .b_rx_data(b_rx_data), .b_rx_data_vld(b_rx_data_vld), // B 网数据
        .b_rx_sop(b_rx_sop), .b_rx_eop(b_rx_eop), .b_rx_err(b_rx_err), // B 网控制
        .b_rx_rdy(b_rx_rdy),                                // B 网准备
        .ff_rx_data(core_rx_data), .ff_rx_data_vld(core_rx_data_vld), // 到核心的数据
        .ff_rx_sop(core_rx_sop), .ff_rx_eop(core_rx_eop), .ff_rx_err(core_rx_err), // 到核心的控制
        .ff_rx_rdy(core_rx_rdy), .frame_net(core_frame_net) // 核心准备与网络标记
    );                                                      // 胶合实例化结束

    // ==================== 端系统核心 ====================
    AFDX_top #(                                             // 例化端系统顶层
        .DATA_WIDTH(8), .VLID_WIDTH(16), .VL_ADDR_WIDTH(12), .CNT_WIDTH(32),  // 连接参数
        .VL_INDEX_WIDTH(4), .BYTE_OFFSET_WIDTH(11), .RTC_WIDTH(48), .STATE_WIDTH(64),  // 连接参数
        .REDUNDANCY_EN(1'b1), .VL_INDEX_SNMP(4'd1), .VL_INDEX_615A(4'd2),  // 连接参数
        .VL_INDEX_RTC(4'd3), .RTC_MASTER_MODE(1'b0), .RTC_SYNC_PERIOD(16'd1),  // 连接参数
        .RTC_PROC_DELAY(32'd0)                              // 连接参数
    ) dut (                                                 // 实例化
        .clk_sys(clk), .rst_b(rst_b),                       // 时钟与复位
        .ff_rx_data(core_rx_data), .ff_rx_data_vld(core_rx_data_vld),  // 接收数据
        .ff_rx_sop(core_rx_sop), .ff_rx_eop(core_rx_eop), .ff_rx_err(core_rx_err),  // 接收控制
        .ff_rx_rdy(core_rx_rdy), .rx_frame_net(core_frame_net), // 接收准备与网络标记
        .ff_tx_data(core_tx_data), .ff_tx_wren(core_tx_wren), // 发送数据
        .ff_tx_sop(core_tx_sop), .ff_tx_eop(core_tx_eop), .ff_tx_err(core_tx_err),  // 发送控制
        .ff_tx_rdy(core_tx_rdy),                            // 发送准备
        .cfg_wr_en(cfg_wr_en), .cfg_wr_addr(cfg_wr_addr),   // 配置写
        .cfg_wr_vlid(cfg_wr_vlid), .cfg_wr_udp_port(cfg_wr_udp_port),  // 配置写
        .cfg_wr_port_type(cfg_wr_port_type), .cfg_wr_bag(cfg_wr_bag),  // 配置写
        .cfg_wr_lmax(cfg_wr_lmax), .cfg_wr_rm_en(cfg_wr_rm_en),  // 配置写
        .cfg_wr_ic_mode(cfg_wr_ic_mode), .cfg_done(cfg_done),  // 配置写
        .app_rd_vl_index(app_rd_vl_index), .app_rd_byte_offset(app_rd_byte_offset),  // 应用读
        .app_rd_en(app_rd_en), .app_rd_data(app_rd_data), .app_rd_valid(app_rd_valid),  // 应用读
        .app_rd_frame_len(app_rd_frame_len), .app_rd_frame_cnt(app_rd_frame_cnt),  // 应用读
        .app_wr_en(app_wr_en), .app_wr_vl_index(app_wr_vl_index),  // 应用写
        .app_wr_byte_offset(app_wr_byte_offset), .app_wr_data(app_wr_data),  // 应用写
        .app_tx_req(app_tx_req), .app_wr_gnt(app_wr_gnt),   // 应用写
        .local_rtc(local_rtc), .rtc_sync_valid(rtc_sync_valid),  // RTC
        .irq_rx_frame(irq_rx_frame), .irq_tx_done(irq_tx_done), .irq_error(irq_error)  // 中断
    );                                                      // 核心例化结束

    // ==================== 计数观测 ====================
    always @(posedge clk) begin                             // 每拍观测
        if (rst_b) begin                                    // 复位释放后
            if (dut.mib_rx_frame_inc) g_commit = g_commit + 1; // 成功帧
            if (dut.mib_rm_drop_inc)  g_rm_drop = g_rm_drop + 1; // RM 丢弃
            if (dut.mib_rx_error_inc) g_err = g_err + 1;     // 错误帧
        end                                                 // 观测结束
    end                                                     // 观测结束

    // ==================== 发送字节采集 ====================
    always @(posedge clk) begin                             // 每拍采集
        if (rst_b && core_tx_wren) begin                    // 有效发送拍
            tx_mem[tx_cnt] = core_tx_data;                  // 缓存
            tx_cnt = tx_cnt + 1;                            // 计数
            if (core_tx_eop) tx_frames = tx_frames + 1;     // 帧数
        end                                                 // 采集结束
    end                                                     // 采集结束

    // ==================== 配置写任务 ====================
    task cfg_write;                                         // 写一条 VL 配置
        input [15:0] vlid;                                  // VLID
        input [15:0] udp_port;                              // UDP 目的端口
        input [1:0]  ptype;                                 // 端口类型
        input [15:0] bag;                                   // BAG
        input [15:0] lmax;                                  // Lmax
        input        rm_en;                                 // RM 使能
        begin                                               // 任务主体
            @(posedge clk);                                 // 等采样沿
            cfg_wr_addr      <= vlid[VL_ADDR_WIDTH-1:0];    // 地址
            cfg_wr_vlid      <= vlid;                       // VLID
            cfg_wr_udp_port  <= udp_port;                   // UDP 端口
            cfg_wr_port_type <= ptype;                      // 端口类型
            cfg_wr_bag       <= bag;                        // BAG
            cfg_wr_lmax      <= lmax;                       // Lmax
            cfg_wr_rm_en     <= rm_en;                      // RM 使能
            cfg_wr_ic_mode   <= 1'b0;                       // IC 模式
            cfg_wr_en        <= 1'b1;                       // 写使能
            @(posedge clk);                                 // 等采样沿
            cfg_wr_en        <= 1'b0;                       // 撤销
            repeat (2) @(posedge clk);                      // 等落表
        end                                                 // 任务主体结束
    endtask                                                 // 配置写任务结束

    // ==================== 帧组装任务 ====================
    task build_frame;                                       // 组装一帧 AFDX 报文
        input [7:0] sn;                                     // 序列号
        begin                                               // 任务主体
            g_frame_buf[0] = 8'h01; g_frame_buf[1] = 8'h00; // 目的 MAC 前缀
            g_frame_buf[2] = 8'h00; g_frame_buf[3] = 8'h00; // 目的 MAC 前缀
            g_frame_buf[4] = 8'h00; g_frame_buf[5] = 8'h04; // VLID=4
            g_frame_buf[6] = 8'h02; g_frame_buf[7] = 8'h00; // 源 MAC
            g_frame_buf[8] = 8'h00; g_frame_buf[9] = 8'h00; // 源 MAC
            g_frame_buf[10] = 8'h00; g_frame_buf[11] = 8'h01; // 源 MAC
            g_frame_buf[12] = 8'h08; g_frame_buf[13] = 8'h00; // IPv4
            g_frame_buf[14] = 8'h45; g_frame_buf[15] = 8'h00; // 版本/IHL、TOS
            g_frame_buf[16] = 8'h00; g_frame_buf[17] = 8'h2E; // IP 总长度 46
            g_frame_buf[18] = 8'h00; g_frame_buf[19] = 8'h01; // 标识
            g_frame_buf[20] = 8'h40; g_frame_buf[21] = 8'h00; // DF、片偏移
            g_frame_buf[22] = 8'h01; g_frame_buf[23] = 8'h11; // TTL、UDP
            g_frame_buf[24] = 8'h00; g_frame_buf[25] = 8'h00; // 校验和占位
            g_frame_buf[26] = 8'h04; g_frame_buf[27] = 8'h00; // 源 IP
            g_frame_buf[28] = 8'h00; g_frame_buf[29] = 8'h01; // 源 IP
            g_frame_buf[30] = 8'hE0; g_frame_buf[31] = 8'hE0; // 目的 IP 前缀
            g_frame_buf[32] = 8'h00; g_frame_buf[33] = 8'h04; // 目的 IP 低位
            g_frame_buf[34] = 8'h00; g_frame_buf[35] = 8'hA1; // UDP 源端口
            g_frame_buf[36] = 8'h0F; g_frame_buf[37] = 8'hA1; // UDP 目的端口 4001
            g_frame_buf[38] = 8'h00; g_frame_buf[39] = 8'h1A; // UDP 长度
            g_frame_buf[40] = 8'h00; g_frame_buf[41] = 8'h00; // UDP 校验和
            for (i = 0; i < 17; i = i + 1)                  // 应用数据
                g_frame_buf[42 + i] = i[7:0];               // 数据
            g_frame_buf[59] = sn;                           // 序列号
            g_cksum = 32'd0;                                // 校验和清零
            for (i = 0; i < 10; i = i + 1)                  // 逐 16bit 字累加
                g_cksum = g_cksum + {1'b0, g_frame_buf[14 + i*2], g_frame_buf[15 + i*2]}; // 累加
            g_cksum = (g_cksum & 32'hFFFF) + (g_cksum >> 16); // 回卷
            g_cksum = (g_cksum & 32'hFFFF) + (g_cksum >> 16); // 再回卷
            g_frame_buf[24] = ~g_cksum[15:8];               // 校验和高字节
            g_frame_buf[25] = ~g_cksum[7:0];                // 校验和低字节
        end                                                 // 任务主体结束
    endtask                                                 // 帧组装任务结束

    // ==================== 双网注入任务 ====================
    task inject_a;                                          // 在 A 网注入整帧
        input [7:0] sn;                                     // 序列号
        begin                                               // 任务主体
            build_frame(sn);                                // 组装
            for (i = 0; i < FRAME_LEN; i = i + 1) begin     // 逐字节注入
                @(negedge clk);                             // 非采样沿改值
                a_rx_data     = g_frame_buf[i];             // 数据
                a_rx_data_vld = 1'b1;                       // 有效
                a_rx_sop      = (i == 0);                   // 帧首
                a_rx_eop      = (i == FRAME_LEN-1);         // 帧尾
            end                                             // 注入结束
            @(negedge clk); a_rx_data_vld = 1'b0; a_rx_sop = 1'b0; a_rx_eop = 1'b0; // 撤销
            repeat (80) @(posedge clk);                     // 等缓存/核心处理
        end                                                 // 任务主体结束
    endtask                                                 // A 网注入任务结束

    task inject_b;                                          // 在 B 网注入整帧
        input [7:0] sn;                                     // 序列号
        begin                                               // 任务主体
            build_frame(sn);                                // 组装
            for (i = 0; i < FRAME_LEN; i = i + 1) begin     // 逐字节注入
                @(negedge clk);                             // 非采样沿改值
                b_rx_data     = g_frame_buf[i];             // 数据
                b_rx_data_vld = 1'b1;                       // 有效
                b_rx_sop      = (i == 0);                   // 帧首
                b_rx_eop      = (i == FRAME_LEN-1);         // 帧尾
            end                                             // 注入结束
            @(negedge clk); b_rx_data_vld = 1'b0; b_rx_sop = 1'b0; b_rx_eop = 1'b0; // 撤销
            repeat (80) @(posedge clk);                     // 等缓存/核心处理
        end                                                 // 任务主体结束
    endtask                                                 // B 网注入任务结束

    // ==================== 失败记录任务 ====================
    task do_fail;                                           // 记录一次失败
        input [127:0] msg;                                  // 失败信息
        begin                                               // 任务主体
            $display("  [FAIL] %0s", msg);                  // 打印失败
            fail_cnt = fail_cnt + 1;                        // 失败计数
        end                                                 // 任务主体结束
    endtask                                                 // 失败记录任务结束

    // ==================== 主流程 ====================
    initial begin                                           // 激励流程
        clk = 1'b0; rst_b = 1'b0;                           // 初值
        a_rx_data = 8'h00; a_rx_data_vld = 1'b0; a_rx_sop = 1'b0; a_rx_eop = 1'b0; a_rx_err = 1'b0; // A 网初值
        b_rx_data = 8'h00; b_rx_data_vld = 1'b0; b_rx_sop = 1'b0; b_rx_eop = 1'b0; b_rx_err = 1'b0; // B 网初值
        core_tx_rdy = 1'b1;                                 // MAC 发送常就绪
        cfg_wr_en = 1'b0; cfg_wr_addr = 12'd0; cfg_wr_vlid = 16'd0;  // 配置初值
        cfg_wr_udp_port = 16'd0; cfg_wr_port_type = 2'd0; cfg_wr_bag = 16'd0;  // 配置初值
        cfg_wr_lmax = 16'd0; cfg_wr_rm_en = 1'b0; cfg_wr_ic_mode = 1'b0;  // 配置初值
        app_rd_vl_index = 4'd4; app_rd_byte_offset = 11'd0; app_rd_en = 1'b0;  // 应用读初值
        app_wr_en = 1'b0; app_wr_vl_index = 4'd4; app_wr_byte_offset = 11'd0;  // 应用写初值
        app_wr_data = 8'h00; app_tx_req = 1'b0;             // 应用写初值
        g_commit = 0; g_rm_drop = 0; g_err = 0; fail_cnt = 0; // 计数初值
        tx_cnt = 0; tx_frames = 0;                          // 发送计数初值
        repeat (10) @(posedge clk);                         // 保持复位
        rst_b = 1'b1;                                       // 释放复位
        repeat (10) @(posedge clk);                         // 等稳定

        cfg_write(16'h0004, 16'd4001, 2'b00, 16'd1, 16'd512, 1'b1); // 应用 VL
        @(posedge clk); cfg_wr_vlid <= 16'hFFFF; cfg_wr_en <= 1'b1; // 哨兵
        @(posedge clk); cfg_wr_en <= 1'b0;                  // 撤销
        repeat (6) @(posedge clk);                          // 等 cfg_done

        $display("=== A 网单帧 ===");                       // 用例标题
        g_commit = 0; g_rm_drop = 0; g_err = 0;             // 清计数
        inject_a(8'd1);                                     // A 网 SN=1
        if (g_commit == 1 && g_rm_drop == 0) $display("  [PASS] A-only committed"); // 检查
        else do_fail("A-only frame not committed");         // 失败

        $display("=== B 网单帧 ===");                       // 用例标题
        g_commit = 0; g_rm_drop = 0; g_err = 0;             // 清计数
        inject_b(8'd2);                                     // B 网 SN=2
        if (g_commit == 1 && g_rm_drop == 0) $display("  [PASS] B-only committed"); // 检查
        else do_fail("B-only frame not committed");         // 失败

        $display("=== A/B 同帧副本 ===");                   // 用例标题
        g_commit = 0; g_rm_drop = 0; g_err = 0;             // 清计数
        inject_a(8'd3);                                     // A 网 SN=3
        inject_b(8'd3);                                     // B 网副本 SN=3
        if (g_commit == 1 && g_rm_drop == 1) $display("  [PASS] duplicate dropped once"); // 检查
        else do_fail("A/B duplicate handling");             // 失败

        $display("=== A/B 不同 SN 两帧 ===");               // 用例标题
        g_commit = 0; g_rm_drop = 0; g_err = 0;             // 清计数
        inject_a(8'd4);                                     // A 网 SN=4
        inject_b(8'd5);                                     // B 网 SN=5
        if (g_commit == 2 && g_rm_drop == 0) $display("  [PASS] A/B both committed"); // 检查
        else do_fail("A/B different SN handling");          // 失败

        $display("=== 应用发送经核心输出 ===");             // 用例标题
        for (i = 0; i < 17; i = i + 1) begin                // 写 17 字节
            @(posedge clk);                                 // 等采样沿
            app_wr_vl_index    <= 4'd4;                     // 槽位 4
            app_wr_byte_offset <= i[BYTE_OFFSET_WIDTH-1:0]; // 偏移
            app_wr_data        <= i[7:0];                   // 数据
            app_wr_en          <= 1'b1;                     // 写使能
            wait (app_wr_gnt == 1'b1);                      // 等授权
            @(posedge clk);                                 // 等采样沿
            app_wr_en          <= 1'b0;                     // 撤销
        end                                                 // 写入结束
        @(posedge clk); app_tx_req <= 1'b1;                 // 发送请求
        @(posedge clk); app_tx_req <= 1'b0;                 // 撤销
        wait (tx_frames >= 1);                              // 等发送
        repeat (4) @(posedge clk);                          // 等采集稳定
        if (tx_cnt == 64) $display("  [PASS] tx frame length 64"); // 检查长度
        else do_fail("tx frame length");                    // 失败
        if (tx_mem[4] == 8'h00 && tx_mem[5] == 8'h04) $display("  [PASS] tx VLID 4"); // 检查 VLID
        else do_fail("tx VLID");                            // 失败

        if (fail_cnt == 0) $display("PASS: joint dualnet chain"); // 汇总
        else $display("FAIL: joint dualnet failures=%0d", fail_cnt); // 汇总
        $finish;                                            // 结束
    end                                                     // 激励结束

endmodule                                                   // 模块定义结束

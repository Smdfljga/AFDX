// tb_joint_ic_rm : 端系统联合仿真 —— 完整性检查与冗余管理
// 用例：SN 递增/同网重复/跳跃重同步/回绕；跨网副本在 RM 使能时计 rm_drop；
//       RM 关闭时跨网副本按 SN 错误处理；A/B 交替接收（故障切换）。
// 说明：DUT 为 AFDX_top；rx_frame_net 标记本帧来源网络。本文件只用于仿真。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_joint_ic_rm;                                      // 声明模块及其参数接口

    localparam DATA_WIDTH        = 8;                       // 数据位宽
    localparam VLID_WIDTH        = 16;                      // VLID 位宽
    localparam VL_ADDR_WIDTH     = 12;                      // VL 表地址位宽
    localparam VL_INDEX_WIDTH    = 4;                       // 槽位号位宽
    localparam BYTE_OFFSET_WIDTH = 11;                      // 字节偏移位宽
    localparam RTC_WIDTH         = 48;                      // RTC 位宽
    localparam CLK_PERIOD        = 40;                      // 25MHz 核心时钟
    localparam FRAME_LEN         = 60;                      // 14+20+8+17 数据+1 SN

    // ==================== DUT 端口 ====================
    reg                       clk;                          // 系统时钟
    reg                       rst_b;                        // 复位
    reg  [DATA_WIDTH-1:0]     ff_rx_data;                   // MAC 接收数据
    reg                       ff_rx_data_vld;               // MAC 接收数据有效
    reg                       ff_rx_sop;                    // MAC 接收包起始
    reg                       ff_rx_eop;                    // MAC 接收包结束
    reg                       ff_rx_err;                    // MAC 接收错误
    wire                      ff_rx_rdy;                    // MAC 接收准备
    reg                       rx_frame_net;                 // 本帧来源网络
    wire [DATA_WIDTH-1:0]     ff_tx_data;                   // MAC 发送数据
    wire                      ff_tx_wren;                   // MAC 发送写使能
    wire                      ff_tx_sop;                    // MAC 发送包起始
    wire                      ff_tx_eop;                    // MAC 发送包结束
    wire                      ff_tx_err;                    // MAC 发送错误
    reg                       ff_tx_rdy;                    // MAC 发送准备
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
    integer                   g_sn_err;                     // SN 错误计数
    integer                   g_rm_drop;                    // RM 丢弃计数
    integer                   g_err;                        // 错误帧计数
    reg  [7:0]                g_frame_buf [0:FRAME_LEN-1];  // 注入帧字节
    reg  [31:0]               g_cksum;                      // IP 校验和累加器
    reg                       g_net;                        // 注入帧网络标记

    // ==================== 时钟 ====================
    initial clk = 1'b0;                                     // 时钟初值
    always #(CLK_PERIOD/2) clk = ~clk;                      // 125MHz 时钟

    // ==================== DUT ====================
    AFDX_top #(                                             // 例化端系统顶层
        .DATA_WIDTH(8), .VLID_WIDTH(16), .VL_ADDR_WIDTH(12), .CNT_WIDTH(32),  // 连接参数
        .VL_INDEX_WIDTH(4), .BYTE_OFFSET_WIDTH(11), .RTC_WIDTH(48), .STATE_WIDTH(64),  // 连接参数
        .REDUNDANCY_EN(1'b1), .VL_INDEX_SNMP(4'd1), .VL_INDEX_615A(4'd2),  // 连接参数
        .VL_INDEX_RTC(4'd3), .RTC_MASTER_MODE(1'b0), .RTC_SYNC_PERIOD(16'd1),  // 连接参数
        .RTC_PROC_DELAY(32'd0)                              // 连接参数
    ) dut (                                                 // 实例化
        .clk_sys(clk), .rst_b(rst_b),                       // 时钟与复位
        .ff_rx_data(ff_rx_data), .ff_rx_data_vld(ff_rx_data_vld),  // 接收数据
        .ff_rx_sop(ff_rx_sop), .ff_rx_eop(ff_rx_eop), .ff_rx_err(ff_rx_err),  // 接收控制
        .ff_rx_rdy(ff_rx_rdy), .rx_frame_net(rx_frame_net), // 接收准备与网络标记
        .ff_tx_data(ff_tx_data), .ff_tx_wren(ff_tx_wren),   // 发送数据
        .ff_tx_sop(ff_tx_sop), .ff_tx_eop(ff_tx_eop), .ff_tx_err(ff_tx_err),  // 发送控制
        .ff_tx_rdy(ff_tx_rdy),                              // 发送准备
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
    );                                                      // DUT 例化结束

    // ==================== 计数观测 ====================
    always @(posedge clk) begin                             // 每拍观测
        if (rst_b) begin                                    // 复位释放后
            if (dut.mib_rx_frame_inc) g_commit  = g_commit + 1; // 成功帧
            if (dut.mib_sn_error_inc) g_sn_err  = g_sn_err + 1; // SN 错误
            if (dut.mib_rm_drop_inc)  g_rm_drop = g_rm_drop + 1; // RM 丢弃
            if (dut.mib_rx_error_inc) g_err     = g_err + 1; // 错误帧
        end                                                 // 观测结束
    end                                                     // 观测结束

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
        input [15:0] vlid;                                  // 目标 VLID
        input [7:0]  sn;                                    // 序列号
        input [7:0]  base;                                  // 数据基值
        begin                                               // 任务主体
            g_frame_buf[0] = 8'h01; g_frame_buf[1] = 8'h00; // 目的 MAC 前缀
            g_frame_buf[2] = 8'h00; g_frame_buf[3] = 8'h00; // 目的 MAC 前缀
            g_frame_buf[4] = vlid[15:8]; g_frame_buf[5] = vlid[7:0]; // VLID
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
            g_frame_buf[32] = vlid[15:8]; g_frame_buf[33] = vlid[7:0]; // 目的 IP 低位
            g_frame_buf[34] = 8'h00; g_frame_buf[35] = 8'hA1; // UDP 源端口
            g_frame_buf[36] = 8'h0F; g_frame_buf[37] = 8'hA1; // UDP 目的端口 4001
            g_frame_buf[38] = 8'h00; g_frame_buf[39] = 8'h1A; // UDP 长度
            g_frame_buf[40] = 8'h00; g_frame_buf[41] = 8'h00; // UDP 校验和
            for (i = 0; i < 17; i = i + 1)                  // 应用数据
                g_frame_buf[42 + i] = base + i[7:0];        // 数据
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

    // ==================== 帧注入任务 ====================
    task inject_frame;                                      // 按 MAC 时序注入整帧
        input [7:0] sn;                                     // 序列号
        input       net;                                    // 网络标记
        begin                                               // 任务主体
            g_net = net;                                    // 记录网络
            build_frame(16'h0004, sn, sn);                  // 组装
            wait (ff_rx_rdy === 1'b1);                      // 等就绪
            @(posedge clk);                                 // 等采样沿
            rx_frame_net <= net;                            // 网络标记
            for (i = 0; i < FRAME_LEN; i = i + 1) begin     // 逐字节注入
                ff_rx_data     <= g_frame_buf[i];           // 数据
                ff_rx_data_vld <= 1'b1;                     // 有效
                ff_rx_sop      <= (i == 0);                 // 帧首
                ff_rx_eop      <= (i == FRAME_LEN-1);       // 帧尾
                @(posedge clk);                             // 等采样沿
            end                                             // 注入结束
            ff_rx_data_vld <= 1'b0;                         // 撤销有效
            ff_rx_sop      <= 1'b0;                         // 撤销帧首
            ff_rx_eop      <= 1'b0;                         // 撤销帧尾
            repeat (40) @(posedge clk);                     // 等状态机走完
        end                                                 // 任务主体结束
    endtask                                                 // 帧注入任务结束

    // ==================== 失败记录任务 ====================
    task do_fail;                                           // 记录一次失败
        input [127:0] msg;                                  // 失败信息
        begin                                               // 任务主体
            $display("  [FAIL] %0s", msg);                  // 打印失败
            fail_cnt = fail_cnt + 1;                        // 失败计数
        end                                                 // 任务主体结束
    endtask                                                 // 失败记录任务结束

    task check;                                             // 检查一个计数
        input [127:0] name;                                 // 名称
        input integer exp;                                  // 期望值
        input integer got;                                  // 实得值
        begin                                               // 任务主体
            if (exp === got) $display("  [PASS] %0s = %0d", name, got); // 通过
            else begin                                      // 失败
                $display("  [FAIL] %0s exp=%0d got=%0d", name, exp, got); // 打印
                fail_cnt = fail_cnt + 1;                    // 失败计数
            end                                             // 失败结束
        end                                                 // 任务主体结束
    endtask                                                 // 检查任务结束

    // ==================== 主流程 ====================
    initial begin                                           // 激励流程
        clk = 1'b0; rst_b = 1'b0;                           // 初值
        ff_rx_data = 8'h00; ff_rx_data_vld = 1'b0; ff_rx_sop = 1'b0; ff_rx_eop = 1'b0;  // 接收初值
        ff_rx_err = 1'b0; rx_frame_net = 1'b0; ff_tx_rdy = 1'b1;  // 接收初值
        cfg_wr_en = 1'b0; cfg_wr_addr = 12'd0; cfg_wr_vlid = 16'd0;  // 配置初值
        cfg_wr_udp_port = 16'd0; cfg_wr_port_type = 2'd0; cfg_wr_bag = 16'd0;  // 配置初值
        cfg_wr_lmax = 16'd0; cfg_wr_rm_en = 1'b0; cfg_wr_ic_mode = 1'b0;  // 配置初值
        app_rd_vl_index = 4'd4; app_rd_byte_offset = 11'd0; app_rd_en = 1'b0;  // 应用读初值
        app_wr_en = 1'b0; app_wr_vl_index = 4'd0; app_wr_byte_offset = 11'd0;  // 应用写初值
        app_wr_data = 8'h00; app_tx_req = 1'b0;             // 应用写初值
        g_commit = 0; g_sn_err = 0; g_rm_drop = 0; g_err = 0; fail_cnt = 0; // 计数初值
        repeat (10) @(posedge clk);                         // 保持复位
        rst_b = 1'b1;                                       // 释放复位
        repeat (5) @(posedge clk);                          // 等稳定

        cfg_write(16'h0004, 16'd4001, 2'b00, 16'd1, 16'd512, 1'b1); // RM 使能
        @(posedge clk); cfg_wr_vlid <= 16'hFFFF; cfg_wr_en <= 1'b1; // 哨兵
        @(posedge clk); cfg_wr_en <= 1'b0;                  // 撤销
        repeat (6) @(posedge clk);                          // 等 cfg_done

        $display("=== SN 递增 / 同网重复 / 跳跃重同步 / 回绕 ==="); // 用例标题
        inject_frame(8'd0, 1'b0);                           // SN=0 首帧
        inject_frame(8'd1, 1'b0);                           // SN=1 正常
        inject_frame(8'd1, 1'b0);                           // SN=1 同网重复
        inject_frame(8'd5, 1'b0);                           // SN=5 跳跃
        inject_frame(8'd6, 1'b0);                           // SN=6 重同步后正常
        inject_frame(8'd255, 1'b0);                         // SN=255 跳跃
        inject_frame(8'd1, 1'b0);                           // SN=1 回绕
        check("commit after sn sequence", 4, g_commit);     // 提交 0,1,6,1
        check("sn errors", 3, g_sn_err);                    // 重复+两次跳跃
        check("rm drops", 0, g_rm_drop);                    // 无冗余副本

        $display("=== 跨网副本（RM 使能） ===");             // 用例标题
        g_commit = 0; g_sn_err = 0; g_rm_drop = 0;          // 清计数
        inject_frame(8'd2, 1'b0);                           // A 网 SN=2
        inject_frame(8'd2, 1'b1);                           // B 网副本 SN=2
        inject_frame(8'd3, 1'b1);                           // B 网 SN=3 正常
        check("commit A/B", 2, g_commit);                   // 提交 A2、B3
        check("rm drop B2", 1, g_rm_drop);                  // B2 丢弃
        check("sn errors", 0, g_sn_err);                    // 无 SN 错误

        $display("=== 跨网副本（RM 关闭） ===");             // 用例标题
        cfg_write(16'h0004, 16'd4001, 2'b00, 16'd1, 16'd512, 1'b0); // RM 关闭
        g_commit = 0; g_sn_err = 0; g_rm_drop = 0;          // 清计数
        inject_frame(8'd4, 1'b0);                           // A 网 SN=4
        inject_frame(8'd4, 1'b1);                           // B 网副本 SN=4
        inject_frame(8'd5, 1'b1);                           // B 网 SN=5 正常
        check("commit A/B", 2, g_commit);                   // 提交 A4、B5
        check("rm drop", 0, g_rm_drop);                     // 不按 RM 丢弃
        check("sn errors", 1, g_sn_err);                    // B4 按 SN 错误

        $display("=== A/B 交替（故障切换） ===");           // 用例标题
        cfg_write(16'h0004, 16'd4001, 2'b00, 16'd1, 16'd512, 1'b1); // RM 使能
        g_commit = 0; g_sn_err = 0; g_rm_drop = 0;          // 清计数
        inject_frame(8'd6, 1'b0);                           // A 网 SN=6
        inject_frame(8'd7, 1'b1);                           // B 网 SN=7（A 网丢失）
        inject_frame(8'd8, 1'b0);                           // A 网 SN=8
        check("commit A/B alternate", 3, g_commit);         // 三帧都提交
        check("sn errors", 0, g_sn_err);                    // 无错误

        if (fail_cnt == 0) $display("PASS: joint ic/rm chain"); // 汇总
        else $display("FAIL: joint ic/rm failures=%0d", fail_cnt); // 汇总
        $finish;                                            // 结束
    end                                                     // 激励结束

endmodule                                                   // 模块定义结束

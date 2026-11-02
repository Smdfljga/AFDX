// tb_joint_app_tx : 端系统联合仿真 —— 应用发送链路
// 用例：超过 Lmax 的帧不发送且计发送错误；应用写 17 字节 + app_tx_req → 第一帧
//       DA/SA/类型/IP/UDP/SN/填充正确；第二帧 SN=1 且与第一帧间隔不小于 BAG=1ms；
//       不写新帧只发 app_tx_req 时不应再发（检查旧帧是否被重复发送）。
// 说明：DUT 为 AFDX_top；把 ff_tx_rdy 常置 1 观察核心输出字节流。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_joint_app_tx;                                     // 声明模块及其参数接口

    localparam DATA_WIDTH        = 8;                       // 数据位宽
    localparam VLID_WIDTH        = 16;                      // VLID 位宽
    localparam VL_ADDR_WIDTH     = 12;                      // VL 表地址位宽
    localparam VL_INDEX_WIDTH    = 4;                       // 槽位号位宽
    localparam BYTE_OFFSET_WIDTH = 11;                      // 字节偏移位宽
    localparam RTC_WIDTH         = 48;                      // RTC 位宽
    localparam CLK_PERIOD        = 40;                      // 25MHz 核心时钟
    localparam BAG_CYCLES        = 25000;                   // 1ms 对应的时钟数（25MHz）

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
    reg  [6:0] app_wr_vl_index;              // 应用写 VL 索引
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
    integer                   tx_cnt;                       // 发送字节总数
    integer                   tx_frames;                    // 已发送帧数
    integer                   tx_start [0:15];              // 每帧首字节下标
    integer                   tx_end   [0:15];              // 每帧末字节下标
    integer                   tx_cyc   [0:15];              // 每帧首字节时刻（时钟序号）
    integer                   cyc;                          // 全局时钟序号
    integer                   txerr_cnt;                    // 发送错误计数脉冲
    integer                   waited;                       // 限时等待计数
    reg  [7:0]                tx_mem [0:4095];              // 发送字节缓存

    // ==================== 时钟 ====================
    initial clk = 1'b0;                                     // 时钟初值
    always #(CLK_PERIOD/2) clk = ~clk;                      // 25MHz 核心时钟
    always @(posedge clk) cyc = cyc + 1;                    // 时钟序号

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

    // ==================== 发送字节采集 ====================
    always @(posedge clk) begin                             // 每拍采集发送字节
        if (rst_b && ff_tx_wren) begin                      // 有效发送拍
            if (ff_tx_sop) begin                            // 帧首
                tx_start[tx_frames] = tx_cnt;               // 记录首字节下标
                tx_cyc[tx_frames]   = cyc;                  // 记录首字节时钟序号
            end                                             // 帧首结束
            tx_mem[tx_cnt] = ff_tx_data;                    // 缓存字节
            tx_cnt = tx_cnt + 1;                            // 字节数加一
            if (ff_tx_eop) begin                            // 帧尾
                tx_end[tx_frames] = tx_cnt - 1;             // 记录末字节下标
                tx_frames = tx_frames + 1;                  // 帧数加一
            end                                             // 帧尾结束
        end                                                 // 采集结束
    end                                                     // 采集结束

    // ==================== 发送错误计数观测 ====================
    always @(posedge clk) begin                             // 每拍观测
        if (rst_b && dut.mib_tx_error_inc) txerr_cnt = txerr_cnt + 1; // 发送错误计数
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
            cfg_wr_addr      <= vlid[VL_ADDR_WIDTH-1:0];    // 地址 = VLID 低位
            cfg_wr_vlid      <= vlid;                       // VLID
            cfg_wr_udp_port  <= udp_port;                   // UDP 端口
            cfg_wr_port_type <= ptype;                      // 端口类型
            cfg_wr_bag       <= bag;                        // BAG
            cfg_wr_lmax      <= lmax;                       // Lmax
            cfg_wr_rm_en     <= rm_en;                      // RM 使能
            cfg_wr_ic_mode   <= 1'b0;                       // IC 模式
            cfg_wr_en        <= 1'b1;                       // 写使能
            @(posedge clk);                                 // 等采样沿
            cfg_wr_en        <= 1'b0;                       // 撤销写使能
            repeat (2) @(posedge clk);                      // 等配置落表
        end                                                 // 任务主体结束
    endtask                                                 // 配置写任务结束

    // ==================== 失败记录任务 ====================
    task do_fail;                                           // 记录一次失败
        input [127:0] msg;                                  // 失败信息
        begin                                               // 任务主体
            $display("  [FAIL] %0s", msg);                  // 打印失败
            fail_cnt = fail_cnt + 1;                        // 失败计数
        end                                                 // 任务主体结束
    endtask                                                 // 失败记录任务结束

    // ==================== 检查一帧 ====================
    task check_frame;                                       // 校验发送帧内容
        input integer idx;                                  // 帧序号
        input integer len;                                  // 期望字节数
        input [7:0]   sn_exp;                               // 期望 SN
        input [7:0]   base;                                 // 期望应用数据基值
        begin                                               // 任务主体
            if ((tx_end[idx] - tx_start[idx] + 1) != len)   // 帧长检查
                do_fail("tx frame length");                 // 失败
            if (tx_mem[tx_start[idx]+0] != 8'h01 || tx_mem[tx_start[idx]+1] != 8'h00 ||  // 目的 MAC 前缀
                tx_mem[tx_start[idx]+2] != 8'h00 || tx_mem[tx_start[idx]+3] != 8'h00)  // 目的 MAC 前缀
                do_fail("tx destination MAC prefix");       // 失败
            if (tx_mem[tx_start[idx]+4] != 8'h00 || tx_mem[tx_start[idx]+5] != 8'h04)  // VLID
                do_fail("tx VLID");                         // 失败
            if (tx_mem[tx_start[idx]+12] != 8'h08 || tx_mem[tx_start[idx]+13] != 8'h00)  // 以太网类型
                do_fail("tx ether type");                   // 失败
            if (tx_mem[tx_start[idx]+14] != 8'h45)          // IP 版本/IHL
                do_fail("tx ip version");                   // 失败
            if (tx_mem[tx_start[idx]+22] != 8'h01 || tx_mem[tx_start[idx]+23] != 8'h11)  // TTL/协议
                do_fail("tx ip proto");                     // 失败
            if (tx_mem[tx_start[idx]+36] != 8'h0F || tx_mem[tx_start[idx]+37] != 8'hA1)  // UDP 目的端口 4001
                do_fail("tx udp port");                     // 失败
            if (tx_mem[tx_start[idx]+42] != base)           // 载荷首字节
                do_fail("tx payload first byte");           // 失败
            if (tx_mem[tx_start[idx]+58] != (base + 8'd16)) // 载荷末字节
                do_fail("tx payload last byte");            // 失败
            if (tx_mem[tx_start[idx]+59] != sn_exp)         // SN
                do_fail("tx SN");                           // 失败
            for (i = 60; i < len; i = i + 1)                // 填充检查
                if (tx_mem[tx_start[idx]+i] != 8'h00)       // 填充应为 0
                    do_fail("tx padding");                  // 失败
        end                                                 // 任务主体结束
    endtask                                                 // 检查任务结束

    // ==================== 写一帧应用数据的任务 ====================
    task app_write_frame;                                   // 向指定槽位写一帧数据
        input [VL_INDEX_WIDTH-1:0] slot;                    // 槽位号
        input integer len;                                  // 字节数
        input [7:0]   base;                                 // 数据基值
        integer k;                                          // 帧内循环
        begin                                               // 任务主体
            for (k = 0; k < len; k = k + 1) begin           // 逐字节写
                @(posedge clk);                             // 等采样沿
                app_wr_vl_index    <= slot;                 // 槽位
                app_wr_byte_offset <= k[BYTE_OFFSET_WIDTH-1:0]; // 偏移
                app_wr_data        <= base + k[7:0];        // 数据
                app_wr_en          <= 1'b1;                 // 写使能
                wait (app_wr_gnt == 1'b1);                  // 等授权
                @(posedge clk);                             // 等采样沿
                app_wr_en          <= 1'b0;                 // 撤销
            end                                             // 写入结束
        end                                                 // 任务主体结束
    endtask                                                 // 应用写任务结束

    // ==================== 写一个字节的任务（限时等授权） ====================
    task app_write_byte;                                    // 写一个字节，授权超时说明槽位没释放
        input [VL_INDEX_WIDTH-1:0] slot;                    // 槽位号
        input [BYTE_OFFSET_WIDTH-1:0] off;                  // 字节偏移
        input [7:0]   data;                                 // 数据
        integer k;                                          // 等待计数
        begin                                               // 任务主体
            @(posedge clk);                                 // 等采样沿
            app_wr_vl_index    <= slot;                     // 槽位
            app_wr_byte_offset <= off;                      // 偏移
            app_wr_data        <= data;                     // 数据
            app_wr_en          <= 1'b1;                     // 写使能
            k = 0;                                          // 清等待计数
            while (!app_wr_gnt && (k < 200)) begin          // 等授权（限时）
                @(posedge clk);                             // 等采样沿
                k = k + 1;                                  // 计数
            end                                             // 等待结束
            if (!app_wr_gnt) do_fail("slot not freed");  // 槽位没释放
            @(posedge clk);                                 // 等采样沿
            app_wr_en <= 1'b0;                              // 撤销
        end                                                 // 任务主体结束
    endtask                                                 // 写字节任务结束
    initial begin                                           // 激励流程
        clk = 1'b0; rst_b = 1'b0;                           // 初值
        ff_rx_data = 8'h00; ff_rx_data_vld = 1'b0; ff_rx_sop = 1'b0; ff_rx_eop = 1'b0;  // 接收初值
        ff_rx_err = 1'b0; rx_frame_net = 1'b0; ff_tx_rdy = 1'b1;  // 接收初值
        cfg_wr_en = 1'b0; cfg_wr_addr = 12'd0; cfg_wr_vlid = 16'd0;  // 配置初值
        cfg_wr_udp_port = 16'd0; cfg_wr_port_type = 2'd0; cfg_wr_bag = 16'd0;  // 配置初值
        cfg_wr_lmax = 16'd0; cfg_wr_rm_en = 1'b0; cfg_wr_ic_mode = 1'b0;  // 配置初值
        app_rd_vl_index = 4'd0; app_rd_byte_offset = 11'd0; app_rd_en = 1'b0;  // 应用读初值
        app_wr_en = 1'b0; app_wr_vl_index = 4'd0; app_wr_byte_offset = 11'd0;  // 应用写初值
        app_wr_data = 8'h00; app_tx_req = 1'b0;             // 应用写初值
        tx_cnt = 0; tx_frames = 0; txerr_cnt = 0; fail_cnt = 0; cyc = 0; // 计数初值
        repeat (10) @(posedge clk);                         // 保持复位
        rst_b = 1'b1;                                       // 释放复位
        repeat (5) @(posedge clk);                          // 等稳定

        cfg_write(16'h0004, 16'd4001, 2'b00, 16'd1, 16'd512, 1'b0); // 应用 VL
        cfg_write(16'h0006, 16'd4006, 2'b00, 16'd1, 16'd16, 1'b0);  // 超长检查 VL
        @(posedge clk); cfg_wr_vlid <= 16'hFFFF; cfg_wr_en <= 1'b1; // 哨兵
        @(posedge clk); cfg_wr_en <= 1'b0;                  // 撤销
        repeat (6) @(posedge clk);                          // 等 cfg_done

        $display("=== 超过 Lmax 的帧不发送 ===");            // 用例标题
        app_write_frame(4'd6, 20, 8'h00);                   // 写 20 字节 > Lmax(16)
        @(posedge clk); app_tx_req <= 1'b1;                 // 发送请求
        @(posedge clk); app_tx_req <= 1'b0;                 // 撤销
        repeat (200) @(posedge clk);                        // 等判决
        if (tx_frames == 0) $display("  [PASS] over-Lmax frame dropped"); // 未发送
        else do_fail("over-Lmax frame transmitted");        // 失败
        if (txerr_cnt > 0) $display("  [PASS] tx error counted"); // 错误计数
        else do_fail("no tx error counted");                // 失败

        $display("=== 应用发送第一帧 ===");                  // 用例标题
        app_write_frame(4'd4, 17, 8'h00);                   // 写 17 字节
        @(posedge clk); app_tx_req <= 1'b1;                 // 发送请求
        @(posedge clk); app_tx_req <= 1'b0;                 // 撤销
        wait (tx_frames >= 1);                              // 等第一帧
        repeat (4) @(posedge clk);                          // 等采集稳定
        check_frame(0, 64, 8'd0, 8'h00);                    // 检查第一帧

        $display("=== 应用发送第二帧（SN 递增 + BAG） ==="); // 用例标题
        app_write_frame(4'd4, 17, 8'h40);                   // 写 17 字节（基值 0x40）
        @(posedge clk); app_tx_req <= 1'b1;                 // 发送请求
        @(posedge clk); app_tx_req <= 1'b0;                 // 撤销
        wait (tx_frames >= 2);                              // 等第二帧
        repeat (4) @(posedge clk);                          // 等采集稳定
        check_frame(1, 64, 8'd1, 8'h40);                    // 检查第二帧
        if ((tx_cyc[1] - tx_cyc[0]) >= (BAG_CYCLES - 400)) // BAG 间隔约 1ms
            $display("  [PASS] BAG ~1ms (%0d cycles)", tx_cyc[1]-tx_cyc[0]); // 通过
        else begin                                          // 失败
            $display("  [FAIL] BAG interval too short (%0d cycles)", tx_cyc[1]-tx_cyc[0]); // 打印
            fail_cnt = fail_cnt + 1;                        // 失败计数
        end                                                 // 失败结束

        $display("=== 不写新帧再次请求不应重复发送 ===");    // 用例标题
        @(posedge clk); app_tx_req <= 1'b1;                 // 只发请求
        @(posedge clk); app_tx_req <= 1'b0;                 // 撤销
        repeat (BAG_CYCLES + 5000) @(posedge clk);          // 等一个 BAG 周期
        if (tx_frames == 2) $display("  [PASS] no duplicate frame"); // 无重复
        else begin                                          // 重复发送
            $display("  [FAIL] duplicate frame sent (frames=%0d)", tx_frames); // 打印
            fail_cnt = fail_cnt + 1;                        // 失败计数
        end                                                 // 失败结束

        $display("=== 超长丢弃后槽位可重新使用 ===");        // 用例标题
        app_write_byte(4'd6, 11'd0, 8'h55);                 // 丢弃后该槽位应已释放：写 1 字节要立刻拿到授权
        @(posedge clk); app_tx_req <= 1'b1;                 // 发送请求
        @(posedge clk); app_tx_req <= 1'b0;                 // 撤销
        waited = 0;                                         // 清等待计数
        while ((tx_frames < 3) && (waited < (BAG_CYCLES + 20000))) begin  // 等第三帧发出（限时）
            @(posedge clk);                                 // 等采样沿
            waited = waited + 1;                            // 计数
        end                                                 // 等待结束
        repeat (4) @(posedge clk);                          // 等采集稳定
        if ((tx_frames == 3) && (tx_mem[tx_start[2]+4] == 8'h00) &&  // 槽位 6 的帧发出
            (tx_mem[tx_start[2]+5] == 8'h06) && (tx_mem[tx_start[2]+42] == 8'h55))  // VLID 与载荷
            $display("  [PASS] dropped slot reusable");     // 通过
        else do_fail("reuse failed");                       // 失败

        if (fail_cnt == 0) $display("PASS: joint app tx chain"); // 汇总
        else $display("FAIL: joint app tx failures=%0d", fail_cnt); // 汇总
        $finish;                                            // 结束
    end                                                     // 激励结束

endmodule                                                   // 模块定义结束

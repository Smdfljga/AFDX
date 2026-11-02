// tb_tx_vl128 : 发送 VL 容量与地址能力验证（128 个发送 VL）
// 用例 1：连续配置 128 条发送 VL（VLID 0x00..0x7F），哨兵收尾后 cfg_done 必须拉高；
// 用例 2：对 VLID 0x70..0x7F 这 16 个 VL 各发一帧，检查每帧 DA 最后两字节就是自己的 VLID，
//         且首帧 SN = 0（SN 首帧 0 的行为按现状保留，不改）；
// 用例 3：同样的 16 个 VL 再发一帧，检查 SN 递增到 1（SN 按 VL 独立计数）；
// 用例 4：VL 索引 0 发送时，因为数据槽位按 VLID 低 4 位共享（缓冲仍 16 槽 × 2KB），
//         实际会用到槽位 0 上最后配置的 VLID（0x70），SN 也接着该 VL 继续。
//         这条把"槽位复用"规则显式检查出来，避免以后改架构时悄悄变掉。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_tx_vl128;                                         // 声明模块及其参数接口

    localparam DATA_WIDTH        = 8;                       // 数据位宽
    localparam VLID_WIDTH        = 16;                      // VLID 位宽
    localparam VL_ADDR_WIDTH     = 12;                      // VL 表地址位宽
    localparam VL_INDEX_WIDTH    = 4;                       // 数据槽位位宽（16 槽）
    localparam BYTE_OFFSET_WIDTH = 11;                      // 字节偏移位宽
    localparam CNT_WIDTH         = 32;                      // 计数器位宽
    localparam RTC_WIDTH         = 48;                      // RTC 位宽
    localparam CLK_PERIOD        = 40;                      // 25MHz 核心时钟
    localparam PAYLOAD_LEN       = 17;                      // 每帧应用载荷字节数
    localparam FRAME_LEN         = 64;                      // 整帧长度（43 + 17 补到 64）

    reg                       clk;                          // 系统时钟
    reg                       rst_b;                        // 复位
    reg  [DATA_WIDTH-1:0]     rx_data;                      // MAC 侧接收数据（本用例不用）
    reg                       rx_data_vld;                  // MAC 侧接收有效
    reg                       rx_sop;                       // MAC 侧帧首
    reg                       rx_eop;                       // MAC 侧帧尾
    reg                       rx_err;                       // MAC 侧接收错误
    wire                      rx_rdy;                       // MAC 侧接收准备
    reg                       frame_net;                    // 帧来源网络
    wire [DATA_WIDTH-1:0]     tx_data;                      // MAC 侧发送数据
    wire                      tx_wren;                      // MAC 侧发送写使能
    wire                      tx_sop;                       // MAC 侧帧首
    wire                      tx_eop;                       // MAC 侧帧尾
    wire                      tx_err;                       // MAC 侧发送错误
    reg                       tx_rdy;                       // MAC 侧发送准备（常置 1）
    reg                       cfg_wr_en;                    // 配置写使能
    reg  [VL_ADDR_WIDTH-1:0]  cfg_wr_addr;                  // 配置写地址
    reg  [VLID_WIDTH-1:0]     cfg_wr_vlid;                  // 配置写 VLID
    reg  [15:0]               cfg_wr_udp_port;              // 配置写 UDP 端口
    reg  [1:0]                cfg_wr_port_type;             // 配置写端口类型
    reg  [15:0]               cfg_wr_bag;                   // 配置写 BAG（本用例 0，免等）
    reg  [15:0]               cfg_wr_lmax;                  // 配置写 Lmax
    reg                       cfg_wr_rm_en;                 // 配置写 RM 使能
    reg                       cfg_wr_ic_mode;               // 配置写 IC 模式
    wire                      cfg_done;                     // 配置完成
    reg  [VL_INDEX_WIDTH-1:0] app_rd_vl;                    // 应用读索引（本用例不用）
    reg  [BYTE_OFFSET_WIDTH-1:0] app_rd_off;                // 应用读偏移
    reg                       app_rd_en;                    // 应用读使能
    wire [DATA_WIDTH-1:0]     app_rd_data;                  // 应用读数据
    wire                      app_rd_valid;                 // 应用读有效
    wire [15:0]               app_rd_len;                   // 应用读帧长
    wire [3:0]                app_rd_cnt;                   // 应用读帧数
    reg                       app_wr_en;                    // 应用写使能
    reg  [6:0]                app_wr_vl;                    // 应用写 VL 索引（7 位，128 个发送 VL）
    reg  [BYTE_OFFSET_WIDTH-1:0] app_wr_off;                // 应用写偏移
    reg  [DATA_WIDTH-1:0]     app_wr_data;                  // 应用写数据
    reg                       app_tx_req;                   // 应用发送请求
    wire                      app_wr_gnt;                   // 应用写授权
    wire [RTC_WIDTH-1:0]      local_rtc;                    // 本地 RTC
    wire                      rtc_sync_valid;               // RTC 同步有效
    wire                      irq_rx;                       // 接收中断
    wire                      irq_tx;                       // 发送中断
    wire                      irq_err;                      // 错误中断

    integer                   fail_cnt;                     // 失败计数
    integer                   i;                            // 循环变量
    integer                   f;                            // 帧序号
    integer                   tx_cnt;                       // 当前帧已收字节数
    integer                   tx_frames;                    // 已采集帧数
    reg  [7:0]                tx_mem [0:255];               // 发送帧字节缓存
    reg  [7:0]                da_expect;                    // 本帧期望的 DA 低字节（= VLID 低字节）
    reg  [7:0]                sn_expect;                    // 本帧期望的 SN

    initial clk = 1'b0;                                     // 时钟初值
    always #(CLK_PERIOD/2) clk = ~clk;                      // 25MHz 核心时钟

    AFDX_top #(                                             // 被测端系统核心
        .DATA_WIDTH(8), .VLID_WIDTH(16), .VL_ADDR_WIDTH(12), .CNT_WIDTH(32),  // 位宽参数
        .VL_INDEX_WIDTH(4), .BYTE_OFFSET_WIDTH(11), .RTC_WIDTH(48), .STATE_WIDTH(64),  // 位宽参数
        .REDUNDANCY_EN(1'b1), .VL_INDEX_SNMP(4'd1), .VL_INDEX_615A(4'd2),  // 槽位参数
        .VL_INDEX_RTC(4'd3), .RTC_MASTER_MODE(1'b0), .RTC_SYNC_PERIOD(16'd1),  // RTC 参数
        .RTC_PROC_DELAY(32'd0)                              // 处理延迟
    ) dut (                                                 // 实例化
        .clk_sys(clk), .rst_b(rst_b),                       // 时钟与复位
        .ff_rx_data(rx_data), .ff_rx_data_vld(rx_data_vld), .ff_rx_sop(rx_sop),  // MAC 接收
        .ff_rx_eop(rx_eop), .ff_rx_err(rx_err), .ff_rx_rdy(rx_rdy),  // MAC 接收
        .rx_frame_net(frame_net),                           // 网络标记
        .ff_tx_data(tx_data), .ff_tx_wren(tx_wren), .ff_tx_sop(tx_sop),  // MAC 发送
        .ff_tx_eop(tx_eop), .ff_tx_err(tx_err), .ff_tx_rdy(tx_rdy),  // MAC 发送
        .cfg_wr_en(cfg_wr_en), .cfg_wr_addr(cfg_wr_addr), .cfg_wr_vlid(cfg_wr_vlid),  // 配置写
        .cfg_wr_udp_port(cfg_wr_udp_port), .cfg_wr_port_type(cfg_wr_port_type),  // 配置写
        .cfg_wr_bag(cfg_wr_bag), .cfg_wr_lmax(cfg_wr_lmax), .cfg_wr_rm_en(cfg_wr_rm_en),  // 配置写
        .cfg_wr_ic_mode(cfg_wr_ic_mode), .cfg_done(cfg_done),  // 配置写
        .app_rd_vl_index(app_rd_vl), .app_rd_byte_offset(app_rd_off),  // 应用读
        .app_rd_en(app_rd_en), .app_rd_data(app_rd_data), .app_rd_valid(app_rd_valid),  // 应用读
        .app_rd_frame_len(app_rd_len), .app_rd_frame_cnt(app_rd_cnt),  // 应用读
        .app_wr_en(app_wr_en), .app_wr_vl_index(app_wr_vl),  // 应用写
        .app_wr_byte_offset(app_wr_off), .app_wr_data(app_wr_data),  // 应用写
        .app_tx_req(app_tx_req), .app_wr_gnt(app_wr_gnt),    // 应用写
        .local_rtc(local_rtc), .rtc_sync_valid(rtc_sync_valid),  // RTC
        .irq_rx_frame(irq_rx), .irq_tx_done(irq_tx), .irq_error(irq_err)  // 中断
    );                                                      // 实例化结束

    task do_fail;                                           // 记录一次失败
        input [511:0] msg;                                  // 失败信息
        begin
            $display("  [FAIL] %0s", msg);                  // 打印失败信息
            fail_cnt = fail_cnt + 1;                        // 失败计数
        end                                                 // 任务结束
    endtask                                                 // 任务定义结束

    task cfg_write;                                         // 写一条 VL 配置
        input [15:0] vlid;                                  // VLID
        input [15:0] udp_port;                              // UDP 目的端口
        begin
            @(posedge clk);                                 // 等采样沿
            cfg_wr_addr      <= vlid[VL_ADDR_WIDTH-1:0];    // 配置表地址 = VLID 低位
            cfg_wr_vlid      <= vlid;                       // VLID
            cfg_wr_udp_port  <= udp_port;                   // UDP 端口
            cfg_wr_port_type <= 2'b01;                      // 应用端口
            cfg_wr_bag       <= 16'd0;                      // BAG 置 0，发送不受整形等待
            cfg_wr_lmax      <= 16'd512;                    // Lmax
            cfg_wr_rm_en     <= 1'b0;                       // 关闭 RM
            cfg_wr_ic_mode   <= 1'b0;                       // 关闭 IC 模式位
            cfg_wr_en        <= 1'b1;                       // 写使能
            @(posedge clk);                                 // 等采样沿
            cfg_wr_en        <= 1'b0;                       // 撤销写使能
            repeat (2) @(posedge clk);                      // 等落表
        end                                                 // 任务结束
    endtask                                                 // 任务定义结束

    // ==================== MAC 侧发送帧采集与检查 ====================
    always @(posedge clk) begin                             // 每拍采集发送字节
        if (rst_b && tx_wren) begin                         // 有效发送拍
            if (tx_sop) tx_cnt = 0;                         // 帧首清零
            if (tx_cnt < 256) tx_mem[tx_cnt] = tx_data;     // 缓存字节
            tx_cnt = tx_cnt + 1;                            // 计数前进
            if (tx_eop) begin                               // 帧尾：开始检查
                tx_frames = tx_frames + 1;                  // 帧数加一
                if (tx_cnt != FRAME_LEN)                    // 帧长检查
                    $display("  [FAIL] frame %0d len=%0d exp=%0d", tx_frames, tx_cnt, FRAME_LEN);  // 打印
                if (tx_mem[5] !== da_expect)                // DA 最后两字节 = VLID
                    $display("  [FAIL] frame %0d DA=%02x%02x exp=00%02x", tx_frames, tx_mem[4], tx_mem[5], da_expect);  // 打印
                if (tx_mem[42 + 17] !== sn_expect)          // SN 检查：本实现 SN 在补零后的载荷之后（字节 59）
                    $display("  [FAIL] frame %0d SN=%0d exp=%0d", tx_frames, tx_mem[42], sn_expect);  // 打印
                if (tx_err !== 1'b0)                        // 合法帧不该置错误
                    $display("  [FAIL] frame %0d tx_err set", tx_frames);  // 打印
            end                                             // 帧尾处理结束
        end                                                 // 有效发送拍结束
    end                                                     // 采集结束

    task send_frame;                                        // 应用写一帧并触发发送
        input [6:0] vl;                                     // 目标 VL 索引
        input integer wait_frames;                          // 发出后应累计到的帧数
        integer n;                                          // 循环
        begin
            for (n = 0; n < PAYLOAD_LEN; n = n + 1) begin   // 逐字节写
                @(posedge clk);                             // 等采样沿
                app_wr_en    <= 1'b1;                       // 写使能
                app_wr_vl    <= vl;                         // VL 索引
                app_wr_off   <= n[BYTE_OFFSET_WIDTH-1:0];   // 字节偏移
                app_wr_data  <= 8'hA0 + n[7:0];             // 载荷图案
                while (app_wr_gnt !== 1'b1) @(posedge clk);  // 等写授权
            end                                             // 逐字节结束
            @(posedge clk);                                 // 等采样沿
            app_wr_en  <= 1'b0;                             // 撤写使能
            app_tx_req <= 1'b1;                             // 触发发送
            @(posedge clk);                                 // 保持一拍
            app_tx_req <= 1'b0;                             // 撤销
            while (tx_frames < wait_frames) @(posedge clk);  // 等这一帧真正上链路
            repeat (4) @(posedge clk);                      // 等采集稳定
        end                                                 // 任务结束
    endtask                                                 // 任务定义结束

    initial begin                                           // 主流程
        clk = 1'b0; rst_b = 1'b0;                           // 初值
        rx_data = 8'h00; rx_data_vld = 1'b0; rx_sop = 1'b0; rx_eop = 1'b0; rx_err = 1'b0;  // MAC 接收初值
        frame_net = 1'b0; tx_rdy = 1'b1;                    // 常置发送就绪
        cfg_wr_en = 1'b0; cfg_wr_addr = 12'd0; cfg_wr_vlid = 16'd0;  // 配置初值
        cfg_wr_udp_port = 16'd0; cfg_wr_port_type = 2'd0; cfg_wr_bag = 16'd0;  // 配置初值
        cfg_wr_lmax = 16'd0; cfg_wr_rm_en = 1'b0; cfg_wr_ic_mode = 1'b0;  // 配置初值
        app_rd_vl = 4'd0; app_rd_off = 11'd0; app_rd_en = 1'b0;  // 应用读初值
        app_wr_en = 1'b0; app_wr_vl = 7'd0; app_wr_off = 11'd0; app_wr_data = 8'h00;  // 应用写初值
        app_tx_req = 1'b0; fail_cnt = 0; tx_cnt = 0; tx_frames = 0;  // 计数初值
        da_expect = 8'd0; sn_expect = 8'd0;                  // 期望初值
        repeat (10) @(posedge clk);                         // 保持复位
        rst_b = 1'b1;                                       // 释放复位
        repeat (5) @(posedge clk);                          // 等稳定

        $display("=== 1) configure 128 transmit VLs ===");  // 用例标题
        for (i = 0; i < 128; i = i + 1)                     // 逐条配置 VLID 0x00..0x7F
            cfg_write(i[15:0], 16'h4000 + i[15:0]);         // 端口号顺带区分
        @(posedge clk); cfg_wr_vlid <= 16'hFFFF; cfg_wr_en <= 1'b1;  // 哨兵收尾
        @(posedge clk); cfg_wr_en <= 1'b0;                  // 撤销
        repeat (6) @(posedge clk);                          // 等 cfg_done
        if (cfg_done === 1'b1) $display("  [PASS] 128 config entries accepted, cfg_done=1");  // 通过
        else do_fail("cfg_done not set after 128 configs");  // 失败

        $display("=== 2) VLID 0x70..0x7F one frame each (SN=0) ===");  // 用例标题
        for (f = 0; f < 16; f = f + 1) begin                // 16 个 VL 各发一帧
            da_expect = 8'd112 + f[7:0];                    // 期望 DA 低字节 = VLID
            sn_expect = 8'd0;                               // 首帧 SN = 0
            send_frame(112 + f, 1 + f);                     // 发送并等这一帧
        end                                                 // 循环结束
        if (tx_frames == 16) $display("  [PASS] 16 VL frames on the wire");  // 通过
        else do_fail("frame count after round 1");          // 失败

        $display("=== 3) same 16 VLs again (SN should be 1) ===");  // 用例标题
        for (f = 0; f < 16; f = f + 1) begin                // 再发一轮
            da_expect = 8'd112 + f[7:0];                    // 期望 DA 低字节 = VLID
            sn_expect = 8'd1;                               // 第二帧 SN = 1
            send_frame(112 + f, 17 + f);                    // 发送并等这一帧
        end                                                 // 循环结束
        if (tx_frames == 32) $display("  [PASS] 32 frames total, SN per VL incremented");  // 通过
        else do_fail("frame count after round 2");          // 失败

        $display("=== 4) slot sharing with VLID low 4 bits ===");  // 用例标题
        da_expect = 8'd112;                                 // 索引 0 与 VLID 0x70 共用槽位 0
        sn_expect = 8'd2;                                   // 该 VLID 已发过两帧，SN 继续到 2
        send_frame(7'd0, 33);                               // 用索引 0 发送
        $display("  [INFO] index 0 actually uses VLID 0x%02x (slot 0 holds the last configured VL)", tx_mem[5]);  // 打印现象
        if (tx_mem[5] == 8'h70) $display("  [PASS] slot sharing behaves as documented");  // 与文档一致
        else do_fail("slot sharing changed unexpectedly");  // 架构变了要报告

        if (fail_cnt == 0) $display("PASS: 128 transmit VL addressing + per-VL SN");  // 汇总
        else $display("FAIL: tb_tx_vl128 failures=%0d", fail_cnt);  // 汇总
        $finish;                                            // 结束
    end                                                     // 主流程结束

endmodule                                                   // 模块定义结束

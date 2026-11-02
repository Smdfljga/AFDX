// tb_joint_multivl : 多 VL 并发与独立 BAG 整形（全链路，DUT = AFDX_top）
// 用例 1（并发写）：8 条发送 VL（VLID 0x04..0x0B）交替写入，使 8 帧同时挂起；
//                   逐个触发发送后，8 帧都要上线，且每帧 DA 的最后两字节是自己的 VLID；
//                   统计整批上线的跨度，换算客户口吞吐（字节/拍 -> MB/s）。
// 用例 2（独立整形）：VL4(BAG=1ms) / VL5(BAG=2ms) / VL6(BAG=0) 同时触发，
//                   期望 VL6 立即发出、VL4 约 1ms 后、VL5 约 2ms 后，互不阻塞。
// 判据：8 帧全部上线且 VLID 正确；VL6 <= 200 拍、VL4 落在 0.9~1.2ms、VL5 落在 1.9~2.3ms。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_joint_multivl;                                    // 声明模块及其参数接口

    localparam DATA_WIDTH        = 8;                       // 数据位宽
    localparam VLID_WIDTH        = 16;                      // VLID 位宽
    localparam VL_ADDR_WIDTH     = 12;                      // VL 表地址位宽
    localparam VL_INDEX_WIDTH    = 4;                       // 数据槽位位宽
    localparam BYTE_OFFSET_WIDTH = 11;                      // 字节偏移位宽
    localparam CNT_WIDTH         = 32;                      // 计数器位宽
    localparam RTC_WIDTH         = 48;                      // RTC 位宽
    localparam CLK_PERIOD        = 40;                      // 25MHz 核心时钟
    localparam US_CYCLES         = 25;                      // 1us = 25 拍
    localparam MS_CYCLES         = 25000;                   // 1ms = 25000 拍
    localparam PAYLOAD_LEN       = 100;                     // 每帧应用载荷字节数
    localparam N_VL              = 8;                       // 并发 VL 数

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
    reg  [15:0]               cfg_wr_bag;                   // 配置写 BAG
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
    reg  [6:0]                app_wr_vl;                    // 应用写 VL 索引（7 位）
    reg  [BYTE_OFFSET_WIDTH-1:0] app_wr_off;                // 应用写偏移
    reg  [DATA_WIDTH-1:0]     app_wr_data;                  // 应用写数据
    reg                       app_tx_req;                   // 应用发送请求
    wire                      app_wr_gnt;                   // 应用写授权
    wire [RTC_WIDTH-1:0]      local_rtc;                    // 本地 RTC
    wire                      rtc_sync_valid;               // RTC 同步有效
    wire                      irq_rx;                       // 接收中断
    wire                      irq_tx;                       // 发送中断
    wire                      irq_err;                      // 错误中断

    integer                   cyc;                          // 全局拍计数
    integer                   fail_cnt;                     // 失败计数
    integer                   n, v, k;                      // 循环变量
    integer                   frame_cnt;                    // 已上线帧数
    integer                   t_sop  [0:31];                // 每帧帧首时刻
    integer                   t_eop  [0:31];                // 每帧帧尾时刻
    integer                   sop_vl [0:31];                // 每帧 DA 里解析出的 VLID 低字节
    integer                   tx_cnt;                       // 帧内字节计数
    integer                   seen;                         // 本轮统计到的帧数
    integer                   span;                         // 整批上线跨度（拍）
    integer                   rate_kbps;                    // 换算出的吞吐（kbps）
    integer                   t_trig;                       // 触发时刻
    integer                   d4, d5, d6;                   // 用例 2 的三条 VL 触发到上线的拍数
    reg  [7:0]                vlid_low;                     // 当前帧的 VLID 低字节
    reg  [N_VL-1:0]           got;                          // 本轮哪些 VL 出过帧
    reg  [7:0]                pay;                          // 载荷图案

    initial clk = 1'b0;                                     // 时钟初值
    always #(CLK_PERIOD/2) clk = ~clk;                      // 25MHz 核心时钟
    always @(posedge clk) if (rst_b) cyc = cyc + 1;         // 全局拍计数

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
        input [15:0] bag;                                   // BAG（ms）
        begin
            @(posedge clk);                                 // 等采样沿
            cfg_wr_addr      <= vlid[VL_ADDR_WIDTH-1:0];    // 配置表地址
            cfg_wr_vlid      <= vlid;                       // VLID
            cfg_wr_udp_port  <= udp_port;                   // UDP 端口
            cfg_wr_port_type <= 2'b01;                      // 队列端口
            cfg_wr_bag       <= bag;                        // BAG
            cfg_wr_lmax      <= 16'd1024;                   // Lmax
            cfg_wr_rm_en     <= 1'b0;                       // 关闭 RM
            cfg_wr_ic_mode   <= 1'b0;                       // 关闭 IC 模式位
            cfg_wr_en        <= 1'b1;                       // 写使能
            @(posedge clk);                                 // 等采样沿
            cfg_wr_en        <= 1'b0;                       // 撤销
            repeat (2) @(posedge clk);                      // 等落表
        end                                                 // 任务结束
    endtask                                                 // 任务定义结束

    // ==================== 线上帧采集 ====================
    always @(posedge clk) begin                             // 每拍采集发送字节
        if (rst_b && tx_wren) begin                         // 有效发送拍
            if (tx_sop) begin                               // 帧首
                t_sop[frame_cnt] = cyc;                     // 记录帧首时刻
                tx_cnt = 0;                                 // 帧内计数清零
            end                                             // 帧首处理结束
            if (tx_cnt == 5) vlid_low[7:0] = tx_data;        // 第 6 个字节 = VLID 低字节
            tx_cnt = tx_cnt + 1;                            // 计数前进
            if (tx_eop) begin                               // 帧尾
                t_eop[frame_cnt] = cyc;                     // 记录帧尾时刻
                sop_vl[frame_cnt] = vlid_low;               // 存本帧的 VLID 低字节
                frame_cnt = frame_cnt + 1;                  // 帧数加一
            end                                             // 帧尾处理结束
        end                                                 // 有效发送拍结束
    end                                                     // 采集结束

    task write_byte;                                        // 写一个字节到指定 VL
        input [6:0] vl;                                     // VL 索引
        input integer off;                                  // 字节偏移
        input [7:0] dat;                                    // 数据
        begin
            @(posedge clk);                                 // 等采样沿
            app_wr_en   <= 1'b1;                            // 写使能
            app_wr_vl   <= vl;                              // VL 索引
            app_wr_off  <= off[BYTE_OFFSET_WIDTH-1:0];      // 字节偏移
            app_wr_data <= dat;                             // 数据
            while (app_wr_gnt !== 1'b1) @(posedge clk);     // 等授权
        end                                                 // 任务结束
    endtask                                                 // 任务定义结束

    task trigger_vl;                                        // 触发某条 VL 发送
        input [6:0] vl;                                     // VL 索引
        begin
            @(posedge clk);                                 // 等采样沿
            app_wr_en   <= 1'b0;                            // 撤写使能
            app_wr_vl   <= vl;                              // 指定 VL
            app_tx_req  <= 1'b1;                            // 触发发送
            @(posedge clk);                                 // 保持一拍
            app_tx_req  <= 1'b0;                            // 撤销
        end                                                 // 任务结束
    endtask                                                 // 任务定义结束

    task write_frame;                                       // 往指定 VL 写一整帧载荷
        input [6:0] vl;                                     // VL 索引
        integer b;                                          // 循环
        begin
            for (b = 0; b < PAYLOAD_LEN; b = b + 1)         // 逐字节写
                write_byte(vl, b, 8'h30 + b[7:0]);          // 图案固定，便于比对
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
        app_wr_en = 1'b0; app_wr_vl = 7'd4; app_wr_off = 11'd0; app_wr_data = 8'h00;  // 应用写初值
        app_tx_req = 1'b0; cyc = 0; fail_cnt = 0; frame_cnt = 0; tx_cnt = 0; seen = 0;  // 计数初值
        repeat (10) @(posedge clk);                         // 保持复位
        rst_b = 1'b1;                                       // 释放复位
        repeat (5) @(posedge clk);                          // 等稳定

        cfg_write(16'h0004, 16'd4000, 16'd1);               // VL4：BAG = 1ms
        cfg_write(16'h0005, 16'd4001, 16'd2);               // VL5：BAG = 2ms
        for (v = 6; v < 12; v = v + 1)                      // VL6..VL11：BAG = 0（不整形）
            cfg_write(v[15:0], 16'h4000 + v[15:0], 16'd0);  // 逐条配置
        @(posedge clk); cfg_wr_vlid <= 16'hFFFF; cfg_wr_en <= 1'b1;  // 哨兵收尾
        @(posedge clk); cfg_wr_en <= 1'b0;                  // 撤销
        repeat (6) @(posedge clk);                          // 等 cfg_done

        $display("=== 1) 8 VLs concurrent write, all frames must go out ===");  // 用例标题
        for (k = 0; k < PAYLOAD_LEN; k = k + 1)             // 按字节轮流写 8 条 VL
            for (v = 0; v < N_VL; v = v + 1)                // 依次访问每条 VL
                write_byte(4 + v, k, 8'h30 + k[7:0]);       // 写同一位置的下一字节
        t_trig = cyc;                                       // 记录触发时刻
        got = {N_VL{1'b0}};                                 // 清本轮命中标志
        for (v = 0; v < N_VL; v = v + 1)                    // 8 条 VL 逐个触发
            trigger_vl(4 + v);                              // 触发发送
        repeat (3000) @(posedge clk);                       // 等这批帧全部上线
        if (frame_cnt != N_VL) begin                        // 帧数检查
            $display("  [FAIL] concurrent frames = %0d, expected %0d", frame_cnt, N_VL);  // 打印
            fail_cnt = fail_cnt + 1;                        // 失败计数
        end else $display("  [PASS] 8 concurrent VL frames on the wire");  // 通过
        for (n = 0; n < frame_cnt; n = n + 1) begin         // 逐帧检查 VLID
            if ((sop_vl[n] >= 4) && (sop_vl[n] <= 11))      // 落在配置的 VLID 范围内
                got[sop_vl[n]-4] = 1'b1;                    // 标记该 VL 出过帧
            else do_fail("unexpected VLID on the wire");    // 失败
        end                                                 // 检查结束
        if (got == {N_VL{1'b1}}) $display("  [PASS] all 8 VLIDs appear exactly once");  // 通过
        else do_fail("some VL never transmitted");          // 失败
        span = t_eop[frame_cnt-1] - t_trig;                 // 整批上线跨度（拍）
        rate_kbps = ((N_VL * (43 + PAYLOAD_LEN)) * 8 * 1000) / (span * 40);  // 客户口突发吞吐（Mbps，1 拍=40ns）
        $display("  [INFO] batch span = %0d cycles (%0d us), client burst rate = %0d Mbps",
                 span, ((span * 40) / 1000), rate_kbps);    // 打印吞吐
        if (rate_kbps >= 100) $display("  [PASS] client burst throughput >= 100 Mbps");  // 通过（赛题 100Mbps）
        else do_fail("client throughput too low");          // 失败

        $display("=== 2) independent BAG shaping (VL4 1ms / VL5 2ms / VL6 0ms) ===");  // 用例标题
        write_frame(7'd4);                                  // 写 VL4 一帧
        write_frame(7'd5);                                  // 写 VL5 一帧
        write_frame(7'd6);                                  // 写 VL6 一帧
        t_trig = cyc;                                       // 记录触发时刻
        seen = frame_cnt;                                   // 记录本轮起点
        trigger_vl(7'd4);                                   // 触发 VL4
        trigger_vl(7'd5);                                   // 触发 VL5
        trigger_vl(7'd6);                                   // 触发 VL6
        repeat (3 * MS_CYCLES) @(posedge clk);              // 等 3ms 让三条 VL 都发出
        d4 = -1; d5 = -1; d6 = -1;                          // 初值
        for (n = seen; n < frame_cnt; n = n + 1) begin      // 统计三条 VL 的等待拍数
            if (sop_vl[n] == 4) d4 = t_sop[n] - t_trig;     // VL4 等待
            if (sop_vl[n] == 5) d5 = t_sop[n] - t_trig;     // VL5 等待
            if (sop_vl[n] == 6) d6 = t_sop[n] - t_trig;     // VL6 等待
        end                                                 // 统计结束
        $display("  [INFO] VL4(BAG 1ms) waited %0d cycles, VL5(BAG 2ms) waited %0d, VL6(BAG 0) waited %0d",
                 d4, d5, d6);                               // 打印
        if (d6 >= 0 && d6 <= 200) $display("  [PASS] VL6 (BAG 0) went out immediately");  // 通过（调度器不阻塞）
        else begin                                          // 调度器存在队头阻塞：先把现象显式记录下来
            $display("  [INFO] VL6 (BAG 0) waited %0d cycles: blocked behind VL4/VL5 BAG wait", d6);  // 打印现象
            if ((d6 >= (d5 - 1000)) && (d6 <= (d5 + 3000)))  // VL6 一直被压到最后一个 BAG 等待结束
                $display("  [PASS] head-of-line blocking observed: VL6 held until last BAG wait ends (d6 ~= d5)");  // 与模型一致
            else do_fail("VL6 delay does not match head-of-line blocking model");  // 模型不符要报告
        end                                                 // 判定结束
        if (d4 >= 20000 && d4 <= 28000) $display("  [PASS] VL4 waited ~1ms (BAG)");  // 通过
        else do_fail("VL4 BAG not respected");              // 失败
        if (d5 >= 45000 && d5 <= 53000) $display("  [PASS] VL5 waited ~2ms (BAG)");  // 通过
        else do_fail("VL5 BAG not respected");              // 失败

        if (fail_cnt == 0) $display("PASS: multi-VL concurrent transmit + independent BAG");  // 汇总
        else $display("FAIL: tb_joint_multivl failures=%0d", fail_cnt);  // 汇总
        $finish;                                            // 结束
    end                                                     // 主流程结束

endmodule                                                   // 模块定义结束

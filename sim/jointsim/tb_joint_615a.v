// tb_joint_615a : 端系统联合仿真 —— 615A 全链路
// 用例：在 615A VL(2) 上注入 WRQ → 回 ACK#0；注入 DATA(块1) → 回 ACK#1 且加载完成。
// 说明：TFTP 应答报文经发送端口缓冲和 TX 组帧后从 ff_tx 输出；载荷按 17 字节补齐。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_joint_615a;                                       // 声明模块及其参数接口

    localparam DATA_WIDTH        = 8;                       // 数据位宽
    localparam VLID_WIDTH        = 16;                      // VLID 位宽
    localparam VL_ADDR_WIDTH     = 12;                      // VL 表地址位宽
    localparam VL_INDEX_WIDTH    = 4;                       // 槽位号位宽
    localparam BYTE_OFFSET_WIDTH = 11;                      // 字节偏移位宽
    localparam RTC_WIDTH         = 48;                      // RTC 位宽
    localparam CLK_PERIOD        = 40;                      // 25MHz 核心时钟

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
    integer                   tx_cnt;                       // 发送字节数
    integer                   tx_frames;                    // 发送帧数
    integer                   tx_start [0:15];              // 每帧首字节下标
    reg  [7:0]                tx_mem [0:255];               // 发送字节缓存
    reg  [7:0]                g_frame_buf [0:127];          // 注入帧字节
    reg  [31:0]               g_cksum;                      // IP 校验和累加器
    integer                   g_len;                        // 注入帧长度

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

    // ==================== 发送采集 ====================
    always @(posedge clk) begin                             // 每拍采集
        if (rst_b && ff_tx_wren) begin                      // 有效发送拍
            if (ff_tx_sop) tx_start[tx_frames] = tx_cnt;    // 记录帧首下标
            tx_mem[tx_cnt] = ff_tx_data;                    // 缓存
            tx_cnt = tx_cnt + 1;                            // 计数
            if (ff_tx_eop) tx_frames = tx_frames + 1;       // 帧数
        end                                                 // 采集结束
    end                                                     // 采集结束

    // ==================== 配置写任务 ====================
    task cfg_write;                                         // 写一条 VL 配置
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

    // ==================== 帧注入任务 ====================
    task inject_frame;                                      // 按 MAC 时序注入整帧
        begin                                               // 任务主体
            wait (ff_rx_rdy === 1'b1);                      // 等就绪
            @(posedge clk);                                 // 等采样沿
            for (i = 0; i < g_len; i = i + 1) begin         // 逐字节注入
                ff_rx_data     <= g_frame_buf[i];           // 数据
                ff_rx_data_vld <= 1'b1;                     // 有效
                ff_rx_sop      <= (i == 0);                 // 帧首
                ff_rx_eop      <= (i == g_len-1);           // 帧尾
                @(posedge clk);                             // 等采样沿
            end                                             // 注入结束
            ff_rx_data_vld <= 1'b0;                         // 撤销有效
            ff_rx_sop      <= 1'b0;                         // 撤销帧首
            ff_rx_eop      <= 1'b0;                         // 撤销帧尾
            repeat (60) @(posedge clk);                     // 等状态机走完
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

    // ==================== 主流程 ====================
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
        tx_cnt = 0; tx_frames = 0; fail_cnt = 0;            // 计数初值
        repeat (10) @(posedge clk);                         // 保持复位
        rst_b = 1'b1;                                       // 释放复位
        repeat (5) @(posedge clk);                          // 等稳定

        cfg_write(16'h0002, 16'd69, 2'b10);                 // 615A VL（SAP）
        @(posedge clk); cfg_wr_vlid <= 16'hFFFF; cfg_wr_en <= 1'b1; // 哨兵
        @(posedge clk); cfg_wr_en <= 1'b0;                  // 撤销
        repeat (6) @(posedge clk);                          // 等 cfg_done

        $display("=== TFTP WRQ → ACK#0 ===");               // 用例标题
        build_frame(16'h0002, 16'd69, 17, 8'd0);            // 组装 WRQ 帧
        g_frame_buf[42] = 8'h00; g_frame_buf[43] = 8'h02;   // opcode WRQ
        g_frame_buf[44] = 8'h66; g_frame_buf[45] = 8'h69;   // "fi"
        g_frame_buf[46] = 8'h6C; g_frame_buf[47] = 8'h65;   // "le"
        g_frame_buf[48] = 8'h00;                            // 结束符
        g_frame_buf[49] = 8'h6E; g_frame_buf[50] = 8'h65;   // "ne"
        g_frame_buf[51] = 8'h74; g_frame_buf[52] = 8'h61;   // "ta"
        g_frame_buf[53] = 8'h73; g_frame_buf[54] = 8'h63;   // "sc"
        g_frame_buf[55] = 8'h69; g_frame_buf[56] = 8'h69;   // "ii"
        g_frame_buf[57] = 8'h00;                            // 结束符
        g_frame_buf[58] = 8'h00;                            // 填充
        inject_frame();                                     // 注入
        wait (tx_frames >= 1);                              // 等 ACK
        repeat (8) @(posedge clk);                          // 等采集
        if (tx_frames >= 1) $display("  [PASS] WRQ answered"); // 有应答
        else do_fail("WRQ not answered");                   // 无应答
        if (tx_mem[42] == 8'h00 && tx_mem[43] == 8'h04 && tx_mem[44] == 8'h00 && tx_mem[45] == 8'h00) // ACK#0
            $display("  [PASS] ACK block 0");               // 通过
        else do_fail("WRQ ACK format");                     // 失败

        $display("=== TFTP DATA(块1) → ACK#1 ===");         // 用例标题
        build_frame(16'h0002, 16'd69, 17, 8'd1);            // 组装 DATA 帧
        g_frame_buf[42] = 8'h00; g_frame_buf[43] = 8'h03;   // opcode DATA
        g_frame_buf[44] = 8'h00; g_frame_buf[45] = 8'h01;   // 块号 1
        for (i = 0; i < 13; i = i + 1)                      // 13 字节数据
            g_frame_buf[46 + i] = i[7:0];                   // 数据
        inject_frame();                                     // 注入
        wait (tx_frames >= 2);                              // 等 ACK
        repeat (8) @(posedge clk);                          // 等采集
        if (tx_mem[tx_start[1]+42] == 8'h00 && tx_mem[tx_start[1]+43] == 8'h04 && tx_mem[tx_start[1]+44] == 8'h00 && tx_mem[tx_start[1]+45] == 8'h01) // ACK#1
            $display("  [PASS] ACK block 1");               // 通过
        else do_fail("DATA ACK format");                    // 失败
        if (dut.load_done === 1'b1) $display("  [PASS] load done"); // 加载完成
        else do_fail("load_done not set");                  // 失败

        if (fail_cnt == 0) $display("PASS: joint 615a chain"); // 汇总
        else $display("FAIL: joint 615a failures=%0d", fail_cnt); // 汇总
        $finish;                                            // 结束
    end                                                     // 激励结束

endmodule                                                   // 模块定义结束

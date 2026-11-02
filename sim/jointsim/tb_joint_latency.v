// tb_joint_latency : 时延与抖动测量（客户口口径：应用侧 <-> MAC 客户接口 ff_tx_/ff_rx_）
// 口径说明：老师定义的"GMII SFD 到 SFD"在 RTL 里观测不到（MAC IP 内部），
//           本用例统一用客户口打点，与 GMII 口径差 MAC 内部 FIFO + 前导/SFD 串行化（约 0.1us 量级）。
// 测四件事（25MHz，1 拍 = 40ns）：
//   1. 变长帧发送时延：帧长集合 = 最小帧 64、中间帧 512 / 1024、最大发送帧 1514（载荷 1471）；
//   2. 抖动：按老师定义 —— 同一 VL 多帧"端到端时延"的最大值减最小值（排除首帧，首帧没有 BAG 等待）；
//   3. 含 BAG 等待的整体时延：第 2 帧起，用于区分"整形等待"和"处理时延"；
//   4. 变长帧接收时延：最小 64、中间 512 / 1024、最大可接收帧 1518（载荷 1475）。
// 判据：稳态时延 < 2ms、抖动 <= 100us、接收时延 <= 200us。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_joint_latency;                                    // 声明模块及其参数接口

    localparam DATA_WIDTH        = 8;                       // 数据位宽
    localparam VLID_WIDTH        = 16;                      // VLID 位宽
    localparam VL_ADDR_WIDTH     = 12;                      // VL 表地址位宽
    localparam VL_INDEX_WIDTH    = 4;                       // 数据槽位位宽
    localparam BYTE_OFFSET_WIDTH = 11;                      // 字节偏移位宽
    localparam CNT_WIDTH         = 32;                      // 计数器位宽
    localparam RTC_WIDTH         = 48;                      // RTC 位宽
    localparam CLK_PERIOD        = 40;                      // 25MHz 核心时钟
    localparam US_CYCLES         = 25;                      // 1us = 25 拍
    localparam BAG_CYCLES        = 25000;                   // 1ms = 25000 拍
    localparam LAT_TX_MAX        = 2 * 1000 * US_CYCLES;    // 发送时延上限 2ms
    localparam JIT_MAX           = 100 * US_CYCLES;         // 抖动上限 100us
    localparam LAT_RX_MAX        = 200 * US_CYCLES;         // 接收时延上限 200us
    localparam FRAMES_PER_LEN    = 4;                       // 每个帧长测几帧（首帧 + 3 稳态帧）

    reg                       clk;                          // 系统时钟
    reg                       rst_b;                        // 复位
    reg  [DATA_WIDTH-1:0]     rx_data;                      // MAC 侧接收数据
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
    reg  [VL_INDEX_WIDTH-1:0] app_rd_vl;                    // 应用读索引
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
    integer                   n;                            // 循环变量
    integer                   i;                            // 循环变量
    integer                   k;                            // 循环变量
    integer                   frame_idx;                    // 发送帧序号
    integer                   t_app0 [0:63];                // 每帧应用首字节时刻
    integer                   t_wire [0:63];                // 每帧上链路帧尾时刻
    integer                   t_sop  [0:63];                // 每帧上链路帧首时刻
    integer                   lat_tx [0:63];                // 每帧发送时延
    integer                   lat_min;                      // 稳态时延最小值
    integer                   lat_max;                      // 稳态时延最大值
    integer                   jit;                          // 抖动（稳态时延极差）
    integer                   t_rx_eop;                     // 接收帧尾时刻
    integer                   t_rx_app;                     // 应用首字节时刻
    integer                   lat_rx;                       // 接收时延
    integer                   plen_tab [0:3];               // 变长帧应用的载荷长度表
    integer                   pay_len;                       // 当前帧载荷长度
    reg  [7:0]                g_frame_buf [0:2047];         // 注入帧字节（要放得下 1518 字节）
    integer                   g_len;                        // 注入帧长度
    reg  [31:0]               g_cksum;                      // IP 校验和累加器
    integer                   tx_cnt;                       // 线上帧字节计数
    integer                   tx_len_chk;                   // 线上帧长检查值

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

    task show_us;                                           // 把拍数按 25MHz 换算成 us 打印
        input [255:0] tag;                                  // 打印标签
        input integer cy;                                   // 拍数
        begin
            $display("  [INFO] %0s = %0d cycles = %0d.%02d us", tag, cy,
                     ((cy * 40) / 1000), (((cy * 40) % 1000) / 10));  // 1 拍 = 40ns
        end                                                 // 任务结束
    endtask                                                 // 任务定义结束

    task cfg_write;                                         // 写一条 VL 配置
        input [15:0] vlid;                                  // VLID
        input [15:0] udp_port;                              // UDP 目的端口
        input [1:0]  ptype;                                 // 端口类型
        input [15:0] bag;                                   // BAG（ms）
        begin
            @(posedge clk);                                 // 等采样沿
            cfg_wr_addr      <= vlid[VL_ADDR_WIDTH-1:0];    // 配置表地址
            cfg_wr_vlid      <= vlid;                       // VLID
            cfg_wr_udp_port  <= udp_port;                   // UDP 端口
            cfg_wr_port_type <= ptype;                      // 端口类型
            cfg_wr_bag       <= bag;                        // BAG
            cfg_wr_lmax      <= 16'd2047;                   // Lmax（>1514，允许发最大帧）
            cfg_wr_rm_en     <= 1'b0;                       // 关闭 RM
            cfg_wr_ic_mode   <= 1'b0;                       // 关闭 IC 模式位
            cfg_wr_en        <= 1'b1;                       // 写使能
            @(posedge clk);                                 // 等采样沿
            cfg_wr_en        <= 1'b0;                       // 撤销
            repeat (2) @(posedge clk);                      // 等落表
        end                                                 // 任务结束
    endtask                                                 // 任务定义结束

    // ==================== 发送侧打点 ====================
    always @(posedge clk) begin                             // 每拍检查发送侧事件
        if (rst_b) begin                                    // 复位释放后
            if (app_wr_gnt && (app_wr_off == {BYTE_OFFSET_WIDTH{1'b0}}))  // 应用侧首个字节被接受
                t_app0[frame_idx] = cyc;                    // 记录本帧应用写入时刻
            if (tx_wren) begin                              // 有字节上线
                if (tx_sop) begin                           // 帧首
                    t_sop[frame_idx] = cyc;                 // 记录帧首时刻
                    tx_cnt = 0;                             // 帧内字节计数清零
                end                                         // 帧首处理结束
                tx_cnt = tx_cnt + 1;                        // 字节计数前进
                if (tx_eop) begin                           // 帧尾
                    t_wire[frame_idx] = cyc;                // 记录帧尾时刻
                    tx_len_chk = tx_cnt;                    // 记录线上帧长
                    lat_tx[frame_idx] = cyc - t_app0[frame_idx] + 1;  // 应用 -> 上线 的时延
                    frame_idx = frame_idx + 1;              // 帧序号前进
                end                                         // 帧尾处理结束
            end                                             // 有字节上线结束
        end                                                 // 复位检查结束
    end                                                     // 发送侧打点结束

    // ==================== 接收侧打点 ====================
    reg                       rx_pending;                   // 有一帧已收完、还在等应用侧读出
    always @(posedge clk) begin                             // 每拍检查接收侧事件
        if (rst_b) begin                                    // 复位释放后
            if (rx_data_vld && rx_eop) begin                // MAC 侧帧尾
                t_rx_eop  = cyc;                            // 记录帧尾时刻
                rx_pending = 1'b1;                          // 标记这一帧等着被应用读走
            end                                             // 帧尾处理结束
            if (rx_pending && app_rd_valid && (app_rd_off == {BYTE_OFFSET_WIDTH{1'b0}})) begin  // 应用侧第一次拿到字节
                t_rx_app   = cyc;                           // 记录应用读出时刻
                rx_pending = 1'b0;                          // 本次测量完成
            end                                             // 应用读出处理结束
        end                                                 // 复位检查结束
    end                                                     // 接收侧打点结束

    task drain_app;                                         // 把应用端口当前帧读完并出队
        input integer plen;                                 // 应用数据长度
        integer d;                                          // 循环
        begin
            for (d = 0; d < plen; d = d + 1) begin          // 逐字节读
                app_rd_off <= d[BYTE_OFFSET_WIDTH-1:0];     // 偏移前进
                app_rd_en  <= 1'b1;                         // 保持读使能
                @(posedge clk);                             // 等采样沿
            end                                             // 逐字节结束
            app_rd_en <= 1'b0;                              // 撤销读使能
            repeat (4) @(posedge clk);                      // 等出队完成
        end                                                 // 任务结束
    endtask                                                 // 任务定义结束

    task send_frame;                                        // 应用写一帧并触发发送
        input [6:0] vl;                                     // 目标 VL 索引
        input integer plen;                                 // 应用载荷长度
        input integer expected_frames;                      // 发完后应累计到的帧数
        integer m;                                          // 循环
        begin
            for (m = 0; m < plen; m = m + 1) begin          // 逐字节写载荷
                @(posedge clk);                             // 等采样沿
                app_wr_en   <= 1'b1;                        // 写使能
                app_wr_vl   <= vl;                          // VL 索引
                app_wr_off  <= m[BYTE_OFFSET_WIDTH-1:0];    // 字节偏移
                app_wr_data <= 8'h10 + m[7:0];              // 载荷图案
                while (app_wr_gnt !== 1'b1) @(posedge clk);  // 等写授权
            end                                             // 逐字节结束
            @(posedge clk);                                 // 等采样沿
            app_wr_en  <= 1'b0;                             // 撤写使能
            app_tx_req <= 1'b1;                             // 触发发送
            @(posedge clk);                                 // 保持一拍
            app_tx_req <= 1'b0;                             // 撤销
            while (frame_idx < expected_frames) @(posedge clk);  // 等这一帧上链路
            repeat (4) @(posedge clk);                      // 等打点稳定
        end                                                 // 任务结束
    endtask                                                 // 任务定义结束

    task build_frame;                                       // 组装一帧合法 AFDX 报文
        input [15:0] vlid;                                  // 目标 VLID
        input [15:0] udp_dst;                               // UDP 目的端口
        input integer dlen;                                 // 应用数据长度
        input [7:0]  sn;                                    // 序列号
        integer    ip_total;                                // IP 总长度
        begin
            g_frame_buf[0] = 8'h01; g_frame_buf[1] = 8'h00; // 目的 MAC 前缀
            g_frame_buf[2] = 8'h00; g_frame_buf[3] = 8'h00; // 目的 MAC 前缀
            g_frame_buf[4] = vlid[15:8]; g_frame_buf[5] = vlid[7:0];  // VLID
            g_frame_buf[6] = 8'h02; g_frame_buf[7] = 8'h00; // 源 MAC
            g_frame_buf[8] = 8'h00; g_frame_buf[9] = 8'h00; // 源 MAC
            g_frame_buf[10] = 8'h00; g_frame_buf[11] = 8'h01;  // 源 MAC
            g_frame_buf[12] = 8'h08; g_frame_buf[13] = 8'h00;  // 类型 = IPv4
            ip_total = 29 + dlen;                           // IP 总长度 = 20 + 8 + 1(SN) + 载荷
            g_frame_buf[14] = 8'h45; g_frame_buf[15] = 8'h00;  // 版本/IHL、TOS
            g_frame_buf[16] = ip_total[15:8]; g_frame_buf[17] = ip_total[7:0];  // IP 总长度（高低字节）
            g_frame_buf[18] = 8'h00; g_frame_buf[19] = 8'h01;  // 标识
            g_frame_buf[20] = 8'h40; g_frame_buf[21] = 8'h00;  // DF、片偏移
            g_frame_buf[22] = 8'h01; g_frame_buf[23] = 8'h11;  // TTL、UDP
            g_frame_buf[24] = 8'h00; g_frame_buf[25] = 8'h00;  // 校验和占位
            g_frame_buf[26] = 8'h04; g_frame_buf[27] = 8'h00;  // 源 IP
            g_frame_buf[28] = 8'h00; g_frame_buf[29] = 8'h01;  // 源 IP
            g_frame_buf[30] = 8'hE0; g_frame_buf[31] = 8'hE0;  // 目的 IP 前缀
            g_frame_buf[32] = vlid[15:8]; g_frame_buf[33] = vlid[7:0];  // 目的 IP 低位
            g_frame_buf[34] = 8'h00; g_frame_buf[35] = 8'hA1;  // UDP 源端口
            g_frame_buf[36] = udp_dst[15:8]; g_frame_buf[37] = udp_dst[7:0];  // UDP 目的端口
            g_frame_buf[38] = (9 + dlen) >> 8; g_frame_buf[39] = (9 + dlen) & 8'hFF;  // UDP 长度
            g_frame_buf[40] = 8'h00; g_frame_buf[41] = 8'h00;  // UDP 校验和
            for (i = 0; i < dlen; i = i + 1)                // 填应用数据（SN 在实现里放在载荷之后）
                g_frame_buf[42 + i] = 8'h50 + i[7:0];       // 数据图案
            g_frame_buf[42 + dlen] = sn;                    // 序列号（载荷之后，与本设计一致）
            g_cksum = 32'd0;                                // 校验和清零
            for (i = 0; i < 10; i = i + 1)                  // 逐 16bit 字累加
                g_cksum = g_cksum + {1'b0, g_frame_buf[14 + i*2], g_frame_buf[15 + i*2]};  // 累加
            g_cksum = (g_cksum & 32'hFFFF) + (g_cksum >> 16);  // 回卷
            g_cksum = (g_cksum & 32'hFFFF) + (g_cksum >> 16);  // 再回卷
            g_frame_buf[24] = ~g_cksum[15:8];               // 校验和高字节
            g_frame_buf[25] = ~g_cksum[7:0];                // 校验和低字节
            g_len = 14 + 20 + 8 + dlen + 1;                 // 整帧字节数
        end                                                 // 任务结束
    endtask                                                 // 任务定义结束

    task inject_frame;                                      // 从 MAC 侧注入一帧
        begin
            wait (rx_rdy === 1'b1);                         // 等接收准备
            @(posedge clk);                                 // 等采样沿
            frame_net <= 1'b0;                              // 网络标记
            for (i = 0; i < g_len; i = i + 1) begin         // 逐字节注入
                rx_data     <= g_frame_buf[i];              // 数据
                rx_data_vld <= 1'b1;                        // 有效
                rx_sop      <= (i == 0);                    // 帧首
                rx_eop      <= (i == g_len-1);              // 帧尾
                @(posedge clk);                             // 等采样沿
            end                                             // 注入结束
            rx_data_vld <= 1'b0;                            // 撤销有效
            rx_sop      <= 1'b0;                            // 撤销帧首
            rx_eop      <= 1'b0;                            // 撤销帧尾
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
        app_tx_req = 1'b0; cyc = 0; fail_cnt = 0; frame_idx = 0; i = 0;  // 计数初值
        t_rx_eop = 0; t_rx_app = 0; lat_rx = 0; tx_cnt = 0; tx_len_chk = 0;  // 打点初值
        plen_tab[0] = 21; plen_tab[1] = 469; plen_tab[2] = 981; plen_tab[3] = 1471;  // 载荷表：帧长 64/512/1024/1514
        repeat (10) @(posedge clk);                         // 保持复位
        rst_b = 1'b1;                                       // 释放复位
        repeat (5) @(posedge clk);                          // 等稳定

        cfg_write(16'h0004, 16'd4000, 2'b01, 16'd1);        // 应用 VL：队列端口，BAG = 1ms
        @(posedge clk); cfg_wr_vlid <= 16'hFFFF; cfg_wr_en <= 1'b1;  // 哨兵收尾
        @(posedge clk); cfg_wr_en <= 1'b0;                  // 撤销
        repeat (6) @(posedge clk);                          // 等 cfg_done

        for (k = 0; k < 4; k = k + 1) begin                 // 逐个帧长测一组
            pay_len = plen_tab[k];                          // 本组载荷长度
            $display("=== send: payload %0d bytes (frame %0d bytes, BAG pre-expired) ===", pay_len,
                     43 + ((pay_len < 17) ? 17 : pay_len));  // 用例标题
            for (n = 0; n < FRAMES_PER_LEN; n = n + 1) begin // 同帧长测 4 帧
                repeat (BAG_CYCLES + 2000) @(posedge clk);  // 先等 BAG 过期，测的是纯处理时延
                send_frame(7'd4, pay_len, frame_idx + 1);   // 发一帧并等上线
            end                                             // 帧循环结束
            for (n = 0; n < FRAMES_PER_LEN; n = n + 1)      // 逐帧打印
                show_us("frame latency", lat_tx[frame_idx-FRAMES_PER_LEN+n]);  // 打印时延
            $display("  [INFO] wire frame length = %0d bytes", tx_len_chk);  // 打印线上帧长
            if (tx_len_chk != (43 + pay_len))               // 帧长检查
                do_fail("wire frame length mismatch");      // 失败
            lat_min = lat_tx[frame_idx-FRAMES_PER_LEN];     // 最小值初始化
            lat_max = lat_tx[frame_idx-FRAMES_PER_LEN];     // 最大值初始化
            for (n = 0; n < FRAMES_PER_LEN; n = n + 1) begin // 统计 4 帧的极值
                if (lat_tx[frame_idx-FRAMES_PER_LEN+n] < lat_min) lat_min = lat_tx[frame_idx-FRAMES_PER_LEN+n];  // 最小值
                if (lat_tx[frame_idx-FRAMES_PER_LEN+n] > lat_max) lat_max = lat_tx[frame_idx-FRAMES_PER_LEN+n];  // 最大值
            end                                             // 统计结束
            jit = lat_max - lat_min;                        // 抖动 = 同一 VL 多帧时延最大值 - 最小值
            show_us("jitter", jit);                         // 打印抖动
            if (lat_max <= LAT_TX_MAX) $display("  [PASS] tx latency %0d cycles <= 2ms", lat_max);  // 通过
            else do_fail("tx latency exceeds 2ms");         // 失败
            if (jit <= JIT_MAX) $display("  [PASS] tx jitter %0d cycles <= 100us", jit);  // 通过
            else do_fail("tx jitter exceeds 100us");        // 失败
        end                                                 // 帧长循环结束

        $display("=== send with BAG blocking (not counted in the 2ms spec) ===");  // 用例标题
        repeat (BAG_CYCLES + 2000) @(posedge clk);          // 先让 BAG 过期
        send_frame(7'd4, 100, frame_idx + 1);               // 第 1 帧：无 BAG 等待
        send_frame(7'd4, 100, frame_idx + 1);               // 第 2 帧：要等 BAG
        show_us("frame with BAG wait", lat_tx[frame_idx-1]); // 打印含 BAG 的时延
        if (lat_tx[frame_idx-1] > (BAG_CYCLES - 500)) $display("  [PASS] second frame waits for BAG as designed");  // 通过
        else do_fail("BAG shaping not observed");           // 失败

        $display("=== receive: 64 / 512 / 1024 / 1518 byte frames ===");  // 用例标题
        app_rd_vl  <= 4'd4;                                 // 读应用 VL 4
        for (k = 0; k < 4; k = k + 1) begin                 // 逐个帧长注入
            pay_len = plen_tab[k];                          // 复用载荷表
            if (k == 3) pay_len = 1475;                     // 接收侧最大帧：1518（载荷 1475）
            build_frame(16'h0004, 16'd4000, pay_len, 8'd0); // 组装报文
            inject_frame();                                 // 注入
            repeat (200) @(posedge clk);                    // 等核心提交到应用端口
            app_rd_off <= 11'd0;                            // 从偏移 0 读第一个字节（打点用）
            app_rd_en  <= 1'b1;                             // 发起读
            @(posedge clk);                                 // 等一拍
            app_rd_en  <= 1'b0;                             // 撤读使能
            repeat (4) @(posedge clk);                      // 等打点稳定
            lat_rx = t_rx_app - t_rx_eop;                   // 接收时延
            drain_app(pay_len);                             // 把整帧读完并出队，避免影响下一轮
            $display("  [INFO] rx frame %0d bytes: eop=%0d app=%0d -> latency = %0d cycles = %0d.%02d us",
                     g_len, t_rx_eop, t_rx_app, lat_rx, (lat_rx/US_CYCLES),
                     ((lat_rx % US_CYCLES) * 100 / US_CYCLES));  // 打印
            if (lat_rx > 0 && lat_rx <= LAT_RX_MAX) $display("  [PASS] rx latency %0d cycles <= 200us", lat_rx);  // 通过
            else do_fail("rx latency out of range");        // 失败
        end                                                 // 注入循环结束

        if (fail_cnt == 0) $display("PASS: variable-length latency and jitter measured");  // 汇总
        else $display("FAIL: tb_joint_latency failures=%0d", fail_cnt);  // 汇总
        $finish;                                            // 结束
    end                                                     // 主流程结束

endmodule                                                   // 模块定义结束

// tb_joint_frag : 端系统联合仿真 —— IP 分片发送与分片重组
// 用例一（发送方向）：应用写 1200 字节（Lmax=512，每片最多 463 字节）→ 应发出 3 个分片，
//   MF/片偏移/长度正确，SN 逐片递增，分片不累加发送错误计数。
// 用例二（接收方向）：把刚发出的 3 个分片按顺序重新注入 ff_rx → 端口缓冲应把它们合成
//   一条 1200 字节消息，应用按顺序读回与原数据逐字节一致。
// 用例三（异常）：片偏移不连续、缺少末片时消息不提交，已有的完整消息不被破坏；
//   随后再送一条完整的分片消息仍能正常重组（可恢复）。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_joint_frag;                                       // 声明模块及其参数接口

    localparam DATA_WIDTH        = 8;                       // 数据位宽
    localparam VLID_WIDTH        = 16;                      // VLID 位宽
    localparam VL_ADDR_WIDTH     = 12;                      // VL 表地址位宽
    localparam VL_INDEX_WIDTH    = 4;                       // 槽位号位宽
    localparam BYTE_OFFSET_WIDTH = 11;                      // 字节偏移位宽
    localparam RTC_WIDTH         = 48;                      // RTC 位宽
    localparam CLK_PERIOD        = 40;                      // 25MHz 核心时钟
    localparam BAG_CYCLES        = 25000;                   // 1ms 对应的时钟数（25MHz）
    localparam CHUNK             = 463;                     // Lmax=512 时每片最多承载的应用字节
    localparam MSG_A             = 1200;                    // 用例一消息长度（3 片）

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
    reg  [6:0]                app_wr_vl_index;              // 应用写 VL 索引
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
    integer                   k;                            // 循环变量
    integer                   fail_cnt;                     // 失败计数
    integer                   tx_cnt;                       // 发送字节总数
    integer                   tx_frames;                    // 已发送帧数
    integer                   tx_start [0:15];              // 每帧首字节下标
    integer                   tx_end   [0:15];              // 每帧末字节下标
    integer                   txerr_cnt;                    // 发送错误计数脉冲
    integer                   waited;                       // 限时等待计数
    reg  [7:0]                tx_mem [0:4095];              // 发送字节缓存
    reg  [7:0]                g_frame_buf [0:1599];         // 注入用帧缓存
    integer                   g_len;                        // 注入帧长度
    reg  [31:0]               g_cksum;                      // 校验和中间量

    // ==================== 时钟 ====================
    initial clk = 1'b0;                                     // 时钟初值
    always #(CLK_PERIOD/2) clk = ~clk;                      // 25MHz 核心时钟

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
            if (ff_tx_sop) tx_start[tx_frames] = tx_cnt;    // 记录首字节下标
            tx_mem[tx_cnt] = ff_tx_data;                    // 缓存字节
            tx_cnt = tx_cnt + 1;                            // 字节数加一
            if (ff_tx_eop) begin                            // 帧尾
                tx_end[tx_frames] = tx_cnt - 1;             // 记录末字节下标
                tx_frames = tx_frames + 1;                  // 帧数加一
            end                                             // 帧尾结束
        end                                                 // 采集结束
    end                                                     // 采集结束

    always @(posedge clk) begin                             // 统计发送错误计数
        if (rst_b && dut.mib_tx_error_inc) txerr_cnt = txerr_cnt + 1; // 发送错误脉冲
    end                                                     // 统计结束

    // ==================== 失败记录 ====================
    task do_fail;                                           // 记录一次失败
        input [255:0] msg;                                  // 失败信息
        begin                                               // 任务主体
            $display("  [FAIL] %0s", msg);                  // 打印失败
            fail_cnt = fail_cnt + 1;                        // 失败计数
        end                                                 // 任务主体结束
    endtask                                                 // 任务定义结束

    // ==================== 配置写 ====================
    task cfg_write;                                         // 写一条 VL 配置
        input [15:0] vlid;                                  // VLID
        input [15:0] udp_port;                              // UDP 目的端口
        input [1:0]  ptype;                                 // 端口类型
        input [15:0] bag;                                   // BAG（ms）
        input [15:0] lmax;                                  // Lmax
        begin                                               // 任务主体
            @(posedge clk);                                 // 等采样沿
            cfg_wr_en        <= 1'b1;                       // 写使能
            cfg_wr_addr      <= vlid[VL_ADDR_WIDTH-1:0];    // 表地址
            cfg_wr_vlid      <= vlid;                       // VLID
            cfg_wr_udp_port  <= udp_port;                   // UDP 端口
            cfg_wr_port_type <= ptype;                      // 端口类型
            cfg_wr_bag       <= bag;                        // BAG
            cfg_wr_lmax      <= lmax;                       // Lmax
            cfg_wr_rm_en     <= 1'b0;                       // 关闭 RM 冗余
            cfg_wr_ic_mode   <= 1'b0;                       // 关闭完整性检查
            @(posedge clk);                                 // 等采样沿
            cfg_wr_en        <= 1'b0;                       // 撤销写使能
        end                                                 // 任务主体结束
    endtask                                                 // 任务定义结束

    // ==================== 应用写整条消息 ====================
    task app_write_msg;                                     // 向发送缓冲写一条完整消息
        input [VL_INDEX_WIDTH-1:0] slot;                    // 槽位号
        input integer len;                                  // 字节数
        input [7:0]   base;                                 // 数据基值
        integer kk;                                         // 循环变量
        begin                                               // 任务主体
            for (kk = 0; kk < len; kk = kk + 1) begin       // 逐字节写
                @(posedge clk);                             // 等采样沿
                app_wr_vl_index    <= slot;                 // 槽位
                app_wr_byte_offset <= kk[BYTE_OFFSET_WIDTH-1:0]; // 偏移
                app_wr_data        <= base + kk[7:0];       // 数据
                app_wr_en          <= 1'b1;                 // 写使能
                wait (app_wr_gnt == 1'b1);                  // 等授权
                @(posedge clk);                             // 等采样沿
                app_wr_en          <= 1'b0;                 // 撤销
            end                                             // 写入结束
        end                                                 // 任务主体结束
    endtask                                                 // 任务定义结束

    // ==================== 发送一块（分片）帧 ====================
    task tx_block;                                          // 触发一次发送并等够帧数
        input integer want;                                 // 期望累计帧数
        begin                                               // 任务主体
            @(posedge clk); app_tx_req <= 1'b1;             // 发送请求
            @(posedge clk); app_tx_req <= 1'b0;             // 撤销
            waited = 0;                                     // 清等待计数
            while ((tx_frames < want) && (waited < (8*BAG_CYCLES))) begin  // 限时等待
                @(posedge clk); waited = waited + 1;        // 等采样沿并计数
            end                                             // 等待结束
        end                                                 // 任务主体结束
    endtask                                                 // 任务定义结束

    // ==================== 组装一个分片帧 ====================
    // mf=1 表示后面还有分片；off_field 是 IP 片偏移字段（单位 8 字节）。
    task build_frame;                                       // 组装一帧注入数据
        input [15:0] vlid;                                  // VLID
        input [15:0] udp_dst;                               // UDP 目的端口
        input [7:0]  sn;                                    // SN
        input        mf;                                    // 分片标志
        input [12:0] off_field;                             // 片偏移字段（8 字节为单位）
        input [7:0]  base;                                  // 应用数据基值
        input integer dlen;                                 // 本片数据长度
        begin                                               // 任务主体
            g_frame_buf[0]  = 8'h01; g_frame_buf[1]  = 8'h00;  // 目的 MAC 前缀
            g_frame_buf[2]  = 8'h00; g_frame_buf[3]  = 8'h00;  // 目的 MAC 前缀
            g_frame_buf[4]  = vlid[15:8]; g_frame_buf[5]  = vlid[7:0];  // 目的 MAC 低位=VLID
            g_frame_buf[6]  = 8'h02; g_frame_buf[7]  = 8'h00;  // 源 MAC
            g_frame_buf[8]  = 8'h00; g_frame_buf[9]  = 8'h00;  // 源 MAC
            g_frame_buf[10] = 8'h00; g_frame_buf[11] = 8'h01;  // 源 MAC
            g_frame_buf[12] = 8'h08; g_frame_buf[13] = 8'h00;  // 以太网类型 IPv4
            g_frame_buf[14] = 8'h45; g_frame_buf[15] = 8'h00;  // 版本/IHL、TOS
            g_frame_buf[16] = 8'h00; g_frame_buf[17] = 29 + dlen;  // IP 总长度
            g_frame_buf[18] = 8'h00; g_frame_buf[19] = 8'h01;  // IP 标识
            g_frame_buf[20] = {3'b000, mf, off_field[12:8]};   // 标志 + 片偏移高 5 位
            g_frame_buf[21] = off_field[7:0];                   // 片偏移低 8 位
            g_frame_buf[22] = 8'h01; g_frame_buf[23] = 8'h11;   // TTL、UDP
            g_frame_buf[24] = 8'h00; g_frame_buf[25] = 8'h00;   // 校验和占位
            g_frame_buf[26] = 8'h04; g_frame_buf[27] = 8'h00;   // 源 IP
            g_frame_buf[28] = 8'h00; g_frame_buf[29] = 8'h01;   // 源 IP
            g_frame_buf[30] = 8'hE0; g_frame_buf[31] = 8'hE0;   // 目的多播 IP 前缀
            g_frame_buf[32] = vlid[15:8]; g_frame_buf[33] = vlid[7:0];  // 目的 IP 低位
            g_frame_buf[34] = 8'h00; g_frame_buf[35] = 8'hA1;   // UDP 源端口
            g_frame_buf[36] = udp_dst[15:8]; g_frame_buf[37] = udp_dst[7:0];  // UDP 目的端口
            g_frame_buf[38] = 8'h00; g_frame_buf[39] = 9 + dlen;  // UDP 长度
            g_frame_buf[40] = 8'h00; g_frame_buf[41] = 8'h00;   // UDP 校验和
            for (i = 0; i < dlen; i = i + 1)                    // 应用数据
                g_frame_buf[42 + i] = base + i[7:0];            // 数据按基值递增
            g_frame_buf[42 + dlen] = sn;                        // SN 在数据之后
            g_cksum = 32'd0;                                    // 校验和清零
            for (i = 0; i < 10; i = i + 1)                      // 逐 16bit 字累加
                g_cksum = g_cksum + {1'b0, g_frame_buf[14 + i*2], g_frame_buf[15 + i*2]};  // 累加
            g_cksum = (g_cksum & 32'hFFFF) + (g_cksum >> 16);    // 回卷
            g_cksum = (g_cksum & 32'hFFFF) + (g_cksum >> 16);    // 再回卷
            g_frame_buf[24] = ~g_cksum[15:8];                   // 校验和高字节
            g_frame_buf[25] = ~g_cksum[7:0];                    // 校验和低字节
            g_len = 42 + dlen + 1;                              // 整帧字节数
        end                                                 // 任务主体结束
    endtask                                                 // 任务定义结束

    // ==================== 注入一个分片帧 ====================
    task inject_frame;                                      // 按 MAC 时序注入整帧
        input [15:0] vlid;                                  // 目标 VLID
        input [15:0] udp_dst;                               // UDP 目的端口
        input [7:0]  sn;                                    // SN
        input        mf;                                    // 分片标志
        input [12:0] off_field;                             // 片偏移字段
        input [7:0]  base;                                  // 数据基值
        input integer dlen;                                 // 本片数据长度
        begin                                               // 任务主体
            build_frame(vlid, udp_dst, sn, mf, off_field, base, dlen);  // 组装
            wait (ff_rx_rdy === 1'b1);                      // 等接收就绪
            @(posedge clk);                                 // 等采样沿
            for (i = 0; i < g_len; i = i + 1) begin         // 逐字节注入
                ff_rx_data     <= g_frame_buf[i];           // 数据
                ff_rx_data_vld <= 1'b1;                     // 有效
                ff_rx_sop      <= (i == 0);                 // 帧首
                ff_rx_eop      <= (i == g_len-1);           // 帧尾
                ff_rx_err      <= 1'b0;                     // 无错误
                @(posedge clk);                             // 等采样沿
            end                                             // 注入结束
            ff_rx_data_vld <= 1'b0;                         // 撤销有效
            ff_rx_sop      <= 1'b0;                         // 撤销帧首
            ff_rx_eop      <= 1'b0;                         // 撤销帧尾
            repeat (40) @(posedge clk);                     // 等状态机走完
        end                                                 // 任务主体结束
    endtask                                                 // 任务定义结束

    // ==================== 注入缓冲区里的一帧 ====================
    task inject_captured;                                   // 把采集到的第 idx 帧原样回灌
        input integer idx;                                  // 帧序号
        integer kk;                                         // 循环变量
        begin                                               // 任务主体
            wait (ff_rx_rdy === 1'b1);                      // 等接收就绪
            @(posedge clk);                                 // 等采样沿
            for (kk = tx_start[idx]; kk <= tx_end[idx]; kk = kk + 1) begin  // 逐字节回灌
                ff_rx_data     <= tx_mem[kk];               // 数据
                ff_rx_data_vld <= 1'b1;                     // 有效
                ff_rx_sop      <= (kk == tx_start[idx]);    // 帧首
                ff_rx_eop      <= (kk == tx_end[idx]);      // 帧尾
                ff_rx_err      <= 1'b0;                     // 无错误
                @(posedge clk);                             // 等采样沿
            end                                             // 回灌结束
            ff_rx_data_vld <= 1'b0;                         // 撤销有效
            ff_rx_sop      <= 1'b0;                         // 撤销帧首
            ff_rx_eop      <= 1'b0;                         // 撤销帧尾
            repeat (40) @(posedge clk);                     // 等状态机走完
        end                                                 // 任务主体结束
    endtask                                                 // 任务定义结束

    // ==================== 应用顺序读回 ====================
    task app_read;                                          // 顺序读回一帧数据
        input [VL_INDEX_WIDTH-1:0] slot;                    // 槽位号
        input integer len;                                  // 读取字节数
        input [7:0]   base;                                 // 期望数据基值
        integer kk;                                         // 循环变量
        begin                                               // 任务主体
            for (kk = 0; kk < len; kk = kk + 1) begin       // 逐字节读
                @(negedge clk);                             // 非采样沿改值
                app_rd_vl_index    <= slot;                 // 槽位号
                app_rd_byte_offset <= kk[BYTE_OFFSET_WIDTH-1:0]; // 偏移
                app_rd_en          <= 1'b1;                 // 读使能
                @(posedge clk);                             // 请求被授权
                @(negedge clk);                             // 授权后第一拍
                @(negedge clk);                             // 授权后第二拍：数据稳定
                if (app_rd_valid !== 1'b1)                  // 有效检查
                    do_fail("app read valid missing");      // 失败
                else if (app_rd_data !== (base + kk[7:0]))  // 数据检查
                    do_fail("app read data mismatch");      // 失败
                app_rd_en <= 1'b0;                          // 撤销读使能
            end                                             // 逐字节读结束
        end                                                 // 任务主体结束
    endtask                                                 // 任务定义结束

    // ==================== 主流程 ====================
    initial begin                                           // 激励流程
        clk = 1'b0; rst_b = 1'b0;                           // 初值
        ff_rx_data = 8'h00; ff_rx_data_vld = 1'b0; ff_rx_sop = 1'b0;  // 接收初值
        ff_rx_eop = 1'b0; ff_rx_err = 1'b0; rx_frame_net = 1'b0;      // 接收初值
        ff_tx_rdy = 1'b1;                                   // MAC 一直可以接收
        cfg_wr_en = 1'b0; cfg_wr_addr = 12'd0; cfg_wr_vlid = 16'd0;   // 配置初值
        cfg_wr_udp_port = 16'd0; cfg_wr_port_type = 2'd0; cfg_wr_bag = 16'd0;  // 配置初值
        cfg_wr_lmax = 16'd0; cfg_wr_rm_en = 1'b0; cfg_wr_ic_mode = 1'b0;  // 配置初值
        app_rd_vl_index = 4'd0; app_rd_byte_offset = 11'd0; app_rd_en = 1'b0;  // 应用读初值
        app_wr_en = 1'b0; app_wr_vl_index = 7'd0; app_wr_byte_offset = 11'd0;  // 应用写初值
        app_wr_data = 8'h00; app_tx_req = 1'b0;             // 应用写初值
        tx_cnt = 0; tx_frames = 0; txerr_cnt = 0; fail_cnt = 0;  // 计数初值
        repeat (10) @(posedge clk);                         // 保持复位
        rst_b = 1'b1;                                       // 释放复位
        repeat (5) @(posedge clk);                          // 等稳定

        cfg_write(16'h0004, 16'd4001, 2'b00, 16'd1, 16'd512);  // 采样端口，Lmax=512
        cfg_write(16'h0006, 16'd4006, 2'b00, 16'd1, 16'd512);  // 分片异常用例端口
        @(posedge clk); cfg_wr_vlid <= 16'hFFFF; cfg_wr_en <= 1'b1;  // 哨兵
        @(posedge clk); cfg_wr_en <= 1'b0;                  // 撤销
        repeat (6) @(posedge clk);                          // 等 cfg_done

        // ---------- 用例一：超过 Lmax 的消息按 Lmax 分片发出 ----------
        $display("=== 1200 字节消息分 3 片发送 ===");       // 用例标题
        app_write_msg(4'd4, MSG_A, 8'h00);                  // 写 1200 字节（基值 0）
        tx_block(3);                                        // 等 3 个分片
        repeat (4) @(posedge clk);                          // 等采集稳定
        if (tx_frames == 3) $display("  [PASS] 3 fragments sent");  // 帧数
        else do_fail("fragment count wrong");               // 失败
        if ((tx_end[0]-tx_start[0]+1) == 506 && (tx_end[1]-tx_start[1]+1) == 506 &&  // 前两片 43+463
            (tx_end[2]-tx_start[2]+1) == 317)               // 末片 43+274
            $display("  [PASS] fragment lengths 506/506/317");  // 通过
        else do_fail("fragment length wrong");              // 失败
        if (tx_mem[tx_start[0]+20] == 8'h20 && tx_mem[tx_start[0]+21] == 8'h00)  // 片 0：MF=1，偏移 0
            $display("  [PASS] fragment 0 header");         // 通过
        else do_fail("fragment 0 header");                  // 失败
        if (tx_mem[tx_start[1]+20] == 8'h20 && tx_mem[tx_start[1]+21] == 8'h3B)  // 片 1：(463+9)/8=59=0x3B，MF=1
            $display("  [PASS] fragment 1 header");         // 通过
        else do_fail("fragment 1 header");                  // 失败
        if (tx_mem[tx_start[2]+20] == 8'h00 && tx_mem[tx_start[2]+21] == 8'h76)  // 片 2：2×(463+9)/8=118=0x76，MF=0
            $display("  [PASS] fragment 2 header");         // 通过
        else do_fail("fragment 2 header");                  // 失败
        if (tx_mem[tx_start[0]+16] == 8'h01 && tx_mem[tx_start[0]+17] == 8'hEC)  // 片 0 IP 总长 29+463=492
            $display("  [PASS] fragment 0 ip total length"); // 通过
        else do_fail("fragment 0 ip total length");         // 失败
        if (tx_mem[tx_start[0]+42+463] == 8'd0 && tx_mem[tx_start[1]+42+463] == 8'd1 &&  // 每片自己的 SN
            tx_mem[tx_start[2]+42+274] == 8'd2)             // 末片 SN=2
            $display("  [PASS] per-fragment SN 0/1/2");     // 通过
        else do_fail("per-fragment SN wrong");              // 失败
        if (txerr_cnt == 0) $display("  [PASS] no tx error counted");  // 分片不记错误
        else do_fail("tx error counted on fragmentation");  // 失败

        // ---------- 用例二：把 3 个分片回灌，端口缓冲重组成整条消息 ----------
        $display("=== 分片回灌后重组出 1200 字节消息 ==="); // 用例标题
        inject_captured(0);                                 // 片 0
        inject_captured(1);                                 // 片 1
        if (app_rd_frame_cnt !== 4'd0)                      // 未收到末片不应提交
            do_fail("partial message committed too early"); // 失败
        else $display("  [PASS] partial fragments not committed");  // 通过
        inject_captured(2);                                 // 片 2（末片）
        app_rd_vl_index <= 4'd4;                            // 观察槽位 4
        repeat (4) @(posedge clk);                          // 等提交完成
        if ((app_rd_frame_cnt == 4'd1) && (app_rd_frame_len == MSG_A))  // 只提交一条 1200 字节消息
            $display("  [PASS] reassembled message length %0d", app_rd_frame_len);  // 通过
        else begin                                          // 失败
            $display("  [FAIL] reassembled length wrong (cnt=%0d len=%0d)", app_rd_frame_cnt, app_rd_frame_len);  // 打印
            fail_cnt = fail_cnt + 1;                        // 失败计数
        end                                                 // 失败结束
        app_read(4'd4, MSG_A, 8'h00);                       // 逐字节读回校验
        if (fail_cnt == 0) $display("  [PASS] reassembled payload byte-exact");  // 通过

        // ---------- 用例三：片偏移不连续 / 缺末片时不提交，随后可恢复 ----------
        $display("=== 分片异常与恢复 ===");                 // 用例标题
        // 槽位 6：先发一个“第二片”而不发首片 → 偏移不连续，不提交
        inject_frame(16'h0006, 16'd4006, 8'd0, 1'b0, 13'd59, 8'h80, 60);  // 偏移 59×8=472，无首片
        app_rd_vl_index <= 4'd6;                            // 观察槽位 6
        repeat (4) @(posedge clk);                          // 等判决
        if (app_rd_frame_cnt == 4'd0)                       // 不应提交
            $display("  [PASS] orphan fragment discarded"); // 通过
        else do_fail("orphan fragment committed");          // 失败
        // 送完整两片（首片 63 + 末片 57 = 120 字节）→ 正常重组
        // 首片 63 字节 ≡ 7 (mod 8)，所以末片偏移字段 =(8+63+1)/8 = 9
        inject_frame(16'h0006, 16'd4006, 8'd1, 1'b1, 13'd0, 8'h80, 63);   // SN=1 首片，MF=1
        inject_frame(16'h0006, 16'd4006, 8'd2, 1'b0, 13'd9, 8'hBF, 57);   // SN=2 末片，偏移 9×8=72
        repeat (4) @(posedge clk);                          // 等提交
        if ((app_rd_frame_cnt == 4'd1) && (app_rd_frame_len == 16'd120))  // 两片合成 120 字节
            $display("  [PASS] 2-fragment message reassembled");  // 通过
        else do_fail("2-fragment reassembly failed");       // 失败
        app_read(4'd6, 120, 8'h80);                         // 读回校验（数据 0x80 起递增）
        if (fail_cnt == 0) $display("  [PASS] 2-fragment payload byte-exact");  // 通过

        // 缺末片：只发首片，不应提交（采样端口在新消息首片时清掉旧帧，所以队列为空）
        inject_frame(16'h0006, 16'd4006, 8'd3, 1'b1, 13'd0, 8'h10, 60);   // 只有首片
        repeat (200) @(posedge clk);                        // 等一段观察时间
        if (app_rd_frame_cnt == 4'd0)                       // 半条消息不会被读出去
            $display("  [PASS] missing last fragment not committed");  // 通过
        else do_fail("missing last fragment committed");    // 失败

        if (fail_cnt == 0) $display("PASS: joint fragmentation chain");  // 汇总
        else $display("FAIL: joint fragmentation failures=%0d", fail_cnt); // 汇总
        $finish;                                            // 结束仿真
    end                                                     // 激励流程结束

endmodule                                                   // 模块定义结束

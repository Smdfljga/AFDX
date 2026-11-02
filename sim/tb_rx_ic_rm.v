// tb_rx_ic_rm : afdx_rx 的 IC（序列号）与 RM（冗余管理）判据仿真
// 用例 1：SN = 0 / 1 / 1 / 5 / 6 依次注入，验证首帧接受、正常递增接受、
// 同网重复丢弃、SN 跳跃丢弃并重同步 PSN、重同步后下一帧恢复正常；
// 用例 2：SN = 255 / 1，验证 255 -> 1 的环上回绕判据；
// 用例 3：非首帧收到 SN = 0，验证丢弃且不更新 PSN；
// 用例 4：跨网副本（frame_net 不同）在 RM 使能时计 rm_drop_count，不发送；
// 配合 ip_sim_models.v 使用；本文件只用于仿真，不参与 FPGA 综合。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_rx_ic_rm;                                         // 声明模块及其参数接口

    localparam DATA_WIDTH        = 8;                       // 声明localparam、DATA_WIDTH所需的信号或常量
    localparam VLID_WIDTH        = 16;                      // 声明localparam、VLID_WIDTH所需的信号或常量
    localparam VL_ADDR_WIDTH     = 12;                      // 声明localparam、VL_ADDR_WIDTH所需的信号或常量
    localparam VL_INDEX_WIDTH    = 4;                       // 声明localparam、VL_INDEX_WIDTH所需的信号或常量
    localparam BYTE_OFFSET_WIDTH = 11;                      // 声明localparam、BYTE_OFFSET_WIDTH所需的信号或常量
    localparam STATE_WIDTH       = 64;                      // 声明localparam、STATE_WIDTH所需的信号或常量
    localparam FRAME_LEN         = 60;                          // 14 + 20 + 8 + 17 应用数据 + 1 SN
    localparam DATA_LEN          = 17;                          // 本用例的应用数据字节数

    reg clk;                                                // 声明clk所需的信号或常量
    reg rst_b;                                              // 声明rst_b所需的信号或常量
    reg [DATA_WIDTH-1:0] ff_rx_data;                        // 声明DATA_WIDTH、ff_rx_data所需的信号或常量
    reg ff_rx_data_vld, ff_rx_sop, ff_rx_eop, ff_rx_err;    // 声明ff_rx_data_vld、ff_rx_sop、ff_rx_eop所需的信号或常量
    wire ff_rx_rdy;                                         // 声明ff_rx_rdy所需的信号或常量
    reg frame_net;                                          // 声明frame_net所需的信号或常量

    wire [VL_ADDR_WIDTH-1:0] cfg_addr;                      // 声明VL_ADDR_WIDTH、cfg_addr所需的信号或常量
    wire cfg_rd_en;                                         // 声明cfg_rd_en所需的信号或常量
    wire [VLID_WIDTH-1:0]    cfg_tag;                       // 声明VLID_WIDTH、cfg_tag所需的信号或常量
    wire cfg_valid;                                         // 声明cfg_valid所需的信号或常量
    wire [1:0]  cfg_port_type;                              // 声明cfg_port_type所需的信号或常量
    wire [15:0] cfg_udp_port, cfg_bag, cfg_lmax;            // 声明cfg_udp_port、cfg_bag、cfg_lmax所需的信号或常量
    wire cfg_rm_en, cfg_ic_mode;                            // 声明cfg_rm_en、cfg_ic_mode所需的信号或常量

    wire [VL_ADDR_WIDTH-1:0] st_addr;                       // 声明VL_ADDR_WIDTH、st_addr所需的信号或常量
    wire st_rd_en;                                          // 声明st_rd_en所需的信号或常量
    wire [STATE_WIDTH-1:0] st_rd_data;                      // 声明STATE_WIDTH、st_rd_data所需的信号或常量
    wire st_wr_en;                                          // 声明st_wr_en所需的信号或常量
    wire [STATE_WIDTH-1:0] st_wr_data;                      // 声明STATE_WIDTH、st_wr_data所需的信号或常量

    wire port_wr_en;                                        // 声明port_wr_en所需的信号或常量
    wire [VL_INDEX_WIDTH-1:0]    port_wr_vl_index;          // 声明VL_INDEX_WIDTH、port_wr_vl_index所需的信号或常量
    wire [BYTE_OFFSET_WIDTH-1:0] port_wr_byte_offset;       // 声明BYTE_OFFSET_WIDTH、port_wr_byte_offset所需的信号或常量
    wire [DATA_WIDTH-1:0]        port_wr_data;              // 声明DATA_WIDTH、port_wr_data所需的信号或常量
    wire [1:0]  port_type;                                  // 声明port_type所需的信号或常量
    wire rx_ready_app, rx_ready_snmp, rx_ready_615a, rx_ready_rtc;  // 声明rx_ready_app、rx_ready_snmp、rx_ready_615a所需的信号或常量
    wire port_wr_frame_done;                                // 声明port_wr_frame_done所需的信号或常量
    wire [15:0] port_wr_frame_len;                          // 声明port_wr_frame_len所需的信号或常量
    wire port_wr_queue_mode;                                // 声明port_wr_queue_mode所需的信号或常量
    reg  port_wr_full;                                      // 声明port_wr_full所需的信号或常量

    wire [VL_ADDR_WIDTH-1:0] mib_addr;                      // 声明VL_ADDR_WIDTH、mib_addr所需的信号或常量
    wire mib_rx_frame_inc, mib_rx_error_inc, mib_sn_error_inc;  // 声明mib_rx_frame_inc、mib_rx_error_inc、mib_sn_error_inc所需的信号或常量
    wire mib_rm_drop_inc, mib_rx_byte_inc;                  // 声明mib_rm_drop_inc、mib_rx_byte_inc所需的信号或常量
    wire irq_rx_frame, irq_error;                           // 声明irq_rx_frame、irq_error所需的信号或常量

    // 配置表写入（TB 直接写端口 A，不经 config_wr）
    reg        cfg_wr_en;                                   // 声明cfg_wr_en所需的信号或常量
    reg [VL_ADDR_WIDTH-1:0] cfg_wr_addr;                    // 声明VL_ADDR_WIDTH、cfg_wr_addr所需的信号或常量
    reg [VLID_WIDTH-1:0]    cfg_wr_vlid;                    // 声明VLID_WIDTH、cfg_wr_vlid所需的信号或常量
    reg [15:0] cfg_wr_udp_port;                             // 声明cfg_wr_udp_port所需的信号或常量
    reg [1:0]  cfg_wr_port_type;                            // 声明cfg_wr_port_type所需的信号或常量
    reg [15:0] cfg_wr_bag, cfg_wr_lmax;                     // 声明cfg_wr_bag、cfg_wr_lmax所需的信号或常量
    reg cfg_wr_rm_en, cfg_wr_ic_mode;                       // 声明cfg_wr_rm_en、cfg_wr_ic_mode所需的信号或常量

    // 计数与判据
    integer g_commit;                                           // 端口缓冲提交次数
    integer g_frame;                                            // 成功帧计数脉冲
    integer g_err;                                              // 错误帧计数脉冲
    integer g_sn_err;                                           // SN 错误计数脉冲
    integer g_rm_drop;                                          // RM 冗余副本丢弃脉冲
    integer g_byte;                                             // 字节计数脉冲
    integer g_fail;                                             // 失败计数
    integer i;                                              // 声明integer、i所需的信号或常量

    reg [7:0]  g_frame_buf [0:FRAME_LEN-1];                     // 注入用的整帧字节
    reg [16:0] g_cksum;                                         // IP 首部校验和累加器

    always #5 clk = ~clk;                                       // 100MHz

    // ==================== 计数脉冲监视 ====================
    always @(posedge clk) begin                             // 按时钟沿更新寄存器，并响应声明的异步复位
        if (rst_b) begin                                    // 检查复位或正常运行条件
            if (port_wr_frame_done) g_commit  = g_commit + 1;  // 检查port_wr_frame_done、端口缓冲提交次数、端口缓冲提交次数的条件
            if (mib_rx_frame_inc)   g_frame   = g_frame + 1;  // 检查mib_rx_frame_inc、成功帧计数脉冲、成功帧计数脉冲的条件
            if (mib_rx_error_inc)   g_err     = g_err + 1;  // 检查mib_rx_error_inc、错误帧计数脉冲、错误帧计数脉冲的条件
            if (mib_sn_error_inc)   g_sn_err  = g_sn_err + 1;  // 检查mib_sn_error_inc、SN 错误计数脉冲、SN 错误计数脉冲的条件
            if (mib_rm_drop_inc)    g_rm_drop = g_rm_drop + 1;  // 检查mib_rm_drop_inc、RM 冗余副本丢弃脉冲、RM 冗余副本丢弃脉冲的条件
            if (mib_rx_byte_inc)    g_byte    = g_byte + 1;  // 检查mib_rx_byte_inc、字节计数脉冲、字节计数脉冲的条件
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    // ==================== 被测接收模块 ====================
    afdx_rx #(                                              // 例化子模块并连接数据通路
        .DATA_WIDTH(DATA_WIDTH), .VLID_WIDTH(VLID_WIDTH), .VL_ADDR_WIDTH(VL_ADDR_WIDTH),  // 连接子模块对应端口
        .VL_INDEX_WIDTH(VL_INDEX_WIDTH), .BYTE_OFFSET_WIDTH(BYTE_OFFSET_WIDTH),  // 连接子模块对应端口
        .CNT_WIDTH(32), .STATE_WIDTH(STATE_WIDTH),          // 连接子模块对应端口
        .VL_INDEX_SNMP(4'd1), .VL_INDEX_615A(4'd2), .VL_INDEX_RTC(4'd3)  // 连接子模块对应端口
    ) dut (                                                 // 参数绑定结束，开始连接实例端口
        .clk(clk), .rst_b(rst_b),                           // 连接子模块对应端口
        .ff_rx_data(ff_rx_data), .ff_rx_data_vld(ff_rx_data_vld),  // 连接子模块对应端口
        .ff_rx_sop(ff_rx_sop), .ff_rx_eop(ff_rx_eop), .ff_rx_err(ff_rx_err),  // 连接子模块对应端口
        .ff_rx_rdy(ff_rx_rdy),                              // 连接子模块对应端口
        .frame_net(frame_net),                              // 连接子模块对应端口
        .cfg_addr(cfg_addr), .cfg_rd_en(cfg_rd_en), .cfg_tag(cfg_tag),  // 连接子模块对应端口
        .cfg_valid(cfg_valid), .cfg_port_type(cfg_port_type),  // 连接子模块对应端口
        .cfg_udp_port(cfg_udp_port), .cfg_bag(cfg_bag), .cfg_lmax(cfg_lmax),  // 连接子模块对应端口
        .cfg_rm_en(cfg_rm_en), .cfg_ic_mode(cfg_ic_mode),   // 连接子模块对应端口
        .st_addr(st_addr), .st_rd_en(st_rd_en), .st_rd_data(st_rd_data),  // 连接子模块对应端口
        .st_wr_en(st_wr_en), .st_wr_data(st_wr_data),       // 连接子模块对应端口
        .port_wr_en(port_wr_en), .port_wr_vl_index(port_wr_vl_index),  // 连接子模块对应端口
        .port_wr_byte_offset(port_wr_byte_offset), .port_wr_data(port_wr_data),  // 连接子模块对应端口
        .port_type(port_type),                              // 连接子模块对应端口
        .rx_ready_app(rx_ready_app), .rx_ready_snmp(rx_ready_snmp),  // 连接子模块对应端口
        .rx_ready_615a(rx_ready_615a), .rx_ready_rtc(rx_ready_rtc),  // 连接子模块对应端口
        .port_wr_frame_done(port_wr_frame_done), .port_wr_frame_len(port_wr_frame_len),  // 连接子模块对应端口
        .port_wr_queue_mode(port_wr_queue_mode), .port_wr_full(port_wr_full),  // 连接子模块对应端口
        .mib_addr(mib_addr), .mib_rx_frame_inc(mib_rx_frame_inc),  // 连接子模块对应端口
        .mib_rx_error_inc(mib_rx_error_inc), .mib_sn_error_inc(mib_sn_error_inc),  // 连接子模块对应端口
        .mib_rm_drop_inc(mib_rm_drop_inc), .mib_rx_byte_inc(mib_rx_byte_inc),  // 连接子模块对应端口
        .irq_rx_frame(irq_rx_frame), .irq_error(irq_error)  // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    // ==================== 配置表与状态表（端口 A 接 RX） ====================
    vl_config_ram #(                                        // 例化子模块并连接数据通路
        .VLID_WIDTH(VLID_WIDTH), .VL_ADDR_WIDTH(VL_ADDR_WIDTH)  // 连接子模块对应端口
    ) u_vl_config_ram (                                     // 参数绑定结束，开始连接实例端口
        .clk_a(clk), .rst_a(~rst_b), .addr_a(cfg_addr), .rd_en_a(cfg_rd_en),  // 连接子模块对应端口
        .tag_a(cfg_tag), .valid_a(cfg_valid), .port_type_a(cfg_port_type),  // 连接子模块对应端口
        .udp_port_a(cfg_udp_port), .bag_a(cfg_bag), .lmax_a(cfg_lmax),  // 连接子模块对应端口
        .rm_en_a(cfg_rm_en), .ic_mode_a(cfg_ic_mode),       // 连接子模块对应端口
        .clk_b(clk), .rst_b(~rst_b), .addr_b({VL_ADDR_WIDTH{1'b0}}),  // 连接子模块对应端口
        .rd_en_b(1'b0), .tag_b(), .valid_b(), .port_type_b(), .udp_port_b(),  // 连接子模块对应端口
        .bag_b(), .lmax_b(), .rm_en_b(), .ic_mode_b(),      // 连接子模块对应端口
        .cfg_wr_en(cfg_wr_en), .cfg_wr_addr(cfg_wr_addr), .cfg_wr_vlid(cfg_wr_vlid),  // 连接子模块对应端口
        .cfg_wr_udp_port(cfg_wr_udp_port), .cfg_wr_port_type(cfg_wr_port_type),  // 连接子模块对应端口
        .cfg_wr_bag(cfg_wr_bag), .cfg_wr_lmax(cfg_wr_lmax),  // 连接子模块对应端口
        .cfg_wr_rm_en(cfg_wr_rm_en), .cfg_wr_ic_mode(cfg_wr_ic_mode)  // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    vl_state_ram #(                                         // 例化子模块并连接数据通路
        .VL_ADDR_WIDTH(VL_ADDR_WIDTH), .STATE_WIDTH(STATE_WIDTH)  // 连接子模块对应端口
    ) u_vl_state_ram (                                      // 参数绑定结束，开始连接实例端口
        .clk_a(clk), .rst_a(~rst_b), .addr_a(st_addr), .rd_en_a(st_rd_en),  // 连接子模块对应端口
        .rd_data_a(st_rd_data), .wr_en_a(st_wr_en), .wr_data_a(st_wr_data),  // 连接子模块对应端口
        .clk_b(clk), .rst_b(~rst_b), .addr_b({VL_ADDR_WIDTH{1'b0}}),  // 连接子模块对应端口
        .rd_en_b(1'b0), .rd_data_b(), .wr_en_b(1'b0), .wr_data_b({STATE_WIDTH{1'b0}})  // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    // ==================== 激励任务 ====================
    // 写一条 VL 配置：地址 = VLID 低位，端口类型由入参决定
    task cfg_write;                                         // 声明可重复调用的仿真任务
        input [1:0] port_type_in;                           // 声明input、port_type_in所需的信号或常量
        input       rm_en_in;                               // 声明input、rm_en_in所需的信号或常量
        begin                                               // 开始执行当前条件或循环的语句组
            @(posedge clk);                                 // 等待指定时钟边沿后继续仿真
            cfg_wr_addr      <= 12'h004;                    // 时钟沿更新cfg_wr_addr
            cfg_wr_vlid      <= 16'h0004;                   // 时钟沿更新cfg_wr_vlid
            cfg_wr_udp_port  <= 16'd4001;                   // 时钟沿更新cfg_wr_udp_port
            cfg_wr_port_type <= port_type_in;               // 时钟沿更新cfg_wr_port_type
            cfg_wr_bag       <= 16'd1;                      // 时钟沿更新cfg_wr_bag
            cfg_wr_lmax      <= 16'd512;                    // 时钟沿更新cfg_wr_lmax
            cfg_wr_rm_en     <= rm_en_in;                   // 时钟沿更新cfg_wr_rm_en
            cfg_wr_ic_mode   <= 1'b0;                       // 时钟沿更新cfg_wr_ic_mode
            cfg_wr_en        <= 1'b1;                       // 时钟沿更新cfg_wr_en
            @(posedge clk);                                 // 等待指定时钟边沿后继续仿真
            cfg_wr_en        <= 1'b0;                       // 时钟沿更新cfg_wr_en
            repeat (4) @(posedge clk);                      // 等待指定数量的时钟周期
        end                                                 // 当前语句组结束
    endtask                                                 // 仿真任务定义结束

    // 组装一帧 VLID=0x0004、UDP 目的端口 4001、17 字节应用数据的 AFDX 报文
    task build_frame;                                       // 声明可重复调用的仿真任务
        input [7:0] sn;                                     // 声明input、sn所需的信号或常量
        begin                                               // 开始执行当前条件或循环的语句组
            // 目的 MAC：前缀 01 00 00 00 + VLID 高/低字节
            g_frame_buf[0] = 8'h01; g_frame_buf[1] = 8'h00;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[2] = 8'h00; g_frame_buf[3] = 8'h00;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[4] = 8'h00; g_frame_buf[5] = 8'h04;  // 设置或组合计算注入用的整帧字节
            // 源 MAC
            g_frame_buf[6]  = 8'h02; g_frame_buf[7]  = 8'h00;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[8]  = 8'h00; g_frame_buf[9]  = 8'h00;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[10] = 8'h00; g_frame_buf[11] = 8'h01;  // 设置或组合计算注入用的整帧字节
            // 以太网类型 = IPv4
            g_frame_buf[12] = 8'h08; g_frame_buf[13] = 8'h00;  // 设置或组合计算注入用的整帧字节
            // IP 头：版本/IHL、TOS、总长度 46、标识、DF=1、TTL、协议 UDP、校验和、源/目的 IP
            g_frame_buf[14] = 8'h45; g_frame_buf[15] = 8'h00;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[16] = 8'h00; g_frame_buf[17] = 8'h2E;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[18] = 8'h00; g_frame_buf[19] = 8'h01;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[20] = 8'h40; g_frame_buf[21] = 8'h00;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[22] = 8'h01; g_frame_buf[23] = 8'h11;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[24] = 8'h00; g_frame_buf[25] = 8'h00;   // 校验和先填 0
            g_frame_buf[26] = 8'h04; g_frame_buf[27] = 8'h00;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[28] = 8'h00; g_frame_buf[29] = 8'h01;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[30] = 8'hE0; g_frame_buf[31] = 8'hE0;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[32] = 8'h00; g_frame_buf[33] = 8'h04;  // 设置或组合计算注入用的整帧字节
            // UDP 头：源端口、目的端口 4001、UDP 长度 26、校验和
            g_frame_buf[34] = 8'h00; g_frame_buf[35] = 8'hA1;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[36] = 8'h0F; g_frame_buf[37] = 8'hA1;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[38] = 8'h00; g_frame_buf[39] = 8'h1A;  // 设置或组合计算注入用的整帧字节
            g_frame_buf[40] = 8'h00; g_frame_buf[41] = 8'h00;  // 设置或组合计算注入用的整帧字节
            // 应用数据 00..10，其后 1 字节 SN
            for (i = 0; i < DATA_LEN; i = i + 1)            // 依次处理指定范围内的表项或位段
                g_frame_buf[42 + i] = i[7:0];               // 设置或组合计算注入用的整帧字节
            g_frame_buf[42 + DATA_LEN] = sn;                // 设置或组合计算注入用的整帧字节

            // IP 首部校验和：16bit 大端求和、进位回卷、取反
            g_cksum = 17'd0;                                // 设置或组合计算IP 首部校验和累加器
            for (i = 0; i < 10; i = i + 1)                  // 依次处理指定范围内的表项或位段
                g_cksum = g_cksum + {1'b0, g_frame_buf[14 + i*2], g_frame_buf[15 + i*2]};  // 设置或组合计算IP 首部校验和累加器
            g_cksum = {1'b0, g_cksum[15:0]} + {16'b0, g_cksum[16]};  // 设置或组合计算IP 首部校验和累加器
            g_frame_buf[24] = ~g_cksum[15:8];               // 设置或组合计算注入用的整帧字节
            g_frame_buf[25] = ~g_cksum[7:0];                // 设置或组合计算注入用的整帧字节
        end                                                 // 当前语句组结束
    endtask                                                 // 仿真任务定义结束

    // 按 MAC 字节流注入整帧
    task inject_frame;                                      // 声明可重复调用的仿真任务
        input [7:0] sn;                                     // 声明input、sn所需的信号或常量
        begin                                               // 开始执行当前条件或循环的语句组
            build_frame(sn);                                // 例化子模块并连接数据通路
            wait (ff_rx_rdy === 1'b1);                      // 继续计算g_frame_buf
            @(posedge clk);                                 // 等待指定时钟边沿后继续仿真
            for (i = 0; i < FRAME_LEN; i = i + 1) begin     // 依次处理指定范围内的表项或位段
                ff_rx_data     <= g_frame_buf[i];           // 时钟沿更新ff_rx_data
                ff_rx_data_vld <= 1'b1;                     // 时钟沿更新ff_rx_data_vld
                ff_rx_sop      <= (i == 0);                 // 时钟沿更新ff_rx_sop
                ff_rx_eop      <= (i == FRAME_LEN-1);       // 时钟沿更新ff_rx_eop
                @(posedge clk);                             // 等待指定时钟边沿后继续仿真
            end                                             // 当前语句组结束
            ff_rx_data_vld <= 1'b0;                         // 时钟沿更新ff_rx_data_vld
            ff_rx_sop      <= 1'b0;                         // 时钟沿更新ff_rx_sop
            ff_rx_eop      <= 1'b0;                         // 时钟沿更新ff_rx_eop
            repeat (40) @(posedge clk);                          // 等状态机走完 DISPATCH/MIB_BYTES/DONE
        end                                                 // 当前语句组结束
    endtask                                                 // 仿真任务定义结束

    task check;                                             // 声明可重复调用的仿真任务
        input [255:0] name;                                 // 声明input、name所需的信号或常量
        input integer exp;                                  // 声明input、integer、exp所需的信号或常量
        input integer got;                                  // 声明input、integer、got所需的信号或常量
        begin                                               // 开始执行当前条件或循环的语句组
            if (exp === got)                                // 检查exp、got的条件
                $display("  [PASS] %0s = %0d", name, got);  // 输出当前仿真检查结果或报文字节
            else begin                                      // 前一条件不满足时执行本分支
                $display("  [FAIL] %0s exp=%0d got=%0d", name, exp, got);  // 输出当前仿真检查结果或报文字节
                g_fail = g_fail + 1;                        // 设置或组合计算失败计数并推进至下一项
            end                                             // 当前语句组结束
        end                                                 // 当前语句组结束
    endtask                                                 // 仿真任务定义结束

    // ==================== 激励主体 ====================
    initial begin                                           // 仿真初始化或激励流程
        clk = 0; rst_b = 0;                                 // 设置或组合计算clk
        ff_rx_data = 8'd0; ff_rx_data_vld = 0; ff_rx_sop = 0; ff_rx_eop = 0; ff_rx_err = 0;  // 设置或组合计算ff_rx_data
        frame_net = 1'b0; port_wr_full = 1'b0;              // 设置或组合计算frame_net
        cfg_wr_en = 0; cfg_wr_addr = 0; cfg_wr_vlid = 0; cfg_wr_udp_port = 0;  // 设置或组合计算cfg_wr_en
        cfg_wr_port_type = 0; cfg_wr_bag = 0; cfg_wr_lmax = 0;  // 设置或组合计算cfg_wr_port_type
        cfg_wr_rm_en = 0; cfg_wr_ic_mode = 0;               // 设置或组合计算cfg_wr_rm_en
        g_commit = 0; g_frame = 0; g_err = 0; g_sn_err = 0; g_rm_drop = 0; g_byte = 0;  // 设置或组合计算端口缓冲提交次数
        g_fail = 0;                                         // 设置或组合计算失败计数

        repeat (10) @(posedge clk);                         // 等待指定数量的时钟周期
        rst_b = 1;                                          // 设置或组合计算rst_b
        repeat (5) @(posedge clk);                          // 等待指定数量的时钟周期

        // 队列端口、不使能 RM，便于逐个判据观察
        cfg_write(2'b01, 1'b0);                             // 例化子模块并连接数据通路

        $display("=== RX IC sequence 0/1/1/5/6 ===");       // 输出当前仿真检查结果或报文字节
        inject_frame(8'd0);                                     // 首帧：无条件接受
        check("commit after sn=0", 1, g_commit);            // 继续计算rst_b
        inject_frame(8'd1);                                     // 正常递增：接受
        check("commit after sn=1", 2, g_commit);            // 继续计算rst_b
        inject_frame(8'd1);                                     // 同网重复：丢弃 + SN 错误
        check("commit after dup sn=1", 2, g_commit);        // 继续计算rst_b
        check("sn_err after dup", 1, g_sn_err);             // 例化子模块并连接数据通路
        inject_frame(8'd5);                                     // SN 跳跃：丢弃 + 重同步 PSN=5
        check("commit after sn=5 jump", 2, g_commit);       // 继续计算rst_b
        check("sn_err after jump", 2, g_sn_err);            // 例化子模块并连接数据通路
        inject_frame(8'd6);                                     // 重同步后应恢复正常：接受
        check("commit after resync sn=6", 3, g_commit);     // 继续计算rst_b

        $display("=== RX SN wrap 255 -> 1 ===");            // 输出当前仿真检查结果或报文字节
        inject_frame(8'd255);                                   // 跳跃：丢弃并把 PSN 重同步到 255
        check("sn_err after 255", 3, g_sn_err);             // 例化子模块并连接数据通路
        inject_frame(8'd1);                                     // 环上回绕：应接受
        check("commit after wrap sn=1", 4, g_commit);       // 继续计算rst_b

        $display("=== RX invalid sn=0 and recovery ===");   // 输出当前仿真检查结果或报文字节
        inject_frame(8'd0);                                     // 非首帧的 0：丢弃且不更新 PSN
        check("commit after bad sn=0", 4, g_commit);        // 继续计算rst_b
        check("sn_err after bad sn=0", 4, g_sn_err);        // 继续计算rst_b
        inject_frame(8'd2);                                     // PSN 仍为 1：2 是期望值，应接受
        check("commit after recovery sn=2", 5, g_commit);   // 继续计算rst_b

        $display("=== RX cross-network duplicate with RM enabled ===");  // 输出当前仿真检查结果或报文字节
        cfg_write(2'b01, 1'b1);                                 // 打开 RM
        frame_net = 1'b1;                                       // 换一张网注入同一 SN
        inject_frame(8'd2);                                     // 跨网副本：计 RM 丢弃，不发错误
        check("commit after cross dup", 5, g_commit);       // 例化子模块并连接数据通路
        check("rm_drop after cross dup", 1, g_rm_drop);     // 例化子模块并连接数据通路
        check("sn_err after cross dup", 4, g_sn_err);       // 例化子模块并连接数据通路
        frame_net = 1'b0;                                   // 设置或组合计算frame_net
        inject_frame(8'd3);                                     // 下一帧正常递增
        check("commit after sn=3", 6, g_commit);            // 继续计算frame_net

        check("rx_error_count", 4, g_err);                  // 例化子模块并连接数据通路
        check("rx_frame_count", 6, g_frame);                // 例化子模块并连接数据通路
        check("rx_byte_count", 6 * DATA_LEN, g_byte);       // 例化子模块并连接数据通路

        $display("=== result: %0d failures ===", g_fail);   // 输出当前仿真检查结果或报文字节
        if (g_fail == 0) $display(" >>> CASE PASSED");      // 检查失败计数、display、CASE的条件
        else             $display(" >>> CASE FAILED");      // 采用前一条件未满足时的处理
        $finish;                                            // 结束当前自检仿真
    end                                                     // 当前语句组结束

endmodule                                                   // 模块定义结束

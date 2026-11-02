`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_afdx_rx;                                          // 声明模块及其参数接口

    // ---------------- ?? ----------------
    localparam VLID_VAL     = 16'h0001;                     // 声明localparam、VLID_VAL、h0001所需的信号或常量
    localparam UDP_PORT_VAL = 16'h0BB8;   // 3000
    localparam APP_DATA_LEN = 32;         // ???????

    // ---------------- ??/?? ----------------
    reg clk;                                                // 声明clk所需的信号或常量
    reg rst_b;                                              // 声明rst_b所需的信号或常量

    // ---------------- MAC ?? ----------------
    reg  [7:0] ff_rx_data;                                  // 声明ff_rx_data所需的信号或常量
    reg        ff_rx_data_vld;                              // 声明ff_rx_data_vld所需的信号或常量
    reg        ff_rx_sop;                                   // 声明ff_rx_sop所需的信号或常量
    reg        ff_rx_eop;                                   // 声明ff_rx_eop所需的信号或常量
    reg        ff_rx_err;                                   // 声明ff_rx_err所需的信号或常量
    wire       ff_rx_rdy;                                   // 声明ff_rx_rdy所需的信号或常量

    // ---------------- ?? ----------------
    reg        frame_net;                                   // 声明frame_net所需的信号或常量

    // ---------------- ??? ----------------
    wire [11:0] cfg_addr;                                   // 声明cfg_addr所需的信号或常量
    wire        cfg_rd_en;                                  // 声明cfg_rd_en所需的信号或常量
    wire [15:0] cfg_tag;                                    // 声明cfg_tag所需的信号或常量
    wire        cfg_valid;                                  // 声明cfg_valid所需的信号或常量
    wire [1:0]  cfg_port_type;                              // 声明cfg_port_type所需的信号或常量
    wire [15:0] cfg_udp_port;                               // 声明cfg_udp_port所需的信号或常量
    wire [15:0] cfg_bag;                                    // 声明cfg_bag所需的信号或常量
    wire [15:0] cfg_lmax;                                   // 声明cfg_lmax所需的信号或常量
    wire        cfg_rm_en;                                  // 声明cfg_rm_en所需的信号或常量
    wire        cfg_ic_mode;                                // 声明cfg_ic_mode所需的信号或常量

    // ---------------- ??? ----------------
    wire [11:0] st_addr;                                    // 声明st_addr所需的信号或常量
    wire        st_rd_en;                                   // 声明st_rd_en所需的信号或常量
    wire [63:0] st_rd_data;                                 // 声明st_rd_data所需的信号或常量
    wire        st_wr_en;                                   // 声明st_wr_en所需的信号或常量
    wire [63:0] st_wr_data;                                 // 声明st_wr_data所需的信号或常量

    // ---------------- ???? ----------------
    wire        port_wr_en;                                 // 声明port_wr_en所需的信号或常量
    wire [3:0]  port_wr_vl_index;                           // 声明port_wr_vl_index所需的信号或常量
    wire [10:0] port_wr_byte_offset;                        // 声明port_wr_byte_offset所需的信号或常量
    wire [7:0]  port_wr_data;                               // 声明port_wr_data所需的信号或常量
    wire [1:0]  port_type;                                  // 声明port_type所需的信号或常量
    wire        rx_ready_app;                               // 声明rx_ready_app所需的信号或常量
    wire        rx_ready_snmp;                              // 声明rx_ready_snmp所需的信号或常量
    wire        rx_ready_615a;                              // 声明rx_ready_615a所需的信号或常量
    wire        rx_ready_rtc;                               // 声明rx_ready_rtc所需的信号或常量
    wire        port_wr_frame_done;                         // 声明port_wr_frame_done所需的信号或常量
    wire [15:0] port_wr_frame_len;                          // 声明port_wr_frame_len所需的信号或常量
    wire        port_wr_queue_mode;                         // 声明port_wr_queue_mode所需的信号或常量
    reg         port_wr_full;                               // 声明port_wr_full所需的信号或常量

    // ---------------- MIB ----------------
    wire [11:0] mib_addr;                                   // 声明mib_addr所需的信号或常量
    wire        mib_rx_frame_inc;                           // 声明mib_rx_frame_inc所需的信号或常量
    wire        mib_rx_error_inc;                           // 声明mib_rx_error_inc所需的信号或常量
    wire        mib_sn_error_inc;                           // 声明mib_sn_error_inc所需的信号或常量
    wire        mib_rm_drop_inc;                            // 声明mib_rm_drop_inc所需的信号或常量
    wire        mib_rx_byte_inc;                            // 声明mib_rx_byte_inc所需的信号或常量

    // ---------------- ?? ----------------
    wire irq_rx_frame;                                      // 声明irq_rx_frame所需的信号或常量
    wire irq_error;                                         // 声明irq_error所需的信号或常量

    // ============================================================
    // DUT
    // ============================================================
    afdx_rx #(                                              // 例化子模块并连接数据通路
        .DATA_WIDTH(8),                                     // 连接子模块对应端口
        .VLID_WIDTH(16),                                    // 连接子模块对应端口
        .VL_ADDR_WIDTH(12),                                 // 连接子模块对应端口
        .VL_INDEX_WIDTH(4),                                 // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH(11),                             // 连接子模块对应端口
        .CNT_WIDTH(32),                                     // 连接子模块对应端口
        .STATE_WIDTH(64),                                   // 连接子模块对应端口
        .VL_INDEX_SNMP(4'd1),                               // 连接子模块对应端口
        .VL_INDEX_615A(4'd2),                               // 连接子模块对应端口
        .VL_INDEX_RTC(4'd3)                                 // 连接子模块对应端口
    ) dut (                                                 // 参数绑定结束，开始连接实例端口
        .clk(clk),                                          // 连接子模块对应端口
        .rst_b(rst_b),                                      // 连接子模块对应端口
        .ff_rx_data(ff_rx_data),                            // 连接子模块对应端口
        .ff_rx_data_vld(ff_rx_data_vld),                    // 连接子模块对应端口
        .ff_rx_sop(ff_rx_sop),                              // 连接子模块对应端口
        .ff_rx_eop(ff_rx_eop),                              // 连接子模块对应端口
        .ff_rx_err(ff_rx_err),                              // 连接子模块对应端口
        .ff_rx_rdy(ff_rx_rdy),                              // 连接子模块对应端口
        .frame_net(frame_net),                              // 连接子模块对应端口
        .cfg_addr(cfg_addr),                                // 连接子模块对应端口
        .cfg_rd_en(cfg_rd_en),                              // 连接子模块对应端口
        .cfg_tag(cfg_tag),                                  // 连接子模块对应端口
        .cfg_valid(cfg_valid),                              // 连接子模块对应端口
        .cfg_port_type(cfg_port_type),                      // 连接子模块对应端口
        .cfg_udp_port(cfg_udp_port),                        // 连接子模块对应端口
        .cfg_bag(cfg_bag),                                  // 连接子模块对应端口
        .cfg_lmax(cfg_lmax),                                // 连接子模块对应端口
        .cfg_rm_en(cfg_rm_en),                              // 连接子模块对应端口
        .cfg_ic_mode(cfg_ic_mode),                          // 连接子模块对应端口
        .st_addr(st_addr),                                  // 连接子模块对应端口
        .st_rd_en(st_rd_en),                                // 连接子模块对应端口
        .st_rd_data(st_rd_data),                            // 连接子模块对应端口
        .st_wr_en(st_wr_en),                                // 连接子模块对应端口
        .st_wr_data(st_wr_data),                            // 连接子模块对应端口
        .port_wr_en(port_wr_en),                            // 连接子模块对应端口
        .port_wr_vl_index(port_wr_vl_index),                // 连接子模块对应端口
        .port_wr_byte_offset(port_wr_byte_offset),          // 连接子模块对应端口
        .port_wr_data(port_wr_data),                        // 连接子模块对应端口
        .port_type(port_type),                              // 连接子模块对应端口
        .rx_ready_app(rx_ready_app),                        // 连接子模块对应端口
        .rx_ready_snmp(rx_ready_snmp),                      // 连接子模块对应端口
        .rx_ready_615a(rx_ready_615a),                      // 连接子模块对应端口
        .rx_ready_rtc(rx_ready_rtc),                        // 连接子模块对应端口
        .port_wr_frame_done(port_wr_frame_done),            // 连接子模块对应端口
        .port_wr_frame_len(port_wr_frame_len),              // 连接子模块对应端口
        .port_wr_queue_mode(port_wr_queue_mode),            // 连接子模块对应端口
        .port_wr_full(port_wr_full),                        // 连接子模块对应端口
        .mib_addr(mib_addr),                                // 连接子模块对应端口
        .mib_rx_frame_inc(mib_rx_frame_inc),                // 连接子模块对应端口
        .mib_rx_error_inc(mib_rx_error_inc),                // 连接子模块对应端口
        .mib_sn_error_inc(mib_sn_error_inc),                // 连接子模块对应端口
        .mib_rm_drop_inc(mib_rm_drop_inc),                  // 连接子模块对应端口
        .mib_rx_byte_inc(mib_rx_byte_inc),                  // 连接子模块对应端口
        .irq_rx_frame(irq_rx_frame),                        // 连接子模块对应端口
        .irq_error(irq_error)                               // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    // ============================================================
            // ??
    // ============================================================
    initial begin                                           // 仿真初始化或激励流程
        clk = 1'b0;                                         // 设置或组合计算clk
        forever #5 clk = ~clk;   // 100 MHz
    end                                                     // 当前语句组结束

    // ============================================================
    // ??? RAM?????1 ????
    // ============================================================
    reg [15:0] cfg_mem_tag   [0:4095];                      // 声明cfg_mem_tag所需的信号或常量
    reg        cfg_mem_valid [0:4095];                      // 声明cfg_mem_valid所需的信号或常量
    reg [1:0]  cfg_mem_ptype [0:4095];                      // 声明cfg_mem_ptype所需的信号或常量
    reg [15:0] cfg_mem_port  [0:4095];                      // 声明cfg_mem_port所需的信号或常量
    reg [15:0] cfg_mem_bag   [0:4095];                      // 声明cfg_mem_bag所需的信号或常量
    reg [15:0] cfg_mem_lmax  [0:4095];                      // 声明cfg_mem_lmax所需的信号或常量
    reg        cfg_mem_rm    [0:4095];                      // 声明cfg_mem_rm所需的信号或常量
    reg        cfg_mem_ic    [0:4095];                      // 声明cfg_mem_ic所需的信号或常量

    reg [15:0] cfg_tag_r;                                   // 声明cfg_tag_r所需的信号或常量
    reg        cfg_valid_r;                                 // 声明cfg_valid_r所需的信号或常量
    reg [1:0]  cfg_port_type_r;                             // 声明cfg_port_type_r所需的信号或常量
    reg [15:0] cfg_udp_port_r;                              // 声明cfg_udp_port_r所需的信号或常量
    reg [15:0] cfg_bag_r;                                   // 声明cfg_bag_r所需的信号或常量
    reg [15:0] cfg_lmax_r;                                  // 声明cfg_lmax_r所需的信号或常量
    reg        cfg_rm_en_r;                                 // 声明cfg_rm_en_r所需的信号或常量
    reg        cfg_ic_mode_r;                               // 声明cfg_ic_mode_r所需的信号或常量

    assign cfg_tag       = cfg_tag_r;                       // 设置或组合计算cfg_tag
    assign cfg_valid     = cfg_valid_r;                     // 设置或组合计算cfg_valid
    assign cfg_port_type = cfg_port_type_r;                 // 设置或组合计算cfg_port_type
    assign cfg_udp_port  = cfg_udp_port_r;                  // 设置或组合计算cfg_udp_port
    assign cfg_bag       = cfg_bag_r;                       // 设置或组合计算cfg_bag
    assign cfg_lmax      = cfg_lmax_r;                      // 设置或组合计算cfg_lmax
    assign cfg_rm_en     = cfg_rm_en_r;                     // 设置或组合计算cfg_rm_en
    assign cfg_ic_mode   = cfg_ic_mode_r;                   // 设置或组合计算cfg_ic_mode

    always @(posedge clk) begin                             // 按时钟沿更新寄存器，并响应声明的异步复位
        cfg_tag_r       <= cfg_mem_tag  [cfg_addr];         // 时钟沿更新cfg_tag_r
        cfg_valid_r     <= cfg_mem_valid[cfg_addr];         // 时钟沿更新cfg_valid_r
        cfg_port_type_r <= cfg_mem_ptype[cfg_addr];         // 时钟沿更新cfg_port_type_r
        cfg_udp_port_r  <= cfg_mem_port [cfg_addr];         // 时钟沿更新cfg_udp_port_r
        cfg_bag_r       <= cfg_mem_bag  [cfg_addr];         // 时钟沿更新cfg_bag_r
        cfg_lmax_r      <= cfg_mem_lmax [cfg_addr];         // 时钟沿更新cfg_lmax_r
        cfg_rm_en_r     <= cfg_mem_rm   [cfg_addr];         // 时钟沿更新cfg_rm_en_r
        cfg_ic_mode_r   <= cfg_mem_ic   [cfg_addr];         // 时钟沿更新cfg_ic_mode_r
    end                                                     // 当前语句组结束

    // ============================================================
    // ??? RAM?????1 ?????????
    // ============================================================
    reg [63:0] st_mem [0:4095];                             // 声明st_mem所需的信号或常量
    reg [63:0] st_rd_data_r;                                // 声明st_rd_data_r所需的信号或常量

    assign st_rd_data = st_rd_data_r;                       // 设置或组合计算st_rd_data

    always @(posedge clk) begin                             // 按时钟沿更新寄存器，并响应声明的异步复位
        if (st_wr_en)                                       // 检查st_wr_en的条件
            st_mem[st_addr] <= st_wr_data;                  // 时钟沿更新st_mem
        st_rd_data_r <= st_mem[st_addr];                    // 时钟沿更新st_rd_data_r
    end                                                     // 当前语句组结束

    // ============================================================
    // ??????????
    // ============================================================
    integer k;                                              // 声明integer、k所需的信号或常量
    initial begin                                           // 仿真初始化或激励流程
        for (k = 0; k < 4096; k = k + 1) begin              // 依次处理指定范围内的表项或位段
            cfg_mem_tag[k]   = 16'd0;                       // 设置或组合计算cfg_mem_tag
            cfg_mem_valid[k] = 1'b0;                        // 设置或组合计算cfg_mem_valid
            cfg_mem_ptype[k] = 2'd0;                        // 设置或组合计算cfg_mem_ptype
            cfg_mem_port[k]  = 16'd0;                       // 设置或组合计算cfg_mem_port
            cfg_mem_bag[k]   = 16'd0;                       // 设置或组合计算cfg_mem_bag
            cfg_mem_lmax[k]  = 16'd0;                       // 设置或组合计算cfg_mem_lmax
            cfg_mem_rm[k]    = 1'b0;                        // 设置或组合计算cfg_mem_rm
            cfg_mem_ic[k]    = 1'b0;                        // 设置或组合计算cfg_mem_ic
            st_mem[k]        = 64'd0;                       // 设置或组合计算st_mem
        end                                                 // 当前语句组结束

        // ? VLID_VAL ???????????
        cfg_mem_tag  [VLID_VAL[11:0]] = VLID_VAL;           // 继续计算st_mem
        cfg_mem_valid[VLID_VAL[11:0]] = 1'b1;               // 继续计算st_mem
        cfg_mem_ptype[VLID_VAL[11:0]] = 2'd0;          // ????
        cfg_mem_port [VLID_VAL[11:0]] = UDP_PORT_VAL;       // 继续计算st_mem
        cfg_mem_bag  [VLID_VAL[11:0]] = 16'd1;              // 继续计算st_mem
        cfg_mem_lmax [VLID_VAL[11:0]] = 16'd256;            // 继续计算st_mem
        cfg_mem_rm   [VLID_VAL[11:0]] = 1'b0;               // 继续计算st_mem
        cfg_mem_ic   [VLID_VAL[11:0]] = 1'b0;               // 继续计算st_mem
    end                                                     // 当前语句组结束

    // ============================================================
    // ??????
    // ------------------------------------------------------------
            // ????
    // [0..5]   ?? MAC  : 01 00 00 00 | VLID[15:8] VLID[7:0]
    // [6..11]  ? MAC    : 02 00 00 00 00 01
    // [12..13] ??      : 08 00
    // [14..33] IP ?     : 20 ????? 0x11(UDP)
    // [34..41] UDP ?    : 8 ??
    // [42..]   ????  : APP_DATA_LEN ??
    // [??]   SN        : 1 ??
    // ============================================================
    reg [7:0] frame_bytes [0:255];                          // 声明frame_bytes所需的信号或常量
    integer   frame_len;                                    // 声明integer、frame_len所需的信号或常量

    task build_frame;                                       // 声明可重复调用的仿真任务
        input [15:0] vlid;                                  // 声明input、vlid所需的信号或常量
        input [15:0] udp_dst;                               // 声明input、udp_dst所需的信号或常量
        input [15:0] app_len;                               // 声明input、app_len所需的信号或常量
        input [7:0]  sn;                                    // 声明input、sn所需的信号或常量
        integer i;                                          // 声明integer、i所需的信号或常量
        reg [15:0] ip_total_len;                            // 声明ip_total_len所需的信号或常量
        reg [15:0] udp_len;                                 // 声明udp_len所需的信号或常量
        reg [7:0]  ip_hdr [0:19];                           // 声明ip_hdr所需的信号或常量
        reg [31:0] cksum_sum;                               // 声明cksum_sum所需的信号或常量
        reg [15:0] cksum;                                   // 声明cksum所需的信号或常量
        begin                                               // 开始执行当前条件或循环的语句组
            // ?? MAC
            frame_bytes[0] = 8'h01;                         // 设置或组合计算frame_bytes
            frame_bytes[1] = 8'h00;                         // 设置或组合计算frame_bytes
            frame_bytes[2] = 8'h00;                         // 设置或组合计算frame_bytes
            frame_bytes[3] = 8'h00;                         // 设置或组合计算frame_bytes
            frame_bytes[4] = vlid[15:8];                    // 设置或组合计算frame_bytes
            frame_bytes[5] = vlid[7:0];                     // 设置或组合计算frame_bytes

            // ? MAC
            frame_bytes[6]  = 8'h02;                        // 设置或组合计算frame_bytes
            frame_bytes[7]  = 8'h00;                        // 设置或组合计算frame_bytes
            frame_bytes[8]  = 8'h00;                        // 设置或组合计算frame_bytes
            frame_bytes[9]  = 8'h00;                        // 设置或组合计算frame_bytes
            frame_bytes[10] = 8'h00;                        // 设置或组合计算frame_bytes
            frame_bytes[11] = 8'h01;                        // 设置或组合计算frame_bytes

    // ?????
            frame_bytes[12] = 8'h08;                        // 设置或组合计算frame_bytes
            frame_bytes[13] = 8'h00;                        // 设置或组合计算frame_bytes

            // ??
            ip_total_len = 16'd29 + app_len;                // 设置或组合计算ip_total_len
            udp_len      = ip_total_len - 16'd20;           // 设置或组合计算udp_len

            // IP ?
            ip_hdr[0]  = 8'h45;                             // 设置或组合计算ip_hdr
            ip_hdr[1]  = 8'h00;                             // 设置或组合计算ip_hdr
            ip_hdr[2]  = ip_total_len[15:8];                // 设置或组合计算ip_hdr
            ip_hdr[3]  = ip_total_len[7:0];                 // 设置或组合计算ip_hdr
            ip_hdr[4]  = 8'h00;                             // 设置或组合计算ip_hdr
            ip_hdr[5]  = 8'h00;                             // 设置或组合计算ip_hdr
            ip_hdr[6]  = 8'h00;                             // 设置或组合计算ip_hdr
            ip_hdr[7]  = 8'h00;                             // 设置或组合计算ip_hdr
            ip_hdr[8]  = 8'h40;                             // 设置或组合计算ip_hdr
            ip_hdr[9]  = 8'h11;   // UDP
            ip_hdr[10] = 8'h00;   // ?????
            ip_hdr[11] = 8'h00;                             // 设置或组合计算ip_hdr
            ip_hdr[12] = 8'hC0;                             // 设置或组合计算ip_hdr
            ip_hdr[13] = 8'hA8;                             // 设置或组合计算ip_hdr
            ip_hdr[14] = 8'h00;                             // 设置或组合计算ip_hdr
            ip_hdr[15] = 8'h01;                             // 设置或组合计算ip_hdr
            ip_hdr[16] = 8'hC0;                             // 设置或组合计算ip_hdr
            ip_hdr[17] = 8'hA8;                             // 设置或组合计算ip_hdr
            ip_hdr[18] = 8'h00;                             // 设置或组合计算ip_hdr
            ip_hdr[19] = 8'h02;                             // 设置或组合计算ip_hdr

            // ???? IP ?????
            cksum_sum = 32'd0;                              // 设置或组合计算cksum_sum
            for (i = 0; i < 20; i = i + 2)                  // 依次处理指定范围内的表项或位段
                cksum_sum = cksum_sum + {ip_hdr[i], ip_hdr[i+1]};  // 设置或组合计算cksum_sum并推进至下一项
            while (cksum_sum[31:16] != 0)                   // 等待当前握手或完成条件满足
                cksum_sum = (cksum_sum & 32'hFFFF) + (cksum_sum >> 16);  // 设置或组合计算cksum_sum
            cksum = ~cksum_sum[15:0];                       // 设置或组合计算cksum
            ip_hdr[10] = cksum[15:8];                       // 设置或组合计算ip_hdr
            ip_hdr[11] = cksum[7:0];                        // 设置或组合计算ip_hdr

            for (i = 0; i < 20; i = i + 1)                  // 依次处理指定范围内的表项或位段
                frame_bytes[14 + i] = ip_hdr[i];            // 设置或组合计算frame_bytes

            // UDP ?
            frame_bytes[34] = 8'h12;                        // 设置或组合计算frame_bytes
            frame_bytes[35] = 8'h34;                        // 设置或组合计算frame_bytes
            frame_bytes[36] = udp_dst[15:8];                // 设置或组合计算frame_bytes
            frame_bytes[37] = udp_dst[7:0];                 // 设置或组合计算frame_bytes
            frame_bytes[38] = udp_len[15:8];                // 设置或组合计算frame_bytes
            frame_bytes[39] = udp_len[7:0];                 // 设置或组合计算frame_bytes
            frame_bytes[40] = 8'h00;                        // 设置或组合计算frame_bytes
            frame_bytes[41] = 8'h00;                        // 设置或组合计算frame_bytes

            // ????
            for (i = 0; i < app_len; i = i + 1)             // 依次处理指定范围内的表项或位段
                frame_bytes[42 + i] = i[7:0];               // 设置或组合计算frame_bytes

            // SN
            frame_bytes[42 + app_len] = sn;                 // 设置或组合计算frame_bytes

            frame_len = 42 + app_len + 1;                   // 设置或组合计算frame_len并推进至下一项
        end                                                 // 当前语句组结束
    endtask                                                 // 仿真任务定义结束

    // ============================================================
    // ?????
    // ============================================================
    task send_frame;                                        // 声明可重复调用的仿真任务
        integer i;                                          // 声明integer、i所需的信号或常量
        begin                                               // 开始执行当前条件或循环的语句组
            wait (ff_rx_rdy === 1'b1);                      // 继续计算frame_len
            @(posedge clk);                                 // 等待指定时钟边沿后继续仿真

            for (i = 0; i < frame_len; i = i + 1) begin     // 依次处理指定范围内的表项或位段
                ff_rx_data     <= frame_bytes[i];           // 时钟沿更新ff_rx_data
                ff_rx_data_vld <= 1'b1;                     // 时钟沿更新ff_rx_data_vld
                ff_rx_sop      <= (i == 0);                 // 时钟沿更新ff_rx_sop
                ff_rx_eop      <= (i == frame_len - 1);     // 时钟沿更新ff_rx_eop
                ff_rx_err      <= 1'b0;                     // 时钟沿更新ff_rx_err
                @(posedge clk);                             // 等待指定时钟边沿后继续仿真
            end                                             // 当前语句组结束

            ff_rx_data_vld <= 1'b0;                         // 时钟沿更新ff_rx_data_vld
            ff_rx_sop      <= 1'b0;                         // 时钟沿更新ff_rx_sop
            ff_rx_eop      <= 1'b0;                         // 时钟沿更新ff_rx_eop
            @(posedge clk);                                 // 等待指定时钟边沿后继续仿真
        end                                                 // 当前语句组结束
    endtask                                                 // 仿真任务定义结束

    // ============================================================
    // ???
    // ============================================================
    initial begin                                           // 仿真初始化或激励流程
        rst_b          = 0;                                 // 设置或组合计算rst_b
        ff_rx_data     = 0;                                 // 设置或组合计算ff_rx_data
        ff_rx_data_vld = 0;                                 // 设置或组合计算ff_rx_data_vld
        ff_rx_sop      = 0;                                 // 设置或组合计算ff_rx_sop
        ff_rx_eop      = 0;                                 // 设置或组合计算ff_rx_eop
        ff_rx_err      = 0;                                 // 设置或组合计算ff_rx_err
        frame_net      = 0;                                 // 设置或组合计算frame_net
        port_wr_full   = 0;                                 // 设置或组合计算port_wr_full

        // 在 GUI 波形窗口查看时不需要 VCD；打开下面两行会转储大量内存数组，导致仿真非常慢。
        // $dumpfile("tb_afdx_rx.vcd");
        // $dumpvars(0, tb_afdx_rx);

        #100;                                               // 等待组合逻辑稳定或执行超时检查
        rst_b = 1;                                          // 设置或组合计算rst_b
        #100;                                               // 等待组合逻辑稳定或执行超时检查

        // ?????VLID=1?UDP ????=3000????? 32 ???SN=1
        build_frame(VLID_VAL, UDP_PORT_VAL, APP_DATA_LEN, 8'd1);  // 例化子模块并连接数据通路
        send_frame();                                       // 例化子模块并连接数据通路

        #2000;                                              // 等待组合逻辑稳定或执行超时检查
        $finish;                                            // 结束当前自检仿真
    end                                                     // 当前语句组结束

endmodule                                                   // 模块定义结束

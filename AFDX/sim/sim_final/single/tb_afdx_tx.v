// tb_afdx_tx : AFDX 发送方向波形测试
// 在 TB 内用简单 RAM/长度寄存器模型代替 tx_port_buf，向 afdx_tx 提供一条
// 槽位 4 的 32 字节待发帧，触发一次应用发送，观察组帧与 MAC 输出波形。
// 本文件只用于仿真，不参与 FPGA 综合。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_afdx_tx;                                          // 声明模块及其参数接口

    // ---------------- 参数 ----------------
    localparam VLID_VAL     = 16'h0004;                         // 测试 VL，低 4 位映射到槽位 4
    localparam UDP_PORT_VAL = 16'h4001;                         // UDP 目的端口
    localparam APP_DATA_LEN = 32;                               // 应用数据字节数

    // ---------------- 时钟 / 复位 ----------------
    reg clk;                                                // 声明clk所需的信号或常量
    reg rst_b;                                              // 声明rst_b所需的信号或常量

    // ---------------- 系统时间戳（BAG 整形） ----------------
    reg [31:0] sys_ts;                                      // 声明sys_ts所需的信号或常量

    // ---------------- MAC 发送侧 ----------------
    wire [7:0] ff_tx_data;                                  // 声明ff_tx_data所需的信号或常量
    wire       ff_tx_wren;                                  // 声明ff_tx_wren所需的信号或常量
    wire       ff_tx_sop;                                   // 声明ff_tx_sop所需的信号或常量
    wire       ff_tx_eop;                                   // 声明ff_tx_eop所需的信号或常量
    wire       ff_tx_err;                                   // 声明ff_tx_err所需的信号或常量
    reg        ff_tx_rdy;                                   // 声明ff_tx_rdy所需的信号或常量

    // ---------------- 槽位到 VLID 映射 ----------------
    wire [255:0] slot_vlid;                                 // 声明slot_vlid所需的信号或常量

    // ---------------- 配置表读 ----------------
    wire [11:0] cfg_addr;                                   // 声明cfg_addr所需的信号或常量
    wire        cfg_rd_en;                                  // 声明cfg_rd_en所需的信号或常量
    reg  [15:0] cfg_tag;                                    // 声明cfg_tag所需的信号或常量
    reg         cfg_valid;                                  // 声明cfg_valid所需的信号或常量
    reg  [1:0]  cfg_port_type;                              // 声明cfg_port_type所需的信号或常量
    reg  [15:0] cfg_udp_port;                               // 声明cfg_udp_port所需的信号或常量
    reg  [15:0] cfg_bag;                                    // 声明cfg_bag所需的信号或常量
    reg  [15:0] cfg_lmax;                                   // 声明cfg_lmax所需的信号或常量
    reg         cfg_rm_en;                                  // 声明cfg_rm_en所需的信号或常量

    // ---------------- 状态表读写 ----------------
    wire [11:0] st_addr;                                    // 声明st_addr所需的信号或常量
    wire        st_rd_en;                                   // 声明st_rd_en所需的信号或常量
    wire [63:0] st_rd_data;                                 // 声明st_rd_data所需的信号或常量
    wire        st_wr_en;                                   // 声明st_wr_en所需的信号或常量
    wire [63:0] st_wr_data;                                 // 声明st_wr_data所需的信号或常量

    // ---------------- 发送端口缓冲读侧 ----------------
    wire       port_rd_en;                                  // 声明port_rd_en所需的信号或常量
    wire [3:0] port_rd_vl_index;                            // 声明port_rd_vl_index所需的信号或常量
    wire [10:0] port_rd_byte_offset;                        // 声明port_rd_byte_offset所需的信号或常量
    wire [7:0] port_rd_data;                                // 声明port_rd_data所需的信号或常量
    wire       port_rd_valid;                               // 声明port_rd_valid所需的信号或常量
    wire [15:0] port_payload_len;                           // 声明port_payload_len所需的信号或常量

    // ---------------- 发送请求 ----------------
    reg tx_valid_app;                                       // 声明tx_valid_app所需的信号或常量
    reg tx_valid_snmp;                                      // 声明tx_valid_snmp所需的信号或常量
    reg tx_valid_615a;                                      // 声明tx_valid_615a所需的信号或常量
    reg tx_valid_rtc;                                       // 声明tx_valid_rtc所需的信号或常量

    // ---------------- MIB / 中断 ----------------
    wire [11:0] mib_addr;                                   // 声明mib_addr所需的信号或常量
    wire mib_tx_frame_inc;                                  // 声明mib_tx_frame_inc所需的信号或常量
    wire mib_tx_byte_inc;                                   // 声明mib_tx_byte_inc所需的信号或常量
    wire mib_tx_error_inc;                                  // 声明mib_tx_error_inc所需的信号或常量
    wire mib_tx_frag_inc;                                   // 声明mib_tx_frag_inc所需的信号或常量
    wire mib_tx_bag_inc;                                    // 声明mib_tx_bag_inc所需的信号或常量
    wire irq_tx_done;                                       // 声明irq_tx_done所需的信号或常量

    // ============================================================
    // DUT
    // ============================================================
    afdx_tx #(                                              // 例化子模块并连接数据通路
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
        .sys_ts(sys_ts),                                    // 连接子模块对应端口
        .ff_tx_data(ff_tx_data),                            // 连接子模块对应端口
        .ff_tx_wren(ff_tx_wren),                            // 连接子模块对应端口
        .ff_tx_sop(ff_tx_sop),                              // 连接子模块对应端口
        .ff_tx_eop(ff_tx_eop),                              // 连接子模块对应端口
        .ff_tx_err(ff_tx_err),                              // 连接子模块对应端口
        .ff_tx_rdy(ff_tx_rdy),                              // 连接子模块对应端口
        .slot_vlid(slot_vlid),                              // 连接子模块对应端口
        .cfg_addr(cfg_addr),                                // 连接子模块对应端口
        .cfg_rd_en(cfg_rd_en),                              // 连接子模块对应端口
        .cfg_tag(cfg_tag),                                  // 连接子模块对应端口
        .cfg_valid(cfg_valid),                              // 连接子模块对应端口
        .cfg_port_type(cfg_port_type),                      // 连接子模块对应端口
        .cfg_udp_port(cfg_udp_port),                        // 连接子模块对应端口
        .cfg_bag(cfg_bag),                                  // 连接子模块对应端口
        .cfg_lmax(cfg_lmax),                                // 连接子模块对应端口
        .cfg_rm_en(cfg_rm_en),                              // 连接子模块对应端口
        .st_addr(st_addr),                                  // 连接子模块对应端口
        .st_rd_en(st_rd_en),                                // 连接子模块对应端口
        .st_rd_data(st_rd_data),                            // 连接子模块对应端口
        .st_wr_en(st_wr_en),                                // 连接子模块对应端口
        .st_wr_data(st_wr_data),                            // 连接子模块对应端口
        .port_rd_en(port_rd_en),                            // 连接子模块对应端口
        .port_rd_vl_index(port_rd_vl_index),                // 连接子模块对应端口
        .port_rd_byte_offset(port_rd_byte_offset),          // 连接子模块对应端口
        .port_rd_data(port_rd_data),                        // 连接子模块对应端口
        .port_rd_valid(port_rd_valid),                      // 连接子模块对应端口
        .port_payload_len(port_payload_len),                // 连接子模块对应端口
        .tx_valid_app(tx_valid_app),                        // 连接子模块对应端口
        .tx_valid_snmp(tx_valid_snmp),                      // 连接子模块对应端口
        .tx_valid_615a(tx_valid_615a),                      // 连接子模块对应端口
        .tx_valid_rtc(tx_valid_rtc),                        // 连接子模块对应端口
        .mib_addr(mib_addr),                                // 连接子模块对应端口
        .mib_tx_frame_inc(mib_tx_frame_inc),                // 连接子模块对应端口
        .mib_tx_byte_inc(mib_tx_byte_inc),                  // 连接子模块对应端口
        .mib_tx_error_inc(mib_tx_error_inc),                // 连接子模块对应端口
        .mib_tx_frag_inc(mib_tx_frag_inc),                  // 连接子模块对应端口
        .mib_tx_bag_inc(mib_tx_bag_inc),                    // 连接子模块对应端口
        .irq_tx_done(irq_tx_done)                           // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    // ============================================================
    // 时钟：5ns 翻转一次，结合 timescale 得到 10ns / 100MHz
    // ============================================================
    initial begin                                           // 仿真初始化或激励流程
        clk = 1'b0;                                         // 设置或组合计算clk
        forever #5 clk = ~clk;                              // 继续计算clk
    end                                                     // 当前语句组结束

    // ============================================================
    // 槽位到 VLID 映射：仅槽位 4 配置为 VLID_VAL
    // ============================================================
    assign slot_vlid = {176'd0, VLID_VAL, 64'd0};               // [79:64] = 槽位 4

    // ============================================================
    // 配置表简单模型（读延迟 1 拍）
    // ============================================================
    reg [15:0] cfg_mem_tag   [0:4095];                      // 声明cfg_mem_tag所需的信号或常量
    reg        cfg_mem_valid [0:4095];                      // 声明cfg_mem_valid所需的信号或常量
    reg [1:0]  cfg_mem_ptype [0:4095];                      // 声明cfg_mem_ptype所需的信号或常量
    reg [15:0] cfg_mem_port  [0:4095];                      // 声明cfg_mem_port所需的信号或常量
    reg [15:0] cfg_mem_bag   [0:4095];                      // 声明cfg_mem_bag所需的信号或常量
    reg [15:0] cfg_mem_lmax  [0:4095];                      // 声明cfg_mem_lmax所需的信号或常量
    reg        cfg_mem_rm    [0:4095];                      // 声明cfg_mem_rm所需的信号或常量

    integer cfg_i;                                          // 声明integer、cfg_i所需的信号或常量
    initial begin                                           // 仿真初始化或激励流程
        for (cfg_i = 0; cfg_i < 4096; cfg_i = cfg_i + 1) begin  // 依次处理指定范围内的表项或位段
            cfg_mem_tag[cfg_i]   = 16'd0;                   // 设置或组合计算cfg_mem_tag
            cfg_mem_valid[cfg_i] = 1'b0;                    // 设置或组合计算cfg_mem_valid
            cfg_mem_ptype[cfg_i] = 2'd0;                    // 设置或组合计算cfg_mem_ptype
            cfg_mem_port[cfg_i]  = 16'd0;                   // 设置或组合计算cfg_mem_port
            cfg_mem_bag[cfg_i]   = 16'd0;                   // 设置或组合计算cfg_mem_bag
            cfg_mem_lmax[cfg_i]  = 16'd0;                   // 设置或组合计算cfg_mem_lmax
            cfg_mem_rm[cfg_i]    = 1'b0;                    // 设置或组合计算cfg_mem_rm
        end                                                 // 当前语句组结束

        cfg_mem_tag[VLID_VAL[11:0]]   = VLID_VAL;           // 继续计算cfg_mem_rm
        cfg_mem_valid[VLID_VAL[11:0]] = 1'b1;               // 继续计算cfg_mem_rm
        cfg_mem_ptype[VLID_VAL[11:0]] = 2'd0;               // 继续计算cfg_mem_rm
        cfg_mem_port[VLID_VAL[11:0]]  = UDP_PORT_VAL;       // 继续计算cfg_mem_rm
        cfg_mem_bag[VLID_VAL[11:0]]   = 16'd1;              // 继续计算cfg_mem_rm
        cfg_mem_lmax[VLID_VAL[11:0]]  = 16'd512;            // 继续计算cfg_mem_rm
        cfg_mem_rm[VLID_VAL[11:0]]    = 1'b0;               // 继续计算cfg_mem_rm
    end                                                     // 当前语句组结束

    always @(posedge clk) begin                             // 按时钟沿更新寄存器，并响应声明的异步复位
        cfg_tag       <= cfg_mem_tag[cfg_addr];             // 时钟沿更新cfg_tag
        cfg_valid     <= cfg_mem_valid[cfg_addr];           // 时钟沿更新cfg_valid
        cfg_port_type <= cfg_mem_ptype[cfg_addr];           // 时钟沿更新cfg_port_type
        cfg_udp_port  <= cfg_mem_port[cfg_addr];            // 时钟沿更新cfg_udp_port
        cfg_bag       <= cfg_mem_bag[cfg_addr];             // 时钟沿更新cfg_bag
        cfg_lmax      <= cfg_mem_lmax[cfg_addr];            // 时钟沿更新cfg_lmax
        cfg_rm_en     <= cfg_mem_rm[cfg_addr];              // 时钟沿更新cfg_rm_en
    end                                                     // 当前语句组结束

    // ============================================================
    // 状态表简单模型（读延迟 1 拍，写使能时写回）
    // ============================================================
    reg [63:0] st_mem [0:4095];                             // 声明st_mem所需的信号或常量
    reg [63:0] st_rd_data_r;                                // 声明st_rd_data_r所需的信号或常量

    integer st_i;                                           // 声明integer、st_i所需的信号或常量
    initial begin                                           // 仿真初始化或激励流程
        for (st_i = 0; st_i < 4096; st_i = st_i + 1)        // 依次处理指定范围内的表项或位段
            st_mem[st_i] = 64'd0;                           // 设置或组合计算st_mem
    end                                                     // 当前语句组结束

    reg [63:0] st_rd_data_s1;                               // 第一级读数据
    always @(posedge clk) begin                             // 按时钟沿更新寄存器，并响应声明的异步复位
        if (st_wr_en)                                       // 检查st_wr_en的条件
            st_mem[st_addr] <= st_wr_data;                  // 时钟沿更新st_mem
        if (st_rd_en)                                       // 读使能有效时采地址（与 IP 的 rden 一致）
            st_rd_data_s1 <= st_mem[st_addr];               // 第一级读数据
        st_rd_data_r <= st_rd_data_s1;                      // 第二级：两拍后输出
    end                                                     // 当前语句组结束
    assign st_rd_data = st_rd_data_r;                       // 设置或组合计算st_rd_data

    // ============================================================
    // 发送端口缓冲简单模型：槽位长度 + 载荷 RAM（读延迟 1 拍）
    // ============================================================
    reg [15:0] tx_len_mem [0:15];                           // 声明tx_len_mem所需的信号或常量
    reg [7:0]  payload_mem [0:2047];                        // 声明payload_mem所需的信号或常量

    integer buf_i;                                          // 声明integer、buf_i所需的信号或常量
    initial begin                                           // 仿真初始化或激励流程
        for (buf_i = 0; buf_i < 16; buf_i = buf_i + 1)      // 依次处理指定范围内的表项或位段
            tx_len_mem[buf_i] = 16'd0;                      // 设置或组合计算tx_len_mem
        tx_len_mem[4] = APP_DATA_LEN;                       // 设置或组合计算tx_len_mem

        for (buf_i = 0; buf_i < 2048; buf_i = buf_i + 1)    // 依次处理指定范围内的表项或位段
            payload_mem[buf_i] = 8'd0;                      // 设置或组合计算payload_mem
        for (buf_i = 0; buf_i < APP_DATA_LEN; buf_i = buf_i + 1)  // 依次处理指定范围内的表项或位段
            payload_mem[buf_i] = buf_i[7:0];                // 设置或组合计算payload_mem
    end                                                     // 当前语句组结束

    assign port_payload_len = tx_len_mem[port_rd_vl_index];  // 设置或组合计算port_payload_len

    // 端口缓冲 RAM 读延迟两拍：地址/rden 打一拍，输出再打一拍
    reg [7:0]  port_rd_data_r;                              // 第一级读数据
    reg        port_rd_valid_r;                             // 第一级读有效
    reg [7:0]  port_rd_data_d;                              // 第二级读数据（对外输出）
    reg        port_rd_valid_d;                             // 第二级读有效（对外输出）
    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            port_rd_data_r  <= 8'd0;                        // 时钟沿更新port_rd_data_r
            port_rd_valid_r <= 1'b0;                        // 时钟沿更新port_rd_valid_r
            port_rd_data_d  <= 8'd0;                        // 时钟沿更新port_rd_data_d
            port_rd_valid_d <= 1'b0;                        // 时钟沿更新port_rd_valid_d
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            if (port_rd_en)                                 // 检查port_rd_en的条件
                port_rd_data_r <= payload_mem[port_rd_byte_offset];  // 第一级取数
            port_rd_valid_r <= port_rd_en;                  // 第一级有效
            port_rd_data_d  <= port_rd_data_r;              // 第二级取数，与真实 RAM 的两拍延迟一致
            port_rd_valid_d <= port_rd_valid_r;             // 第二级有效
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束
    assign port_rd_data  = port_rd_data_d;                  // 设置或组合计算port_rd_data
    assign port_rd_valid = port_rd_valid_d;                 // 设置或组合计算port_rd_valid

    // ============================================================
    // 激励主体
    // ============================================================
    reg [7:0] tx_cap [0:255];                               // 声明tx_cap所需的信号或常量
    integer   tx_cnt;                                       // 声明integer、tx_cnt所需的信号或常量

    always @(posedge clk) begin                             // 按时钟沿更新寄存器，并响应声明的异步复位
        if (ff_tx_wren) begin                               // 检查ff_tx_wren的条件
            tx_cap[tx_cnt] = ff_tx_data;                    // 设置或组合计算tx_cap
            tx_cnt = tx_cnt + 1;                            // 设置或组合计算tx_cnt并推进至下一项
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    integer j;                                              // 声明integer、j所需的信号或常量
    initial begin                                           // 仿真初始化或激励流程
        clk            = 0;                                 // 设置或组合计算clk
        rst_b          = 0;                                 // 设置或组合计算rst_b
        sys_ts         = 0;                                 // 设置或组合计算sys_ts
        ff_tx_rdy      = 1;                                 // 设置或组合计算ff_tx_rdy
        tx_valid_app   = 0;                                 // 设置或组合计算tx_valid_app
        tx_valid_snmp  = 0;                                 // 设置或组合计算tx_valid_snmp
        tx_valid_615a  = 0;                                 // 设置或组合计算tx_valid_615a
        tx_valid_rtc   = 0;                                 // 设置或组合计算tx_valid_rtc
        tx_cnt         = 0;                                 // 设置或组合计算tx_cnt

        #100;                                               // 等待组合逻辑稳定或执行超时检查
        rst_b = 1;                                          // 设置或组合计算rst_b
        #100;                                               // 等待组合逻辑稳定或执行超时检查

        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        tx_valid_app <= 1'b1;                               // 时钟沿更新tx_valid_app
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        tx_valid_app <= 1'b0;                               // 时钟沿更新tx_valid_app

        wait (irq_tx_done === 1'b1);                        // 继续计算tx_valid_app
        #100;                                               // 等待组合逻辑稳定或执行超时检查

        $display("TX captured bytes: %0d", tx_cnt);         // 输出当前仿真检查结果或报文字节
        for (j = 0; j < tx_cnt; j = j + 1)                  // 依次处理指定范围内的表项或位段
            $write("%02x ", tx_cap[j]);                     // 输出当前仿真检查结果或报文字节
        $display("");                                       // 输出当前仿真检查结果或报文字节
        $finish;                                            // 结束当前自检仿真
    end                                                     // 当前语句组结束

endmodule                                                   // 模块定义结束

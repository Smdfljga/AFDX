// tb_afdx_top.v : 最小冒烟测试（自包含，不依赖其他文件）
// 作用：验证工程能编译、复位与时钟正常、VL 配置写入与 cfg_done 时序通顺、RTC 在走
// 注意：本用例只做配置/RTC 框架级检查；完整 RX/TX、SNMP、TFTP、RTC 用例见：
// 手册/新手解释/仿真方案与波形判读指南.md
// 运行（ModelSim，工作目录 = 本 sim 文件夹）：
// vlib work
// vlog -quiet ../rtl/ip/*.v ../rtl/*.v tb_afdx_top.v     （顺序见 ../rtl/filelist.f）
// vsim -voptargs=+acc work.tb_afdx_top
// add wave -r /tb_afdx_top/*
// run -all
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_afdx_top;                                         // 声明模块及其参数接口

    // ==================== 参数（与 AFDX_top 默认值一致） ====================
    localparam DATA_WIDTH        = 8;                       // 声明localparam、DATA_WIDTH所需的信号或常量
    localparam VLID_WIDTH        = 16;                      // 声明localparam、VLID_WIDTH所需的信号或常量
    localparam VL_ADDR_WIDTH     = 12;      // 表地址位宽（4096 条，地址 = vlid 低位）
    localparam VL_INDEX_WIDTH    = 4;                       // 声明localparam、VL_INDEX_WIDTH所需的信号或常量
    localparam BYTE_OFFSET_WIDTH = 11;                      // 声明localparam、BYTE_OFFSET_WIDTH所需的信号或常量
    localparam RTC_WIDTH         = 48;                      // 声明localparam、RTC_WIDTH所需的信号或常量
    localparam CLK_PERIOD        = 40;      // 40ns = 25MHz 核心时钟

    // ==================== DUT 端口 ====================
    reg                        clk_sys;                     // 声明clk_sys所需的信号或常量
    reg                        rst_b;                       // 声明rst_b所需的信号或常量
    reg  [DATA_WIDTH-1:0]      ff_rx_data;                  // 声明DATA_WIDTH、ff_rx_data所需的信号或常量
    reg                        ff_rx_data_vld;              // 声明ff_rx_data_vld所需的信号或常量
    reg                        ff_rx_sop;                   // 声明ff_rx_sop所需的信号或常量
    reg                        ff_rx_eop;                   // 声明ff_rx_eop所需的信号或常量
    reg                        ff_rx_err;                   // 声明ff_rx_err所需的信号或常量
    wire                       ff_rx_rdy;                   // 声明ff_rx_rdy所需的信号或常量
    wire [DATA_WIDTH-1:0]      ff_tx_data;                  // 声明DATA_WIDTH、ff_tx_data所需的信号或常量
    wire                       ff_tx_wren;                  // 声明ff_tx_wren所需的信号或常量
    wire                       ff_tx_sop;                   // 声明ff_tx_sop所需的信号或常量
    wire                       ff_tx_eop;                   // 声明ff_tx_eop所需的信号或常量
    wire                       ff_tx_err;                   // 声明ff_tx_err所需的信号或常量
    reg                        ff_tx_rdy;                   // 声明ff_tx_rdy所需的信号或常量
    reg                        cfg_wr_en;                   // 声明cfg_wr_en所需的信号或常量
    reg  [VL_ADDR_WIDTH-1:0]   cfg_wr_addr;                 // 声明表地址位宽（4096 条、cfg_wr_addr所需的信号或常量
    reg  [VLID_WIDTH-1:0]      cfg_wr_vlid;                 // 声明VLID_WIDTH、cfg_wr_vlid所需的信号或常量
    reg  [15:0]                cfg_wr_udp_port;             // 声明cfg_wr_udp_port所需的信号或常量
    reg  [1:0]                 cfg_wr_port_type;            // 声明cfg_wr_port_type所需的信号或常量
    reg  [15:0]                cfg_wr_bag;                  // 声明cfg_wr_bag所需的信号或常量
    reg  [15:0]                cfg_wr_lmax;                 // 声明cfg_wr_lmax所需的信号或常量
    reg                        cfg_wr_rm_en;                // 声明cfg_wr_rm_en所需的信号或常量
    reg                        cfg_wr_ic_mode;              // 声明cfg_wr_ic_mode所需的信号或常量
    wire                       cfg_done;                    // 声明cfg_done所需的信号或常量
    reg  [VL_INDEX_WIDTH-1:0]  app_rd_vl_index;             // 声明VL_INDEX_WIDTH、app_rd_vl_index所需的信号或常量
    reg  [BYTE_OFFSET_WIDTH-1:0] app_rd_byte_offset;        // 声明BYTE_OFFSET_WIDTH、app_rd_byte_offset所需的信号或常量
    reg                        app_rd_en;                   // 声明app_rd_en所需的信号或常量
    wire [DATA_WIDTH-1:0]      app_rd_data;                 // 声明DATA_WIDTH、app_rd_data所需的信号或常量
    wire                       app_rd_valid;                // 声明app_rd_valid所需的信号或常量
    wire [15:0]                app_rd_frame_len;            // 声明app_rd_frame_len所需的信号或常量
    wire [3:0]                 app_rd_frame_cnt;            // 声明app_rd_frame_cnt所需的信号或常量
    reg                        app_wr_en;                   // 声明app_wr_en所需的信号或常量
    reg  [VL_INDEX_WIDTH-1:0]  app_wr_vl_index;             // 声明VL_INDEX_WIDTH、app_wr_vl_index所需的信号或常量
    reg  [BYTE_OFFSET_WIDTH-1:0] app_wr_byte_offset;        // 声明BYTE_OFFSET_WIDTH、app_wr_byte_offset所需的信号或常量
    reg  [DATA_WIDTH-1:0]      app_wr_data;                 // 声明DATA_WIDTH、app_wr_data所需的信号或常量
    reg                        app_tx_req;                  // 声明app_tx_req所需的信号或常量
    wire                       app_wr_gnt;                  // 声明app_wr_gnt所需的信号或常量
    wire [RTC_WIDTH-1:0]       local_rtc;                   // 声明RTC_WIDTH、local_rtc所需的信号或常量
    wire                       rtc_sync_valid;              // 声明rtc_sync_valid所需的信号或常量
    wire                       irq_rx_frame;                // 声明irq_rx_frame所需的信号或常量
    wire                       irq_tx_done;                 // 声明irq_tx_done所需的信号或常量
    wire                       irq_error;                   // 声明irq_error所需的信号或常量

    reg [RTC_WIDTH-1:0] rtc_t0;             // 记录 RTC 初值

    // ==================== 时钟 ====================
    initial clk_sys = 0;                                    // 仿真初始化或激励流程
    always #(CLK_PERIOD/2) clk_sys = ~clk_sys;              // 继续计算当前组合结果

    // ==================== DUT ====================
    AFDX_top #(                                             // 例化子模块并连接数据通路
        .VLID_WIDTH        (VLID_WIDTH),                    // 连接子模块对应端口
        .VL_ADDR_WIDTH     (VL_ADDR_WIDTH),                 // 连接子模块对应端口
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .CNT_WIDTH         (32),                            // 连接子模块对应端口
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             // 连接子模块对应端口
        .RTC_WIDTH         (RTC_WIDTH),                     // 连接子模块对应端口
        .STATE_WIDTH       (64),                            // 连接子模块对应端口
        .REDUNDANCY_EN     (1'b0),          // 单网
        .VL_INDEX_SNMP     (4'd1),                          // 连接子模块对应端口
        .VL_INDEX_615A     (4'd2),                          // 连接子模块对应端口
        .VL_INDEX_RTC      (4'd3),                          // 连接子模块对应端口
        .RTC_MASTER_MODE   (1'b1),                          // 连接子模块对应端口
        .RTC_SYNC_PERIOD   (16'd1),                         // 连接子模块对应端口
        .RTC_PROC_DELAY    (32'd0)                          // 连接子模块对应端口
    ) dut (                                                 // 参数绑定结束，开始连接实例端口
        .clk_sys             (clk_sys),                     // 连接子模块对应端口
        .rst_b               (rst_b),                       // 连接子模块对应端口
        .ff_rx_data          (ff_rx_data),                  // 连接子模块对应端口
        .ff_rx_data_vld      (ff_rx_data_vld),              // 连接子模块对应端口
        .ff_rx_sop           (ff_rx_sop),                   // 连接子模块对应端口
        .ff_rx_eop           (ff_rx_eop),                   // 连接子模块对应端口
        .ff_rx_err           (ff_rx_err),                   // 连接子模块对应端口
        .ff_rx_rdy           (ff_rx_rdy),                   // 连接子模块对应端口
        .rx_frame_net        (1'b0),                        // 单网仿真：恒按 A 网处理
        .ff_tx_data          (ff_tx_data),                  // 连接子模块对应端口
        .ff_tx_wren          (ff_tx_wren),                  // 连接子模块对应端口
        .ff_tx_sop           (ff_tx_sop),                   // 连接子模块对应端口
        .ff_tx_eop           (ff_tx_eop),                   // 连接子模块对应端口
        .ff_tx_err           (ff_tx_err),                   // 连接子模块对应端口
        .ff_tx_rdy           (ff_tx_rdy),                   // 连接子模块对应端口
        .cfg_wr_en           (cfg_wr_en),                   // 连接子模块对应端口
        .cfg_wr_addr         (cfg_wr_addr),                 // 连接子模块对应端口
        .cfg_wr_vlid         (cfg_wr_vlid),                 // 连接子模块对应端口
        .cfg_wr_udp_port     (cfg_wr_udp_port),             // 连接子模块对应端口
        .cfg_wr_port_type    (cfg_wr_port_type),            // 连接子模块对应端口
        .cfg_wr_bag          (cfg_wr_bag),                  // 连接子模块对应端口
        .cfg_wr_lmax         (cfg_wr_lmax),                 // 连接子模块对应端口
        .cfg_wr_rm_en        (cfg_wr_rm_en),                // 连接子模块对应端口
        .cfg_wr_ic_mode      (cfg_wr_ic_mode),              // 连接子模块对应端口
        .cfg_done            (cfg_done),                    // 连接子模块对应端口
        .app_rd_vl_index     (app_rd_vl_index),             // 连接子模块对应端口
        .app_rd_byte_offset  (app_rd_byte_offset),          // 连接子模块对应端口
        .app_rd_en           (app_rd_en),                   // 连接子模块对应端口
        .app_rd_data         (app_rd_data),                 // 连接子模块对应端口
        .app_rd_valid        (app_rd_valid),                // 连接子模块对应端口
        .app_rd_frame_len    (app_rd_frame_len),            // 连接子模块对应端口
        .app_rd_frame_cnt    (app_rd_frame_cnt),            // 连接子模块对应端口
        .app_wr_en           (app_wr_en),                   // 连接子模块对应端口
        .app_wr_vl_index     (app_wr_vl_index),             // 连接子模块对应端口
        .app_wr_byte_offset  (app_wr_byte_offset),          // 连接子模块对应端口
        .app_wr_data         (app_wr_data),                 // 连接子模块对应端口
        .app_tx_req          (app_tx_req),                  // 连接子模块对应端口
        .app_wr_gnt          (app_wr_gnt),                  // 连接子模块对应端口
        .local_rtc           (local_rtc),                   // 连接子模块对应端口
        .rtc_sync_valid      (rtc_sync_valid),              // 连接子模块对应端口
        .irq_rx_frame        (irq_rx_frame),                // 连接子模块对应端口
        .irq_tx_done         (irq_tx_done),                 // 连接子模块对应端口
        .irq_error           (irq_error)                    // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    // ==================== 写一条 VL 配置（协议见 CUSTOM_FORMATS.md 第 6 节） ====================
    task cfg_write;                                         // 声明可重复调用的仿真任务
        input [VLID_WIDTH-1:0] vlid;                        // 声明input、VLID_WIDTH、vlid所需的信号或常量
        input [15:0]           udp_port;                    // 声明input、udp_port所需的信号或常量
        input [1:0]            port_type;   // 00=采样 01=队列 10=SAP
        begin                                               // 开始执行当前条件或循环的语句组
            @(posedge clk_sys);                             // 等待指定时钟边沿后继续仿真
            cfg_wr_addr      <= vlid[VL_ADDR_WIDTH-1:0];    // 地址 = VLID 低位（直接映射）
            cfg_wr_vlid      <= vlid;                       // 时钟沿更新cfg_wr_vlid
            cfg_wr_udp_port  <= udp_port;                   // 时钟沿更新cfg_wr_udp_port
            cfg_wr_port_type <= port_type;                  // 时钟沿更新cfg_wr_port_type
            cfg_wr_bag       <= 16'd4;                      // BAG = 4ms
            cfg_wr_lmax      <= 16'd512;                    // Lmax = 512 字节
            cfg_wr_rm_en     <= 1'b0;                       // 时钟沿更新cfg_wr_rm_en
            cfg_wr_ic_mode   <= 1'b0;                       // 时钟沿更新cfg_wr_ic_mode
            cfg_wr_en        <= 1'b1;                       // 时钟沿更新cfg_wr_en
            @(posedge clk_sys);                             // 等待指定时钟边沿后继续仿真
            cfg_wr_en        <= 1'b0;                       // 时钟沿更新cfg_wr_en
            repeat (2) @(posedge clk_sys);                  // 等待指定数量的时钟周期
        end                                                 // 当前语句组结束
    endtask                                                 // 仿真任务定义结束

    // ==================== 激励 ====================
    initial begin                                           // 仿真初始化或激励流程
        $display("=== tb_afdx_top : smoke test (framework only) ===");  // 输出当前仿真检查结果或报文字节
        // 初始值
        rst_b = 1'b0;                                       // 设置或组合计算rst_b
        ff_rx_data = 8'h00; ff_rx_data_vld = 1'b0; ff_rx_sop = 1'b0; ff_rx_eop = 1'b0;  // 设置或组合计算ff_rx_data
        ff_rx_err = 1'b0;   ff_tx_rdy = 1'b1;               // 设置或组合计算ff_rx_err
        cfg_wr_en = 1'b0;   cfg_wr_addr = {VL_ADDR_WIDTH{1'b0}}; cfg_wr_vlid = 16'h0;  // 设置或组合计算cfg_wr_en
        cfg_wr_udp_port = 16'd0; cfg_wr_port_type = 2'd0; cfg_wr_bag = 16'd0;  // 设置或组合计算cfg_wr_udp_port
        cfg_wr_lmax = 16'd0; cfg_wr_rm_en = 1'b0; cfg_wr_ic_mode = 1'b0;  // 设置或组合计算cfg_wr_lmax
        app_rd_vl_index = 4'd0; app_rd_byte_offset = 11'd0; app_rd_en = 1'b0;  // 设置或组合计算app_rd_vl_index
        app_wr_en = 1'b0; app_wr_vl_index = 4'd0; app_wr_byte_offset = 11'd0;  // 设置或组合计算app_wr_en
        app_wr_data = 8'h00; app_tx_req = 1'b0;             // 设置或组合计算app_wr_data

        repeat (10) @(posedge clk_sys);                     // 等待指定数量的时钟周期
        rst_b = 1'b1;                                       // 设置或组合计算rst_b
        repeat (5) @(posedge clk_sys);                      // 等待指定数量的时钟周期

        // 写 3 条 VL 配置 + 结束哨兵
        cfg_write(16'h0001, 16'd161,  2'b01);     // SNMP
        cfg_write(16'h0002, 16'd69,   2'b10);     // 615A（SAP）
        cfg_write(16'h0004, 16'd4001, 2'b00);     // 应用（采样）
        @(posedge clk_sys);                                 // 等待指定时钟边沿后继续仿真
        cfg_wr_vlid <= 16'hFFFF;                  // 哨兵：不落表，只给 cfg_done
        cfg_wr_en   <= 1'b1;                                // 时钟沿更新cfg_wr_en
        @(posedge clk_sys);                                 // 等待指定时钟边沿后继续仿真
        cfg_wr_en   <= 1'b0;                                // 时钟沿更新cfg_wr_en
        repeat (10) @(posedge clk_sys);                     // 等待指定数量的时钟周期

        // 检查点 1：配置完成
        if (cfg_done === 1'b1) $display("  [PASS] cfg_done = 1 (config write + sentinel works)");  // 检查cfg_done、display的条件
        else                   $display("  [FAIL] cfg_done = %b, expected 1", cfg_done);  // 采用前一条件未满足时的处理

        // 检查点 2：本地 RTC 在走（8us 应 +8，25MHz 下 8us = 200 拍）
        rtc_t0 = local_rtc;                                 // 设置或组合计算记录 RTC 初值
        repeat (200) @(posedge clk_sys);                    // 25MHz 下 8us = 200 拍
        if ((local_rtc - rtc_t0) === 48'd8) $display("  [PASS] local_rtc advanced 8us");  // 检查local_rtc、记录 RTC 初值的条件
        else $display("  [FAIL] local_rtc delta = %0d us, expected 8", local_rtc - rtc_t0);  // 采用前一条件未满足时的处理

        // 检查点 3：空闲时不应有发送帧
        if (ff_tx_wren === 1'b0) $display("  [PASS] no unexpected TX traffic");  // 检查ff_tx_wren、display的条件
        else                     $display("  [WARN] TX activity while idle");  // 采用前一条件未满足时的处理

        $display("--------------------------------------------------");  // 输出当前仿真检查结果或报文字节
        $display("  smoke test finished (config and RTC framework)");  // 输出当前仿真检查结果或报文字节
        $display("--------------------------------------------------");  // 输出当前仿真检查结果或报文字节
        $finish;                                            // 结束当前自检仿真
    end                                                     // 当前语句组结束

endmodule                                                   // 模块定义结束

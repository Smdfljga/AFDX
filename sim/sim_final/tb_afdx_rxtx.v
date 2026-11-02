// tb_afdx_rxtx : RX/TX 端到端功能仿真
// 用例 1：向 VLID=0x0004 注入一帧 17 字节 AFDX 报文，验证应用读回的数据不含 SN；
// 用例 2：应用向槽位 4 写 17 字节并触发发送，验证 MAC 输出帧头、SN 与最小帧填充。
// 配合 ip_sim_models.v 使用；本文件只用于仿真，不参与 FPGA 综合。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_afdx_rxtx;                                        // 声明模块及其参数接口

    localparam DATA_WIDTH        = 8;                       // 声明localparam、DATA_WIDTH所需的信号或常量
    localparam VLID_WIDTH        = 16;                      // 声明localparam、VLID_WIDTH所需的信号或常量
    localparam VL_ADDR_WIDTH     = 12;                      // 声明localparam、VL_ADDR_WIDTH所需的信号或常量
    localparam VL_INDEX_WIDTH    = 4;                       // 声明localparam、VL_INDEX_WIDTH所需的信号或常量
    localparam BYTE_OFFSET_WIDTH = 11;                      // 声明localparam、BYTE_OFFSET_WIDTH所需的信号或常量
    localparam RTC_WIDTH         = 48;                      // 声明localparam、RTC_WIDTH所需的信号或常量

    reg clk_sys;                                            // 声明clk_sys所需的信号或常量
    reg rst_b;                                              // 声明rst_b所需的信号或常量
    reg [7:0] ff_rx_data;                                   // 声明ff_rx_data所需的信号或常量
    reg ff_rx_data_vld, ff_rx_sop, ff_rx_eop, ff_rx_err;    // 声明ff_rx_data_vld、ff_rx_sop、ff_rx_eop所需的信号或常量
    wire ff_rx_rdy;                                         // 声明ff_rx_rdy所需的信号或常量
    wire [7:0] ff_tx_data;                                  // 声明ff_tx_data所需的信号或常量
    wire ff_tx_wren, ff_tx_sop, ff_tx_eop, ff_tx_err;       // 声明ff_tx_wren、ff_tx_sop、ff_tx_eop所需的信号或常量
    reg ff_tx_rdy;                                          // 声明ff_tx_rdy所需的信号或常量

    reg cfg_wr_en;                                          // 声明cfg_wr_en所需的信号或常量
    reg [11:0] cfg_wr_addr;                                 // 声明cfg_wr_addr所需的信号或常量
    reg [15:0] cfg_wr_vlid;                                 // 声明cfg_wr_vlid所需的信号或常量
    reg [15:0] cfg_wr_udp_port;                             // 声明cfg_wr_udp_port所需的信号或常量
    reg [1:0]  cfg_wr_port_type;                            // 声明cfg_wr_port_type所需的信号或常量
    reg [15:0] cfg_wr_bag, cfg_wr_lmax;                     // 声明cfg_wr_bag、cfg_wr_lmax所需的信号或常量
    reg cfg_wr_rm_en, cfg_wr_ic_mode;                       // 声明cfg_wr_rm_en、cfg_wr_ic_mode所需的信号或常量
    wire cfg_done;                                          // 声明cfg_done所需的信号或常量

    reg [3:0]  app_rd_vl_index;                             // 声明app_rd_vl_index所需的信号或常量
    reg [10:0] app_rd_byte_offset;                          // 声明app_rd_byte_offset所需的信号或常量
    reg app_rd_en;                                          // 声明app_rd_en所需的信号或常量
    wire [7:0] app_rd_data;                                 // 声明app_rd_data所需的信号或常量
    wire app_rd_valid;                                      // 声明app_rd_valid所需的信号或常量
    wire [15:0] app_rd_frame_len;                           // 声明app_rd_frame_len所需的信号或常量
    wire [3:0] app_rd_frame_cnt;                            // 声明app_rd_frame_cnt所需的信号或常量

    reg [3:0]  app_wr_vl_index;                             // 声明app_wr_vl_index所需的信号或常量
    reg [10:0] app_wr_byte_offset;                          // 声明app_wr_byte_offset所需的信号或常量
    reg [7:0]  app_wr_data;                                 // 声明app_wr_data所需的信号或常量
    reg app_wr_en, app_tx_req;                              // 声明app_wr_en、app_tx_req所需的信号或常量
    wire app_wr_gnt;                                        // 声明app_wr_gnt所需的信号或常量

    wire [47:0] local_rtc;                                  // 声明local_rtc所需的信号或常量
    wire rtc_sync_valid, irq_rx_frame, irq_tx_done, irq_error;  // 声明rtc_sync_valid、irq_rx_frame、irq_tx_done所需的信号或常量

    integer i;                                              // 声明integer、i所需的信号或常量
    integer fail_cnt;                                       // 声明integer、fail_cnt所需的信号或常量
    reg [7:0] rx_capture [0:80];                            // 声明rx_capture所需的信号或常量
    integer rx_cnt;                                         // 声明integer、rx_cnt所需的信号或常量

    always #5 clk_sys = ~clk_sys;                           // 继续计算当前组合结果

    AFDX_top #(                                             // 例化子模块并连接数据通路
        .VLID_WIDTH(16), .VL_ADDR_WIDTH(12), .DATA_WIDTH(8), .CNT_WIDTH(32),  // 连接子模块对应端口
        .VL_INDEX_WIDTH(4), .BYTE_OFFSET_WIDTH(11), .RTC_WIDTH(48), .STATE_WIDTH(64),  // 连接子模块对应端口
        .REDUNDANCY_EN(1'b0), .VL_INDEX_SNMP(4'd1), .VL_INDEX_615A(4'd2),  // 连接子模块对应端口
        .VL_INDEX_RTC(4'd3), .RTC_MASTER_MODE(1'b0), .RTC_SYNC_PERIOD(16'd1),  // 连接子模块对应端口
        .RTC_PROC_DELAY(32'd0)                              // 连接子模块对应端口
    ) dut (                                                 // 参数绑定结束，开始连接实例端口
        .clk_sys(clk_sys), .rst_b(rst_b),                   // 连接子模块对应端口
        .ff_rx_data(ff_rx_data), .ff_rx_data_vld(ff_rx_data_vld),  // 连接子模块对应端口
        .ff_rx_sop(ff_rx_sop), .ff_rx_eop(ff_rx_eop), .ff_rx_err(ff_rx_err),  // 连接子模块对应端口
        .ff_rx_rdy(ff_rx_rdy),                              // 连接子模块对应端口
        .rx_frame_net(1'b0),                                // 单网仿真：恒按 A 网处理
        .ff_tx_data(ff_tx_data), .ff_tx_wren(ff_tx_wren),   // 连接子模块对应端口
        .ff_tx_sop(ff_tx_sop), .ff_tx_eop(ff_tx_eop), .ff_tx_err(ff_tx_err),  // 连接子模块对应端口
        .ff_tx_rdy(ff_tx_rdy),                              // 连接子模块对应端口
        .cfg_wr_en(cfg_wr_en), .cfg_wr_addr(cfg_wr_addr), .cfg_wr_vlid(cfg_wr_vlid),  // 连接子模块对应端口
        .cfg_wr_udp_port(cfg_wr_udp_port), .cfg_wr_port_type(cfg_wr_port_type),  // 连接子模块对应端口
        .cfg_wr_bag(cfg_wr_bag), .cfg_wr_lmax(cfg_wr_lmax),  // 连接子模块对应端口
        .cfg_wr_rm_en(cfg_wr_rm_en), .cfg_wr_ic_mode(cfg_wr_ic_mode),  // 连接子模块对应端口
        .cfg_done(cfg_done),                                // 连接子模块对应端口
        .app_rd_vl_index(app_rd_vl_index), .app_rd_byte_offset(app_rd_byte_offset),  // 连接子模块对应端口
        .app_rd_en(app_rd_en), .app_rd_data(app_rd_data), .app_rd_valid(app_rd_valid),  // 连接子模块对应端口
        .app_rd_frame_len(app_rd_frame_len), .app_rd_frame_cnt(app_rd_frame_cnt),  // 连接子模块对应端口
        .app_wr_en(app_wr_en), .app_wr_vl_index(app_wr_vl_index),  // 连接子模块对应端口
        .app_wr_byte_offset(app_wr_byte_offset), .app_wr_data(app_wr_data),  // 连接子模块对应端口
        .app_tx_req(app_tx_req), .app_wr_gnt(app_wr_gnt),   // 连接子模块对应端口
        .local_rtc(local_rtc), .rtc_sync_valid(rtc_sync_valid),  // 连接子模块对应端口
        .irq_rx_frame(irq_rx_frame), .irq_tx_done(irq_tx_done), .irq_error(irq_error)  // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    task cfg_write;                                         // 声明可重复调用的仿真任务
        input [15:0] vlid;                                  // 声明input、vlid所需的信号或常量
        input [15:0] udp_port;                              // 声明input、udp_port所需的信号或常量
        input [1:0]  port_type;                             // 声明input、port_type所需的信号或常量
        begin                                               // 开始执行当前条件或循环的语句组
            @(posedge clk_sys);                             // 等待指定时钟边沿后继续仿真
            cfg_wr_addr      <= vlid[11:0];                 // 时钟沿更新cfg_wr_addr
            cfg_wr_vlid      <= vlid;                       // 时钟沿更新cfg_wr_vlid
            cfg_wr_udp_port  <= udp_port;                   // 时钟沿更新cfg_wr_udp_port
            cfg_wr_port_type <= port_type;                  // 时钟沿更新cfg_wr_port_type
            cfg_wr_bag       <= 16'd1;                      // 时钟沿更新cfg_wr_bag
            cfg_wr_lmax      <= 16'd512;                    // 时钟沿更新cfg_wr_lmax
            cfg_wr_rm_en     <= 1'b0;                       // 时钟沿更新cfg_wr_rm_en
            cfg_wr_ic_mode   <= 1'b0;                       // 时钟沿更新cfg_wr_ic_mode
            cfg_wr_en        <= 1'b1;                       // 时钟沿更新cfg_wr_en
            @(posedge clk_sys);                             // 等待指定时钟边沿后继续仿真
            cfg_wr_en <= 1'b0;                              // 时钟沿更新cfg_wr_en
            repeat (2) @(posedge clk_sys);                  // 等待指定数量的时钟周期
        end                                                 // 当前语句组结束
    endtask                                                 // 仿真任务定义结束

    task rx_byte;                                           // 声明可重复调用的仿真任务
        input [7:0] d;                                      // 声明input所需的信号或常量
        input sop, eop;                                     // 声明input、sop、eop所需的信号或常量
        begin                                               // 开始执行当前条件或循环的语句组
            @(negedge clk_sys);                             // 等待指定时钟边沿后继续仿真
            ff_rx_data <= d;                                // 时钟沿更新ff_rx_data
            ff_rx_sop  <= sop;                              // 时钟沿更新ff_rx_sop
            ff_rx_eop  <= eop;                              // 时钟沿更新ff_rx_eop
            ff_rx_data_vld <= 1'b1;                         // 时钟沿更新ff_rx_data_vld
            @(posedge clk_sys);                             // 等待指定时钟边沿后继续仿真
            #1;                                             // 等待组合逻辑稳定或执行超时检查
            ff_rx_data_vld <= 1'b0;                         // 时钟沿更新ff_rx_data_vld
        end                                                 // 当前语句组结束
    endtask                                                 // 仿真任务定义结束

    task wait_app_wr_gnt;                                   // 声明可重复调用的仿真任务
        begin                                               // 开始执行当前条件或循环的语句组
            app_wr_en <= 1'b1;                              // 时钟沿更新app_wr_en
            wait (app_wr_gnt == 1'b1);                      // 继续计算app_wr_en
            @(posedge clk_sys);                             // 等待指定时钟边沿后继续仿真
            #1;                                             // 等待组合逻辑稳定或执行超时检查
            app_wr_en <= 1'b0;                              // 时钟沿更新app_wr_en
        end                                                 // 当前语句组结束
    endtask                                                 // 仿真任务定义结束

    task do_fail;                                           // 声明可重复调用的仿真任务
        input [127:0] msg;                                  // 声明input、msg所需的信号或常量
        begin                                               // 开始执行当前条件或循环的语句组
            $display("  [FAIL] %0s", msg);                  // 输出当前仿真检查结果或报文字节
            fail_cnt = fail_cnt + 1;                        // 设置或组合计算fail_cnt并推进至下一项
        end                                                 // 当前语句组结束
    endtask                                                 // 仿真任务定义结束

    initial begin                                           // 仿真初始化或激励流程
        clk_sys = 0; rst_b = 0; ff_tx_rdy = 1;              // 设置或组合计算clk_sys
        ff_rx_data = 0; ff_rx_data_vld = 0; ff_rx_sop = 0; ff_rx_eop = 0; ff_rx_err = 0;  // 设置或组合计算ff_rx_data
        cfg_wr_en = 0; cfg_wr_addr = 0; cfg_wr_vlid = 0; cfg_wr_udp_port = 0;  // 设置或组合计算cfg_wr_en
        cfg_wr_port_type = 0; cfg_wr_bag = 0; cfg_wr_lmax = 0;  // 设置或组合计算cfg_wr_port_type
        cfg_wr_rm_en = 0; cfg_wr_ic_mode = 0;               // 设置或组合计算cfg_wr_rm_en
        app_rd_vl_index = 4; app_rd_byte_offset = 0; app_rd_en = 0;  // 设置或组合计算app_rd_vl_index
        app_wr_en = 0; app_wr_vl_index = 4; app_wr_byte_offset = 0;  // 设置或组合计算app_wr_en
        app_wr_data = 0; app_tx_req = 0;                    // 设置或组合计算app_wr_data
        fail_cnt = 0;                                       // 设置或组合计算fail_cnt

        repeat (10) @(posedge clk_sys);                     // 等待指定数量的时钟周期
        rst_b = 1;                                          // 设置或组合计算rst_b
        repeat (5) @(posedge clk_sys);                      // 等待指定数量的时钟周期

        cfg_write(16'h0004, 16'd4001, 2'b00);               // 例化子模块并连接数据通路
        @(posedge clk_sys);                                 // 等待指定时钟边沿后继续仿真
        cfg_wr_vlid <= 16'hFFFF;                            // 时钟沿更新cfg_wr_vlid
        cfg_wr_en   <= 1'b1;                                // 时钟沿更新cfg_wr_en
        @(posedge clk_sys);                                 // 等待指定时钟边沿后继续仿真
        cfg_wr_en <= 1'b0;                                  // 时钟沿更新cfg_wr_en
        repeat (8) @(posedge clk_sys);                      // 等待指定数量的时钟周期

        $display("=== RX test ===");                        // 输出当前仿真检查结果或报文字节
        rx_byte(8'h01,1,0); rx_byte(8'h00,0,0); rx_byte(8'h00,0,0); rx_byte(8'h00,0,0);  // 例化子模块并连接数据通路
        rx_byte(8'h00,0,0); rx_byte(8'h04,0,0);             // 例化子模块并连接数据通路
        rx_byte(8'h02,0,0); rx_byte(8'h00,0,0); rx_byte(8'h00,0,0); rx_byte(8'h00,0,0);  // 例化子模块并连接数据通路
        rx_byte(8'h00,0,0); rx_byte(8'h01,0,0);             // 例化子模块并连接数据通路
        rx_byte(8'h08,0,0); rx_byte(8'h00,0,0);             // 例化子模块并连接数据通路
        rx_byte(8'h45,0,0); rx_byte(8'h00,0,0); rx_byte(8'h00,0,0); rx_byte(8'h2E,0,0);  // 例化子模块并连接数据通路
        rx_byte(8'h00,0,0); rx_byte(8'h01,0,0); rx_byte(8'h40,0,0); rx_byte(8'h00,0,0);  // 例化子模块并连接数据通路
        rx_byte(8'h01,0,0); rx_byte(8'h11,0,0); rx_byte(8'h94,0,0); rx_byte(8'hD9,0,0);  // 例化子模块并连接数据通路
        rx_byte(8'h04,0,0); rx_byte(8'h00,0,0); rx_byte(8'h00,0,0); rx_byte(8'h01,0,0);  // 例化子模块并连接数据通路
        rx_byte(8'hE0,0,0); rx_byte(8'hE0,0,0); rx_byte(8'h00,0,0); rx_byte(8'h04,0,0);  // 例化子模块并连接数据通路
        rx_byte(8'h00,0,0); rx_byte(8'hA1,0,0); rx_byte(8'h0F,0,0); rx_byte(8'hA1,0,0);  // 例化子模块并连接数据通路
        rx_byte(8'h00,0,0); rx_byte(8'h1A,0,0); rx_byte(8'h00,0,0); rx_byte(8'h00,0,0);  // 例化子模块并连接数据通路
        for (i = 0; i < 17; i = i + 1) rx_byte(i[7:0],0,0);  // 依次处理指定范围内的表项或位段
        rx_byte(8'h00,0,0);                                 // 例化子模块并连接数据通路
        rx_byte(8'h00,0,0); rx_byte(8'h00,0,0); rx_byte(8'h00,0,0); rx_byte(8'h00,0,1);  // 例化子模块并连接数据通路

        wait (app_rd_frame_cnt == 4'd1);                        // 提交可能发生在最后一个填充字节之前
        repeat (4) @(posedge clk_sys);                      // 等待指定数量的时钟周期
        if (app_rd_frame_cnt != 4'd1) do_fail("rx frame_cnt != 1");  // 检查app_rd_frame_cnt、do_fail的条件
        if (app_rd_frame_len != 16'd17) do_fail("rx frame_len != 17");  // 检查app_rd_frame_len、do_fail的条件

        for (i = 0; i < 17; i = i + 1) begin                // 依次处理指定范围内的表项或位段
            @(negedge clk_sys);                             // 在非采样沿改值
            app_rd_vl_index <= 4;                           // 时钟沿更新app_rd_vl_index
            app_rd_byte_offset <= i[10:0];                  // 时钟沿更新app_rd_byte_offset
            app_rd_en <= 1;                                 // 时钟沿更新app_rd_en
            @(posedge clk_sys);                             // 本拍请求被仲裁授权
            @(negedge clk_sys);                             // 授权后一拍：valid 与读数据都已稳定，此时采样
            if (app_rd_valid !== 1'b1) begin                // 检查授权
                $display("  [FAIL] rx rd_valid missing at %0d", i);  // 输出当前仿真检查结果
                fail_cnt = fail_cnt + 1;                    // 设置或组合计算fail_cnt并推进至下一项
            end                                             // 当前语句组结束
            else if (app_rd_data !== i[7:0]) begin          // 检查app_rd_data、i的条件
                $display("  [FAIL] rx data[%0d] = %02x", i, app_rd_data);  // 输出当前仿真检查结果或报文字节
                fail_cnt = fail_cnt + 1;                    // 设置或组合计算fail_cnt并推进至下一项
            end                                             // 当前语句组结束
            app_rd_en <= 0;                                 // 撤销读使能
        end                                                 // 当前语句组结束
        if (fail_cnt == 0) $display("  [PASS] RX 17B payload");  // 检查fail_cnt、display、PASS的条件

        $display("=== TX test ===");                        // 输出当前仿真检查结果或报文字节
        for (i = 0; i < 17; i = i + 1) begin                // 依次处理指定范围内的表项或位段
            @(posedge clk_sys);                             // 等待指定时钟边沿后继续仿真
            app_wr_vl_index <= 4;                           // 时钟沿更新app_wr_vl_index
            app_wr_byte_offset <= i[10:0];                  // 时钟沿更新app_wr_byte_offset
            app_wr_data <= i[7:0];                          // 时钟沿更新app_wr_data
            wait_app_wr_gnt();                              // 例化子模块并连接数据通路
        end                                                 // 当前语句组结束
        @(posedge clk_sys);                                 // 等待指定时钟边沿后继续仿真
        app_tx_req <= 1'b1;                                 // 时钟沿更新app_tx_req
        @(posedge clk_sys);                                 // 等待指定时钟边沿后继续仿真
        app_tx_req <= 1'b0;                                 // 时钟沿更新app_tx_req

        rx_cnt = 0;                                         // 设置或组合计算rx_cnt
        begin : tx_capture                                  // 继续计算rx_cnt
            forever begin                                   // 继续计算rx_cnt
                @(negedge clk_sys);                         // 等待指定时钟边沿后继续仿真
                if (ff_tx_wren) begin                       // 检查ff_tx_wren的条件
                    rx_capture[rx_cnt] = ff_tx_data;        // 设置或组合计算rx_capture
                    rx_cnt = rx_cnt + 1;                    // 设置或组合计算rx_cnt并推进至下一项
                end                                         // 当前语句组结束
                @(posedge clk_sys);                         // 等待指定时钟边沿后继续仿真
                if (ff_tx_eop && ff_tx_wren)                // 检查ff_tx_eop、ff_tx_wren的条件
                    disable tx_capture;                     // 继续计算rx_cnt
            end                                             // 当前语句组结束
        end                                                 // 当前语句组结束

        for (i = 0; i < rx_cnt; i = i + 1) $write("%02x ", rx_capture[i]);  // 依次处理指定范围内的表项或位段
        $display("");                                       // 输出当前仿真检查结果或报文字节

        if (rx_cnt != 64) do_fail("tx frame length != 64");  // 检查rx_cnt、do_fail、tx的条件
        if (rx_capture[0] != 8'h01 || rx_capture[1] != 8'h00 ||  // 检查rx_capture、rx_capture的条件
            rx_capture[2] != 8'h00 || rx_capture[3] != 8'h00 ||  // 继续计算rx_cnt
            rx_capture[4] != 8'h00 || rx_capture[5] != 8'h04)  // 继续计算rx_cnt
            do_fail("tx destination MAC wrong");            // 例化子模块并连接数据通路
        if (rx_capture[42] != 8'h00) do_fail("tx payload first byte wrong");  // 检查rx_capture、do_fail的条件
        if (rx_capture[58] != 8'h10) do_fail("tx payload last byte wrong");  // 检查rx_capture、do_fail的条件
        if (rx_capture[59] != 8'h00) do_fail("tx SN != 0");  // 检查rx_capture、do_fail的条件
        if (rx_capture[60] != 8'h00) do_fail("tx pad wrong");  // 检查rx_capture、do_fail的条件
        if (fail_cnt == 0) $display("  [PASS] TX frame assembly");  // 检查fail_cnt、display、PASS的条件

        $display("=== result: %0d failures ===", fail_cnt);  // 输出当前仿真检查结果或报文字节
        $finish;                                            // 结束当前自检仿真
    end                                                     // 当前语句组结束

endmodule                                                   // 模块定义结束

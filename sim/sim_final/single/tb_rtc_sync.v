// tb_rtc_sync : local_rtc / rtc_rx / rtc_tx / delay_comp 模块级仿真
// 验证 1us 计数、10 字节同步报文大端收发与延迟补偿公式。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_rtc_sync;                                         // 声明模块及其参数接口
    reg clk, rst_b;                                         // 声明clk、rst_b所需的信号或常量
    reg sync_en;                                            // 声明sync_en所需的信号或常量
    reg [47:0] sync_value;                                  // 声明sync_value所需的信号或常量
    reg [15:0] sync_period_ms;                              // 声明sync_period_ms所需的信号或常量
    wire [47:0] rtc_value;                                  // 声明rtc_value所需的信号或常量
    wire rtc_tick;                                          // 声明rtc_tick所需的信号或常量

    reg tx_req;                                             // 声明tx_req所需的信号或常量
    reg [47:0] local_ts;                                    // 声明local_ts所需的信号或常量
    reg tx_wr_gnt;                                          // 声明tx_wr_gnt所需的信号或常量
    wire tx_wr_en;                                          // 声明tx_wr_en所需的信号或常量
    wire [10:0] tx_wr_byte_offset;                          // 声明tx_wr_byte_offset所需的信号或常量
    wire [7:0] tx_wr_data;                                  // 声明tx_wr_data所需的信号或常量
    wire tx_frame_done;                                     // 声明tx_frame_done所需的信号或常量

    reg rx_start;                                           // 声明rx_start所需的信号或常量
    reg [15:0] rx_frame_len;                                // 声明rx_frame_len所需的信号或常量
    wire rx_rd_req;                                         // 声明rx_rd_req所需的信号或常量
    wire [10:0] rx_rd_byte_offset;                          // 声明rx_rd_byte_offset所需的信号或常量
    reg rx_rd_valid;                                        // 声明rx_rd_valid所需的信号或常量
    wire [7:0] rx_rd_data;                                  // 声明rx_rd_data所需的信号或常量
    wire [47:0] master_ts;                                  // 声明master_ts所需的信号或常量
    wire [31:0] delay_val;                                  // 声明delay_val所需的信号或常量
    wire rx_valid;                                          // 声明rx_valid所需的信号或常量

    reg [7:0] rx_mem [0:15];                                // 声明rx_mem所需的信号或常量
    reg [7:0] tx_mem [0:15];                                // 声明tx_mem所需的信号或常量
    wire [47:0] corrected_ts;                               // 声明corrected_ts所需的信号或常量
    wire calc_done;                                         // 声明calc_done所需的信号或常量
    integer i, fail_cnt;                                    // 声明integer、i、fail_cnt所需的信号或常量

    always #4 clk = ~clk;                                   // 继续计算当前组合结果

    local_rtc #(.RTC_WIDTH(48)) u_local_rtc (               // 例化子模块并连接数据通路
        .clk(clk), .rst_b(rst_b), .sync_en(sync_en), .sync_value(sync_value),  // 连接子模块对应端口
        .sync_period_ms(sync_period_ms), .rtc_value(rtc_value), .rtc_tick(rtc_tick)  // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    rtc_tx #(.DATA_WIDTH(8), .RTC_WIDTH(48), .BYTE_OFFSET_WIDTH(11)) u_rtc_tx (  // 例化子模块并连接数据通路
        .clk(clk), .rst_b(rst_b), .tx_req(tx_req), .local_ts(local_ts),  // 连接子模块对应端口
        .tx_wr_gnt(tx_wr_gnt), .tx_wr_en(tx_wr_en),         // 连接子模块对应端口
        .tx_wr_byte_offset(tx_wr_byte_offset), .tx_wr_data(tx_wr_data),  // 连接子模块对应端口
        .tx_frame_done(tx_frame_done)                       // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    rtc_rx #(.DATA_WIDTH(8), .RTC_WIDTH(48), .BYTE_OFFSET_WIDTH(11)) u_rtc_rx (  // 例化子模块并连接数据通路
        .clk(clk), .rst_b(rst_b), .start(rx_start), .rx_frame_len(rx_frame_len),  // 连接子模块对应端口
        .rx_rd_req(rx_rd_req), .rx_rd_byte_offset(rx_rd_byte_offset),  // 连接子模块对应端口
        .rx_rd_data(rx_rd_data), .rx_rd_valid(rx_rd_valid),  // 连接子模块对应端口
        .master_ts(master_ts), .delay_val(delay_val), .rx_valid(rx_valid)  // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    delay_comp #(.RTC_WIDTH(48)) u_delay_comp (             // 例化子模块并连接数据通路
        .clk(clk), .rst_b(rst_b), .master_ts(master_ts), .delay_val(delay_val),  // 连接子模块对应端口
        .rx_process_delay(32'd1000), .calc_req(rx_valid),   // 连接子模块对应端口
        .corrected_ts(corrected_ts), .calc_done(calc_done)  // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            rx_rd_valid <= 0;                               // 时钟沿更新rx_rd_valid
            tx_wr_gnt <= 0;                                 // 时钟沿更新tx_wr_gnt
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            rx_rd_valid <= rx_rd_req;                       // 时钟沿更新rx_rd_valid
            tx_wr_gnt <= tx_wr_en;                          // 时钟沿更新tx_wr_gnt
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束
    assign rx_rd_data = rx_mem[rx_rd_byte_offset];          // 设置或组合计算rx_rd_data

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b)                                         // 检查复位或正常运行条件
            tx_mem[10] <= 0;                                // 时钟沿更新tx_mem
        else if (tx_wr_en)                                  // 检查tx_wr_en的条件
            tx_mem[tx_wr_byte_offset] <= tx_wr_data;        // 时钟沿更新tx_mem
    end                                                     // 当前语句组结束

    initial begin                                           // 仿真初始化或激励流程
        clk = 0; rst_b = 0; sync_en = 0; sync_value = 0; sync_period_ms = 1;  // 设置或组合计算clk
        tx_req = 0; local_ts = 48'h010203040506; rx_start = 0; rx_frame_len = 10;  // 设置或组合计算tx_req
        rx_rd_valid = 0; tx_wr_gnt = 0; fail_cnt = 0;       // 设置或组合计算rx_rd_valid

        rx_mem[0] = 8'h11; rx_mem[1] = 8'h22; rx_mem[2] = 8'h33;  // 设置或组合计算rx_mem
        rx_mem[3] = 8'h44; rx_mem[4] = 8'h55; rx_mem[5] = 8'h66;  // 设置或组合计算rx_mem
        rx_mem[6] = 8'h00; rx_mem[7] = 8'h00; rx_mem[8] = 8'h01; rx_mem[9] = 8'h02;  // 设置或组合计算rx_mem

        repeat (10) @(posedge clk);                         // 等待指定数量的时钟周期
        rst_b = 1;                                          // 设置或组合计算rst_b
        repeat (251) @(posedge clk);                        // 25MHz 下 1us = 25 拍，多等一拍
        if (rtc_value != 48'd10) fail_cnt = fail_cnt + 1;   // 检查rtc_value、fail_cnt的条件
        $display("after rtc: %0d rtc_hex=%012h", fail_cnt, rtc_value);  // 输出当前仿真检查结果或报文字节

        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        tx_req <= 1;                                        // 时钟沿更新tx_req
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        tx_req <= 0;                                        // 时钟沿更新tx_req
        wait (tx_frame_done == 1'b1);                       // 继续计算tx_req
        repeat (4) @(posedge clk);                          // 等待指定数量的时钟周期
        if ({tx_mem[0],tx_mem[1],tx_mem[2],tx_mem[3],tx_mem[4],tx_mem[5]} !=  // 检查tx_mem、tx_mem、tx_mem的条件
            48'h010203040506) fail_cnt = fail_cnt + 1;      // 继续计算tx_req
        $display("after tx: %0d", fail_cnt);                // 输出当前仿真检查结果或报文字节
        $write("tx:");                                      // 输出当前仿真检查结果或报文字节
        for (i = 0; i < 10; i = i + 1) $write(" %02x", tx_mem[i]);  // 依次处理指定范围内的表项或位段
        $display("");                                       // 输出当前仿真检查结果或报文字节

        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        rx_start <= 1;                                      // 时钟沿更新rx_start
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        rx_start <= 0;                                      // 时钟沿更新rx_start
        wait (calc_done == 1'b1);                           // 继续计算rx_start
        repeat (4) @(posedge clk);                          // 等待指定数量的时钟周期
        if (master_ts != 48'h112233445566) fail_cnt = fail_cnt + 1;  // 检查master_ts、fail_cnt的条件
        if (delay_val != 32'd258) fail_cnt = fail_cnt + 1;  // 检查delay_val、fail_cnt的条件
        if (corrected_ts != 48'h112233445669) fail_cnt = fail_cnt + 1;  // 检查corrected_ts、fail_cnt的条件
        $display("after rx: %0d", fail_cnt);                // 输出当前仿真检查结果或报文字节

        $display("rtc=%0d master=%012h delay=%0d corrected=%012h failures=%0d",  // 输出当前仿真检查结果或报文字节
                 rtc_value, master_ts, delay_val, corrected_ts, fail_cnt);  // 继续计算rx_start
        $display("checks rtc=%0d tx=%0d master=%0d delay=%0d corr=%0d",  // 输出当前仿真检查结果或报文字节
                 (rtc_value == 48'd10),                     // 继续计算rx_start
                 ({tx_mem[0],tx_mem[1],tx_mem[2],tx_mem[3],tx_mem[4],tx_mem[5]} ==  // 继续计算rx_start
                  48'h010203040506),                        // 继续计算rx_start
                 (master_ts == 48'h112233445566),           // 继续计算rx_start
                 (delay_val == 32'd258),                    // 继续计算rx_start
                 (corrected_ts == 48'h112233445669));       // 继续计算rx_start
        if (fail_cnt == 0) $display("[PASS] RTC sync");     // 检查fail_cnt、display、PASS的条件
        $finish;                                            // 结束当前自检仿真
    end                                                     // 当前语句组结束

endmodule                                                   // 模块定义结束

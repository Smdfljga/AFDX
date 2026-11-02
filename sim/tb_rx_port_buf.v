// tb_rx_port_buf : 接收端口缓冲队列/采样语义仿真
// 队列模式连写 3 帧并顺序读出；采样模式连续覆盖，frame_cnt 恒为 1。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_rx_port_buf;                                      // 声明模块及其参数接口
    reg clk, rst_b;                                         // 声明clk、rst_b所需的信号或常量
    reg wr_en, wr_frame_done, wr_queue_mode;                // 声明wr_en、wr_frame_done、wr_queue_mode所需的信号或常量
    reg [3:0] wr_vl_index;                                  // 声明wr_vl_index所需的信号或常量
    reg [10:0] wr_byte_offset;                              // 声明wr_byte_offset所需的信号或常量
    reg [7:0] wr_data;                                      // 声明wr_data所需的信号或常量
    reg [15:0] wr_frame_len;                                // 声明wr_frame_len所需的信号或常量
    wire wr_full;                                           // 声明wr_full所需的信号或常量
    reg rd_en;                                              // 声明rd_en所需的信号或常量
    reg [3:0] rd_vl_index;                                  // 声明rd_vl_index所需的信号或常量
    reg [10:0] rd_byte_offset;                              // 声明rd_byte_offset所需的信号或常量
    wire [7:0] rd_data;                                     // 声明rd_data所需的信号或常量
    wire rd_valid;                                          // 声明rd_valid所需的信号或常量
    wire [255:0] rd_frame_len_all;                          // 声明rd_frame_len_all所需的信号或常量
    wire [63:0] rd_frame_cnt_all;                           // 声明rd_frame_cnt_all所需的信号或常量
    integer i, fail_cnt;                                    // 声明integer、i、fail_cnt所需的信号或常量

    always #5 clk = ~clk;                                   // 继续计算当前组合结果

    rx_port_buf #(.DATA_WIDTH(8),.VL_INDEX_WIDTH(4),.BYTE_OFFSET_WIDTH(11),  // 例化子模块并连接数据通路
                  .FRAME_LEN_WIDTH(16),.FRAME_CNT_WIDTH(3)) dut (  // 连接子模块对应端口
        .clk(clk), .rst_b(rst_b),                           // 连接子模块对应端口
        .wr_en(wr_en), .wr_vl_index(wr_vl_index), .wr_byte_offset(wr_byte_offset),  // 连接子模块对应端口
        .wr_data(wr_data), .wr_frame_done(wr_frame_done), .wr_frame_len(wr_frame_len),  // 连接子模块对应端口
        .wr_queue_mode(wr_queue_mode), .wr_full(wr_full),   // 连接子模块对应端口
        .rd_en(rd_en), .rd_vl_index(rd_vl_index), .rd_byte_offset(rd_byte_offset),  // 连接子模块对应端口
        .rd_data(rd_data), .rd_valid(rd_valid),             // 连接子模块对应端口
        .rd_frame_len_all(rd_frame_len_all), .rd_frame_cnt_all(rd_frame_cnt_all)  // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    task write_frame;                                       // 声明可重复调用的仿真任务
        input [7:0] base;                                   // 声明input、base所需的信号或常量
        input [15:0] len;                                   // 声明input、len所需的信号或常量
        begin                                               // 开始执行当前条件或循环的语句组
            for (i = 0; i < len; i = i + 1) begin           // 依次处理指定范围内的表项或位段
                @(posedge clk);                             // 等待指定时钟边沿后继续仿真
                wr_vl_index <= 4'd5;                        // 时钟沿更新wr_vl_index
                wr_byte_offset <= i[10:0];                  // 时钟沿更新wr_byte_offset
                wr_data <= base + i[7:0];                   // 时钟沿更新wr_data
                wr_en <= 1;                                 // 时钟沿更新wr_en
            end                                             // 当前语句组结束
            @(posedge clk);                                 // 等待指定时钟边沿后继续仿真
            wr_en <= 0;                                     // 时钟沿更新wr_en
            wr_frame_done <= 1;                             // 时钟沿更新wr_frame_done
            wr_frame_len <= len;                            // 时钟沿更新wr_frame_len
            @(posedge clk);                                 // 等待指定时钟边沿后继续仿真
            wr_frame_done <= 0;                             // 时钟沿更新wr_frame_done
        end                                                 // 当前语句组结束
    endtask                                                 // 仿真任务定义结束

    initial begin                                           // 仿真初始化或激励流程
        clk=0; rst_b=0; wr_en=0; wr_frame_done=0; wr_queue_mode=1;  // 设置或组合计算clk
        wr_vl_index=5; wr_byte_offset=0; wr_data=0; wr_frame_len=0;  // 设置或组合计算wr_vl_index
        rd_en=0; rd_vl_index=5; rd_byte_offset=0; fail_cnt=0;  // 设置或组合计算rd_en

        repeat (10) @(posedge clk);                         // 等待指定数量的时钟周期
        rst_b=1;                                            // 设置或组合计算rst_b
        repeat (4) @(posedge clk);                          // 等待指定数量的时钟周期

        write_frame(8'h10, 16'd3);                          // 例化子模块并连接数据通路
        write_frame(8'h20, 16'd4);                          // 例化子模块并连接数据通路
        write_frame(8'h30, 16'd2);                          // 例化子模块并连接数据通路
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        $display("before read cnt5=%0d len5=%0d",           // 输出当前仿真检查结果或报文字节
                 rd_frame_cnt_all[5*4 +: 4], rd_frame_len_all[5*16 +: 16]);  // 继续计算rst_b
        if (rd_frame_cnt_all[5*4 +: 4] != 4'd3) fail_cnt = fail_cnt + 1;  // 检查rd_frame_cnt_all、fail_cnt的条件
        if (rd_frame_len_all[5*16 +: 16] != 16'd3) fail_cnt = fail_cnt + 1;  // 检查rd_frame_len_all、fail_cnt的条件

        for (i = 0; i < 3; i = i + 1) begin                 // 依次处理指定范围内的表项或位段
            wait (rd_valid == 1'b0);                        // 继续计算rst_b
            @(posedge clk);                                 // 等待指定时钟边沿后继续仿真
            rd_byte_offset <= i[10:0];                      // 时钟沿更新rd_byte_offset
            rd_en <= 1;                                     // 时钟沿更新rd_en
            wait (rd_valid == 1'b1);                        // 继续计算rd_en
            $display("read[%0d]=%02x expected=%02x", i, rd_data, 8'h10 + i[7:0]);  // 输出当前仿真检查结果或报文字节
            if (rd_data != 8'h10 + i[7:0]) fail_cnt = fail_cnt + 1;  // 检查rd_data、i的条件
            @(posedge clk);                                 // 等待指定时钟边沿后继续仿真
            rd_en <= 0;                                     // 时钟沿更新rd_en
        end                                                 // 当前语句组结束
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        $display("after first frame cnt5=%0d len5=%0d",     // 输出当前仿真检查结果或报文字节
                 rd_frame_cnt_all[5*4 +: 4], rd_frame_len_all[5*16 +: 16]);  // 继续计算rd_en
        if (rd_frame_cnt_all[5*4 +: 4] != 4'd2) fail_cnt = fail_cnt + 1;  // 检查rd_frame_cnt_all、fail_cnt的条件

        // 采样模式：第一字节复位旧队列，写入 1 字节后 frame_cnt 应为 1。
        wr_queue_mode <= 0;                                 // 时钟沿更新wr_queue_mode
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        wr_vl_index <= 5; wr_byte_offset <= 0; wr_data <= 8'hAA; wr_en <= 1;  // 时钟沿更新wr_vl_index
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        wr_en <= 0; wr_frame_done <= 1; wr_frame_len <= 1;  // 时钟沿更新wr_en
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        wr_frame_done <= 0;                                 // 时钟沿更新wr_frame_done
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        $display("sample cnt5=%0d len5=%0d",                // 输出当前仿真检查结果或报文字节
                 rd_frame_cnt_all[5*4 +: 4], rd_frame_len_all[5*16 +: 16]);  // 继续计算wr_frame_done
        if (rd_frame_cnt_all[5*4 +: 4] != 4'd1) fail_cnt = fail_cnt + 1;  // 检查rd_frame_cnt_all、fail_cnt的条件

        $display("rx_port_buf failures: %0d", fail_cnt);    // 输出当前仿真检查结果或报文字节
        if (fail_cnt == 0) $display("[PASS] RX port buffer queue/sampling");  // 检查fail_cnt、display、PASS的条件
        $finish;                                            // 结束当前自检仿真
    end                                                     // 当前语句组结束

endmodule                                                   // 模块定义结束

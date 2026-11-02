// tb_tftp : TFTP DATA 解析、文件 FIFO、Flash 写与 ACK 模块级仿真
// 注入 100 字节 DATA#1，预期 Flash 写入 100 字节并回 ACK#1，load_done 拉高。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_tftp;                                             // 声明模块及其参数接口
    reg clk, rst_b, start;                                  // 声明clk、rst_b、start所需的信号或常量
    reg [15:0] rx_frame_len;                                // 声明rx_frame_len所需的信号或常量
    wire rx_rd_req;                                         // 声明rx_rd_req所需的信号或常量
    wire [10:0] rx_rd_byte_offset;                          // 声明rx_rd_byte_offset所需的信号或常量
    wire [7:0] rx_rd_data;                                  // 声明rx_rd_data所需的信号或常量
    reg rx_rd_valid;                                        // 声明rx_rd_valid所需的信号或常量
    wire buf_wr_en;                                         // 声明buf_wr_en所需的信号或常量
    wire [7:0] buf_wr_data;                                 // 声明buf_wr_data所需的信号或常量
    wire buf_rd_en;                                         // 声明buf_rd_en所需的信号或常量
    reg [7:0] buf_rd_data;                                  // 声明buf_rd_data所需的信号或常量
    reg buf_rd_valid;                                       // 声明buf_rd_valid所需的信号或常量
    wire flash_wr_req;                                      // 声明flash_wr_req所需的信号或常量
    wire [23:0] flash_wr_addr;                              // 声明flash_wr_addr所需的信号或常量
    reg flash_wr_done;                                      // 声明flash_wr_done所需的信号或常量
    wire tx_wr_en;                                          // 声明tx_wr_en所需的信号或常量
    wire [10:0] tx_wr_byte_offset;                          // 声明tx_wr_byte_offset所需的信号或常量
    wire [7:0] tx_wr_data;                                  // 声明tx_wr_data所需的信号或常量
    wire tx_frame_done;                                     // 声明tx_frame_done所需的信号或常量
    reg tx_wr_gnt;                                          // 声明tx_wr_gnt所需的信号或常量
    wire tftp_op_valid;                                     // 声明tftp_op_valid所需的信号或常量
    wire [1:0] tftp_op_type;                                // 声明tftp_op_type所需的信号或常量
    wire [15:0] tftp_block_num, tftp_data_len;              // 声明tftp_block_num、tftp_data_len所需的信号或常量
    wire load_busy, load_done, load_error;                  // 声明load_busy、load_done、load_error所需的信号或常量

    reg [7:0] req_mem [0:255];                              // 声明req_mem所需的信号或常量
    reg [7:0] fifo_mem [0:255];                             // 声明fifo_mem所需的信号或常量
    reg [8:0] fifo_wr, fifo_rd, fifo_cnt;                   // 声明fifo_wr、fifo_rd、fifo_cnt所需的信号或常量
    reg [7:0] ack_mem [0:3];                                // 声明ack_mem所需的信号或常量
    integer i, flash_cnt, fail_cnt;                         // 声明integer、i、flash_cnt所需的信号或常量

    always #5 clk = ~clk;                                   // 继续计算当前组合结果

    tftp #(.DATA_WIDTH(8), .BYTE_OFFSET_WIDTH(11)) dut (    // 例化子模块并连接数据通路
        .clk(clk), .rst_b(rst_b), .start(start), .rx_frame_len(rx_frame_len),  // 连接子模块对应端口
        .rx_rd_req(rx_rd_req), .rx_rd_byte_offset(rx_rd_byte_offset),  // 连接子模块对应端口
        .rx_rd_data(rx_rd_data), .rx_rd_valid(rx_rd_valid),  // 连接子模块对应端口
        .tftp_op_valid(tftp_op_valid), .tftp_op_type(tftp_op_type),  // 连接子模块对应端口
        .tftp_block_num(tftp_block_num), .tftp_data_len(tftp_data_len),  // 连接子模块对应端口
        .buf_wr_en(buf_wr_en), .buf_wr_data(buf_wr_data),   // 连接子模块对应端口
        .buf_rd_en(buf_rd_en), .buf_rd_data(buf_rd_data), .buf_rd_valid(buf_rd_valid),  // 连接子模块对应端口
        .flash_wr_req(flash_wr_req), .flash_wr_addr(flash_wr_addr),  // 连接子模块对应端口
        .flash_wr_done(flash_wr_done),                      // 连接子模块对应端口
        .tx_wr_en(tx_wr_en), .tx_wr_byte_offset(tx_wr_byte_offset),  // 连接子模块对应端口
        .tx_wr_data(tx_wr_data), .tx_frame_done(tx_frame_done), .tx_wr_gnt(tx_wr_gnt),  // 连接子模块对应端口
        .load_busy(load_busy), .load_done(load_done), .load_error(load_error)  // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            rx_rd_valid <= 0;                               // 时钟沿更新rx_rd_valid
            flash_wr_done <= 0;                             // 时钟沿更新flash_wr_done
            tx_wr_gnt <= 0;                                 // 时钟沿更新tx_wr_gnt
            buf_rd_valid <= 0;                              // 时钟沿更新buf_rd_valid
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            rx_rd_valid  <= rx_rd_req;                      // 时钟沿更新rx_rd_valid
            flash_wr_done <= flash_wr_req;                  // 时钟沿更新flash_wr_done
            tx_wr_gnt    <= tx_wr_en;                       // 时钟沿更新tx_wr_gnt
            buf_rd_valid <= buf_rd_en;                      // 时钟沿更新buf_rd_valid
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束
    assign rx_rd_data = req_mem[rx_rd_byte_offset];         // 设置或组合计算rx_rd_data

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            fifo_wr <= 0; fifo_rd <= 0; fifo_cnt <= 0; flash_cnt <= 0;  // 时钟沿更新fifo_wr
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            if (buf_wr_en) begin                            // 检查buf_wr_en的条件
                fifo_mem[fifo_wr[7:0]] <= buf_wr_data;      // 继续计算fifo_wr
                fifo_wr <= fifo_wr + 1;                     // 时钟沿更新fifo_wr并推进至下一项
                fifo_cnt <= fifo_cnt + 1;                   // 时钟沿更新fifo_cnt并推进至下一项
            end                                             // 当前语句组结束
            if (buf_rd_en) begin                            // 检查buf_rd_en的条件
                buf_rd_data <= fifo_mem[fifo_rd[7:0]];      // 时钟沿更新buf_rd_data
                fifo_rd <= fifo_rd + 1;                     // 时钟沿更新fifo_rd并推进至下一项
                fifo_cnt <= fifo_cnt - 1;                   // 时钟沿更新fifo_cnt
            end                                             // 当前语句组结束
            if (flash_wr_req) flash_cnt <= flash_cnt + 1;   // 检查flash_wr_req、flash_cnt、flash_cnt的条件
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b)                                         // 检查复位或正常运行条件
            ack_mem[3] <= 0;                                // 时钟沿更新ack_mem
        else if (tx_wr_en)                                  // 检查tx_wr_en的条件
            ack_mem[tx_wr_byte_offset] <= tx_wr_data;       // 时钟沿更新ack_mem
    end                                                     // 当前语句组结束

    initial begin                                           // 仿真初始化或激励流程
        clk = 0; rst_b = 0; start = 0; rx_frame_len = 104;  // 设置或组合计算clk
        rx_rd_valid = 0; buf_rd_data = 0; buf_rd_valid = 0;  // 设置或组合计算rx_rd_valid
        flash_wr_done = 0; tx_wr_gnt = 0; flash_cnt = 0; fail_cnt = 0;  // 设置或组合计算flash_wr_done

        req_mem[0] = 8'h00; req_mem[1] = 8'h03;   // DATA opcode
        req_mem[2] = 8'h00; req_mem[3] = 8'h01;   // block#1
        for (i = 0; i < 100; i = i + 1) req_mem[4+i] = i[7:0];  // 依次处理指定范围内的表项或位段

        repeat (10) @(posedge clk);                         // 等待指定数量的时钟周期
        rst_b = 1;                                          // 设置或组合计算rst_b
        repeat (4) @(posedge clk);                          // 等待指定数量的时钟周期
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        start <= 1;                                         // 时钟沿更新start
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        start <= 0;                                         // 时钟沿更新start

        wait (tx_frame_done == 1'b1);                       // 继续计算start
        repeat (4) @(posedge clk);                          // 等待指定数量的时钟周期
        if (flash_cnt != 100) fail_cnt = fail_cnt + 1;      // 检查flash_cnt、fail_cnt、fail_cnt的条件
        if ({ack_mem[0],ack_mem[1],ack_mem[2],ack_mem[3]} != 32'h00040001)  // 检查ack_mem、ack_mem、ack_mem的条件
            fail_cnt = fail_cnt + 1;                        // 设置或组合计算fail_cnt并推进至下一项
        if (load_done != 1'b1) fail_cnt = fail_cnt + 1;     // 检查load_done、fail_cnt的条件

        $display("TFTP flash writes: %0d, ACK: %02x%02x%02x%02x, failures: %0d",  // 输出当前仿真检查结果或报文字节
                 flash_cnt, ack_mem[0],ack_mem[1],ack_mem[2],ack_mem[3], fail_cnt);  // 继续计算fail_cnt
        if (fail_cnt == 0) $display("[PASS] TFTP DATA/ACK");  // 检查fail_cnt、display、PASS的条件
        $finish;                                            // 结束当前自检仿真
    end                                                     // 当前语句组结束

endmodule                                                   // 模块定义结束

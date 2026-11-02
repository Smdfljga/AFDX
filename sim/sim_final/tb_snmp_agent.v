// tb_snmp_agent : SNMP GetRequest → MIB 查询 → GetResponse 模块级仿真
// 请求对象：RX 表 VL=4 的 cnt0；测试侧用一拍延时应答 rx_rd / mib_rd / tx_wr_gnt。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_snmp_agent;                                       // 声明模块及其参数接口
    reg clk, rst_b;                                         // 声明clk、rst_b所需的信号或常量
    reg rx_ready_snmp;                                      // 声明rx_ready_snmp所需的信号或常量
    wire rx_rd_req;                                         // 声明rx_rd_req所需的信号或常量
    wire [10:0] rx_rd_byte_offset;                          // 声明rx_rd_byte_offset所需的信号或常量
    wire [7:0] rx_rd_data;                                  // 声明rx_rd_data所需的信号或常量
    reg rx_rd_valid;                                        // 声明rx_rd_valid所需的信号或常量
    wire tx_wr_en;                                          // 声明tx_wr_en所需的信号或常量
    wire [10:0] tx_wr_byte_offset;                          // 声明tx_wr_byte_offset所需的信号或常量
    wire [7:0] tx_wr_data;                                  // 声明tx_wr_data所需的信号或常量
    wire tx_frame_done;                                     // 声明tx_frame_done所需的信号或常量
    reg tx_wr_gnt;                                          // 声明tx_wr_gnt所需的信号或常量
    wire mib_sel;                                           // 声明mib_sel所需的信号或常量
    wire [11:0] mib_addr;                                   // 声明mib_addr所需的信号或常量
    wire mib_rd_en;                                         // 声明mib_rd_en所需的信号或常量
    reg [159:0] mib_rd_data;                                // 声明mib_rd_data所需的信号或常量

    reg [7:0] req_mem [0:127];                              // 声明req_mem所需的信号或常量
    reg [7:0] tx_mem [0:127];                               // 声明tx_mem所需的信号或常量
    integer i, tx_cnt, fail_cnt;                            // 声明integer、i、tx_cnt所需的信号或常量

    always #5 clk = ~clk;                                   // 继续计算当前组合结果

    snmp_agent #(                                           // 例化子模块并连接数据通路
        .DATA_WIDTH(8), .VL_INDEX_WIDTH(4), .BYTE_OFFSET_WIDTH(11),  // 连接子模块对应端口
        .CNT_WIDTH(32), .VL_ADDR_WIDTH(12), .OID_WIDTH(16), .VL_INDEX_SELF(4'd1)  // 连接子模块对应端口
    ) dut (                                                 // 参数绑定结束，开始连接实例端口
        .clk(clk), .rst_b(rst_b), .rx_ready_snmp(rx_ready_snmp),  // 连接子模块对应端口
        .rx_rd_req(rx_rd_req), .rx_rd_byte_offset(rx_rd_byte_offset),  // 连接子模块对应端口
        .rx_rd_data(rx_rd_data), .rx_rd_valid(rx_rd_valid),  // 连接子模块对应端口
        .rx_frame_len(16'd46),                              // 连接子模块对应端口
        .tx_wr_en(tx_wr_en), .tx_wr_byte_offset(tx_wr_byte_offset),  // 连接子模块对应端口
        .tx_wr_data(tx_wr_data), .tx_frame_done(tx_frame_done), .tx_wr_gnt(tx_wr_gnt),  // 连接子模块对应端口
        .mib_sel(mib_sel), .mib_addr(mib_addr), .mib_rd_en(mib_rd_en),  // 连接子模块对应端口
        .mib_rd_data(mib_rd_data)                           // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    task set_req;                                           // 声明可重复调用的仿真任务
        begin                                               // 开始执行当前条件或循环的语句组
            req_mem[0]  = 8'h30; req_mem[1]  = 8'h2C;       // 设置或组合计算req_mem
            req_mem[2]  = 8'h02; req_mem[3]  = 8'h01; req_mem[4]  = 8'h01;  // 设置或组合计算req_mem
            req_mem[5]  = 8'h04; req_mem[6]  = 8'h06;       // 设置或组合计算req_mem
            req_mem[7]  = 8'h70; req_mem[8]  = 8'h75; req_mem[9]  = 8'h62;  // 设置或组合计算req_mem
            req_mem[10] = 8'h6C; req_mem[11] = 8'h69; req_mem[12] = 8'h63;  // 设置或组合计算req_mem
            req_mem[13] = 8'hA0; req_mem[14] = 8'h1F;       // 设置或组合计算req_mem
            req_mem[15] = 8'h02; req_mem[16] = 8'h04;       // 设置或组合计算req_mem
            req_mem[17] = 8'h00; req_mem[18] = 8'h00; req_mem[19] = 8'h00; req_mem[20] = 8'h01;  // 设置或组合计算req_mem
            req_mem[21] = 8'h02; req_mem[22] = 8'h01; req_mem[23] = 8'h00;  // 设置或组合计算req_mem
            req_mem[24] = 8'h02; req_mem[25] = 8'h01; req_mem[26] = 8'h00;  // 设置或组合计算req_mem
            req_mem[27] = 8'h30; req_mem[28] = 8'h11;       // 设置或组合计算req_mem
            req_mem[29] = 8'h30; req_mem[30] = 8'h0F;       // 设置或组合计算req_mem
            req_mem[31] = 8'h06; req_mem[32] = 8'h0B;       // 设置或组合计算req_mem
            req_mem[33] = 8'h2B; req_mem[34] = 8'h06; req_mem[35] = 8'h01;  // 设置或组合计算req_mem
            req_mem[36] = 8'h04; req_mem[37] = 8'h01; req_mem[38] = 8'hCE;  // 设置或组合计算req_mem
            req_mem[39] = 8'h0F; req_mem[40] = 8'h01; req_mem[41] = 8'h00;  // 设置或组合计算req_mem
            req_mem[42] = 8'h04; req_mem[43] = 8'h00;       // 设置或组合计算req_mem
            req_mem[44] = 8'h05; req_mem[45] = 8'h00;       // 设置或组合计算req_mem
        end                                                 // 当前语句组结束
    endtask                                                 // 仿真任务定义结束

    // 输入、MIB、写授权均打一拍，模拟同步读延迟和仲裁回执。
    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            rx_rd_valid <= 1'b0;                            // 时钟沿更新rx_rd_valid
            tx_wr_gnt   <= 1'b0;                            // 时钟沿更新tx_wr_gnt
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            rx_rd_valid <= rx_rd_req;                       // 时钟沿更新rx_rd_valid
            tx_wr_gnt   <= tx_wr_en;                        // 时钟沿更新tx_wr_gnt
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束
    assign rx_rd_data = req_mem[rx_rd_byte_offset];             // 数据与当前偏移同拍，valid 延迟一拍

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b)                                         // 检查复位或正常运行条件
            mib_rd_data <= 160'd0;                          // 时钟沿更新mib_rd_data
        else if (mib_rd_en)                                 // 检查mib_rd_en的条件
            mib_rd_data <= {32'd5, 32'd4, 32'd3, 32'd2, 32'h11223344};  // 时钟沿更新mib_rd_data
    end                                                     // 当前语句组结束

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b)                                         // 检查复位或正常运行条件
            tx_cnt <= 0;                                    // 时钟沿更新tx_cnt
        else if (tx_wr_en) begin                            // 检查tx_wr_en的条件
            tx_mem[tx_wr_byte_offset] <= tx_wr_data;        // 时钟沿更新tx_mem
            if (tx_wr_byte_offset == 11'd50)                // 检查tx_wr_byte_offset的条件
                tx_cnt <= 51;                               // 时钟沿更新tx_cnt
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    initial begin                                           // 仿真初始化或激励流程
        clk = 0; rst_b = 0; rx_ready_snmp = 0;              // 设置或组合计算clk
        rx_rd_valid = 0; tx_wr_gnt = 0; mib_rd_data = 0;    // 设置或组合计算rx_rd_valid
        tx_cnt = 0; fail_cnt = 0;                           // 设置或组合计算tx_cnt
        set_req();                                          // 例化子模块并连接数据通路

        repeat (10) @(posedge clk);                         // 等待指定数量的时钟周期
        rst_b = 1;                                          // 设置或组合计算rst_b
        repeat (4) @(posedge clk);                          // 等待指定数量的时钟周期
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        rx_ready_snmp <= 1;                                 // 时钟沿更新rx_ready_snmp
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        rx_ready_snmp <= 0;                                 // 时钟沿更新rx_ready_snmp

        wait (tx_cnt == 51);                                // 继续计算rx_ready_snmp
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真

        if (tx_mem[0] != 8'h30) fail_cnt = fail_cnt + 1;    // 检查tx_mem、fail_cnt的条件
        if (tx_mem[13] != 8'hA2) fail_cnt = fail_cnt + 1;   // 检查tx_mem、fail_cnt的条件
        if ({tx_mem[47],tx_mem[48],tx_mem[49],tx_mem[50]} != 32'h11223344)  // 检查tx_mem、tx_mem、tx_mem的条件
            fail_cnt = fail_cnt + 1;                        // 设置或组合计算fail_cnt并推进至下一项
        $display("SNMP response bytes captured: %0d, failures: %0d", tx_cnt, fail_cnt);  // 输出当前仿真检查结果或报文字节
        if (fail_cnt == 0) $display("[PASS] SNMP GetResponse");  // 检查fail_cnt、display、PASS的条件
        $finish;                                            // 结束当前自检仿真
    end                                                     // 当前语句组结束

endmodule                                                   // 模块定义结束

// tb_mib_query_regression：验证同步双表、连续查询、OID撤销和非法计数器编号
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度
module tb_mib_query_regression;                             // 声明模块及其参数接口
    reg clk = 1'b0;                                         // 声明clk、b0所需的信号或常量
    reg rst_b = 1'b0;                                       // 声明rst_b、b0所需的信号或常量
    reg query_req = 1'b0;                                   // 声明query_req、b0所需的信号或常量
    reg [15:0] oid = 16'd0;                                 // 声明oid、d0所需的信号或常量
    wire mib_sel;                                           // 声明mib_sel所需的信号或常量
    wire [11:0] mib_addr;                                   // 声明mib_addr所需的信号或常量
    wire mib_rd_en;                                         // 声明mib_rd_en所需的信号或常量
    reg [159:0] rx_q;                                       // 声明rx_q所需的信号或常量
    reg [159:0] tx_q;                                       // 声明tx_q所需的信号或常量
    wire [159:0] mib_rd_data = mib_sel ? tx_q : rx_q;       // 声明mib_rd_data、mib_sel、tx_q所需的信号或常量
    wire query_done;                                        // 声明query_done所需的信号或常量
    wire [31:0] query_value;                                // 声明query_value所需的信号或常量
    integer failures = 0;                                   // 声明integer、failures所需的信号或常量
    always #5 clk = ~clk;                                   // 继续计算mib_rd_data
    // 与工程MIB两表一致：共享地址、无硬件读使能、一拍同步读。
    always @(posedge clk) begin                             // 按时钟沿更新寄存器，并响应声明的异步复位
        rx_q <= {32'd555,32'd444,32'd333,32'd222,{20'd0,mib_addr}};  // 时钟沿更新rx_q
        tx_q <= {32'd999,32'd888,32'd777,{20'd0,mib_addr},32'd666};  // 时钟沿更新tx_q
    end                                                     // 当前语句组结束
    mib_query dut (                                         // 例化子模块并连接数据通路
        .clk(clk), .rst_b(rst_b), .query_req(query_req), .oid(oid),  // 连接子模块对应端口
        .mib_sel(mib_sel), .mib_addr(mib_addr), .mib_rd_en(mib_rd_en),  // 连接子模块对应端口
        .mib_rd_data(mib_rd_data), .query_done(query_done), .query_value(query_value)  // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束
    task check_result;                                      // 声明可重复调用的仿真任务
        input [31:0] expected;                              // 声明input、expected所需的信号或常量
        begin                                               // 开始执行当前条件或循环的语句组
            if (query_done !== 1'b1 || query_value !== expected) begin  // 检查query_done、query_value的条件
                $display("[FAIL] MIB expected=%0d got=%0d done=%b",expected,query_value,query_done);  // 输出当前仿真检查结果或报文字节
                failures = failures + 1;                    // 设置或组合计算failures并推进至下一项
            end                                             // 当前语句组结束
        end                                                 // 当前语句组结束
    endtask                                                 // 仿真任务定义结束
    initial begin                                           // 仿真初始化或激励流程
        repeat (3) @(negedge clk);                          // 等待指定数量的时钟周期
        rst_b = 1'b1;                                       // 设置或组合计算rst_b
        @(negedge clk); query_req = 1'b1; oid = {1'b0,12'd37,3'd0};  // 等待指定时钟边沿后继续仿真
        @(negedge clk); query_req = 1'b0; oid = 16'hffff;   // 等待指定时钟边沿后继续仿真
        @(posedge clk); #1; check_result(32'd37);           // 等待指定时钟边沿后继续仿真
        @(negedge clk); query_req = 1'b1; oid = {1'b1,12'd93,3'd1};  // 等待指定时钟边沿后继续仿真
        @(negedge clk); oid = {1'b0,12'd52,3'd0};           // 等待指定时钟边沿后继续仿真
        @(posedge clk); #1; check_result(32'd93);           // 等待指定时钟边沿后继续仿真
        @(negedge clk); query_req = 1'b0; oid = 16'hffff;   // 等待指定时钟边沿后继续仿真
        @(posedge clk); #1; check_result(32'd52);           // 等待指定时钟边沿后继续仿真
        @(negedge clk); query_req = 1'b1; oid = {1'b0,12'd1,3'd7};  // 等待指定时钟边沿后继续仿真
        @(negedge clk); query_req = 1'b0; oid = 16'd0;      // 等待指定时钟边沿后继续仿真
        @(posedge clk); #1; check_result(32'd0);            // 等待指定时钟边沿后继续仿真
        @(negedge clk); rst_b = 1'b0;                       // 等待指定时钟边沿后继续仿真
        #1; if (query_done !== 1'b0 || query_value !== 32'd0) failures = failures + 1;  // 等待组合逻辑稳定或执行超时检查
        if (failures == 0) $display("[PASS] MIB query synchronous alignment and consecutive tables");  // 检查failures、display、PASS的条件
        else $display("[FAIL] MIB query failures=%0d",failures);  // 采用前一条件未满足时的处理
        $finish;                                            // 结束当前自检仿真
    end                                                     // 当前语句组结束
    initial begin #2000; $display("[FAIL] MIB query timeout"); $finish; end  // 仿真初始化或激励流程
endmodule                                                   // 模块定义结束

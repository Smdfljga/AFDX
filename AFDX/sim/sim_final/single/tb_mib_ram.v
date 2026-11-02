// tb_mib_ram : MIB 读-改-写与连续事件累积仿真
// 连续注入 3 次 cnt0 和 20 次 cnt4，验证计数器分别 +3 / +20。
// RX / TX 各例化一份，确保两套 mib_*_ip 的读-改-写地址都接到 op_addr。
`timescale 1ns/1ps                                          // 设置仿真时间单位与精度

module tb_mib_ram;                                          // 声明模块及其参数接口
    reg clk, rst_b;                                         // 声明clk、rst_b所需的信号或常量
    reg [11:0] inc_addr;                                    // 声明inc_addr所需的信号或常量
    reg cnt0, cnt1, cnt2, cnt3, cnt4;                       // 声明cnt0、cnt1、cnt2所需的信号或常量
    reg [11:0] rd_addr;                                     // 读取物理地址，由槽位与字节偏移拼接
    reg rd_en;                                              // 声明rd_en所需的信号或常量
    wire [159:0] rd_data;                                   // 声明rd_data所需的信号或常量
    wire [159:0] rd_data_tx;                                // 声明rd_data_tx所需的信号或常量
    integer i, fail_cnt;                                    // 声明integer、i、fail_cnt所需的信号或常量

    always #5 clk = ~clk;                                   // 继续计算当前组合结果

    mib_ram #(.CNT_WIDTH(32), .ADDR_WIDTH(12), .IS_RX(1'b1)) dut_rx (  // 例化子模块并连接数据通路
        .clk(clk), .rst_b(rst_b), .inc_addr(inc_addr),      // 连接子模块对应端口
        .cnt0_inc(cnt0), .cnt1_inc(cnt1), .cnt2_inc(cnt2),  // 连接子模块对应端口
        .cnt3_inc(cnt3), .cnt4_inc(cnt4),                   // 连接子模块对应端口
        .rd_addr(rd_addr), .rd_en(rd_en), .rd_data(rd_data)  // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    mib_ram #(.CNT_WIDTH(32), .ADDR_WIDTH(12), .IS_RX(1'b0)) dut_tx (  // 例化子模块并连接数据通路
        .clk(clk), .rst_b(rst_b), .inc_addr(inc_addr),      // 连接子模块对应端口
        .cnt0_inc(cnt0), .cnt1_inc(cnt1), .cnt2_inc(cnt2),  // 连接子模块对应端口
        .cnt3_inc(cnt3), .cnt4_inc(cnt4),                   // 连接子模块对应端口
        .rd_addr(rd_addr), .rd_en(rd_en), .rd_data(rd_data_tx)  // 连接子模块对应端口
    );                                                      // 端口声明或模块例化结束

    initial begin                                           // 仿真初始化或激励流程
        clk = 0; rst_b = 0; inc_addr = 4; rd_addr = 4;      // 设置或组合计算clk
        cnt0 = 0; cnt1 = 0; cnt2 = 0; cnt3 = 0; cnt4 = 0; rd_en = 0;  // 设置或组合计算cnt0
        fail_cnt = 0;                                       // 设置或组合计算fail_cnt

        repeat (10) @(posedge clk);                         // 等待指定数量的时钟周期
        rst_b = 1;                                          // 设置或组合计算rst_b
        repeat (4) @(posedge clk);                          // 等待指定数量的时钟周期

        for (i = 0; i < 3; i = i + 1) begin                 // 依次处理指定范围内的表项或位段
            @(posedge clk);                                 // 等待指定时钟边沿后继续仿真
            cnt0 <= 1;                                      // 时钟沿更新cnt0
            @(posedge clk);                                 // 等待指定时钟边沿后继续仿真
            cnt0 <= 0;                                      // 时钟沿更新cnt0
        end                                                 // 当前语句组结束

        for (i = 0; i < 20; i = i + 1) begin                // 依次处理指定范围内的表项或位段
            @(posedge clk);                                 // 等待指定时钟边沿后继续仿真
            cnt4 <= 1;                                      // 时钟沿更新cnt4
            @(posedge clk);                                 // 等待指定时钟边沿后继续仿真
            cnt4 <= 0;                                      // 时钟沿更新cnt4
        end                                                 // 当前语句组结束

        repeat (30) @(posedge clk);                         // 等待指定数量的时钟周期
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        rd_en <= 1;                                         // 时钟沿更新rd_en
        @(posedge clk);                                     // 等待指定时钟边沿后继续仿真
        rd_en <= 0;                                         // 时钟沿更新rd_en
        repeat (3) @(posedge clk);                          // 等待指定数量的时钟周期

        if (rd_data[31:0] != 32'd3) fail_cnt = fail_cnt + 1;  // 检查rd_data、fail_cnt的条件
        if (rd_data[159:128] != 32'd20) fail_cnt = fail_cnt + 1;  // 检查rd_data、fail_cnt的条件
        if (rd_data_tx[31:0] != 32'd3) fail_cnt = fail_cnt + 1;  // 检查rd_data_tx、fail_cnt的条件
        if (rd_data_tx[159:128] != 32'd20) fail_cnt = fail_cnt + 1;  // 检查rd_data_tx、fail_cnt的条件
        $display("rx_cnt0=%0d rx_cnt4=%0d tx_cnt0=%0d tx_cnt4=%0d failures=%0d",  // 输出当前仿真检查结果或报文字节
                 rd_data[31:0], rd_data[159:128],           // 继续计算rd_en
                 rd_data_tx[31:0], rd_data_tx[159:128], fail_cnt);  // 继续计算rd_en
        if (fail_cnt == 0) $display("[PASS] MIB burst accumulation (RX and TX)");  // 检查fail_cnt、display、PASS的条件
        $finish;                                            // 结束当前自检仿真
    end                                                     // 当前语句组结束

endmodule                                                   // 模块定义结束

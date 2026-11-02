`timescale 1ns/1ps                                          // 时间单位为纳秒，精度为皮秒
module tb_rd_arb_regression;                                // 接收读仲裁握手自检
    reg clk = 1'b0;                                         // 系统时钟
    always #5 clk = ~clk;                                   // 产生一百兆赫时钟
    reg rst_b = 1'b0;                                       // 低有效复位
    integer failures = 0;                                   // 记录失败数
    integer checks = 0;                                     // 记录检查数
    reg app_req = 1'b0;                                     // 应用连续流水读请求
    reg [10:0] app_offset = 11'd0;                          // 应用读偏移
    reg run_agents = 1'b0;                                  // 启动三个等待响应的协议代理
    reg [10:0] snmp_offset = 11'd0;                         // SNMP 仅在读有效时推进
    reg [10:0] dl_offset = 11'd0;                           // 615A 仅在读有效时推进
    reg [10:0] rtc_offset = 11'd0;                          // RTC 仅在读有效时推进
    wire app_valid, snmp_valid, dl_valid, rtc_valid;        // 分别返回四路读响应
    wire buf_en;                                            // 仲裁后的物理 RAM 读使能
    wire [3:0] buf_vl;                                      // 仲裁后的读槽位
    wire [10:0] buf_offset;                                 // 仲裁后的读偏移
    reg [7:0] ram_q = 8'd0;                                 // 一拍读 RAM 行为
    wire [7:0] rd_data;                                     // 四路共用的返回字节
    rx_rd_arb arb (                                         // 保持四路读仲裁原接口
        .clk(clk), .rst_b(rst_b),                           // 时钟与复位
        .app_rd_req(app_req), .app_rd_vl_index(4'd4), .app_rd_byte_offset(app_offset), .app_rd_valid(app_valid),  // 应用连续读
        .snmp_rd_req(run_agents && snmp_offset < 4), .snmp_rd_vl_index(4'd1), .snmp_rd_byte_offset(snmp_offset), .snmp_rd_valid(snmp_valid),  // SNMP 等响应再前进
        .dl_rd_req(run_agents && dl_offset < 4), .dl_rd_vl_index(4'd2), .dl_rd_byte_offset(dl_offset), .dl_rd_valid(dl_valid),  // 615A 等响应再前进
        .rtc_rd_req(run_agents && rtc_offset < 4), .rtc_rd_vl_index(4'd3), .rtc_rd_byte_offset(rtc_offset), .rtc_rd_valid(rtc_valid),  // RTC 等响应再前进
        .buf_rd_en(buf_en), .buf_rd_vl_index(buf_vl), .buf_rd_byte_offset(buf_offset), .buf_rd_data(ram_q), .rd_data(rd_data)  // 物理一拍 RAM 接口
    );                                                      // 结束读仲裁例化
    always @(posedge clk) if (buf_en) ram_q <= {buf_vl, buf_offset[3:0]};  // 用可区分槽位与偏移的字节模拟同步 RAM
    task check;                                             // 统一自检任务
        input condition;                                    // 期望为真的条件
        input [511:0] name;                                 // 检查说明
        begin                                               // 开始检查
            checks = checks + 1;                            // 累计检查数
            if (condition !== 1'b1) begin                   // 未知值也视为失败
                failures = failures + 1;                    // 累计失败数
                $display("[FAIL] %0s", name);               // 输出失败原因
            end else $display("[PASS] %0s", name);          // 输出检查通过
        end                                                 // 结束检查
    endtask                                                 // 结束自检任务
    always @(posedge clk or negedge rst_b) begin            // 按真实同步消费者方式处理返回字节
        if (!rst_b) begin                                   // 复位各代理读取进度
            snmp_offset <= 0;                               // SNMP 从帧首开始
            dl_offset <= 0;                                 // 615A 从帧首开始
            rtc_offset <= 0;                                // RTC 从帧首开始
        end else if (run_agents) begin                      // 所有请求均保持到观察到有效
            if (snmp_valid && snmp_offset < 4) begin        // SNMP 收到有效响应
                check(rd_data === {4'd1, snmp_offset[3:0]}, "SNMP response matches current offset");  // 禁止旧地址重复响应
                snmp_offset <= snmp_offset + 1'b1;          // 有效后才推进偏移
            end                                             // 结束 SNMP 响应处理
            if (dl_valid && dl_offset < 4) begin            // 615A 收到有效响应
                check(rd_data === {4'd2, dl_offset[3:0]}, "615A response matches current offset");  // 数据必须对应本次请求
                dl_offset <= dl_offset + 1'b1;              // 有效后才推进偏移
            end                                             // 结束 615A 响应处理
            if (rtc_valid && rtc_offset < 4) begin          // RTC 收到有效响应
                check(rd_data === {4'd3, rtc_offset[3:0]}, "RTC response matches current offset");  // 数据必须对应本次请求
                rtc_offset <= rtc_offset + 1'b1;            // 有效后才推进偏移
            end                                             // 结束 RTC 响应处理
        end                                                 // 结束正常工作分支
    end                                                     // 结束代理消费者
    integer k;                                              // 应用流水字节索引
    initial begin                                           // 执行回归
        repeat (3) @(negedge clk);                          // 保持初始复位
        rst_b = 1'b1;                                       // 释放复位
        for (k = 0; k < 6; k = k + 1) begin                 // 应用连续六拍发起六次不同地址请求
            @(negedge clk); app_req = 1'b1; app_offset = k;  // 每周期提供一个新地址
            @(posedge clk); #1;                             // 等待一拍 RAM 结果
            check(app_valid && (rd_data === {4'd4, app_offset[3:0]}), "application retains one-byte-per-cycle throughput");  // 不允许门控应用连续读
        end                                                 // 结束应用流水检查
        @(negedge clk); app_req = 1'b0;                     // 释放应用优先级
        repeat (2) @(negedge clk);                          // 等待应用响应排空
        run_agents = 1'b1;                                  // 同时启动三个协议代理
        repeat (35) @(negedge clk);                         // 覆盖三路各四次读取与优先级等待
        check((snmp_offset == 4) && (dl_offset == 4) && (rtc_offset == 4), "all waiting protocol agents complete four ordered reads");  // 所有代理最终完成
        $display("RD_ARB_REGRESSION checks=%0d failures=%0d", checks, failures);  // 打印总体结果
        if (failures != 0) $fatal(1, "read arbitration regression failed");  // 失败时非成功结束
        $finish;                                            // 正常结束仿真
    end                                                     // 结束回归激励
endmodule                                                   // 结束测试模块

`timescale 1ns/1ps                                          // 仿真时间单位与精度
// ==================== 固定模板编码器的数据位段与背压回归 ====================
module tb_snmp_encoder_regression;                          // 仅验证既有固定模板的数据通路
    reg clk;                                                // 仿真系统时钟
    reg rst_b;                                              // 低有效复位
    reg enc_req;                                            // 编码启动请求
    reg [15:0] oid;                                         // 内部对象索引
    reg [31:0] value;                                       // 查询返回值
    reg [3:0] grant_phase;                                  // 发送授权暂停计数
    wire grant;                                             // 当前字节写授权
    wire tx_en;                                             // 当前字节写请求
    wire [10:0] offset;                                     // 当前字节写偏移
    wire [7:0] data;                                        // 当前写字节
    wire done;                                              // 编码完成脉冲
    reg [7:0] captured [0:50];                              // 实际获授权写出的固定模板
    integer accepted;                                       // 已接受字节数
    integer failures;                                       // 自检失败数量
    integer timeout_count;                                  // 有界等待计数

    always #5 clk = ~clk;                                   // 一百兆赫仿真时钟
    assign grant = tx_en && (grant_phase[1:0] != 2'b10);    // 在输出过程中插入仲裁暂停
    snmp_encoder dut (                                      // 例化原有固定模板编码器
        .clk(clk),                                          // 系统时钟
        .rst_b(rst_b),                                      // 系统复位
        .enc_req(enc_req),                                  // 编码启动请求
        .oid(oid),                                          // 本次锁存的内部对象索引
        .value(value),                                      // 本次锁存的查询值
        .tx_wr_gnt(grant),                                  // 带暂停的发送授权
        .tx_wr_en(tx_en),                                   // 编码字节写请求
        .tx_wr_byte_offset(offset),                         // 编码字节写偏移
        .tx_wr_data(data),                                  // 编码字节写数据
        .enc_done(done)                                     // 编码完成返回
    );                                                      // 结束模块连接

    always @(posedge clk or negedge rst_b) begin            // 记录每个被接受的字节
        if (!rst_b) begin                                   // 复位统计与仲裁相位
            grant_phase <= 4'd0;                            // 初始授权相位
            accepted = 0;                                   // 清空已接受字节数
        end                                                 // 结束复位分支
        else begin                                          // 运行编码检查
            grant_phase <= grant_phase + 4'd1;              // 推进授权周期
            if (tx_en && grant) begin                       // 只有授权时才记录数据
                if (offset != accepted) failures = failures + 1;  // 每个字节偏移必须连续
                captured[offset] = data;                    // 保存被实际接受的字节
                accepted = accepted + 1;                    // 推进已接受字节数
            end                                             // 结束写授权分支
        end                                                 // 结束运行分支
    end                                                     // 结束字节采样过程

    initial begin                                           // 回归主流程
        clk = 1'b0;                                         // 初始化时钟
        rst_b = 1'b0;                                       // 初始化复位
        enc_req = 1'b0;                                     // 初始没有编码请求
        oid = {1'b1, 12'hABC, 3'd4};                        // 覆盖非零高地址组与高位表选择
        value = 32'h12345678;                               // 设置四字节已知查询结果
        failures = 0;                                       // 初始化自检失败数量
        repeat (5) @(negedge clk);                          // 保持若干系统周期复位
        rst_b = 1'b1;                                       // 非采样沿释放复位
        @(negedge clk);                                     // 准备启动编码
        enc_req = 1'b1;                                     // 编码请求拉高一个周期
        @(negedge clk);                                     // 等待启动被采样
        enc_req = 1'b0;                                     // 撤销编码请求
        oid = 16'd0;                                        // 编码期间改变输入以验证已锁存数据
        value = 32'd0;                                      // 编码期间改变输入以验证锁存查询结果
        timeout_count = 0;                                  // 初始化有界等待
        while (!done && (timeout_count < 500)) begin        // 等待完整固定模板编码
            @(negedge clk);                                 // 在写采样结束后检查进度
            timeout_count = timeout_count + 1;              // 累计等待系统周期
        end                                                 // 结束有界等待
        if (!done || (accepted != 51)) failures = failures + 1;  // 固定模板必须完整写出五十一个字节
        if ((captured[41] !== 8'h01) ||                     // 表选择必须保留
            (captured[42] !== 8'h95) ||                     // 地址高组应为续标志与高五位
            (captured[43] !== 8'h3C) ||                     // 地址低组应为低七位
            (captured[44] !== 8'h04) ||                     // 计数器编号必须保留
            ({captured[47], captured[48], captured[49], captured[50]} !== 32'h12345678))  // 查询值必须大端且锁存
            failures = failures + 1;                        // 累计字段编码失败
        if (failures == 0)                                  // 汇总固定模板数据通路结果
            $display("PASS: SNMP fixed-template VL address groups, latching and write backpressure");  // 输出成功标记
        else                                                // 存在数据通路错误
            $display("FAIL: SNMP encoder regression failures=%0d", failures);  // 输出失败统计
        $finish;                                            // 结束本次仿真
    end                                                     // 结束回归主流程
endmodule                                                   // 结束测试模块

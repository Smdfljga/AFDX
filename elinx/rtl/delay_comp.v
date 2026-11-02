// delay_comp : 时钟同步延迟补偿
// 用主时钟时间戳、链路延迟与本地接收处理延迟算出校正后的时间戳
// 注：补偿计算已实现，calc_done 与 corrected_ts 同拍有效
module delay_comp #(                                        // 声明模块及其参数接口
    parameter RTC_WIDTH = 48                // RTC 计数器位宽
)(                                                          // 参数声明结束，开始端口声明
    // 时钟与复位
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // 计算输入
    input  wire [RTC_WIDTH-1:0]          master_ts,              // 主时钟时间戳
    input  wire [31:0]                   delay_val,              // 链路延迟计数值
    input  wire [31:0]                   rx_process_delay,       // 本地接收处理延迟（ns）
    input  wire                          calc_req,               // 计算请求

    // 计算结果
    output wire [RTC_WIDTH-1:0]          corrected_ts,           // 校正后时间戳
    output wire                          calc_done               // 计算完成
);                                                          // 端口声明或模块例化结束

    // ==================== 单位换算与计算 ====================
    wire [RTC_WIDTH-1:0] proc_delay_us = rx_process_delay / 1000; // ns 折算成 us，参数通常为常量
    wire [RTC_WIDTH:0]   sum =                              // 加宽一位合并主时钟、网络延迟和本地处理延迟
        {1'b0, master_ts} + {1'b0, {16'd0, delay_val}} + {1'b0, proc_delay_us}; // 主时钟时刻 + 链路延迟 + 处理延迟

    reg [RTC_WIDTH-1:0] corrected_r;                            // 计算结果寄存器
    reg                 done_r;                                 // 完成脉冲

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            corrected_r <= {RTC_WIDTH{1'b0}};               // 时钟沿更新计算结果寄存器
            done_r      <= 1'b0;                            // 时钟沿更新完成脉冲
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            if (calc_req)                                   // 检查计算请求的条件
                corrected_r <= sum[RTC_WIDTH-1:0];              // 低 RTC_WIDTH 位自然模 2^RTC_WIDTH
            done_r <= calc_req;                             // 时钟沿更新完成脉冲
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    assign corrected_ts = corrected_r;                          // output [47:0]
    assign calc_done    = done_r;                               // output [0:0]：与结果同拍有效

endmodule                                                   // 模块定义结束

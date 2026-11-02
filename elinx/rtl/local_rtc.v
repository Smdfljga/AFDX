// local_rtc : 本地 RTC 计数器
// 按节拍递增，收到同步校正值时被写入（可加平滑/微调，视实现而定）
// 注：1us 计数与同步装载逻辑已实现
module local_rtc #(                                         // 声明模块及其参数接口
    parameter RTC_WIDTH = 48                // RTC 计数器位宽
)(                                                          // 参数声明结束，开始端口声明
    // 时钟与复位
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // 同步校正
    input  wire                          sync_en,                // 同步使能，单拍有效时装载校正值
    input  wire [RTC_WIDTH-1:0]          sync_value,             // 同步校正值

    // 主时钟广播周期（用于产生同步节拍）
    input  wire [15:0]                   sync_period_ms,         // 主时钟广播周期，单位 ms

    // 输出
    output wire [RTC_WIDTH-1:0]          rtc_value,              // 当前 RTC 值
    output wire                          rtc_tick                // 同步节拍脉冲（每 sync_period_ms 一拍，供主时钟广播用）
);                                                          // 端口声明或模块例化结束

    // ==================== 分频参数 ====================
    localparam US_DIV = 25;                                     // 核心 25MHz 时钟 25 分频后得到 1us 节拍

    reg [6:0]  us_cnt;                                          // 微秒分频计数，0 ~ US_DIV-1
    reg [9:0]  us_in_ms;                                    // 毫秒内的微秒计数，0~999
    reg [15:0] ms_cnt;                                          // 毫秒计数，0 ~ sync_period_ms-1
    reg [RTC_WIDTH-1:0] rtc_r;                                  // 当前 RTC 值

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            us_cnt <= 7'd0;                                 // 时钟沿更新微秒分频计数
            us_in_ms <= 10'd0;                              // 复位毫秒内的微秒相位
            ms_cnt <= 16'd0;                                // 时钟沿更新毫秒计数
            rtc_r  <= {RTC_WIDTH{1'b0}};                    // 时钟沿更新当前 RTC 值
        end                                                 // 当前语句组结束
        else if (sync_en) begin                             // 检查同步使能的条件
            us_cnt <= 7'd0;                                 // 时钟沿更新微秒分频计数
            us_in_ms <= 10'd0;                              // 校正时同时重新对齐毫秒相位
            ms_cnt <= 16'd0;                                // 时钟沿更新毫秒计数
            rtc_r  <= sync_value;                               // 同步使能优先，直接装载校正值
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            if (us_cnt == (US_DIV - 1)) begin               // 检查微秒分频计数、25MHz 时钟 25 分频后得到 1us 节拍的条件
                us_cnt <= 7'd0;                             // 时钟沿更新微秒分频计数
                rtc_r  <= rtc_r + 1'b1;                         // 每 1us 递增
                if (us_in_ms == 10'd999) begin              // 一千个微秒组成一个毫秒
                    us_in_ms <= 10'd0;                      // 进入下一毫秒
                    if ((sync_period_ms == 16'd0) ||        // 零周期禁止广播并清周期计数
                        (ms_cnt >= sync_period_ms - 16'd1))  // 达到周期后从零开始
                        ms_cnt <= 16'd0;                    // 重新累计广播周期
                    else                                    // 继续累计尚未完成的毫秒周期
                        ms_cnt <= ms_cnt + 16'd1;           // 每一毫秒只增加一次
                end                                         // 结束毫秒边界处理
                else begin                                  // 当前毫秒尚未结束
                    us_in_ms <= us_in_ms + 10'd1;           // 每一微秒推进毫秒内计数
                end                                         // 结束毫秒内计数处理
            end                                             // 当前语句组结束
            else begin                                      // 前一条件不满足时执行本分支
                us_cnt <= us_cnt + 7'd1;                    // 时钟沿更新微秒分频计数并推进至下一项
            end                                             // 当前语句组结束
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    assign rtc_value = rtc_r;                                   // output [47:0]：当前 RTC

    // 一个同步周期只产生一拍，主模式由 rtc_sync 把它接到 rtc_tx.tx_req。
    assign rtc_tick = !sync_en &&                           // 校正装载时禁止同拍产生主时钟广播
                      (sync_period_ms != 16'd0) &&          // 继续计算rtc_tick
                      (us_cnt == (US_DIV - 1)) &&           // 继续计算rtc_tick
                      (us_in_ms == 10'd999) &&              // 只在完整毫秒边界产生广播脉冲
                      (ms_cnt == sync_period_ms - 16'd1);       // output [0:0]

endmodule                                                   // 模块定义结束

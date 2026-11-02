`timescale 1ns/1ps                                          // 仿真时间单位与精度
// ==================== 实际二十五兆赫与毫秒广播周期回归 ====================
module tb_local_rtc_regression;                             // 检查微秒计数与毫秒节拍的单位
    reg clk;                                                // 系统时钟
    reg rst_b;                                              // 低有效复位
    reg sync_en;                                            // 同步校正装载请求
    reg [47:0] sync_value;                                  // 同步校正值
    reg [15:0] sync_period_ms;                              // 毫秒广播周期
    wire [47:0] rtc_value;                                  // 本地微秒时间
    wire rtc_tick;                                          // 广播节拍
    integer failure_count;                                  // 自检失败数量
    integer i;                                              // 周期检查循环变量
    integer ticks;                                          // 本轮观察到的广播脉冲数
    integer last_tick_cycle;                                // 上一次广播脉冲位置

    always #20 clk = ~clk;                                  // 二十五兆赫系统时钟（40ns 周期）
    local_rtc dut (                                         // 例化实际本地时钟模块
        .clk(clk),                                          // 系统时钟
        .rst_b(rst_b),                                      // 系统复位
        .sync_en(sync_en),                                  // 同步校正装载使能
        .sync_value(sync_value),                            // 同步校正值
        .sync_period_ms(sync_period_ms),                    // 运行期广播周期
        .rtc_value(rtc_value),                              // 观察微秒计数
        .rtc_tick(rtc_tick)                                 // 观察广播脉冲
    );                                                      // 结束模块连接

    task align_clock;                                       // 用接口重新对齐全部分频相位
        input [47:0] new_value;                             // 新装载的时间值
        begin                                               // 开始相位对齐任务
            @(negedge clk);                                 // 在非采样沿设置校正接口
            sync_value = new_value;                         // 准备校正后的本地时钟值
            sync_en = 1'b1;                                 // 拉高同步校正装载请求
            @(negedge clk);                                 // 等待被采样沿装载一次
            sync_en = 1'b0;                                 // 撤销同步校正请求
            if (rtc_value !== new_value) begin              // 校正必须立即反映在计数输出
                $display("FAIL: RTC correction load");      // 输出装载错误
                failure_count = failure_count + 1;          // 累计失败数量
            end                                             // 结束校正检查
        end                                                 // 结束相位对齐任务主体
    endtask                                                 // 结束相位对齐任务

    task check_period;                                      // 验证多个完整毫秒周期
        input integer period_ms;                            // 当前广播周期毫秒数
        input integer repetitions;                          // 连续观察多少次广播
        integer cycle_index;                                // 当前系统时钟序号
        integer expected_spacing;                           // 每次广播间隔的系统时钟数
        begin                                               // 开始周期检查任务
            sync_period_ms = period_ms;                     // 通过真实配置接口设置周期
            align_clock(48'd0);                             // 用同步接口对齐相位而非强制内部寄存器
            ticks = 0;                                      // 清本轮广播统计
            last_tick_cycle = 0;                            // 第一脉冲也必须等完整周期
            expected_spacing = period_ms * 25000;           // 一毫秒对应二十五兆赫下二万五千个时钟
            for (cycle_index = 1;                           // 从装载后的第一个系统时钟开始计数
                 cycle_index <= expected_spacing * repetitions;  // 覆盖若干完整周期
                 cycle_index = cycle_index + 1) begin       // 推进观察系统时钟序号
                @(posedge clk);                             // 在广播脉冲被下游采样的沿检查
                if (rtc_tick) begin                         // 捕获实际广播脉冲
                    if (cycle_index - last_tick_cycle != expected_spacing) begin  // 验证精确毫秒间隔
                        $display("FAIL: RTC period ms=%0d interval=%0d", period_ms, cycle_index - last_tick_cycle);  // 输出广播间隔错误
                        failure_count = failure_count + 1;  // 累计失败数量
                    end                                     // 结束广播间隔检查
                    last_tick_cycle = cycle_index;          // 保存本次脉冲位置
                    ticks = ticks + 1;                      // 累计广播脉冲
                end                                         // 结束广播脉冲检查
            end                                             // 结束周期观察循环
            @(negedge clk);                                 // 等待最后采样沿的计数更新完成
            if ((ticks != repetitions) ||                   // 检查整个观察区间的脉冲总数
                (rtc_value !== period_ms * repetitions * 1000)) begin  // 检查同一时间跨度的微秒计数
                $display("FAIL: RTC ms=%0d ticks=%0d rtc=%0d", period_ms, ticks, rtc_value);  // 输出周期及单位错误
                failure_count = failure_count + 1;          // 累计失败数量
            end                                             // 结束本轮综合检查
        end                                                 // 结束周期检查任务主体
    endtask                                                 // 结束周期检查任务

    initial begin                                           // 回归主流程
        clk = 1'b0;                                         // 初始化时钟
        rst_b = 1'b0;                                       // 初始化低有效复位
        sync_en = 1'b0;                                     // 初始无校正请求
        sync_value = 48'd0;                                 // 初始校正值为零
        sync_period_ms = 16'd1;                             // 设置最短非零广播周期
        failure_count = 0;                                  // 清失败统计
        repeat (5) @(negedge clk);                          // 保持复位若干系统周期
        rst_b = 1'b1;                                       // 在非采样沿释放复位
        align_clock(48'd0);                                 // 重新对齐首个微秒边界
        repeat (1000) @(posedge clk);                       // 运行一千个系统时钟，即四十微秒
        @(negedge clk);                                     // 等待计数更新结束
        if (rtc_value !== 48'd40) begin                     // 检查二十五兆赫除二十五的微秒计数
            $display("FAIL: RTC microsecond divider");      // 输出微秒分频错误
            failure_count = failure_count + 1;              // 累计失败数量
        end                                                 // 结束微秒计数检查
        check_period(1, 3);                                 // 检查连续三个一毫秒广播周期
        check_period(2, 2);                                 // 检查连续两个二毫秒广播周期
        sync_period_ms = 16'd0;                             // 零周期禁止广播
        align_clock(48'd123456);                            // 装载非零时间并重新对齐相位
        for (i = 0; i < 30000; i = i + 1) begin             // 继续运行一千二百微秒（超过一毫秒）
            @(posedge clk);                                 // 检查每个采样沿
            if (rtc_tick) failure_count = failure_count + 1;  // 零周期期间不允许产生任何广播脉冲
        end                                                 // 结束禁止广播检查
        @(negedge clk);                                     // 等待最后计数沿更新完成
        if (rtc_value !== 48'd124656)                       // 广播关闭期间本地微秒时间仍自由递增
            failure_count = failure_count + 1;              // 累计自由运行失败
        check_period(1, 1);                                 // 从零周期恢复后仍需等待完整一毫秒
        align_clock(48'd0);                                 // 对齐校正与广播同时到达的边界测试
        repeat (24999) @(posedge clk);                      // 推进到首个一毫秒边界之前一拍
        @(negedge clk);                                     // 在广播将被采样前设置校正请求
        sync_value = 48'd400;                               // 准备本次边界校正值
        sync_en = 1'b1;                                     // 校正必须优先于同拍广播
        #1;                                                 // 等待组合广播抑制逻辑稳定
        if (rtc_tick) failure_count = failure_count + 1;    // 校正装载期间禁止产生广播请求
        @(negedge clk);                                     // 等待校正值被时钟沿装载
        sync_en = 1'b0;                                     // 撤销校正使能
        if (rtc_value !== 48'd400)                          // 校正值必须覆盖同拍自由递增
            failure_count = failure_count + 1;              // 累计校正优先级失败
        if (failure_count == 0)                             // 汇总全部自检结果
            $display("PASS: RTC real25MHz us counter, 1ms/2ms periods, correction and zero-period restart");  // 输出成功标记
        else                                                // 存在自检错误
            $display("FAIL: RTC regression failures=%0d", failure_count);  // 输出失败统计
        $finish;                                            // 正常结束仿真
    end                                                     // 结束回归主流程
endmodule                                                   // 结束本地时钟测试模块

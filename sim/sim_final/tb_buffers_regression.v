`timescale 1ns/1ps                                          // 时间单位为纳秒，精度为皮秒
module tb_buffers_regression;                               // 缓冲与状态表自检入口
    reg clk = 1'b0;                                         // 系统时钟
    always #5 clk = ~clk;                                   // 产生一百兆赫时钟
    reg rst_b = 1'b0;                                       // 低有效复位
    integer failures = 0;                                   // 失败总数
    integer checks = 0;                                     // 检查总数
    reg [3:0] done = 4'd0;                                  // 四路帧尾事件
    wire len_en;                                            // 长度登记使能
    wire [3:0] len_vl;                                      // 长度登记槽位
    wire [10:0] len_off;                                    // 末字节偏移
    reg [15:0] done_seen = 16'd0;                           // 已登记槽位集合
    integer done_count = 0;                                 // 已登记事件数
    tx_wr_arb arb (                                         // 四路发送写仲裁
        .clk(clk), .rst_b(rst_b),                           // 时钟与复位
        .app_wr_req(1'b0), .app_wr_vl_index(4'd4), .app_wr_byte_offset(11'd7), .app_wr_data(8'd0), .app_frame_done(done[0]),  // 应用事件
        .snmp_wr_req(1'b0), .snmp_wr_vl_index(4'd1), .snmp_wr_byte_offset(11'd8), .snmp_wr_data(8'd0), .snmp_frame_done(done[1]),  // SNMP 事件
        .dl_wr_req(1'b0), .dl_wr_vl_index(4'd2), .dl_wr_byte_offset(11'd9), .dl_wr_data(8'd0), .dl_frame_done(done[2]),  // 615A 事件
        .rtc_wr_req(1'b0), .rtc_wr_vl_index(4'd3), .rtc_wr_byte_offset(11'd10), .rtc_wr_data(8'd0), .rtc_frame_done(done[3]),  // RTC 事件
        .vl_busy(16'd0), .buf_len_wr_en(len_en), .buf_len_vl_index(len_vl), .buf_len_byte_offset(len_off),  // 观测登记端口
        .buf_wr_en(), .buf_wr_vl_index(), .buf_wr_byte_offset(), .buf_wr_data(),  // 本用例不用数据写端口
        .app_wr_gnt(), .snmp_wr_gnt(), .dl_wr_gnt(), .rtc_wr_gnt()  // 本用例不用写授权
    );                                                      // 结束写仲裁例化
    always @(posedge clk) begin                             // 在实际登记沿统计事件
        if (!rst_b) begin                                   // 复位监视器
            done_seen <= 16'd0;                             // 清空槽位集合
            done_count <= 0;                                // 清空计数
        end else if (len_en) begin                          // 记录有效事件
            done_seen[len_vl] <= 1'b1;                      // 标记槽位
            done_count <= done_count + 1;                   // 累加事件
        end                                                 // 结束事件判断
    end                                                     // 结束监视器
    reg wr_en = 1'b0;                                       // 接收缓冲写使能
    reg [3:0] wr_vl = 4'd5;                                 // 写槽位
    reg [10:0] wr_off = 11'd0;                              // 写偏移
    reg [7:0] wr_data = 8'd0;                               // 写字节
    reg frame_done = 1'b0;                                  // 帧提交使能
    reg [15:0] frame_len = 16'd0;                           // 整帧应用数据长度
    reg queue_mode = 1'b1;                                  // 队列或采样模式
    wire full;                                              // 缓冲满标志
    reg rd_en = 1'b0;                                       // 接收缓冲读使能
    reg [3:0] rd_vl = 4'd5;                                 // 读槽位
    reg [10:0] rd_off = 11'd0;                              // 读偏移
    wire [7:0] rd_data;                                     // 一拍读数据
    wire rd_valid;                                          // 一拍读有效
    wire [255:0] lengths;                                   // 各槽位队首帧长
    wire [63:0] counts;                                     // 各槽位帧数
    rx_port_buf rx (                                        // 接收缓冲
        .clk(clk), .rst_b(rst_b), .wr_en(wr_en), .wr_vl_index(wr_vl), .wr_byte_offset(wr_off), .wr_data(wr_data),  // 字节写接口
        .wr_frame_done(frame_done), .wr_frame_len(frame_len), .wr_queue_mode(queue_mode), .wr_full(full),  // 帧提交接口
        .rd_en(rd_en), .rd_vl_index(rd_vl), .rd_byte_offset(rd_off), .rd_data(rd_data), .rd_valid(rd_valid),  // 一拍读接口
        .rd_frame_len_all(lengths), .rd_frame_cnt_all(counts)  // 状态接口
    );                                                      // 结束接收缓冲例化
    reg st_wa = 1'b0;                                       // RX 状态写使能
    reg st_wb = 1'b0;                                       // TX 状态写使能
    reg [11:0] st_addr_a = 12'd7;                           // RX 状态地址
    reg [11:0] st_addr_b = 12'd7;                           // TX 状态地址
    reg [63:0] st_da = 64'd0;                               // RX 状态写入字
    reg [63:0] st_db = 64'd0;                               // TX 状态写入字
    wire [63:0] st_qa;                                      // RX 状态读结果
    wire [63:0] st_qb;                                      // TX 状态读结果
    vl_state_ram states (                                   // 双端口状态表
        .clk_a(clk), .rst_a(~rst_b), .addr_a(st_addr_a), .rd_en_a(1'b1), .rd_data_a(st_qa), .wr_en_a(st_wa), .wr_data_a(st_da),  // RX 端口
        .clk_b(clk), .rst_b(~rst_b), .addr_b(st_addr_b), .rd_en_b(1'b1), .rd_data_b(st_qb), .wr_en_b(st_wb), .wr_data_b(st_db)  // TX 端口
    );                                                      // 结束状态表例化
    task check;                                             // 自检任务
        input condition;                                    // 期望为真的条件
        input [511:0] name;                                 // 检查说明
        begin                                               // 开始检查
            checks = checks + 1;                            // 累加检查数
            if (condition !== 1'b1) begin                   // 未知值也判为失败
                failures = failures + 1;                    // 累加失败数
                $display("[FAIL] %0s", name);               // 输出失败原因
            end else $display("[PASS] %0s", name);          // 输出检查通过
        end                                                 // 结束检查
    endtask                                                 // 结束自检任务
    task reset_all;                                         // 执行热复位
        begin                                               // 开始复位
            @(negedge clk); rst_b = 1'b0; wr_en = 1'b0; rd_en = 1'b0; frame_done = 1'b0; done = 4'd0; st_wa = 1'b0; st_wb = 1'b0;  // 撤销全部请求
            repeat (3) @(negedge clk);                      // 保持复位三个周期
            rst_b = 1'b1;                                   // 释放复位
            @(negedge clk);                                 // 等待稳定
        end                                                 // 结束复位
    endtask                                                 // 结束复位任务
    task put_frame;                                         // 写入并提交一帧
        input integer n;                                    // 帧长
        input [7:0] seed;                                   // 首字节数值
        integer k;                                          // 字节下标
        begin                                               // 开始写帧
            frame_len = n;                                  // 从帧首起稳定给出帧长
            for (k = 0; k < n; k = k + 1) begin             // 顺序写全部字节
                @(negedge clk); wr_en = 1'b1; wr_off = k; wr_data = seed + k;  // 本拍写入一个字节
            end                                             // 结束字节循环
            @(negedge clk); wr_en = 1'b0; frame_done = 1'b1;  // 提交整帧
            @(negedge clk); frame_done = 1'b0;              // 撤销提交脉冲
        end                                                 // 结束写帧
    endtask                                                 // 结束写帧任务
    task get_byte;                                          // 读取并检查一个字节
        input integer offset;                               // 帧内偏移
        input [7:0] expected_data;                          // 期望数据
        begin                                               // 开始读字节
            @(negedge clk); rd_en = 1'b1; rd_off = offset;  // 给出读请求
            @(posedge clk); #1;                             // 等待同步 RAM 更新
            check(rd_valid && (rd_data === expected_data), "RX one-cycle read data");  // 数据与有效必须同拍
            @(negedge clk); rd_en = 1'b0;                   // 撤销读请求
        end                                                 // 结束读字节
    endtask                                                 // 结束读字节任务
    initial begin                                           // 开始回归激励
        reset_all;                                          // 初始化被测逻辑
        done = 4'b1111;                                     // 四路帧尾同拍到达
        @(negedge clk); done = 4'd0;                        // 撤销脉冲
        repeat (7) @(negedge clk);                          // 等待登记队列排空
        check((done_count == 4) && (done_seen == 16'h001E), "four simultaneous frame-done events preserved");  // 四不能截断成零
        reset_all;                                          // 隔离并发队列用例
        queue_mode = 1'b1;                                  // 采用队列模式
        put_frame(2, 8'h10);                                // 写第一帧
        put_frame(2, 8'h20);                                // 写第二帧
        get_byte(0, 8'h10);                                 // 读取第一帧首字节
        @(negedge clk); wr_en = 1'b1; wr_off = 0; wr_data = 8'h30; frame_len = 1;  // 写第三帧数据
        @(negedge clk); wr_en = 1'b0; frame_done = 1'b1; rd_en = 1'b1; rd_off = 1;  // 同槽入队与出队同拍发生
        @(negedge clk); frame_done = 1'b0; rd_en = 1'b0;    // 撤销并发操作
        check(counts[20 +: 4] == 2, "same-slot enqueue/dequeue keep net frame count");  // 两帧减一加一仍为两帧
        reset_all;                                          // 隔离空间保护用例
        put_frame(1024, 8'h31);                             // 写满前半槽
        put_frame(1024, 8'h51);                             // 写满后半槽
        frame_len = 1;                                      // 新帧需要一个字节空间
        @(negedge clk); wr_en = 1'b1; wr_off = 0; wr_data = 8'hFF;  // 满时尝试破坏队首
        @(negedge clk); wr_en = 1'b0;                       // 撤销非法写入
        get_byte(0, 8'h31);                                 // 未读队首必须保持原值
        reset_all;                                          // 隔离最大长度用例
        put_frame(2048, 8'h00);                             // 写满整个槽位
        check(lengths[80 +: 16] == 2048, "length 2048 remains representable");  // 帧长不能截成零
        reset_all;                                          // 隔离顺序读保护用例
        put_frame(3, 8'h60);                                // 写入三字节帧
        get_byte(2, 8'h62);                                 // 故意跳读末字节
        check(counts[20 +: 4] == 1, "jumping to tail must not dequeue");  // 跳读不能误弹出队首
        reset_all;                                          // 隔离采样覆盖用例
        put_frame(2, 8'h70);                                // 推进队列写指针
        get_byte(0, 8'h70);                                 // 读队首首字节
        get_byte(1, 8'h71);                                 // 读队首尾字节
        queue_mode = 1'b0;                                  // 切换采样覆盖模式
        put_frame(1, 8'hAA);                                // 首字节必须写到槽内零地址
        get_byte(0, 8'hAA);                                 // 最新采样值必须可读
        reset_all;                                          // 隔离状态字段保护用例
        @(negedge clk); st_wa = 1'b1; st_da = 64'h000000000000015A;  // RX 写低位字段
        @(negedge clk); st_wa = 1'b0; st_wb = 1'b1; st_db = 64'h1234567801A50000;  // TX 用旧快照写高位字段
        @(negedge clk); st_wb = 1'b0;                       // 结束 TX 写入
        repeat (2) @(negedge clk);                          // 等待一拍读回
        check((st_qa == 64'h1234567801A5015A) && (st_qb == 64'h1234567801A5015A), "TX preserves latest RX fields");  // RX 新值不得丢失
        st_wa = 1'b1; st_wb = 1'b1; st_da = 64'h000000000000016B; st_db = 64'h8765432101B60000;  // 同址同时写各自字段
        @(negedge clk); st_wa = 1'b0; st_wb = 1'b0;         // 结束并发写入
        repeat (2) @(negedge clk);                          // 等待一拍读回
        check((st_qa == 64'h8765432101B6016B) && (st_qb == 64'h8765432101B6016B), "same-address RX/TX writes both survive");  // 两方字段都必须保留
        reset_all;                                          // 热复位不依赖模型清除存储阵列
        repeat (2) @(negedge clk);                          // 等待旧地址再次读回
        check((st_qa == 64'd0) && (st_qb == 64'd0), "hot reset invalidates retained RAM state");  // 复位后不得再暴露旧状态
        $display("BUFFER_REGRESSION checks=%0d failures=%0d", checks, failures);  // 汇报总体结果
        if (failures != 0) $fatal(1, "buffer regression failed");  // 失败时非成功结束
        $finish;                                            // 正常结束仿真
    end                                                     // 结束回归激励
endmodule                                                   // 结束测试模块

`timescale 1ns/1ps                                          // 仿真时间单位与精度
// ==================== 615A 包装层与同步 FIFO 集成回归 ====================
module tb_615a_fifo_regression;                             // 测试实际数据加载包装层
    reg clk;                                                // 系统仿真时钟
    reg rst_b;                                              // 低有效系统复位
    reg start;                                              // 收到一帧的启动脉冲
    reg [15:0] frame_len;                                   // 当前请求实际字节长度
    reg [7:0] request_mem [0:1023];                         // 待发送的完整 TFTP 请求
    wire rx_req;                                            // 被测模块的缓冲读请求
    wire [10:0] rx_offset;                                  // 被测模块的缓冲读偏移
    reg [7:0] rx_data;                                      // 同步 RAM 返回的数据
    reg rx_valid;                                           // 同步 RAM 返回的数据有效
    reg read_pending;                                       // 同一请求在返回前只接受一次
    wire tx_en;                                             // ACK 字节写请求
    wire [10:0] tx_offset;                                  // ACK 字节位置
    wire [7:0] tx_data;                                     // ACK 当前字节
    wire frame_done;                                        // ACK 最后一字节握手成功
    wire tx_grant;                                          // 模拟写仲裁授权
    reg [3:0] grant_phase;                                  // 产生周期性写暂停
    wire load_busy;                                         // 传输进行标志
    wire load_done;                                         // 文件加载完成标志
    wire load_error;                                        // 文件加载错误标志
    reg [31:0] ack_capture;                                 // 按偏移保存实际被接受的 ACK
    integer failure_count;                                  // 自检失败数量
    integer flash_count;                                    // 当前帧的器件写入次数
    integer ack_count;                                      // 当前帧的 ACK 字节接受数量
    integer completed_count;                                // 已发送完成的 ACK 数量
    integer expected_block;                                 // 当前期望块号
    integer expected_length;                                // 当前期望净荷长度
    integer expected_seed;                                  // 当前数据模式种子
    integer full_seen;                                      // 实际 FIFO 置满次数
    integer i;                                              // 请求生成循环变量

    always #5 clk = ~clk;                                   // 一百兆赫系统时钟
    assign tx_grant = tx_en && (grant_phase[1:0] != 2'b01);  // 每四拍插入一次写仲裁暂停

    data_loader_615a dut (                                  // 例化完整包装层而非单独协议子模块
        .clk(clk),                                          // 系统时钟
        .rst_b(rst_b),                                      // 系统低有效复位
        .rx_ready_615a(start),                              // 一帧接收通知
        .rx_rd_req(rx_req),                                 // 返回同步 RAM 读请求
        .rx_rd_byte_offset(rx_offset),                      // 返回同步 RAM 读地址
        .rx_rd_data(rx_data),                               // 输入同步 RAM 返回值
        .rx_rd_valid(rx_valid),                             // 输入一拍后的返回有效
        .rx_frame_len(frame_len),                           // 输入当前整帧净荷长度
        .tx_wr_en(tx_en),                                   // 返回 ACK 写使能
        .tx_wr_byte_offset(tx_offset),                      // 返回 ACK 写偏移
        .tx_wr_data(tx_data),                               // 返回 ACK 写字节
        .tx_frame_done(frame_done),                         // 返回 ACK 帧尾握手
        .tx_wr_gnt(tx_grant),                               // 输入带暂停的写授权
        .load_busy(load_busy),                              // 返回加载状态
        .load_done(load_done),                              // 返回文件完成状态
        .load_error(load_error)                             // 返回加载错误状态
    );                                                      // 结束包装层连接

    // ==================== 真实一拍同步读与单个在途请求 ====================
    always @(posedge clk or negedge rst_b) begin            // 同步 RAM 只在时钟沿更新读值
        if (!rst_b) begin                                   // 系统复位
            rx_data <= 8'd0;                                // 清空读返回字节
            rx_valid <= 1'b0;                               // 清空返回有效
            read_pending <= 1'b0;                           // 清空在途请求
            grant_phase <= 4'd0;                            // 复位仲裁暂停相位
        end                                                 // 结束复位分支
        else begin                                          // 正常读返回与仲裁
            grant_phase <= grant_phase + 4'd1;              // 推进仲裁周期
            rx_valid <= 1'b0;                               // 每次读返回只保持一拍
            if (read_pending) begin                         // 返回被消费者采样的周期
                read_pending <= 1'b0;                       // 等偏移更新后再接受下一次读
            end                                             // 结束在途请求分支
            else if (rx_req) begin                          // 只接受新的读请求
                if (rx_offset >= frame_len) begin           // 防止被测模块越过当前帧
                    $display("FAIL: RX offset out of frame");  // 报告越界读取
                    failure_count = failure_count + 1;      // 累计失败数量
                end                                         // 结束越界检测
                rx_data <= request_mem[rx_offset];          // 地址采样后更新同步 RAM 输出
                rx_valid <= 1'b1;                           // 与更新后的数据同拍有效
                read_pending <= 1'b1;                       // 标记本次返回正在被消费
            end                                             // 结束新读请求分支
        end                                                 // 结束正常工作分支
    end                                                     // 结束同步 RAM 模型

    // ==================== 检查实际 Flash 接口与写授权 ====================
    always @(posedge clk) begin                             // 在实际写入采样沿检查数据
        if (rst_b) begin                                    // 仅在复位释放后检查
            if (dut.u_file_buffer.rdfull)                   // 观察完整五百一十二字节块是否达到真实满状态
                full_seen = full_seen + 1;                  // 保存满标志出现次数
            if (dut.u_flash_ctrl.flash_wr_en) begin         // 观察包装层内部真实器件接口
                if (dut.u_flash_ctrl.flash_wr_addr !==      // 检查每一个实际写地址
                    expected_block * 512 + flash_count) begin  // 按项目约定块号乘五百一十二
                    $display("FAIL: Flash address index=%0d address=%0h", flash_count, dut.u_flash_ctrl.flash_wr_addr);  // 报告地址错位
                    failure_count = failure_count + 1;      // 累计失败数量
                end                                         // 结束地址检查
                if (dut.u_flash_ctrl.flash_wr_data !==      // 检查同步 FIFO 返回的每一个字节
                    ((flash_count + expected_seed) & 255)) begin  // 期望值使用可重复的数据模式
                    $display("FAIL: Flash data index=%0d data=%0h", flash_count, dut.u_flash_ctrl.flash_wr_data);  // 报告数据错位
                    failure_count = failure_count + 1;      // 累计失败数量
                end                                         // 结束数据检查
                flash_count = flash_count + 1;              // 仅实际器件写使能才累计字节
            end                                             // 结束 Flash 写检查
            if (tx_en && tx_grant) begin                    // 只记录已获授权的 ACK 字节
                case (tx_offset)                            // 按实际偏移拼回应答
                    11'd0: ack_capture[31:24] = tx_data;    // ACK 第一个字节
                    11'd1: ack_capture[23:16] = tx_data;    // ACK 操作码低字节
                    11'd2: ack_capture[15:8] = tx_data;     // ACK 块号高字节
                    11'd3: ack_capture[7:0] = tx_data;      // ACK 块号低字节
                    default: failure_count = failure_count + 1;  // 超过四个字节即报错
                endcase                                     // 结束 ACK 字节拼装
                ack_count = ack_count + 1;                  // 累计被接受的 ACK 字节
            end                                             // 结束 ACK 写检查
            if (frame_done)                                 // 末字节被接受才算完成
                completed_count = completed_count + 1;      // 累计应答完成数量
        end                                                 // 结束运行期检查
    end                                                     // 结束实际输出检查

    task send_current_frame;                                // 输入当前请求并等待完整应答
        integer target_completed;                           // 本次请求完成后的应答数量
        integer timeout_count;                              // 本次请求超时计数
        begin                                               // 开始发送任务
            @(negedge clk);                                 // 在非采样沿准备请求
            flash_count = 0;                                // 清本帧实际写字节数
            ack_count = 0;                                  // 清本帧实际 ACK 字节数
            ack_capture = 32'd0;                            // 清本帧应答缓存
            target_completed = completed_count + 1;         // 记录本次等待目标
            start = 1'b1;                                   // 触发一帧解析
            @(negedge clk);                                 // 保证启动脉冲覆盖一个采样沿
            start = 1'b0;                                   // 撤销启动脉冲
            timeout_count = 0;                              // 初始化有界等待
            while ((completed_count < target_completed) &&  // 等待实际应答完成
                   (timeout_count < 20000)) begin           // 最多等待两万个系统时钟
                @(negedge clk);                             // 在采样完成后检查进度
                timeout_count = timeout_count + 1;          // 推进超时计数
            end                                             // 结束等待循环
            if (completed_count != target_completed) begin  // 检测 FIFO 末字节死锁等异常
                $display("FAIL: 615A timeout state=%0d", dut.u_tftp.state);  // 报告卡住的协议状态
                failure_count = failure_count + 1;          // 累计失败数量
            end                                             // 结束超时检查
            if ((flash_count != expected_length) ||         // 检查实际写入字节总数
                (ack_count != 4) ||                         // 检查 ACK 恰好四个授权字节
                (ack_capture !== (32'h00040000 | expected_block)) ||  // 检查 ACK 内容与块号
                load_error || load_busy) begin              // 检查应答完成后的状态
                $display("FAIL: block=%0d writes=%0d ACK=%08h count=%0d busy=%0b error=%0b", expected_block, flash_count, ack_capture, ack_count, load_busy, load_error);  // 报告本帧统计
                failure_count = failure_count + 1;          // 累计失败数量
            end                                             // 结束本帧综合检查
        end                                                 // 结束发送任务主体
    endtask                                                 // 结束发送任务定义

    task prepare_data;                                      // 生成完整 DATA 帧
        input integer block_number;                         // 请求块号
        input integer data_length;                          // 净荷长度
        input integer data_seed;                            // 数据模式种子
        begin                                               // 开始准备数据
            frame_len = data_length + 4;                    // 加上操作码与块号四字节头
            expected_block = block_number;                  // 保存期望块号
            expected_length = data_length;                  // 保存期望写字节数
            expected_seed = data_seed;                      // 保存期望数据模式
            request_mem[0] = 8'h00;                         // TFTP 操作码高字节
            request_mem[1] = 8'h03;                         // TFTP DATA 操作码
            request_mem[2] = (block_number >> 8) & 255;     // 块号高字节
            request_mem[3] = block_number & 255;            // 块号低字节
            for (i = 0; i < data_length; i = i + 1)         // 遍历净荷字节
                request_mem[i + 4] = (i + data_seed) & 255;  // 创建可检查的数据序列
        end                                                 // 结束数据准备主体
    endtask                                                 // 结束数据准备任务

    initial begin                                           // 回归主流程
        clk = 1'b0;                                         // 初始化时钟
        rst_b = 1'b0;                                       // 保持初始复位
        start = 1'b0;                                       // 初始无接收触发
        frame_len = 16'd0;                                  // 初始无请求长度
        failure_count = 0;                                  // 初始化失败统计
        flash_count = 0;                                    // 初始化实际写统计
        ack_count = 0;                                      // 初始化实际 ACK 统计
        completed_count = 0;                                // 初始化应答完成统计
        full_seen = 0;                                      // 初始化满状态统计
        expected_block = 0;                                 // 初始化期望块号
        expected_length = 0;                                // 初始化期望长度
        expected_seed = 0;                                  // 初始化期望数据模式
        repeat (5) @(negedge clk);                          // 保持足够复位周期
        rst_b = 1'b1;                                       // 在非采样沿释放复位
        prepare_data(1, 512, 37);                           // 覆盖 FIFO 恰好填满的整块
        send_current_frame;                                 // 验证五百一十二字节按序写入和 ACK
        if ((full_seen == 0) || load_done) begin            // 整块必须置满且尚未结束文件
            $display("FAIL: full-block completion/full flag");  // 报告满容量或结束判断错误
            failure_count = failure_count + 1;              // 累计失败数量
        end                                                 // 结束整块检查
        prepare_data(2, 100, 91);                           // 覆盖不足五百一十二字节的结束块
        send_current_frame;                                 // 验证最后一个 FIFO 字节也能返回
        if (!load_done) failure_count = failure_count + 1;  // 短块必须置文件完成
        prepare_data(3, 0, 0);                              // 覆盖整文件恰好对齐后的零长度末块
        send_current_frame;                                 // 零长度 DATA 只应发送 ACK
        if (!load_done) failure_count = failure_count + 1;  // 零长度末块仍然保持完成标志
        @(negedge clk);                                     // 在非采样沿准备下一文件
        expected_block = 0;                                 // WRQ 应回 ACK 零号
        expected_length = 0;                                // WRQ 不写 Flash
        frame_len = 16'd10;                                 // 文件名和模式构成完整写请求
        request_mem[0] = 8'h00;                             // WRQ 操作码高字节
        request_mem[1] = 8'h02;                             // WRQ 操作码低字节
        request_mem[2] = 8'h66;                             // 文件名字符 f
        request_mem[3] = 8'h00;                             // 文件名终止符
        request_mem[4] = 8'h6F;                             // 模式字符 o
        request_mem[5] = 8'h63;                             // 模式字符 c
        request_mem[6] = 8'h74;                             // 模式字符 t
        request_mem[7] = 8'h65;                             // 模式字符 e
        request_mem[8] = 8'h74;                             // 模式字符 t
        request_mem[9] = 8'h00;                             // 模式终止符
        send_current_frame;                                 // 验证新 WRQ 清除旧文件完成状态
        if (load_done) failure_count = failure_count + 1;   // 新写请求不能继承旧完成标志
        if (failure_count == 0)                             // 汇总本次集成回归结果
            $display("PASS: 615A FIFO integration, full512 + short100 + empty + WRQ reset");  // 输出成功标记
        else                                                // 存在任何自检失败
            $display("FAIL: 615A FIFO integration failures=%0d", failure_count);  // 输出失败统计
        $finish;                                            // 正常结束仿真
    end                                                     // 结束回归主流程
endmodule                                                   // 结束测试模块

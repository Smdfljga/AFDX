// rtc_rx : 同步报文接收
// 从接收端口缓冲逐字节读入，提取主时钟时间戳与链路延迟
// 读请求由本模块发出，经 rx_rd_arb 仲裁后取回数据
// 注：10 字节同步报文提取状态机已实现
module rtc_rx #(                                            // 声明模块及其参数接口
    parameter DATA_WIDTH        = 8,        // 数据位宽
    parameter RTC_WIDTH         = 48,       // RTC 计数器位宽
    parameter BYTE_OFFSET_WIDTH = 11        // 字节偏移位宽
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 启动触发 ====================
    input  wire                          start,                  // 接收完成触发（来自 rtc_sync）
    input  wire [15:0]                   rx_frame_len,           // 当前同步报文长度，截断报文不校正

    // ==================== 输入字节流（经 rx_rd_arb） ====================
    output wire                          rx_rd_req,              // 读请求，送 rx_rd_arb
    output wire [BYTE_OFFSET_WIDTH-1:0]  rx_rd_byte_offset,      // 读字节偏移（提取进度）
    input  wire [DATA_WIDTH-1:0]         rx_rd_data,             // 读数据
    input  wire                          rx_rd_valid,            // 读数据有效

    // ==================== 提取结果 ====================
    output wire [RTC_WIDTH-1:0]          master_ts,              // 主时钟时间戳
    output wire [31:0]                   delay_val,              // 链路延迟计数值
    output wire                          rx_valid                // 提取完成
);                                                          // 端口声明或模块例化结束

    // ==================== 状态机 ====================
    localparam S_IDLE = 2'd0;                                   // 空闲，等待 start
    localparam S_RD   = 2'd1;                                   // 读取同步报文
    localparam S_DONE = 2'd2;                                   // 提取完成

    reg [1:0]                 state;                            // 当前状态
    reg [BYTE_OFFSET_WIDTH-1:0] rd_ptr;                         // 读偏移，0~9
    reg [RTC_WIDTH-1:0]      master_r;                          // 主时钟时间戳移位寄存器
    reg [31:0]               delay_r;                           // 延迟值移位寄存器

    // 与 rx_rd_arb 的握手：请求保持到数据有效；数据有效后才推进偏移。
    assign rx_rd_req = (state == S_RD) && (rd_ptr < rx_frame_len); // output [0:0]
    assign rx_rd_byte_offset = rd_ptr;                          // output [10:0]

    // ==================== 状态机：第二段（组合，算次态） ====================
    reg [1:0] nxt_state;                                        // 次态，由本段组合算出

    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        nxt_state = state;                                      // 默认保持当前状态

        case (state)                                        // 根据当前状态选择处理分支
            S_IDLE: begin                                   // 处理空闲阶段
                if (start && (rx_frame_len >= 16'd10))      // 检查接收完成触发（来自 rtc_sync）、当前同步报文长度的条件
                    nxt_state = S_RD;                           // 报文长度够 10 字节才开始提取
            end                                             // 当前语句组结束

            S_RD: begin                                     // 处理读取同步报文阶段
                if (rx_rd_valid) begin                      // 读返回有效时消费当前输入字节
                    if (rd_ptr < 11'd10) begin              // 检查读偏移的条件
                        if (rd_ptr == 11'd9)                // 检查读偏移的条件
                            nxt_state = S_DONE;                 // 10 字节提取完毕
                    end                                     // 当前语句组结束
                    else                                    // 采用前一条件未满足时的处理
                        nxt_state = S_DONE;                     // 偏移越界，结束提取
                end                                         // 当前语句组结束
                else if (rd_ptr >= rx_frame_len)            // 检查读偏移、当前同步报文长度的条件
                    nxt_state = S_IDLE;                         // 截断报文不产生 rx_valid
            end                                             // 当前语句组结束

            S_DONE: begin                                   // 处理提取完成阶段
                nxt_state = S_IDLE;                             // rx_valid 脉冲只有一拍
            end                                             // 当前语句组结束

            default: begin                                  // 未匹配有效分支时采用默认处理
                nxt_state = S_IDLE;                             // 异常状态回空闲
            end                                             // 当前语句组结束
        endcase                                             // 当前分支选择结束
    end                                                     // 当前语句组结束

    // ==================== 状态机：第一段（时序，状态寄存器与数据通路） ====================
    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            state    <= S_IDLE;                             // 时钟沿更新当前状态
            rd_ptr   <= {BYTE_OFFSET_WIDTH{1'b0}};          // 时钟沿更新读偏移
            master_r <= {RTC_WIDTH{1'b0}};                  // 时钟沿更新主时钟时间戳移位寄存器
            delay_r  <= 32'd0;                              // 时钟沿更新延迟值移位寄存器
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            case (state)                                    // 根据当前状态选择处理分支
                S_IDLE: begin                               // 处理空闲阶段
                    if (start && (rx_frame_len >= 16'd10)) begin  // 检查接收完成触发（来自 rtc_sync）、当前同步报文长度的条件
                        rd_ptr   <= {BYTE_OFFSET_WIDTH{1'b0}};  // 时钟沿更新读偏移
                        master_r <= {RTC_WIDTH{1'b0}};      // 时钟沿更新主时钟时间戳移位寄存器
                        delay_r  <= 32'd0;                  // 时钟沿更新延迟值移位寄存器
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_RD: begin                                 // 处理读取同步报文阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        if (rd_ptr < 11'd10) begin          // 检查读偏移的条件
                            if (rd_ptr < 6)                 // 检查读偏移的条件
                                master_r <= {master_r[RTC_WIDTH-9:0], rx_rd_data}; // 先收高字节
                            else                            // 采用前一条件未满足时的处理
                                delay_r <= {delay_r[23:0], rx_rd_data}; // 第 10 字节是延迟低字节
                            if (rd_ptr != 11'd9)            // 检查读偏移的条件
                                rd_ptr <= rd_ptr + 1'b1;    // 时钟沿更新读偏移并推进至下一项
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                default: ;                                       // 其余状态没有数据通路动作
            endcase                                         // 当前分支选择结束

            state <= nxt_state;                                 // 状态寄存器只在第一段更新
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    assign master_ts = master_r;                                // output [47:0]
    assign delay_val = delay_r;                                 // output [31:0]
    assign rx_valid  = (state == S_DONE);                       // output [0:0]：提取完成脉冲

endmodule                                                   // 模块定义结束

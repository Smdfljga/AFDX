// rtc_tx : 同步报文发送
// 把本地时间戳按同步报文格式逐字节写入发送端口缓冲，写完给出帧尾
// 注：10 字节同步报文发送状态机已实现
module rtc_tx #(                                            // 声明模块及其参数接口
    parameter DATA_WIDTH        = 8,        // 数据位宽
    parameter RTC_WIDTH         = 48,       // RTC 计数器位宽
    parameter BYTE_OFFSET_WIDTH = 11        // 字节偏移位宽
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 发送请求 ====================
    input  wire                          tx_req,                 // 发送请求（主时钟按节拍拉起）
    input  wire [RTC_WIDTH-1:0]          local_ts,               // 本地待广播的时间戳

    // ==================== 写授权回执 ====================
    input  wire                          tx_wr_gnt,              // 写请求被 tx_wr_arb 接受的当拍回执

    // ==================== 输出字节流 ====================
    output wire                          tx_wr_en,               // 写使能（一字节）
    output wire [BYTE_OFFSET_WIDTH-1:0]  tx_wr_byte_offset,      // 写字节偏移，由发送器逐字节递增
    output wire [DATA_WIDTH-1:0]         tx_wr_data,             // 写数据
    output wire                          tx_frame_done           // 帧尾脉冲：登记长度并请求 TX 发送
);                                                          // 端口声明或模块例化结束

    // ==================== 状态机 ====================
    localparam S_IDLE = 2'd0;                                   // 空闲
    localparam S_SEND = 2'd1;                                   // 逐字节发送 10 字节报文

    reg [1:0]                 state;                            // 当前状态
    reg [BYTE_OFFSET_WIDTH-1:0] wr_ptr;                         // 写偏移 0~9
    reg [RTC_WIDTH-1:0]      ts_r;                              // 发送时锁存的时间戳

    // 时间戳锁存在 tx_req 那拍，避免后续 RTC 继续走导致报文时间漂移。
    // ==================== 状态机：第二段（组合，算次态） ====================
    reg [1:0] nxt_state;                                        // 次态，由本段组合算出

    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        nxt_state = state;                                      // 默认保持当前状态

        case (state)                                        // 根据当前状态选择处理分支
            S_IDLE: begin                                   // 处理空闲阶段
                if (tx_req)                                 // 检查发送请求（主时钟按节拍拉起）的条件
                    nxt_state = S_SEND;                         // 收到发送请求，逐字节写同步报文
            end                                             // 当前语句组结束

            S_SEND: begin                                   // 处理逐字节发送 10 字节报文阶段
                if (tx_wr_gnt && (wr_ptr == 11'd9))         // 发送缓冲授权后推进当前响应字节
                    nxt_state = S_IDLE;                         // 末字节写完后结束
            end                                             // 当前语句组结束

            default: begin                                  // 未匹配有效分支时采用默认处理
                nxt_state = S_IDLE;                             // 异常状态回空闲
            end                                             // 当前语句组结束
        endcase                                             // 当前分支选择结束
    end                                                     // 当前语句组结束

    // ==================== 状态机：第一段（时序，状态寄存器与数据通路） ====================
    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            state      <= S_IDLE;                           // 时钟沿更新当前状态
            wr_ptr     <= {BYTE_OFFSET_WIDTH{1'b0}};        // 时钟沿更新写偏移 0~9
            ts_r       <= {RTC_WIDTH{1'b0}};                // 时钟沿更新发送时锁存的时间戳
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            case (state)                                    // 根据当前状态选择处理分支
                S_IDLE: begin                               // 处理空闲阶段
                    if (tx_req) begin                       // 检查发送请求（主时钟按节拍拉起）的条件
                        wr_ptr <= {BYTE_OFFSET_WIDTH{1'b0}};  // 时钟沿更新写偏移 0~9
                        ts_r   <= local_ts;                     // 本拍锁存时间戳，报文不会随时间漂移
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_SEND: begin                               // 处理逐字节发送 10 字节报文阶段
                    if (tx_wr_gnt && (wr_ptr != 11'd9))     // 发送缓冲授权后推进当前响应字节
                        wr_ptr <= wr_ptr + 1'b1;                // 每写成功一字节推进偏移
                end                                         // 当前语句组结束

                default: ;                                      // 其余状态没有数据通路动作
            endcase                                         // 当前分支选择结束

            state <= nxt_state;                                 // 状态寄存器只在第一段更新
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    // 大端输出：0~5 为 master_ts，6~9 为 delay_val（固定 0）。
    reg [7:0] out_data_r;                                       // 当前待写字节
    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        case (wr_ptr)                                       // 根据写偏移 0~9选择处理分支
            6'd0: out_data_r = ts_r[47:40];                 // 当前字节或字段索引对应的数据选择
            6'd1: out_data_r = ts_r[39:32];                 // 当前字节或字段索引对应的数据选择
            6'd2: out_data_r = ts_r[31:24];                 // 当前字节或字段索引对应的数据选择
            6'd3: out_data_r = ts_r[23:16];                 // 当前字节或字段索引对应的数据选择
            6'd4: out_data_r = ts_r[15:8];                  // 当前字节或字段索引对应的数据选择
            6'd5: out_data_r = ts_r[7:0];                   // 当前字节或字段索引对应的数据选择
            6'd6: out_data_r = 8'h00;                       // 当前字节或字段索引对应的数据选择
            6'd7: out_data_r = 8'h00;                       // 当前字节或字段索引对应的数据选择
            6'd8: out_data_r = 8'h00;                       // 当前字节或字段索引对应的数据选择
            6'd9: out_data_r = 8'h00;                       // 当前字节或字段索引对应的数据选择
            default: out_data_r = 8'h00;                    // 未匹配有效分支时采用默认处理
        endcase                                             // 当前分支选择结束
    end                                                     // 当前语句组结束

    assign tx_wr_en          = (state == S_SEND);               // output [0:0]
    assign tx_wr_byte_offset = wr_ptr;                          // output [10:0]
    assign tx_wr_data        = out_data_r;                      // output [7:0]
    assign tx_frame_done     = (state == S_SEND) && tx_wr_gnt &&  // 设置或组合计算tx_frame_done
                               (wr_ptr == 11'd9);                 // output [0:0]：末字节写成功

endmodule                                                   // 模块定义结束

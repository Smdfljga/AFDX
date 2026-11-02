// tftp : 615A 使用的 TFTP 协议模块
// 解析 TFTP 报文（RRQ/WRQ/DATA/ACK），把文件数据写入缓冲并发起 Flash 写，
// 同时把应答报文（ACK/ERROR）经发送端口缓冲发回
// 读请求由本模块发出，经 rx_rd_arb 仲裁后取回数据
// 注：TFTP 目标端解析/Flash 写入/ACK 状态机已实现
module tftp #(                                              // 声明模块及其参数接口
    parameter DATA_WIDTH        = 8,        // 数据位宽
    parameter BYTE_OFFSET_WIDTH = 11        // 字节偏移位宽
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 启动触发与帧长 ====================
    input  wire                          start,                  // 接收完成触发（来自 data_loader_615a）
    input  wire [15:0]                   rx_frame_len,           // 当前 TFTP 报文长度

    // ==================== 输入字节流（经 rx_rd_arb） ====================
    output wire                          rx_rd_req,              // 读请求，送 rx_rd_arb
    output wire [BYTE_OFFSET_WIDTH-1:0]  rx_rd_byte_offset,      // 读字节偏移（解析进度）
    input  wire [DATA_WIDTH-1:0]         rx_rd_data,             // 读数据
    input  wire                          rx_rd_valid,            // 读数据有效

    // ==================== TFTP 解析结果 ====================
    output wire                          tftp_op_valid,          // TFTP 操作有效
    output wire [1:0]                    tftp_op_type,           // 操作类型（RRQ/WRQ/DATA/ACK）
    output wire [15:0]                   tftp_block_num,         // 块号
    output wire [15:0]                   tftp_data_len,          // 数据长度

    // ==================== 文件缓冲 ====================
    output wire                          buf_wr_en,              // 文件缓冲写使能
    output wire [DATA_WIDTH-1:0]         buf_wr_data,            // 文件缓冲写数据
    output wire                          buf_rd_en,              // 文件缓冲读使能
    input  wire [DATA_WIDTH-1:0]         buf_rd_data,            // 文件缓冲读数据
    input  wire                          buf_rd_valid,           // 文件缓冲读数据有效

    // ==================== Flash 写 ====================
    output wire                          flash_wr_req,           // Flash 写请求
    output wire [23:0]                   flash_wr_addr,          // Flash 写地址
    input  wire                          flash_wr_done,          // Flash 写完成

    // ==================== 应答报文输出（经 tx_wr_arb 写入发送端口缓冲） ====================
    output wire                          tx_wr_en,               // 写使能（应答报文一字节）
    output wire [BYTE_OFFSET_WIDTH-1:0]  tx_wr_byte_offset,      // 写字节偏移
    output wire [DATA_WIDTH-1:0]         tx_wr_data,             // 写数据
    output wire                          tx_frame_done,          // 帧尾脉冲：登记长度并请求 TX 发送
    input  wire                          tx_wr_gnt,              // 写请求被 tx_wr_arb 接受的当拍回执

    // ==================== 加载状态 ====================
    output wire                          load_busy,              // 加载进行中
    output wire                          load_done,              // 加载完成
    output wire                          load_error              // 加载失败
);                                                          // 端口声明或模块例化结束

    // ==================== 状态机 ====================
    localparam S_IDLE       = 5'd0;                              // 空闲
    localparam S_RD_OP0     = 5'd1;                              // 读 opcode 低字节
    localparam S_RD_OP1     = 5'd2;                              // 读 opcode 高字节
    localparam S_DRAIN      = 5'd3;                              // 丢弃非数据报文的剩余字节
    localparam S_RD_BLOCK0  = 5'd4;                              // 读块号高字节
    localparam S_RD_BLOCK1  = 5'd5;                              // 读块号低字节
    localparam S_RD_DATA    = 5'd6;                              // 读 DATA 载荷并写 FIFO
    localparam S_FIFO_RD    = 5'd7;                              // 发起 FIFO 读
    localparam S_FIFO_WAIT  = 5'd8;                              // 等 FIFO 读数据
    localparam S_FLASH_REQ  = 5'd9;                              // 向 Flash 控制器发起写请求
    localparam S_FLASH_WAIT = 5'd10;                             // 等 Flash 写完成
    localparam S_TX0        = 5'd11;                             // ACK 字节 0
    localparam S_TX1        = 5'd12;                             // ACK 字节 1
    localparam S_TX2        = 5'd13;                             // ACK 字节 2
    localparam S_TX3        = 5'd14;                             // ACK 字节 3
    localparam S_ERR        = 5'd15;                             // 错误结束

    reg [4:0]                  state;                            // 当前状态
    reg [BYTE_OFFSET_WIDTH-1:0] rd_ptr;                          // 输入报文字节偏移
    reg [7:0]                 op_lo;                             // opcode 低字节暂存
    reg [7:0]                 op_hi;                             // opcode 高字节暂存
    reg [15:0]                block_r;                           // 当前 TFTP 块号
    reg [15:0]                data_len_r;                        // DATA 载荷长度
    reg [15:0]                remain_r;                          // 尚未读入/写出的数据字节数
    reg [15:0]                flash_idx_r;                       // 当前块内 Flash 字节偏移
    reg [1:0]                 post_action;                       // DRAIN 结束后动作：0=ACK0 1=错误 2=空闲
    reg                       busy_r;                            // 加载进行中
    reg                       done_r;                            // 加载完成，保持到下一次 WRQ
    reg                       error_r;                           // 加载错误
    reg                       op_valid_r;                        // TFTP 操作有效脉冲

    wire [23:0] flash_base = {8'd0, block_r} * 24'd512;          // Flash 地址 = 块号 × 512

    // ==================== 读握手与输出使能 ====================
    wire reading = (state == S_RD_OP0)    || (state == S_RD_OP1) ||  // 当前阶段是否需要从接收缓冲请求字节
                   (state == S_DRAIN)     || (state == S_RD_BLOCK0) ||  // 继续计算当前阶段是否需要从接收缓冲请求字节
                   (state == S_RD_BLOCK1) || (state == S_RD_DATA); // 当前需要从 RX 缓冲读字节
    assign rx_rd_req = reading;                                  // output [0:0]
    assign rx_rd_byte_offset = rd_ptr;                           // output [10:0]

    wire writing_ack = (state == S_TX0) || (state == S_TX1) ||  // 当前阶段是否正在生成四字节 TFTP ACK
                       (state == S_TX2) || (state == S_TX3);     // 正在写 ACK
    assign tx_wr_en = writing_ack;                               // output [0:0]

    // ==================== 状态机：第二段（组合，算次态） ====================
    reg [4:0] nxt_state;                                        // 次态，由本段组合算出

    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        nxt_state = state;                                      // 默认保持当前状态

        case (state)                                        // 根据当前状态选择处理分支
            S_IDLE: begin                                   // 处理空闲阶段
                if (start)                                  // 检查接收完成触发（来自 data_loader_615a）的条件
                    nxt_state = S_RD_OP0;                       // 收到新报文，开始解析 opcode
            end                                             // 当前语句组结束

            S_RD_OP0: begin                                 // 处理读 opcode 低字节阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_state = S_RD_OP1;                       // opcode 低字节已取到
            end                                             // 当前语句组结束

            S_RD_OP1: begin                                 // 处理读 opcode 高字节阶段
                if (rx_rd_valid) begin                      // 读返回有效时消费当前输入字节
                    if ((op_lo == 8'h00) && (rx_rd_data == 8'h02))  // 检查opcode 低字节暂存、读数据的条件
                        nxt_state = (rd_ptr + 1'b1 >= rx_frame_len) ? S_TX0 : S_DRAIN; // WRQ：回 ACK#0，剩余字节丢弃
                    else if ((op_lo == 8'h00) && (rx_rd_data == 8'h03)) begin  // 检查opcode 低字节暂存、读数据的条件
                        if (rx_frame_len < 16'd4)           // 检查当前 TFTP 报文长度的条件
                            nxt_state = (rd_ptr + 1'b1 >= rx_frame_len) ? S_ERR : S_DRAIN; // 报文太短
                        else                                // 采用前一条件未满足时的处理
                            nxt_state = S_RD_BLOCK0;            // DATA：读块号
                    end                                     // 当前语句组结束
                    else                                    // 采用前一条件未满足时的处理
                        nxt_state = (rd_ptr + 1'b1 >= rx_frame_len) ? S_ERR : S_DRAIN; // 其他操作：丢弃并报错
                end                                         // 当前语句组结束
            end                                             // 当前语句组结束

            S_DRAIN: begin                                  // 处理丢弃非数据报文的剩余字节阶段
                if (rx_rd_valid && (rd_ptr + 1'b1 >= rx_frame_len))  // 读返回有效时消费当前输入字节
                    nxt_state = (post_action == 2'd0) ? S_TX0 : S_ERR; // 丢弃到帧尾后按动作收尾
            end                                             // 当前语句组结束

            S_RD_BLOCK0: begin                              // 处理读块号高字节阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_state = S_RD_BLOCK1;                    // 块号高字节已取到
            end                                             // 当前语句组结束

            S_RD_BLOCK1: begin                              // 处理读块号低字节阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_state = (data_len_r == 16'd0) ? S_TX0 : S_RD_DATA; // 无载荷直接 ACK
            end                                             // 当前语句组结束

            S_RD_DATA: begin                                // 处理读 DATA 载荷并写 FIFO阶段
                if (rx_rd_valid && (remain_r <= 16'd1))     // 读返回有效时消费当前输入字节
                    nxt_state = S_FIFO_RD;                      // 所有 DATA 字节已进 FIFO
            end                                             // 当前语句组结束

            S_FIFO_RD: begin                                // 处理发起 FIFO 读阶段
                nxt_state = S_FIFO_WAIT;                        // 已发起 FIFO 读，等数据
            end                                             // 当前语句组结束

            S_FIFO_WAIT: begin                              // 处理等 FIFO 读数据阶段
                if (buf_rd_valid)                           // 检查文件缓冲读数据有效的条件
                    nxt_state = S_FLASH_REQ;                    // 读数据有效，进入 Flash 写
            end                                             // 当前语句组结束

            S_FLASH_REQ: begin                              // 处理向 Flash 控制器发起写请求阶段
                nxt_state = S_FLASH_WAIT;                       // 已发 Flash 写请求，等完成
            end                                             // 当前语句组结束

            S_FLASH_WAIT: begin                             // 处理等 Flash 写完成阶段
                if (flash_wr_done)                          // 检查Flash 写完成的条件
                    nxt_state = (flash_idx_r + 16'd1 >= data_len_r) ? S_TX0 : S_FIFO_RD; // 本块写完，续读或回 ACK
            end                                             // 当前语句组结束

            S_TX0: begin                                    // 处理ACK 字节 0阶段
                if (tx_wr_gnt) nxt_state = S_TX1;               // ACK 字节 0 写成功
            end                                             // 当前语句组结束

            S_TX1: begin                                    // 处理ACK 字节 1阶段
                if (tx_wr_gnt) nxt_state = S_TX2;           // 发送缓冲授权后推进当前响应字节
            end                                             // 当前语句组结束

            S_TX2: begin                                    // 处理ACK 字节 2阶段
                if (tx_wr_gnt) nxt_state = S_TX3;           // 发送缓冲授权后推进当前响应字节
            end                                             // 当前语句组结束

            S_TX3: begin                                    // 处理ACK 字节 3阶段
                if (tx_wr_gnt) nxt_state = S_IDLE;              // 末字节写成功，返回空闲
            end                                             // 当前语句组结束

            S_ERR: begin                                    // 处理错误结束阶段
                nxt_state = S_IDLE;                             // 错误收尾后回空闲
            end                                             // 当前语句组结束

            default: begin                                  // 未匹配有效分支时采用默认处理
                nxt_state = S_IDLE;                             // 异常状态回空闲
            end                                             // 当前语句组结束
        endcase                                             // 当前分支选择结束
    end                                                     // 当前语句组结束

    // ==================== 状态机：第一段（时序，状态寄存器与数据通路） ====================
    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            state        <= S_IDLE;                         // 时钟沿更新当前状态
            rd_ptr       <= {BYTE_OFFSET_WIDTH{1'b0}};      // 时钟沿更新输入报文字节偏移
            op_lo        <= 8'd0;                           // 时钟沿更新opcode 低字节暂存
            op_hi        <= 8'd0;                           // 时钟沿更新opcode 高字节暂存
            block_r      <= 16'd0;                          // 时钟沿更新当前 TFTP 块号
            data_len_r   <= 16'd0;                          // 时钟沿更新DATA 载荷长度
            remain_r     <= 16'd0;                          // 时钟沿更新尚未读入/写出的数据字节数
            flash_idx_r  <= 16'd0;                          // 时钟沿更新当前块内 Flash 字节偏移
            post_action  <= 2'd0;                           // 时钟沿更新DRAIN 结束后动作：0=ACK0 1=错误 2=空闲
            busy_r       <= 1'b0;                           // 时钟沿更新加载进行中
            done_r       <= 1'b0;                           // 时钟沿更新加载完成
            error_r      <= 1'b0;                           // 时钟沿更新加载错误
            op_valid_r   <= 1'b0;                           // 时钟沿更新TFTP 操作有效脉冲
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            op_valid_r <= 1'b0;                             // 时钟沿更新TFTP 操作有效脉冲

            case (state)                                    // 根据当前状态选择处理分支
                S_IDLE: begin                               // 处理空闲阶段
                    if (start) begin                        // 检查接收完成触发（来自 data_loader_615a）的条件
                        rd_ptr       <= {BYTE_OFFSET_WIDTH{1'b0}};  // 时钟沿更新输入报文字节偏移
                        op_lo        <= 8'd0;               // 时钟沿更新opcode 低字节暂存
                        op_hi        <= 8'd0;               // 时钟沿更新opcode 高字节暂存
                        block_r      <= 16'd0;              // 时钟沿更新当前 TFTP 块号
                        data_len_r   <= 16'd0;              // 时钟沿更新DATA 载荷长度
                        remain_r     <= 16'd0;              // 时钟沿更新尚未读入/写出的数据字节数
                        flash_idx_r  <= 16'd0;              // 时钟沿更新当前块内 Flash 字节偏移
                        post_action  <= 2'd0;               // 时钟沿更新DRAIN 结束后动作：0=ACK0 1=错误 2=空闲
                        busy_r       <= 1'b1;               // 时钟沿更新加载进行中
                        error_r      <= 1'b0;               // 时钟沿更新加载错误
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_RD_OP0: begin                             // 处理读 opcode 低字节阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        op_lo  <= rx_rd_data;                   // 锁存 opcode 低字节，下一拍判报文类型
                        rd_ptr <= rd_ptr + 1'b1;            // 时钟沿更新输入报文字节偏移并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_RD_OP1: begin                             // 处理读 opcode 高字节阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        op_hi <= rx_rd_data;                // 时钟沿更新opcode 高字节暂存
                        rd_ptr <= rd_ptr + 1'b1;            // 时钟沿更新输入报文字节偏移并推进至下一项
                        if ((op_lo == 8'h00) && (rx_rd_data == 8'h02)) begin  // 检查opcode 低字节暂存、读数据的条件
                            // WRQ：目标端回 ACK#0，剩余文件名/模式字节丢弃。
                            post_action <= 2'd0;            // 时钟沿更新DRAIN 结束后动作：0=ACK0 1=错误 2=空闲
                            done_r <= 1'b0;                 // 新写请求开始时清除上一文件的完成标志
                        end                                 // 当前语句组结束
                        else if ((op_lo == 8'h00) && (rx_rd_data == 8'h03)) begin  // 检查opcode 低字节暂存、读数据的条件
                            // DATA：需要至少 4 字节（opcode + block#）。
                            if (rx_frame_len < 16'd4) begin  // 检查当前 TFTP 报文长度的条件
                                post_action <= 2'd1;        // 时钟沿更新DRAIN 结束后动作：0=ACK0 1=错误 2=空闲
                            end                             // 当前语句组结束
                            else begin                      // 前一条件不满足时执行本分支
                                data_len_r <= rx_frame_len - 16'd4;  // 时钟沿更新DATA 载荷长度
                            end                             // 当前语句组结束
                        end                                 // 当前语句组结束
                        else begin                          // 前一条件不满足时执行本分支
                            // RRQ/ACK/ERROR 等目标端不处理，丢弃报文并报错。
                            post_action <= 2'd1;            // 时钟沿更新DRAIN 结束后动作：0=ACK0 1=错误 2=空闲
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_DRAIN: begin                              // 处理丢弃非数据报文的剩余字节阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        if (rd_ptr + 1'b1 < rx_frame_len)   // 检查输入报文字节偏移、当前 TFTP 报文长度的条件
                            rd_ptr <= rd_ptr + 1'b1;        // 时钟沿更新输入报文字节偏移并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_RD_BLOCK0: begin                          // 处理读块号高字节阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        block_r[15:8] <= rx_rd_data;        // 时钟沿更新当前 TFTP 块号
                        rd_ptr <= rd_ptr + 1'b1;            // 时钟沿更新输入报文字节偏移并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_RD_BLOCK1: begin                          // 处理读块号低字节阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        block_r[7:0] <= rx_rd_data;         // 时钟沿更新当前 TFTP 块号
                        rd_ptr <= rd_ptr + 1'b1;            // 时钟沿更新输入报文字节偏移并推进至下一项
                        remain_r <= data_len_r;             // 时钟沿更新尚未读入/写出的数据字节数
                        if (data_len_r == 16'd0)            // 检查DATA 载荷长度的条件
                            done_r <= 1'b1;                 // 时钟沿更新加载完成
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_RD_DATA: begin                            // 处理读 DATA 载荷并写 FIFO阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        rd_ptr <= rd_ptr + 1'b1;            // 时钟沿更新输入报文字节偏移并推进至下一项
                        remain_r <= remain_r - 16'd1;       // 时钟沿更新尚未读入/写出的数据字节数
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_FIFO_RD: begin                            // 处理发起 FIFO 读阶段
                    // 只发出 FIFO 读请求，无数据通路动作
                end                                         // 当前语句组结束

                S_FIFO_WAIT: begin                          // 处理等 FIFO 读数据阶段
                    // 只等 FIFO 读数据，无数据通路动作
                end                                         // 当前语句组结束

                S_FLASH_REQ: begin                          // 处理向 Flash 控制器发起写请求阶段
                    // 只发出 Flash 写请求，无数据通路动作
                end                                         // 当前语句组结束

                S_FLASH_WAIT: begin                         // 处理等 Flash 写完成阶段
                    if (flash_wr_done) begin                // 检查Flash 写完成的条件
                        flash_idx_r <= flash_idx_r + 16'd1;  // 时钟沿更新当前块内 Flash 字节偏移并推进至下一项
                        if (flash_idx_r + 16'd1 >= data_len_r) begin  // 检查当前块内 Flash 字节偏移、DATA 载荷长度的条件
                            if (data_len_r < 16'd512)       // 检查DATA 载荷长度的条件
                                done_r <= 1'b1;             // 时钟沿更新加载完成
                            op_valid_r <= 1'b1;             // 时钟沿更新TFTP 操作有效脉冲
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_TX0: begin                                // 处理ACK 字节 0阶段
                    // 只等写回执，无数据通路动作
                end                                         // 当前语句组结束

                S_TX1: begin                                // 处理ACK 字节 1阶段
                    // 只等写回执，无数据通路动作
                end                                         // 当前语句组结束

                S_TX2: begin                                // 处理ACK 字节 2阶段
                    // 只等写回执，无数据通路动作
                end                                         // 当前语句组结束

                S_TX3: begin                                // 处理ACK 字节 3阶段
                    if (tx_wr_gnt)                          // 发送缓冲授权后推进当前响应字节
                        busy_r <= 1'b0;                     // 时钟沿更新加载进行中
                end                                         // 当前语句组结束

                S_ERR: begin                                // 处理错误结束阶段
                    error_r <= 1'b1;                        // 时钟沿更新加载错误
                    busy_r  <= 1'b0;                        // 时钟沿更新加载进行中
                end                                         // 当前语句组结束

                default: ;                                       // 其余状态没有数据通路动作
            endcase                                         // 当前分支选择结束

            state <= nxt_state;                                 // 状态寄存器只在第一段更新
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    // ==================== 输出信号 ====================
    assign buf_wr_en   = (state == S_RD_DATA) && rx_rd_valid;    // output [0:0]：DATA 字节写 FIFO
    assign buf_wr_data = rx_rd_data;                             // output [7:0]
    assign buf_rd_en   = (state == S_FIFO_RD);                   // output [0:0]：发起 FIFO 读

    assign flash_wr_req  = (state == S_FLASH_REQ);               // output [0:0]
    assign flash_wr_addr = flash_base + {8'd0, flash_idx_r};     // output [23:0]

    // ACK 固定 4 字节：00 04 block_hi block_lo。
    reg [7:0] ack_byte;                                          // 当前 ACK 字节
    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        case (state)                                        // 根据当前状态选择处理分支
            S_TX0: ack_byte = 8'h00;                        // 处理ACK 字节 0阶段
            S_TX1: ack_byte = 8'h04;                        // 处理ACK 字节 1阶段
            S_TX2: ack_byte = block_r[15:8];                // 处理ACK 字节 2阶段
            S_TX3: ack_byte = block_r[7:0];                 // 处理ACK 字节 3阶段
            default: ack_byte = 8'h00;                      // 未匹配有效分支时采用默认处理
        endcase                                             // 当前分支选择结束
    end                                                     // 当前语句组结束

    assign tx_wr_byte_offset = (state == S_TX0) ? 11'd0 :   // 设置或组合计算写字节偏移
                               (state == S_TX1) ? 11'd1 :   // 继续计算tx_wr_byte_offset
                               (state == S_TX2) ? 11'd2 : 11'd3; // output [10:0]
    assign tx_wr_data        = ack_byte;                         // output [7:0]
    assign tx_frame_done     = (state == S_TX3) && tx_wr_gnt;    // output [0:0]：末字节写成功

    assign tftp_op_valid  = op_valid_r;                          // output [0:0]
    assign tftp_op_type   = (op_lo == 8'h00) && (op_hi == 8'h03) ? 2'd1 : 2'd0; // 简化：DATA=1，其他=0
    assign tftp_block_num = block_r;                             // output [15:0]
    assign tftp_data_len  = data_len_r;                          // output [15:0]
    assign load_busy      = busy_r;                              // output [0:0]
    assign load_done      = done_r;                              // output [0:0]
    assign load_error     = error_r;                             // output [0:0]

endmodule                                                   // 模块定义结束

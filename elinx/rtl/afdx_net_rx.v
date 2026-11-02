// afdx_net_rx : 双网接收帧缓存与整帧选路（跨时钟域）
// 每张网一片 4096×8 简单双口 RAM（rx_frame_buf），拆成两个 2048 字节槽位：
//   写侧在 MAC 时钟域（125MHz）把整帧写入空闲槽位，帧尾登记长度/错误并翻转本槽位写标志；
//   读侧在核心时钟域（25MHz）看到写标志与回执不一致就认为该槽位有整帧，读完后翻转回执标志。
// 跨时钟只传递"每槽 1bit 标志"，且都经两级寄存器同步，符合单比特握手的安全做法；
// 长度/错误描述符在标志翻转之前已经稳定，读侧在同步延迟之后采样，属于"数据先稳定、握手后到"。
// 选路：核心空闲时按上一次服务记录在两网之间轮转，把整帧连续送给核心并给出 frame_net。
module afdx_net_rx #(                                        // 声明模块及其参数接口
    parameter DATA_WIDTH = 8,                               // MAC 数据位宽，1 字节/拍
    parameter ADDR_WIDTH = 12,                              // 帧缓存地址位宽（4096 字节）
    parameter MAX_FRAME  = 1536,                            // 单帧最大字节数（含以太网头与填充）
    parameter SLOT_BITS  = 11                               // 每槽字节数位宽（2KB）
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          wr_clk,                 // MAC 侧时钟（125MHz）
    input  wire                          rd_clk,                 // 核心侧时钟（25MHz）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== A 网 MAC 接收侧（wr_clk 域） ====================
    input  wire [DATA_WIDTH-1:0]         a_rx_data,              // A 网接收数据
    input  wire                          a_rx_data_vld,          // A 网接收数据有效
    input  wire                          a_rx_sop,               // A 网接收包起始
    input  wire                          a_rx_eop,               // A 网接收包结束
    input  wire                          a_rx_err,               // A 网接收错误
    output wire                          a_rx_rdy,               // A 网接收准备（整帧入缓存，恒为 1）

    // ==================== B 网 MAC 接收侧（wr_clk 域） ====================
    input  wire [DATA_WIDTH-1:0]         b_rx_data,              // B 网接收数据
    input  wire                          b_rx_data_vld,          // B 网接收数据有效
    input  wire                          b_rx_sop,               // B 网接收包起始
    input  wire                          b_rx_eop,               // B 网接收包结束
    input  wire                          b_rx_err,               // B 网接收错误
    output wire                          b_rx_rdy,               // B 网接收准备（整帧入缓存，恒为 1）

    // ==================== 到 AFDX 接收核心（rd_clk 域） ====================
    output wire [DATA_WIDTH-1:0]         ff_rx_data,             // 送给核心的接收数据
    output wire                          ff_rx_data_vld,         // 送给核心的接收数据有效
    output wire                          ff_rx_sop,              // 送给核心的接收包起始
    output wire                          ff_rx_eop,              // 送给核心的接收包结束
    output wire                          ff_rx_err,              // 送给核心的接收错误（整帧保持）
    input  wire                          ff_rx_rdy,              // 核心接收准备（仅 S_IDLE 为高）
    output wire                          frame_net               // 本帧来源网络：0=A 网 1=B 网
);                                                          // 端口声明或模块例化结束

    // ==================== 每网写侧（MAC 时钟域） ====================
    wire [ADDR_WIDTH-1:0] a_wr_addr;                            // A 网缓存写地址
    wire [DATA_WIDTH-1:0] a_wr_data;                            // A 网缓存写数据
    wire                  a_wr_en;                              // A 网缓存写使能
    wire [1:0]            a_wr_tog;                             // A 网每槽写完成标志
    wire [ADDR_WIDTH-1:0] a_len0, a_len1;                       // A 网每槽整帧长度
    wire [1:0]            a_err;                                // A 网每槽错误标记
    wire [1:0]            a_ack_tog;                            // A 网读侧回执（同步到写域）
    wire [ADDR_WIDTH-1:0] b_wr_addr;                            // B 网缓存写地址
    wire [DATA_WIDTH-1:0] b_wr_data;                            // B 网缓存写数据
    wire                  b_wr_en;                              // B 网缓存写使能
    wire [1:0]            b_wr_tog;                             // B 网每槽写完成标志
    wire [ADDR_WIDTH-1:0] b_len0, b_len1;                       // B 网每槽整帧长度
    wire [1:0]            b_err;                                // B 网每槽错误标记
    wire [1:0]            b_ack_tog;                            // B 网读侧回执（同步到写域）

    // ==================== 握手标志同步 ====================
    reg  [1:0] a_wr_tog_d0, a_wr_tog_d1;                        // A 网写标志同步到读域
    reg  [1:0] b_wr_tog_d0, b_wr_tog_d1;                        // B 网写标志同步到读域
    reg  [1:0] a_ack_d0, a_ack_d1;                              // A 网回执同步到写域
    reg  [1:0] b_ack_d0, b_ack_d1;                              // B 网回执同步到写域
    reg  [1:0] a_rd_tog;                                        // A 网每槽回执（读域寄存器，回执同步链的源）
    reg  [1:0] b_rd_tog;                                        // B 网每槽回执（读域寄存器，回执同步链的源）

    always @(posedge rd_clk or negedge rst_b) begin          // 读域同步写标志
        if (!rst_b) begin                                   // 复位分支
            a_wr_tog_d0 <= 2'b00;                           // 清 A 网同步首级
            a_wr_tog_d1 <= 2'b00;                           // 清 A 网同步末级
            b_wr_tog_d0 <= 2'b00;                           // 清 B 网同步首级
            b_wr_tog_d1 <= 2'b00;                           // 清 B 网同步末级
        end                                                 // 复位分支结束
        else begin                                          // 正常运行分支
            a_wr_tog_d0 <= a_wr_tog;                        // A 网写标志打一拍
            a_wr_tog_d1 <= a_wr_tog_d0;                     // A 网写标志再打一拍
            b_wr_tog_d0 <= b_wr_tog;                        // B 网写标志打一拍
            b_wr_tog_d1 <= b_wr_tog_d0;                     // B 网写标志再打一拍
        end                                                 // 正常运行分支结束
    end                                                     // 读域同步结束

    always @(posedge wr_clk or negedge rst_b) begin          // 写域同步读侧回执
        if (!rst_b) begin                                   // 复位分支
            a_ack_d0 <= 2'b00;                              // 清 A 网同步首级
            a_ack_d1 <= 2'b00;                              // 清 A 网同步末级
            b_ack_d0 <= 2'b00;                              // 清 B 网同步首级
            b_ack_d1 <= 2'b00;                              // 清 B 网同步末级
        end                                                 // 复位分支结束
        else begin                                          // 正常运行分支
            a_ack_d0 <= a_rd_tog;                           // A 网读域回执打一拍（同步链入口必须接读域寄存器）
            a_ack_d1 <= a_ack_d0;                           // A 网回执再打一拍
            b_ack_d0 <= b_rd_tog;                           // B 网读域回执打一拍
            b_ack_d1 <= b_ack_d0;                           // B 网回执再打一拍
        end                                                 // 正常运行分支结束
    end                                                     // 写域同步结束

    assign a_ack_tog = a_ack_d1;                            // A 网回执还给写侧
    assign b_ack_tog = b_ack_d1;                            // B 网回执还给写侧

    // ==================== 每槽是否有整帧可读（读域判断） ====================
    wire [1:0] a_avail_slot = a_wr_tog_d1 ^ a_rd_tog;       // A 网每槽有整帧
    wire [1:0] b_avail_slot = b_wr_tog_d1 ^ b_rd_tog;       // B 网每槽有整帧
    wire       a_avail = |a_avail_slot;                     // A 网有整帧待读
    wire       b_avail = |b_avail_slot;                     // B 网有整帧待读

    // ==================== 选路状态机 ====================
    localparam S_IDLE = 1'd0;                               // 空闲：等核心就绪与待读整帧
    localparam S_READ = 1'd1;                               // 读帧：把一整帧连续送给核心

    reg                   state;                            // 当前选路状态
    reg                   net_sel;                          // 当前正在读的网络（0=A 1=B）
    reg                   slot_sel;                         // 当前正在读的槽位
    reg  [ADDR_WIDTH-1:0] issue_ix;                         // 已发出的读地址个数
    reg  [ADDR_WIDTH-1:0] emit_ix;                          // 已送出的字节数
    reg  [ADDR_WIDTH-1:0] cur_len;                          // 当前帧总字节数
    reg                   cur_err;                          // 当前帧错误标记
    reg                   last_net;                         // 上一次服务的网络（轮转用）
    reg                   ren;                              // 帧缓存读使能
    reg                   ren_d;                            // 读使能打一拍（数据有效标志）
    reg  [ADDR_WIDTH-1:0] rd_addr;                          // 帧缓存读地址

    wire                  start = (state == S_IDLE) && ff_rx_rdy && (a_avail || b_avail); // 核心空闲且有帧
    wire                  pick_b = b_avail && (!a_avail || last_net);  // 两网都有时轮转
    wire [1:0]            pick_avail = pick_b ? b_avail_slot : a_avail_slot; // 被选网络的可读槽位
    wire                  pick_slot = ~pick_avail[0];       // 优先槽位 0，否则槽位 1
    wire [ADDR_WIDTH-1:0] pick_len = pick_b ? (pick_slot ? b_len1 : b_len0) : (pick_slot ? a_len1 : a_len0); // 帧长
    wire                  pick_err = pick_b ? (pick_slot ? b_err[1] : b_err[0]) : (pick_slot ? a_err[1] : a_err[0]); // 错误
    wire                  last_byte = ren_d && (emit_ix == (cur_len - 1'b1)); // 本拍送出的是帧尾
    wire [1:0]            a_tog_next = a_rd_tog ^ ((last_byte && !net_sel) ? (2'b01 << slot_sel) : 2'b00); // A 网回执下一值
    wire [1:0]            b_tog_next = b_rd_tog ^ ((last_byte &&  net_sel) ? (2'b01 << slot_sel) : 2'b00); // B 网回执下一值

    // 读地址按 {槽位, 槽内偏移} 组织，两个网各自一片缓存
    wire [ADDR_WIDTH-1:0] rd_addr_cur = {slot_sel, rd_addr[SLOT_BITS-1:0]}; // 本次读地址

    // ==================== 到核心的帧数据 ====================
    wire [DATA_WIDTH-1:0] a_ram_q;                          // A 网缓存读数据
    wire [DATA_WIDTH-1:0] b_ram_q;                          // B 网缓存读数据

    assign ff_rx_data     = net_sel ? b_ram_q : a_ram_q;    // 按当前网络选通读数据
    assign ff_rx_data_vld = ren_d;                          // 读数据在发地址后一拍有效
    assign ff_rx_sop      = ren_d && (emit_ix == {ADDR_WIDTH{1'b0}}); // 帧首拍
    assign ff_rx_eop      = last_byte;                      // 帧尾拍
    assign ff_rx_err      = ren_d && cur_err;               // 整帧保持错误标记
    assign frame_net      = net_sel;                        // 本帧来源网络

    // a_rx_rdy / b_rx_rdy 由两侧写模块的 rx_rdy 输出驱动（整帧入缓存，恒为 1），
    // 这里不能再 assign，否则一个网络两个驱动，综合工具会直接报错。

    always @(posedge rd_clk or negedge rst_b) begin          // 选路与读帧时序
        if (!rst_b) begin                                   // 复位分支
            state     <= S_IDLE;                            // 回到空闲
            net_sel   <= 1'b0;                              // 默认 A 网
            slot_sel  <= 1'b0;                              // 默认槽位 0
            issue_ix  <= {ADDR_WIDTH{1'b0}};                // 清已发地址计数
            emit_ix   <= {ADDR_WIDTH{1'b0}};                // 清已送字节计数
            cur_len   <= {ADDR_WIDTH{1'b0}};                // 清帧长
            cur_err   <= 1'b0;                              // 清错误标记
            last_net  <= 1'b0;                              // 清轮转记录
            ren       <= 1'b0;                              // 清读使能
            ren_d     <= 1'b0;                              // 清读有效
            rd_addr   <= {ADDR_WIDTH{1'b0}};                // 清读地址
            a_rd_tog  <= 2'b00;                             // 清 A 网回执
            b_rd_tog  <= 2'b00;                             // 清 B 网回执
        end                                                 // 复位分支结束
        else begin                                          // 正常运行分支
            ren_d <= ren;                                   // 读使能打一拍，与缓存输出对齐
            a_rd_tog <= a_tog_next;                         // 读完整帧后翻转该槽位回执
            b_rd_tog <= b_tog_next;                         // 读完整帧后翻转该槽位回执
            case (state)                                    // 按状态处理
                S_IDLE: begin                               // 空闲
                    ren <= 1'b0;                            // 空闲不读
                    if (start) begin                        // 核心就绪且有整帧
                        net_sel  <= pick_b;                 // 选择被服务的网络
                        slot_sel <= pick_slot;              // 选择待读槽位
                        cur_len  <= pick_len;               // 装入帧长
                        cur_err  <= pick_err;               // 装入错误标记
                        issue_ix <= {ADDR_WIDTH{1'b0}};     // 从帧首开始发地址
                        emit_ix  <= {ADDR_WIDTH{1'b0}};     // 从帧首开始送字节
                        rd_addr  <= {ADDR_WIDTH{1'b0}};     // 槽内偏移清零
                        ren      <= 1'b1;                   // 发起首字节读
                        last_net <= pick_b;                 // 记录本次网络
                        state    <= S_READ;                 // 进入读帧
                    end                                     // 启动判断结束
                end                                         // 空闲分支结束
                S_READ: begin                               // 读帧
                    if (ren) begin                          // 还有地址要发
                        if (issue_ix == (cur_len - 1'b1))   // 本拍发出的是最后一个地址
                            ren <= 1'b0;                    // 之后不再发
                        else begin                          // 还有后续地址
                            issue_ix <= issue_ix + 1'b1;    // 地址计数前进
                            rd_addr  <= rd_addr + 1'b1;     // 槽内偏移前进
                        end                                 // 地址推进分支结束
                    end                                     // 发地址分支结束
                    if (ren_d) begin                        // 本拍缓存的读数据有效
                        if (emit_ix == (cur_len - 1'b1)) begin // 送出的是最后一个字节
                            emit_ix <= {ADDR_WIDTH{1'b0}}; // 计数归零
                            state   <= S_IDLE;              // 本帧读完，回空闲
                        end                                 // 帧尾分支结束
                        else                                // 还有字节
                            emit_ix <= emit_ix + 1'b1;      // 送字节计数前进
                    end                                     // 数据有效分支结束
                end                                         // 读帧分支结束
                default: begin                              // 异常状态
                    state <= S_IDLE;                        // 回空闲
                    ren   <= 1'b0;                          // 关闭读使能
                end                                         // 异常分支结束
            endcase                                         // 状态处理结束
        end                                                 // 正常运行分支结束
    end                                                     // 选路状态机结束

    // ==================== 两片帧缓存 IP（读写时钟独立） ====================
    rx_frame_buf u_rx_frame_buf_a (                         // A 网帧缓存，简单双口 RAM
        .wrclock   (wr_clk),                                // 写时钟：MAC 侧
        .rdclock   (rd_clk),                                // 读时钟：核心侧
        .data      (a_wr_data),                             // 写数据
        .rdaddress (rd_addr_cur),                           // 读地址
        .wraddress (a_wr_addr),                             // 写地址
        .wren      (a_wr_en),                               // 写使能
        .rden      (ren && !net_sel),                       // 读使能
        .q         (a_ram_q)                                // 读数据，读使能后一拍有效
    );                                                      // A 网帧缓存例化结束

    rx_frame_buf u_rx_frame_buf_b (                         // B 网帧缓存，简单双口 RAM
        .wrclock   (wr_clk),                                // 写时钟：MAC 侧
        .rdclock   (rd_clk),                                // 读时钟：核心侧
        .data      (b_wr_data),                             // 写数据
        .rdaddress (rd_addr_cur),                           // 读地址
        .wraddress (b_wr_addr),                             // 写地址
        .wren      (b_wr_en),                               // 写使能
        .rden      (ren && net_sel),                        // 读使能
        .q         (b_ram_q)                                // 读数据，读使能后一拍有效
    );                                                      // B 网帧缓存例化结束

    // ==================== 两网写侧 ====================
    afdx_net_rx_wr #(                                       // A 网接收写侧
        .DATA_WIDTH (DATA_WIDTH),                           // 连接参数
        .ADDR_WIDTH (ADDR_WIDTH),                           // 连接参数
        .MAX_FRAME  (MAX_FRAME),                            // 连接参数
        .SLOT_BITS  (SLOT_BITS)                             // 连接参数
    ) u_a_wr (                                              // 例化 A 网写侧
        .clk        (wr_clk),                               // MAC 侧时钟
        .rst_b      (rst_b),                                // 复位
        .rx_data    (a_rx_data),                            // MAC 字节
        .rx_data_vld(a_rx_data_vld),                        // 字节有效
        .rx_sop     (a_rx_sop),                             // 帧首
        .rx_eop     (a_rx_eop),                             // 帧尾
        .rx_err     (a_rx_err),                             // 错误
        .rx_rdy     (a_rx_rdy),                             // 接收准备
        .ram_wr_addr(a_wr_addr),                            // 缓存写地址
        .ram_wr_data(a_wr_data),                            // 缓存写数据
        .ram_wr_en  (a_wr_en),                              // 缓存写使能
        .ack_toggle (a_ack_tog),                            // 读侧回执
        .wr_toggle  (a_wr_tog),                             // 写侧完成标志
        .slot_len0  (a_len0),                               // 槽位 0 长度
        .slot_len1  (a_len1),                               // 槽位 1 长度
        .slot_err   (a_err)                                 // 槽位错误标记
    );                                                      // A 网写侧例化结束

    afdx_net_rx_wr #(                                       // B 网接收写侧
        .DATA_WIDTH (DATA_WIDTH),                           // 连接参数
        .ADDR_WIDTH (ADDR_WIDTH),                           // 连接参数
        .MAX_FRAME  (MAX_FRAME),                            // 连接参数
        .SLOT_BITS  (SLOT_BITS)                             // 连接参数
    ) u_b_wr (                                              // 例化 B 网写侧
        .clk        (wr_clk),                               // MAC 侧时钟
        .rst_b      (rst_b),                                // 复位
        .rx_data    (b_rx_data),                            // MAC 字节
        .rx_data_vld(b_rx_data_vld),                        // 字节有效
        .rx_sop     (b_rx_sop),                             // 帧首
        .rx_eop     (b_rx_eop),                             // 帧尾
        .rx_err     (b_rx_err),                             // 错误
        .rx_rdy     (b_rx_rdy),                             // 接收准备
        .ram_wr_addr(b_wr_addr),                            // 缓存写地址
        .ram_wr_data(b_wr_data),                            // 缓存写数据
        .ram_wr_en  (b_wr_en),                              // 缓存写使能
        .ack_toggle (b_ack_tog),                            // 读侧回执
        .wr_toggle  (b_wr_tog),                             // 写侧完成标志
        .slot_len0  (b_len0),                               // 槽位 0 长度
        .slot_len1  (b_len1),                               // 槽位 1 长度
        .slot_err   (b_err)                                 // 槽位错误标记
    );                                                      // B 网写侧例化结束

endmodule                                                   // 模块定义结束

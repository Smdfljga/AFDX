// afdx_tx_buf : 核心到双网 MAC 的发送跨时钟缓冲
// 写侧在核心时钟域（25MHz）按帧把字节写进 4096×8 缓存的空闲槽位（2 槽 × 2KB），
// 帧尾登记长度/错误并翻转本槽位写标志；读侧在 MAC 时钟域（125MHz）看到标志翻转就按帧读出，
// 同一字节流同时送给 A/B 两片 MAC，两片 MAC 都就绪时才发下一字节，发完翻转回执标志；
// MAC 反压可以落在帧中间：已取到缓存输出的字节一直保持，等 MAC 就绪再发，不丢字节也不会卡死。
// 跨时钟只传每槽 1bit 标志（两级同步），长度/错误在标志翻转前已稳定，读侧在同步延迟后采样。
// 核心侧 tx_rdy = 帧内或还有空闲槽位：保证一次一帧独占一个槽位，槽位不够时核心自然等待。
module afdx_tx_buf #(                                       // 声明模块及其参数接口
    parameter DATA_WIDTH  = 8,                              // 数据位宽
    parameter ADDR_WIDTH  = 12,                             // 缓存地址位宽（4096 字节）
    parameter SLOT_BITS   = 11                              // 每槽字节数位宽（2KB）
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          wr_clk,                 // 核心侧时钟（25MHz）
    input  wire                          rd_clk,                 // MAC 侧时钟（125MHz）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 核心侧发送字节流（wr_clk 域） ====================
    input  wire [DATA_WIDTH-1:0]         core_tx_data,           // 核心发送数据
    input  wire                          core_tx_wren,           // 核心发送写使能
    input  wire                          core_tx_sop,            // 核心发送包起始
    input  wire                          core_tx_eop,            // 核心发送包结束
    input  wire                          core_tx_err,            // 核心发送错误标记（帧末脉冲）
    output wire                          core_tx_rdy,            // 缓冲可接收（帧内恒 1，或还有空槽）

    // ==================== MAC 侧发送字节流（rd_clk 域） ====================
    output wire [DATA_WIDTH-1:0]         mac_tx_data,            // 送往 MAC 的数据
    output wire                          mac_tx_wren,            // 送往 MAC 的写使能
    output wire                          mac_tx_sop,             // 帧首
    output wire                          mac_tx_eop,             // 帧尾
    output wire                          mac_tx_err,             // 帧错误标记
    input  wire                          mac_tx_rdy              // 两片 MAC 都就绪
);                                                          // 端口声明或模块例化结束

    localparam SLOT_BYTES   = (1 << SLOT_BITS);                 // 每槽字节数
    localparam S_IDLE_STATE = 1'b0;                             // 读侧：空闲
    localparam S_READ_STATE = 1'b1;                             // 读侧：读帧送 MAC

    // ==================== 写侧寄存（核心域） ====================
    reg                   busy;                                 // 正在写入一帧
    reg                   drop;                                 // 本帧超长丢弃
    reg  [0:0]            cur_slot;                             // 本帧占用槽位
    reg  [SLOT_BITS-1:0]  wr_off;                               // 本帧已写字节数
    reg  [1:0]            wr_tog;                               // 写侧完成标志
    reg  [1:0]            err_r;                                // 每槽错误标记
    reg  [1:0]            free_ack;                             // 读侧回执（同步到本域）
    reg  [ADDR_WIDTH-1:0] len_rx [0:1];                         // 每槽整帧字节数
    reg                   err_acc;                              // 本帧错误累积
    reg                   finish_pend;                          // 帧尾后错误脉冲采样窗口

    // ==================== 读侧寄存（MAC 域） ====================
    reg  [1:0]            wr_tog_d0, wr_tog_d1;                 // 写标志同步
    reg  [1:0]            ack_tog;                              // 读侧回执（MAC 域）
    reg                   state;                                // 0=空闲 1=读帧
    reg  [0:0]            slot_r;                               // 当前读槽位
    reg  [ADDR_WIDTH-1:0] len_r;                                // 当前帧字节数
    reg                   err_r_sel;                            // 当前帧错误标记
    reg  [ADDR_WIDTH-1:0] issue_ix;                             // 下一个要发读地址的字节序号
    reg  [ADDR_WIDTH-1:0] emit_ix;                              // 下一个要送给 MAC 的字节序号
    reg                   fetch_d1;                             // 读地址已发出第一拍
    reg                   fetch_d2;                             // 读地址已发出第二拍（数据本拍到达）
    reg  [DATA_WIDTH-1:0] f0, f1;                               // 返回缓存：f0 先到，f1 后到
    reg  [1:0]            fcnt;                                 // 缓存内待发字节数（0..2）

    // ==================== 缓存读写口 ====================
    wire free0  = (wr_tog[0] == free_ack[0]);                   // 槽位 0 空闲
    wire free1  = (wr_tog[1] == free_ack[1]);                   // 槽位 1 空闲
    wire any_free = free0 | free1;                              // 还有空闲槽位
    wire [SLOT_BITS-1:0] wr_off_nxt = wr_off + 1'b1;            // 本帧字节数加一
    wire over_len = (wr_off_nxt > SLOT_BYTES);                  // 超槽位容量
    wire        wr_first = core_tx_wren && !busy && core_tx_sop; // 本拍是帧首字节
    wire [0:0]  wr_slot  = wr_first ? (free0 ? 1'b0 : 1'b1) : cur_slot; // 帧首即选空闲槽位
    wire [SLOT_BITS-1:0] wr_off_sel = wr_first ? {SLOT_BITS{1'b0}} : wr_off; // 帧首写首字节位置
    wire [ADDR_WIDTH-1:0] ram_wr_addr = {wr_slot, wr_off_sel};  // 写地址：槽位在高位
    wire                  ram_wr_en   = core_tx_wren &&         // 本拍写入一字节（含帧首）
                                        (busy ? !drop : core_tx_sop) && (busy || any_free); // 帧内或还有空槽才写
    wire [DATA_WIDTH-1:0] ram_q;                                // 缓存读数据（读地址在读侧组合给出）

    assign core_tx_rdy = busy || any_free;                      // 帧内或还有空槽就收

    // ==================== 写侧（核心 25MHz） ====================
    always @(posedge wr_clk or negedge rst_b) begin          // 写侧时序
        if (!rst_b) begin                                   // 复位分支
            busy        <= 1'b0;                            // 退出帧内
            drop        <= 1'b0;                            // 清丢弃
            cur_slot    <= 1'b0;                            // 默认槽位 0
            wr_off      <= {SLOT_BITS{1'b0}};               // 清偏移
            wr_tog      <= 2'b00;                           // 清完成标志
            err_r       <= 2'b00;                           // 清槽位错误
            err_acc     <= 1'b0;                            // 清错误累积
            finish_pend <= 1'b0;                            // 清帧尾窗口
            len_rx[0]   <= {ADDR_WIDTH{1'b0}};              // 清槽位 0 长度
            len_rx[1]   <= {ADDR_WIDTH{1'b0}};              // 清槽位 1 长度
        end                                                 // 复位分支结束
        else begin                                          // 正常运行分支
            if (core_tx_err && (busy || finish_pend))       // 帧末错误脉冲
                err_acc <= err_acc | 1'b1;                  // 累积到本帧
            if (finish_pend) begin                          // 帧尾后等错误脉冲一拍
                err_r[cur_slot]  <= err_acc | core_tx_err;  // 登记本帧错误
                wr_tog[cur_slot] <= ~wr_tog[cur_slot];      // 通知读侧整帧可取
                finish_pend      <= 1'b0;                   // 关闭窗口
                busy             <= 1'b0;                   // 退出帧内
            end                                             // 帧尾窗口结束
            else if (core_tx_wren) begin                    // 核心送来一个字节
                if (!busy) begin                            // 不在帧内：本字节是帧首
                    if (core_tx_sop && any_free) begin      // 有槽位就整帧收下
                        busy     <= 1'b1;                   // 进入帧内
                        drop     <= 1'b0;                   // 不丢弃
                        err_acc  <= core_tx_err;            // 记录错误初值
                        cur_slot <= free0 ? 1'b0 : 1'b1;    // 优先槽位 0
                        wr_off   <= {{(SLOT_BITS-1){1'b0}}, 1'b1}; // 已写 1 字节
                    end                                     // 帧首分支结束
                    else if (core_tx_sop) begin             // 无空闲槽位：整帧丢弃
                        busy <= 1'b1;                       // 进入帧内
                        drop <= 1'b1;                       // 置丢弃
                    end                                     // 丢弃分支结束
                end                                         // 不在帧内分支结束
                else if (!drop) begin                       // 帧内未丢弃
                    wr_off <= wr_off_nxt;                   // 偏移前进
                    if (over_len)                           // 超槽位容量
                        drop <= 1'b1;                       // 剩余字节丢弃
                    if (core_tx_eop) begin                  // 帧尾：登记长度
                        len_rx[cur_slot] <= wr_off_nxt;     // 整帧字节数
                        finish_pend      <= 1'b1;           // 打开错误采样窗口
                    end                                     // 帧尾分支结束
                end                                         // 帧内未丢弃分支结束
                else if (core_tx_eop) begin                 // 丢弃帧的帧尾
                    finish_pend <= 1'b1;                    // 直接收尾
                end                                         // 丢弃帧尾分支结束
            end                                             // 字节处理结束
        end                                                 // 正常运行分支结束
    end                                                     // 写侧时序结束

    // ==================== 写标志同步到 MAC 域 ====================
    always @(posedge rd_clk or negedge rst_b) begin          // 写标志两级同步
        if (!rst_b) begin                                   // 复位分支
            wr_tog_d0 <= 2'b00;                             // 清同步首级
            wr_tog_d1 <= 2'b00;                             // 清同步末级
        end                                                 // 复位分支结束
        else begin                                          // 正常运行分支
            wr_tog_d0 <= wr_tog;                            // 打一拍
            wr_tog_d1 <= wr_tog_d0;                         // 再打一拍
        end                                                 // 正常运行分支结束
    end                                                     // 同步结束

    // ==================== 读侧（MAC 客户端时钟） ====================
    // RAM 读延迟两拍（地址/rden 寄存 + 输出寄存），因此读地址要提前两字节发出，
    // 返回的两字节先落到 f0/f1 两级返回缓存，MAC 每认可一拍就取走最老的一项。
    // MAC 反压时停止发地址，缓存里的两字节原样保留，既不丢字节也不会卡死。
    wire [1:0] avail_slot = wr_tog_d1 ^ ack_tog;            // 每槽有整帧待发
    wire       any_avail  = |avail_slot;                    // 至少一帧待发
    wire       pick_slot  = ~avail_slot[0];                 // 优先槽位 0
    wire       arr        = fetch_d2;                       // 两拍前发出的地址，数据本拍到达
    wire       room       = (({1'b0, fcnt} + {1'b0, fetch_d1}) < 2'd2); // 缓存 + 在途读不超过两级
    wire       fetch      = (state == S_READ_STATE) && room && (issue_ix < len_r); // 本拍发读地址
    wire       pop        = (state == S_READ_STATE) && (fcnt != 2'd0) && mac_tx_rdy; // 本拍向 MAC 送出字节
    wire       frame_last = (emit_ix == (len_r - 1'b1));    // 本拍送出的是本帧最后一个字节
    wire [ADDR_WIDTH-1:0] ram_rd_addr = {slot_r, issue_ix[SLOT_BITS-1:0]}; // 读地址：槽位在高位

    assign mac_tx_data = f0;                                // 最老的一项先发
    assign mac_tx_wren = pop;                               // 写使能
    assign mac_tx_sop  = pop && (emit_ix == {ADDR_WIDTH{1'b0}}); // 帧首
    assign mac_tx_eop  = pop && frame_last;                 // 帧尾
    assign mac_tx_err  = pop && err_r_sel;                  // 错误标记

    // 返回缓存：一进一出时整体搬家，避免额外空转拍
    always @(posedge rd_clk or negedge rst_b) begin          // 两级返回缓存
        if (!rst_b) begin                                   // 复位分支
            f0   <= {DATA_WIDTH{1'b0}};                     // 清第一级
            f1   <= {DATA_WIDTH{1'b0}};                     // 清第二级
            fcnt <= 2'd0;                                   // 清字节数
        end                                                 // 复位分支结束
        else if (arr && pop) begin                          // 本拍同时进和出
            if (fcnt == 2'd1) f0 <= ram_q;                  // 只有一项时新字节直接补第一级
            else begin                                      // 满两级时第二级补位
                f0 <= f1;                                   // 次老的一项补第一级
                f1 <= ram_q;                                // 新字节进第二级
            end                                             // 补位分支结束
        end                                                 // 一进一出结束
        else if (arr) begin                                 // 只有新字节到达
            if (fcnt == 2'd0) f0 <= ram_q;                  // 缓存空：进第一级
            else              f1 <= ram_q;                  // 缓存有一项：进第二级
            fcnt <= fcnt + 2'd1;                            // 字节数加一
        end                                                 // 到达分支结束
        else if (pop) begin                                 // 只有取走
            f0   <= f1;                                     // 次老的一项补第一级
            fcnt <= fcnt - 2'd1;                            // 字节数减一
        end                                                 // 取走分支结束
    end                                                     // 返回缓存结束

    always @(posedge rd_clk or negedge rst_b) begin          // 读侧时序
        if (!rst_b) begin                                   // 复位分支
            state     <= S_IDLE_STATE;                      // 回空闲
            slot_r    <= 1'b0;                              // 清槽位
            len_r     <= {ADDR_WIDTH{1'b0}};                // 清长度
            err_r_sel <= 1'b0;                              // 清错误
            issue_ix  <= {ADDR_WIDTH{1'b0}};                // 清发地址计数
            emit_ix   <= {ADDR_WIDTH{1'b0}};                // 清送字节计数
            fetch_d1  <= 1'b0;                              // 清在途读第一拍
            fetch_d2  <= 1'b0;                              // 清在途读第二拍
            ack_tog   <= 2'b00;                             // 清回执
        end                                                 // 复位分支结束
        else begin                                          // 正常运行分支
            fetch_d1 <= fetch;                              // 地址发出第一拍
            fetch_d2 <= fetch_d1;                           // 地址发出第二拍
            if (fetch) issue_ix <= issue_ix + 1'b1;         // 发过一个地址就指向下一字节
            if (state == S_IDLE_STATE) begin                // 空闲：等整帧
                if (any_avail) begin                        // 有整帧待发
                    slot_r    <= pick_slot;                 // 选择槽位
                    len_r     <= pick_slot ? len_rx[1] : len_rx[0]; // 装入帧长
                    err_r_sel <= pick_slot ? err_r[1] : err_r[0];   // 装入错误
                    issue_ix  <= {ADDR_WIDTH{1'b0}};        // 从帧首开始发地址
                    emit_ix   <= {ADDR_WIDTH{1'b0}};        // 从帧首开始送字节
                    state     <= S_READ_STATE;              // 进入读帧
                end                                         // 启动判断结束
            end                                             // 空闲分支结束
            else if (pop) begin                             // 送出一个字节
                if (frame_last) begin                       // 送出的是帧尾
                    ack_tog[slot_r] <= ~ack_tog[slot_r];    // 翻转回执，释放槽位
                    state           <= S_IDLE_STATE;        // 回空闲
                end                                         // 帧尾分支结束
                else                                        // 还有字节
                    emit_ix <= emit_ix + 1'b1;              // 送字节计数前进
            end                                             // 输出分支结束
        end                                                 // 正常运行分支结束
    end                                                     // 读侧时序结束

    // ==================== 读侧回执同步回写域 ====================
    reg [1:0] ack_d0, ack_d1;                               // 回执同步到写域
    always @(posedge wr_clk or negedge rst_b) begin          // 回执同步
        if (!rst_b) begin                                   // 复位分支
            ack_d0   <= 2'b00;                              // 清首级
            ack_d1   <= 2'b00;                              // 清末级
            free_ack <= 2'b00;                              // 清写域回执
        end                                                 // 复位分支结束
        else begin                                          // 正常运行分支
            ack_d0   <= ack_tog;                            // 打一拍
            ack_d1   <= ack_d0;                             // 再打一拍
            free_ack <= ack_d1;                             // 交给写侧
        end                                                 // 正常运行分支结束
    end                                                     // 同步结束

    // ==================== 缓存 IP（读写时钟独立） ====================
    rx_frame_buf u_tx_frame_buf (                           // 发送帧缓存，简单双口 RAM
        .wrclock   (wr_clk),                                // 写时钟：核心侧
        .rdclock   (rd_clk),                                // 读时钟：MAC 侧
        .data      (core_tx_data),                          // 写数据
        .rdaddress (ram_rd_addr),                           // 读地址
        .wraddress (ram_wr_addr),                           // 写地址
        .wren      (ram_wr_en),                             // 写使能
        .rden      (fetch),                                 // 读使能：本拍要取下一字节
        .q         (ram_q)                                  // 读数据，读使能后两拍有效
    );                                                      // 发送帧缓存例化结束

endmodule                                                   // 模块定义结束

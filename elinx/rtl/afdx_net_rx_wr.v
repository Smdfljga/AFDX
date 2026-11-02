// afdx_net_rx_wr : 单网接收写侧（MAC 时钟域，125MHz）
// 把 MAC 送来的整帧字节写进本网帧缓存的一个空闲槽位，帧尾登记长度/错误并翻转本槽位握手标志；
// 槽位空闲判定用读侧回执标志（已同步到本时钟域）：写侧标志与回执不一致说明该槽位上一帧还没读走。
// 每槽 SLOT 字节（2KB），两槽正好一个 4096 字节缓存；空间够就整帧写入，超长或不可用则整帧丢弃。
module afdx_net_rx_wr #(                                    // 声明模块及其参数接口
    parameter DATA_WIDTH = 8,                               // 数据位宽
    parameter ADDR_WIDTH = 12,                              // 帧缓存地址位宽（4096 字节）
    parameter MAX_FRAME  = 1536,                            // 单帧最大字节数
    parameter SLOT_BITS  = 11                               // 每槽字节数位宽（2KB）
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位（MAC 时钟域） ====================
    input  wire                          clk,                    // 写侧时钟 = MAC 用户时钟 125MHz
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== MAC 接收字节流 ====================
    input  wire [DATA_WIDTH-1:0]         rx_data,                // MAC 接收数据
    input  wire                          rx_data_vld,            // MAC 接收数据有效
    input  wire                          rx_sop,                 // MAC 接收包起始
    input  wire                          rx_eop,                 // MAC 接收包结束
    input  wire                          rx_err,                 // MAC 接收错误
    output wire                          rx_rdy,                 // 接收准备（整帧入缓存，恒为 1）

    // ==================== 帧缓存写口 ====================
    output wire [ADDR_WIDTH-1:0]         ram_wr_addr,            // 缓存写地址 = {槽位, 槽内偏移}
    output wire [DATA_WIDTH-1:0]         ram_wr_data,            // 缓存写数据
    output wire                          ram_wr_en,              // 缓存写使能

    // ==================== 跨时钟握手 ====================
    input  wire [1:0]                    ack_toggle,             // 读侧回执标志（已同步到本域）
    output wire [1:0]                    wr_toggle,              // 本域写侧完成标志（供读侧同步）

    // ==================== 槽位描述符（读侧使用，翻转前已稳定） ====================
    output wire [ADDR_WIDTH-1:0]         slot_len0,              // 槽位 0 整帧字节数
    output wire [ADDR_WIDTH-1:0]         slot_len1,              // 槽位 1 整帧字节数
    output wire [1:0]                    slot_err                 // 槽位错误标记
);                                                          // 端口声明或模块例化结束

    localparam SLOT_BYTES = (1 << SLOT_BITS);                   // 每槽字节数

    // ==================== 入口打拍：切短 MAC 用户侧组合路径 ====================
    // MAC 的 ff_rx_* 是「FIFO RAM 读 + 7 级 LUT 转字节」的组合输出，实测从 MAC 内部触发器
    // 到本模块帧缓存输入寄存器要 10.2ns（MAC 内 5.85ns + 跨块布线 1.3ns），125MHz 过不去。
    // 这里把五个信号一起打一拍，MAC 那一侧只需接到就近的这个触发器；帧内语义不变，
    // 且 rx_rdy 恒为 1，所以对 MAC 侧没有任何反压影响，只多 1 个 125MHz 周期的延迟。
    reg  [DATA_WIDTH-1:0] q_data;                              // 打拍后的接收数据
    reg                   q_vld;                               // 打拍后的数据有效
    reg                   q_sop;                               // 打拍后的帧首
    reg                   q_eop;                               // 打拍后的帧尾
    reg                   q_err;                               // 打拍后的错误标记

    always @(posedge clk or negedge rst_b) begin                // 入口寄存器
        if (!rst_b) begin                                       // 复位分支
            q_data <= {DATA_WIDTH{1'b0}};                       // 清数据
            q_vld  <= 1'b0;                                     // 清有效
            q_sop  <= 1'b0;                                     // 清帧首
            q_eop  <= 1'b0;                                     // 清帧尾
            q_err  <= 1'b0;                                     // 清错误
        end                                                     // 复位分支结束
        else begin                                              // 正常运行分支
            q_data <= rx_data;                                  // 数据打一拍
            q_vld  <= rx_data_vld;                              // 有效打一拍
            q_sop  <= rx_sop;                                   // 帧首打一拍
            q_eop  <= rx_eop;                                   // 帧尾打一拍
            q_err  <= rx_err;                                   // 错误打一拍
        end                                                     // 正常运行分支结束
    end                                                         // 入口寄存器结束

    reg                   busy;                                 // 正在接收一帧
    reg                   drop;                                 // 本帧因超长/无槽位丢弃
    reg  [0:0]            cur_slot;                             // 本帧占用的槽位
    reg  [SLOT_BITS-1:0]  wr_off;                               // 本帧已写字节数（槽内偏移）
    reg  [1:0]            tog_r;                                // 写侧完成标志
    reg  [ADDR_WIDTH-1:0] len_rx [0:1];                         // 每槽整帧字节数
    reg  [1:0]            err_r;                                // 每槽错误标记
    reg                   err_acc;                              // 本帧错误累积

    wire slot_free0 = (tog_r[0] == ack_toggle[0]);              // 槽位 0 空闲（上一帧已被读走）
    wire slot_free1 = (tog_r[1] == ack_toggle[1]);              // 槽位 1 空闲
    wire any_free   = slot_free0 | slot_free1;                  // 还有空闲槽位

    wire        wr_en    = q_vld && (busy ? !drop : q_sop) && (busy || any_free); // 本拍写入一个字节（含帧首字节）
    wire        wr_first = q_vld && !busy && q_sop;              // 本拍是帧首字节（尚未进入帧内）
    wire [0:0]  wr_slot  = wr_first ? (slot_free0 ? 1'b0 : 1'b1) : cur_slot;  // 帧首即选空闲槽位
    wire [SLOT_BITS-1:0] wr_off_sel = wr_first ? {SLOT_BITS{1'b0}} : wr_off;  // 帧首写首字节位置
    wire [SLOT_BITS-1:0] wr_off_nxt = wr_off + 1'b1;            // 本帧字节数加一
    wire        over_len = (wr_off_nxt > MAX_FRAME) ||          // 超单帧上限
                           (wr_off_nxt > SLOT_BYTES);           // 超槽位容量

    assign rx_rdy       = 1'b1;                                 // 整帧先入缓存，MAC 侧恒可接收
    assign ram_wr_en    = wr_en;                                // 缓存写使能
    assign ram_wr_addr  = {wr_slot, wr_off_sel};               // 写地址：槽位在高位（帧首直接用新槽位与 0 偏移）
    assign ram_wr_data  = q_data;                               // 写数据为打拍后的 MAC 字节
    assign wr_toggle    = tog_r;                                // 写侧完成标志引出
    assign slot_len0    = len_rx[0];                            // 槽位 0 长度
    assign slot_len1    = len_rx[1];                            // 槽位 1 长度
    assign slot_err     = err_r;                                // 槽位错误标记

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应异步复位
        if (!rst_b) begin                                   // 复位分支
            busy      <= 1'b0;                              // 退出帧内
            drop      <= 1'b0;                              // 清丢弃标志
            cur_slot  <= 1'b0;                              // 默认槽位 0
            wr_off    <= {SLOT_BITS{1'b0}};                 // 清帧内偏移
            tog_r     <= 2'b00;                             // 清握手标志
            err_acc   <= 1'b0;                              // 清错误累积
            err_r     <= 2'b00;                             // 清槽位错误
            len_rx[0] <= {ADDR_WIDTH{1'b0}};                // 清槽位 0 长度
            len_rx[1] <= {ADDR_WIDTH{1'b0}};                // 清槽位 1 长度
        end                                                 // 复位分支结束
        else if (q_vld) begin                               // MAC 送来一个字节（打拍后）
            if (!busy) begin                                // 不在帧内：本字节是帧首
                if (q_sop) begin                            // 确认是帧首
                    busy    <= 1'b1;                        // 进入帧内
                    err_acc <= q_err;                       // 记录本帧错误初值
                    if (any_free) begin                     // 有空闲槽位就整帧收下
                        drop     <= 1'b0;                   // 本帧不丢弃
                        cur_slot <= slot_free0 ? 1'b0 : 1'b1; // 优先槽位 0
                        wr_off   <= {{(SLOT_BITS-1){1'b0}}, 1'b1}; // 已写 1 字节
                    end                                     // 有空闲槽位分支结束
                    else begin                              // 两槽都在读：整帧丢弃
                        drop   <= 1'b1;                     // 置丢弃
                        wr_off <= {SLOT_BITS{1'b0}};        // 清偏移
                    end                                     // 无空闲槽位分支结束
                end                                         // 帧首分支结束
            end                                             // 不在帧内分支结束
            else if (!drop) begin                           // 帧内且未丢弃
                wr_off <= wr_off_nxt;                       // 帧内偏移前进（与写地址同拍）
                err_acc <= err_acc | q_err;                 // 错误标记累积
                if (over_len) begin                         // 超长：剩余字节全部丢弃
                    drop <= 1'b1;                           // 置丢弃
                end                                         // 超长分支结束
                if (q_eop) begin                            // 帧尾：登记长度与错误
                    if (!over_len) begin                    // 长度合法才登记
                        len_rx[cur_slot] <= wr_off_nxt;     // 整帧字节数
                        err_r[cur_slot]  <= err_acc | q_err; // 整帧错误标记
                        tog_r[cur_slot]  <= ~tog_r[cur_slot]; // 通知读侧有整帧可取
                    end                                     // 长度合法分支结束
                    busy <= 1'b0;                           // 退出帧内
                end                                         // 帧尾分支结束
            end                                             // 帧内未丢弃分支结束
            else if (q_eop) begin                           // 帧内已丢弃：只等帧尾
                busy <= 1'b0;                               // 退出帧内
            end                                             // 丢弃分支结束
        end                                                 // 字节处理结束
    end                                                     // 写侧时序结束

endmodule                                                   // 模块定义结束

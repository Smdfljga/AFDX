// rx_port_buf : 接收端口缓冲（支持采样 / 队列 / SAP 三种端口语义）
// 物理存储：32768 × 8bit 简单双端口 RAM（16 个槽位 × 每槽 2KB）
// 物理地址 = {VL 槽位号[3:0], 槽内偏移[10:0]}
// 每个槽位的队列状态（寄存器，见下方“队列状态”表）：
// 写指针 wr_ptr / 读指针 rd_ptr 在槽内 2KB 空间里按字节环形推进，
// 帧尾提交时把帧长压入该槽位的长度 FIFO，读侧读到该帧最后一字节自动出队。
// 三种端口的差异（由 wr_queue_mode 选择）：
// 采样端口（port_type=00，mode=0）：写指针归零重写，只保留最新一帧（frame_cnt 恒为 1）
// 队列端口（port_type=01，mode=1）：帧按到达顺序入队，读侧逐帧出队（最多 4 帧）
// SAP 端口（port_type=10，mode=1）：同队列端口（615A/TFTP 是请求-响应式）
// 读侧由 rx_rd_arb 仲裁后访问；本模块按“顺序读”约定自动出队（见注释“出队条件”）
module rx_port_buf #(                                       // 声明模块及其参数接口
    parameter DATA_WIDTH        = 8,        // 数据位宽
    parameter VL_INDEX_WIDTH    = 4,        // VL 槽位号位宽（默认 16 个槽位）
    parameter BYTE_OFFSET_WIDTH = 11,        // 槽内偏移位宽（每槽 2KB）
    parameter FRAME_LEN_WIDTH   = 16,       // 帧长位宽
    parameter FRAME_CNT_WIDTH   = 3         // 每槽最多排队的帧数（= 2^FRAME_CNT_WIDTH，默认 8）
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（读写同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 写侧（RX 状态机） ====================
    input  wire                          wr_en,                  // 写使能（每字节一拍）
    input  wire [VL_INDEX_WIDTH-1:0]     wr_vl_index,            // 写槽位号 = vlid[VL_INDEX_WIDTH-1:0]
    input  wire [BYTE_OFFSET_WIDTH-1:0]  wr_byte_offset,         // 帧内数据偏移，从 0 连续递增
    input  wire [DATA_WIDTH-1:0]         wr_data,                // 写数据（应用数据，不含 SN）
    input  wire                          wr_frag_done,           // 每帧结束脉冲（含非末片），用于推进重组状态
    input  wire                          wr_frame_done,          // 消息结束脉冲：仅末片/未分片帧有效，提交整条消息
    input  wire [FRAME_LEN_WIDTH-1:0]    wr_frame_len,           // 本帧数据长度（与 wr_frame_done 同拍）
    input  wire                          wr_queue_mode,          // 0=采样端口（覆盖） 1=队列/SAP 端口（入队）
    input  wire [FRAME_LEN_WIDTH-1:0]    wr_frag_off,            // 本帧数据在整条消息内的起始字节偏移（0=首片或未分片）
    input  wire                          wr_more,                // 本帧之后还有分片（IP MF=1），尚无消息可提交
    output wire                          wr_full,                // 该槽位队列已满：RX 应丢弃新帧并计错

    // ==================== 读侧（来自 rx_rd_arb） ====================
    input  wire                          rd_en,                  // 读使能
    input  wire [VL_INDEX_WIDTH-1:0]     rd_vl_index,            // 读槽位号
    input  wire [BYTE_OFFSET_WIDTH-1:0]  rd_byte_offset,         // 帧内数据偏移（0 = 帧首字节）
    output wire [DATA_WIDTH-1:0]         rd_data,                // 读数据（同步读，M4K 地址寄存 + 输出寄存，地址稳定后两拍有效）
    output wire                          rd_valid,               // 读数据有效（rd_en 打两拍，仲裁器不依赖它）

    // ==================== 读侧状态（供消费者判断帧边界） ====================
    // 做成"全部槽位"的向量，消费者按自己的槽位号切片（槽位号在设计期固定，属常量选择）；
    // 这样每个消费者都能随时查自己的帧长/帧数，不需要经过仲裁。
    output wire [(1<<VL_INDEX_WIDTH)*FRAME_LEN_WIDTH-1:0] rd_frame_len_all,   // 每槽位当前待读帧长度
    output wire [(1<<VL_INDEX_WIDTH)*(FRAME_CNT_WIDTH+1)-1:0] rd_frame_cnt_all // 每槽位待读帧数（0=空）
);                                                          // 端口声明或模块例化结束

    // ==================== 队列参数 ====================
    localparam SLOT_NUM    = 1 << VL_INDEX_WIDTH;               // 槽位数，默认 16
    localparam MAX_FRAMES  = 1 << FRAME_CNT_WIDTH;              // 每槽最多排队帧数，默认 8
    localparam SLOT_BYTES  = 1 << BYTE_OFFSET_WIDTH;            // 每槽容量，默认 2048 字节

    // ==================== 每槽队列状态 ====================
    reg [BYTE_OFFSET_WIDTH-1:0] wr_ptr [0:SLOT_NUM-1];          // 写指针：下一帧的槽内起始偏移
    reg [BYTE_OFFSET_WIDTH-1:0] rd_ptr [0:SLOT_NUM-1];          // 读指针：当前待读帧的槽内起始偏移
    reg [FRAME_CNT_WIDTH:0]     frame_cnt [0:SLOT_NUM-1];   // 待读帧数，额外一位表示队列全满
    reg                         queue_mode [0:SLOT_NUM-1];      // 该槽端口类型：0=采样 1=队列/SAP
    reg [FRAME_CNT_WIDTH-1:0]   fifo_wr_ptr [0:SLOT_NUM-1];  // 长度 FIFO 写指针
    reg [FRAME_CNT_WIDTH-1:0]   fifo_rd_ptr [0:SLOT_NUM-1];  // 长度 FIFO 读指针
    reg [FRAME_LEN_WIDTH-1:0]   len_fifo [0:SLOT_NUM-1][0:MAX_FRAMES-1];  // 完整帧长可表示整槽二千零四十八字节
    reg [BYTE_OFFSET_WIDTH-1:0] rd_progress [0:SLOT_NUM-1];  // 顺序读取时下一次应出现的字节偏移
    // ==================== 分片重组状态（每槽位） ====================
    // 非末片写进槽内的“未提交区”，末片到达时才按整条消息长度一次性提交，
    // 因此读侧看到的永远是一条完整消息，重组过程对上层不可见。
    reg [FRAME_LEN_WIDTH-1:0] reasm_bytes  [0:SLOT_NUM-1];   // 已收到的消息字节数（后续分片的槽内基址）
    reg [FRAME_LEN_WIDTH-1:0] reasm_next   [0:SLOT_NUM-1];   // 下一片应出现的消息内偏移（连续性检查）
    reg                       reasm_active [0:SLOT_NUM-1];   // 该槽位已收到非末片，正在等待后续分片
    reg                       reasm_bad    [0:SLOT_NUM-1];   // 本次重组出错（不连续/越界），末片到达时丢弃

    integer slot_i;                                             // 复位遍历槽位
    integer fifo_i;                                             // 复位遍历长度 FIFO

    // ==================== 物理地址 ====================
    // 两个 11bit 数相加时超出位自然丢弃，恰好实现模 2^BYTE_OFFSET_WIDTH 的环形地址。
    // 消息内偏移 = 已重组字节数 + 帧内偏移；未分片帧的已重组字节数恒为 0。
    wire [FRAME_LEN_WIDTH-1:0] wr_msg_offset = reasm_bytes[wr_vl_index] + wr_byte_offset;  // 消息内字节偏移
    wire wr_overrun = (wr_msg_offset >= SLOT_BYTES);        // 消息超过槽容量：不再写入，末片到达时丢弃
    wire [BYTE_OFFSET_WIDTH-1:0] wr_offset = wr_queue_mode ?  // 队列按环形指针写入，采样立即从槽首覆盖
        wr_ptr[wr_vl_index] + wr_msg_offset[BYTE_OFFSET_WIDTH-1:0] :  // 槽内偏移对 2KB 取模
        wr_msg_offset[BYTE_OFFSET_WIDTH-1:0];               // 采样首字节不依赖尚未复位的旧写指针
    wire [BYTE_OFFSET_WIDTH-1:0] rd_offset = rd_ptr[rd_vl_index] + rd_byte_offset; // 槽内真实读偏移

    wire [VL_INDEX_WIDTH+BYTE_OFFSET_WIDTH-1:0] wr_addr =   // 写入物理地址，由槽位与字节偏移拼接
        {wr_vl_index, wr_offset};                               // 写地址：槽位号在高位
    wire [VL_INDEX_WIDTH+BYTE_OFFSET_WIDTH-1:0] rd_addr =   // 读取物理地址，由槽位与字节偏移拼接
        {rd_vl_index, rd_offset};                               // 读地址：槽位号在高位

    // 简单双端口 M4K IP（8bit × 32768 = 32KB/端口）
    // 由 eLinx 的 Local Memory IP 生成，地址位宽 = VL_INDEX_WIDTH + BYTE_OFFSET_WIDTH = 15，
    // 读写地址拼接方式必须与 IP 的 32768 深一致
    rx_port_buf_ip u_rx_port_buf_ip (                       // 例化子模块并连接数据通路
        .inclock    (clk),                                      // input  [0:0]
        .in_aclr    (~rst_b),                                   // input  [0:0]  高有效异步清零
        .wraddress  (wr_addr),                                  // input  [14:0]
        .data       (wr_data),                                  // input  [7:0]
        .wren       (wr_en && !wr_full),                    // input [0:0] 满时禁止物理写入，保护尚未读出的队列数据
        .outclock   (clk),                                      // input  [0:0]
        .out_aclr   (~rst_b),                                   // input  [0:0]
        .rdaddress  (rd_addr),                                  // input  [14:0]
        .rden       (rd_en),                                    // input  [0:0]
        .q          (rd_data)                                   // output [7:0]
    );                                                      // 端口声明或模块例化结束

    // IP 读输出寄存：地址/rden 被采样后两拍 q 才有数据（厂商 altsyncram 地址寄存 + 输出寄存）
    reg rd_en_d1;                                               // 读使能打第一拍
    reg rd_en_d;                                                // 读使能打第二拍，与 q 同拍
    always @(posedge clk or negedge rst_b)                  // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            rd_en_d1 <= 1'b0;                               // 检查复位或正常运行条件
            rd_en_d  <= 1'b0;                               // 检查复位或正常运行条件
        end                                                 // 当前语句组结束
        else begin                                          // 采用前一条件未满足时的处理
            rd_en_d1 <= rd_en;                              // 读使能打第一拍
            rd_en_d  <= rd_en_d1;                           // 读使能打第二拍
        end                                                 // 当前语句组结束

    assign rd_valid = rd_en_d;                                  // output [0:0]：与 q 同拍有效

    // ==================== 当前写槽的剩余空间 ====================
    wire pointers_equal = (wr_ptr[wr_vl_index] == rd_ptr[wr_vl_index]); // 空环或满环时指针相等
    wire [BYTE_OFFSET_WIDTH:0] used_current =               // 多一位以区分空槽与整槽占满
        (frame_cnt[wr_vl_index] == 0) ? 0 :                 // 没有已提交帧时可用空间为整槽
        pointers_equal ? SLOT_BYTES :                       // 非空且指针相等代表整槽占满
        (wr_ptr[wr_vl_index] > rd_ptr[wr_vl_index])         // 判断写指针是否尚未跨越环形回绕点
            ? {1'b0, wr_ptr[wr_vl_index]} - {1'b0, rd_ptr[wr_vl_index]}  // 未回绕时按写读指针差计算已用空间
            : SLOT_BYTES -                                  // 写指针回绕时按槽容量计算占用
              ({1'b0, rd_ptr[wr_vl_index]} - {1'b0, wr_ptr[wr_vl_index]}); // 已占用的环形字节数
    // 只有末片才会提交，此时整条消息长度 = 已重组字节数 + 本帧长度；
    // 未分片帧的已重组字节数为零，两种情形共用同一表达式。
    wire [FRAME_LEN_WIDTH-1:0] commit_len = reasm_bytes[wr_vl_index] + wr_frame_len;  // 整条消息长度
    wire [BYTE_OFFSET_WIDTH:0] free_current = SLOT_BYTES - used_current;  // 当前写槽可用字节数

    // 队列端口同时受“最多 8 帧”和“2KB 环形空间”两个约束；采样端口覆盖，因此永远不判满。
    assign wr_full = wr_overrun || (commit_len > SLOT_BYTES) ||  // 任意端口都不能容纳超过整槽容量的消息
                     (wr_queue_mode && ((frame_cnt[wr_vl_index] >= MAX_FRAMES) ||  // 队列长度上限只约束队列模式
                     (commit_len > free_current)));         // 使用整条消息长度判断空间，禁止高位截断后误判

    // ==================== 队列状态维护 ====================
    // 顺序读约定：只有 rd_byte_offset == 当前帧长 - 1 才出队；采样端口不出队。
    wire [FRAME_LEN_WIDTH-1:0] head_len =                   // 队首长度保留容量位，二千零四十八不能截成零
        len_fifo[rd_vl_index][fifo_rd_ptr[rd_vl_index]];        // 当前待读帧的队首长度
    wire sample_restart = wr_en && !wr_queue_mode &&        // 采样首字节覆盖优先于同槽旧队列的出队
                          (wr_byte_offset == 0) && (wr_frag_off == 0) &&  // 只有新消息首片才覆盖旧值
                          (wr_vl_index == rd_vl_index);  // 同槽采样覆盖判定
    wire sample_commit = wr_frame_done && !wr_queue_mode &&  // 同槽采样提交不能再被旧队列出队覆盖
                         (wr_vl_index == rd_vl_index);      // 同槽采样提交判定
    wire enqueue_now = wr_frame_done && wr_queue_mode && !wr_full;  // 本拍确实有队列帧入队
    wire dequeue_now = queue_mode[rd_vl_index] &&           // 只有队列或 SAP 模式自动出队
                       rd_en &&                             // 读请求有效后继续判定出队条件
                       (frame_cnt[rd_vl_index] != 4'd0) &&  // 槽内存在完整帧时才允许出队
                       (head_len != 0) &&                   // 空长度不能触发模回绕后的误出队
                       (rd_byte_offset == rd_progress[rd_vl_index]) &&  // 只有完整顺序读才允许弹出
                       !sample_restart && !sample_commit &&  // 采样覆盖时保留新帧状态
                       (rd_byte_offset == head_len - 1'b1);     // 读到队列帧最后一字节

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            for (slot_i = 0; slot_i < SLOT_NUM; slot_i = slot_i + 1) begin  // 依次处理指定范围内的表项或位段
                wr_ptr[slot_i]     <= {BYTE_OFFSET_WIDTH{1'b0}};  // 时钟沿更新写指针：下一帧的槽内起始偏移
                rd_ptr[slot_i]     <= {BYTE_OFFSET_WIDTH{1'b0}};  // 时钟沿更新读指针：当前待读帧的槽内起始偏移
                rd_progress[slot_i] <= {BYTE_OFFSET_WIDTH{1'b0}};  // 复位时从帧首开始跟踪顺序读
                reasm_bytes[slot_i]  <= {FRAME_LEN_WIDTH{1'b0}};  // 复位时重组累计字节数为零
                reasm_next[slot_i]   <= {FRAME_LEN_WIDTH{1'b0}};  // 复位时下一片偏移为零
                reasm_active[slot_i] <= 1'b0;               // 复位时不在重组状态
                reasm_bad[slot_i]    <= 1'b0;               // 复位时无重组错误
                frame_cnt[slot_i]  <= 4'd0;                 // 时钟沿更新待读帧数
                queue_mode[slot_i] <= 1'b0;                 // 时钟沿更新该槽端口类型：0=采样 1=队列/SAP
                fifo_wr_ptr[slot_i] <= 3'd0;                // 时钟沿更新长度 FIFO 写指针
                fifo_rd_ptr[slot_i] <= 3'd0;                // 时钟沿更新长度 FIFO 读指针
                for (fifo_i = 0; fifo_i < MAX_FRAMES; fifo_i = fifo_i + 1)  // 依次处理指定范围内的表项或位段
                    len_fifo[slot_i][fifo_i] <= {FRAME_LEN_WIDTH{1'b0}};  // 清零完整帧长
            end                                             // 当前语句组结束
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            // 采样端口在新帧第一字节到达时丢弃旧值，并锁定该槽为覆盖模式。
            if (wr_en && (wr_byte_offset == {BYTE_OFFSET_WIDTH{1'b0}}) && !wr_queue_mode) begin  // 检查写使能（每字节一拍）、帧内数据偏移、槽内偏移位宽（每槽 2KB）的条件
                wr_ptr[wr_vl_index]     <= {BYTE_OFFSET_WIDTH{1'b0}};  // 时钟沿更新写指针：下一帧的槽内起始偏移
                rd_ptr[wr_vl_index]     <= {BYTE_OFFSET_WIDTH{1'b0}};  // 时钟沿更新读指针：当前待读帧的槽内起始偏移
                rd_progress[wr_vl_index] <= {BYTE_OFFSET_WIDTH{1'b0}};  // 新采样帧重置顺序读取进度
                frame_cnt[wr_vl_index]  <= 4'd0;            // 时钟沿更新待读帧数
                queue_mode[wr_vl_index] <= 1'b0;            // 时钟沿更新该槽端口类型：0=采样 1=队列/SAP
                fifo_wr_ptr[wr_vl_index] <= 3'd0;           // 时钟沿更新长度 FIFO 写指针
                fifo_rd_ptr[wr_vl_index] <= 3'd0;           // 时钟沿更新长度 FIFO 读指针
            end                                             // 当前语句组结束
            else if (wr_en && (wr_byte_offset == {BYTE_OFFSET_WIDTH{1'b0}})) begin  // 检查写使能（每字节一拍）、帧内数据偏移、槽内偏移位宽（每槽 2KB）的条件
                queue_mode[wr_vl_index] <= 1'b1;                // 队列/SAP 端口
            end                                             // 当前语句组结束

            // 分片重组：新消息首片清空重组状态；后续分片检查连续性（缺片/乱序则整条作废）。
            if (wr_en && (wr_byte_offset == {BYTE_OFFSET_WIDTH{1'b0}})) begin  // 每帧首字节到达时判定
                if (wr_frag_off == {FRAME_LEN_WIDTH{1'b0}}) begin  // 首片或未分片帧
                    reasm_bytes[wr_vl_index]  <= {FRAME_LEN_WIDTH{1'b0}};  // 从消息首字节重新累计
                    reasm_next[wr_vl_index]   <= {FRAME_LEN_WIDTH{1'b0}};  // 期望偏移归零
                    reasm_active[wr_vl_index] <= 1'b0;      // 清掉上一条消息残留的重组状态
                    reasm_bad[wr_vl_index]    <= 1'b0;      // 清掉上一条消息的错误标记
                end                                         // 当前语句组结束
                else if (!reasm_active[wr_vl_index] ||      // 没收到首片就来了后续片
                         (wr_frag_off != reasm_next[wr_vl_index]))  // 偏移与期望不符=缺片或乱序
                    reasm_bad[wr_vl_index] <= 1'b1;         // 整条消息作废，末片到达时不提交
            end                                             // 当前语句组结束
            // 每帧结束推进重组累计；末片与未分片帧由 wr_frame_done 一并提交。
            if (wr_frag_done) begin                         // 检查每帧结束脉冲
                if (wr_more) begin                          // 还有后续分片：不提交，只累计
                    reasm_bytes[wr_vl_index]  <= reasm_bytes[wr_vl_index] + wr_frame_len;  // 累计消息字节数
                    reasm_next[wr_vl_index]   <= wr_frag_off + 16'd9 + wr_frame_len;  // 下一片偏移=本片偏移+8B UDP+1B SN+数据
                    reasm_active[wr_vl_index] <= 1'b1;      // 标记正在重组
                end                                         // 当前语句组结束
                else begin                                  // 末片或未分片帧：重组结束
                    reasm_bytes[wr_vl_index]  <= {FRAME_LEN_WIDTH{1'b0}};  // 清空累计
                    reasm_next[wr_vl_index]   <= {FRAME_LEN_WIDTH{1'b0}};  // 清空期望偏移
                    reasm_active[wr_vl_index] <= 1'b0;      // 退出重组状态
                    reasm_bad[wr_vl_index]    <= 1'b0;      // 清除错误标记
                end                                         // 当前语句组结束
            end                                             // 当前语句组结束

            // 帧尾提交：采样模式只保留最新一帧，队列模式在空间允许时入队。
            // 只有末片/未分片帧才提交，提交长度用整条消息长度 commit_len；
            // 重组出错（缺片/乱序/超槽容量）的消息一律丢弃，不破坏已有帧。
            if (wr_frame_done) begin                        // 检查帧尾脉冲：提交本帧（登记长度/入队）的条件
                if (!wr_queue_mode && !reasm_bad[wr_vl_index] && !wr_overrun) begin  // 检查0=采样端口（覆盖） 1=队列/SAP 端口（入队）的条件
                    len_fifo[wr_vl_index][0] <= commit_len;  // 保存完整采样消息长度
                    fifo_wr_ptr[wr_vl_index] <= 3'd0;       // 时钟沿更新长度 FIFO 写指针
                    fifo_rd_ptr[wr_vl_index] <= 3'd0;       // 时钟沿更新长度 FIFO 读指针
                    wr_ptr[wr_vl_index]    <= {BYTE_OFFSET_WIDTH{1'b0}};  // 时钟沿更新写指针：下一帧的槽内起始偏移
                    rd_ptr[wr_vl_index]    <= {BYTE_OFFSET_WIDTH{1'b0}};  // 时钟沿更新读指针：当前待读帧的槽内起始偏移
                    rd_progress[wr_vl_index] <= {BYTE_OFFSET_WIDTH{1'b0}};  // 提交采样帧后从零开始读
                    frame_cnt[wr_vl_index] <= 4'd1;         // 时钟沿更新待读帧数
                end                                         // 当前语句组结束
                else if (wr_queue_mode && !wr_full && !reasm_bad[wr_vl_index]) begin  // 检查该槽位队列已满：RX 应丢弃新帧并计错的条件
                    len_fifo[wr_vl_index][fifo_wr_ptr[wr_vl_index]] <=  // 继续计算frame_cnt
                        commit_len;                          // 队列长度包含整槽容量位
                    fifo_wr_ptr[wr_vl_index] <= fifo_wr_ptr[wr_vl_index] + 3'd1;  // 时钟沿更新长度 FIFO 写指针并推进至下一项
                    frame_cnt[wr_vl_index]  <= frame_cnt[wr_vl_index] + 4'd1;  // 时钟沿更新待读帧数并推进至下一项
                    wr_ptr[wr_vl_index]     <= wr_ptr[wr_vl_index] +  // 时钟沿更新写指针：下一帧的槽内起始偏移
                                               commit_len[BYTE_OFFSET_WIDTH-1:0];  // 继续计算wr_ptr
                end                                         // 当前语句组结束
                // 满时指针与计数都不推进：已经写进“未提交区”的字节由下一帧自然覆盖。
            end                                             // 当前语句组结束

            // 队列端口读到队首帧最后一字节时自动出队。
            if (rd_en && queue_mode[rd_vl_index] && (frame_cnt[rd_vl_index] != 0) &&  // 只维护非空队列的读进度
                !sample_restart && !sample_commit && (rd_byte_offset == rd_progress[rd_vl_index]))  // 跳读或重复读不推进
                rd_progress[rd_vl_index] <= rd_progress[rd_vl_index] + 1'b1;  // 连续读取一个字节后期待下一偏移
            if (dequeue_now) begin                          // 检查只有队列或 SAP 模式自动出队的条件
                rd_ptr[rd_vl_index] <= rd_ptr[rd_vl_index] + head_len;  // 时钟沿更新读指针：当前待读帧的槽内起始偏移
                rd_progress[rd_vl_index] <= {BYTE_OFFSET_WIDTH{1'b0}};  // 下一队首帧重新从偏移零开始
                fifo_rd_ptr[rd_vl_index] <= fifo_rd_ptr[rd_vl_index] + 3'd1;  // 时钟沿更新长度 FIFO 读指针并推进至下一项
                if (enqueue_now && (wr_vl_index == rd_vl_index))  // 同槽同拍入队出队时两次事件抵消
                    frame_cnt[rd_vl_index] <= frame_cnt[rd_vl_index];  // 避免后一个非阻塞赋值覆盖入队增量
                else frame_cnt[rd_vl_index] <= frame_cnt[rd_vl_index] - 1'b1;  // 只有出队时帧数减一
            end                                             // 当前语句组结束
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    // ==================== 读侧状态输出 ====================
    genvar g;                                               // 声明参数化生成循环的索引
    generate                                                // 按参数生成对应硬件结构
        for (g = 0; g < SLOT_NUM; g = g + 1) begin : g_slot_status  // 依次处理指定范围内的表项或位段
            assign rd_frame_len_all[g*FRAME_LEN_WIDTH +: FRAME_LEN_WIDTH] =  // 设置或组合计算每槽位当前待读帧长度
                (frame_cnt[g] == 0) ? {FRAME_LEN_WIDTH{1'b0}} :  // 空槽帧长为零，不暴露过期队首长度
                 len_fifo[g][fifo_rd_ptr[g]];               // 非空槽输出完整队首帧长
            assign rd_frame_cnt_all[g*(FRAME_CNT_WIDTH+1) +: (FRAME_CNT_WIDTH+1)] =  // 设置或组合计算rd_frame_cnt_all
                frame_cnt[g];                                   // 每槽待读帧数
        end                                                 // 当前语句组结束
    endgenerate                                             // 参数化生成结构结束

endmodule                                                   // 模块定义结束

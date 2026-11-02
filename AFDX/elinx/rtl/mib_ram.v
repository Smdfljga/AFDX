// mib_ram : MIB 计数存储（每 VL 一组计数器）
// 管理信息库：每条 VL 的统计计数，SNMP 通过读口查询，计数事件通过维护口累加
// 模块内部对维护口做「读-改-写」：读出该 VL 的 5 个计数器，把本拍有效的事件 +1 后写回
// 例化两次：IS_RX=1（RX 事件，用 mib_rx_ip）、IS_RX=0（TX 事件，用 mib_tx_ip）
// 注：计数器不再放在 vl_config_ram 里，避免写配置把计数清零（见 REVIEW.md）
module mib_ram #(                                           // 声明模块及其参数接口
    parameter CNT_WIDTH  = 32,              // 单个计数器位宽
    parameter ADDR_WIDTH = 12,              // 地址位宽（IP 固定 4096 深，必须与生成的 IP 一致）
    parameter IS_RX      = 1'b1             // 1=接收侧计数（mib_rx_ip） 0=发送侧（mib_tx_ip）
)(                                                          // 参数声明结束，开始端口声明
    // 时钟与复位
    input  wire                          clk,                    // 时钟（维护口与读口同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 计数维护口（RX 或 TX 状态机） ====================
    input  wire [ADDR_WIDTH-1:0]         inc_addr,               // 计数事件所属 VL 条目索引
    input  wire                          cnt0_inc,               // 计数器 0 事件 +1
    input  wire                          cnt1_inc,               // 计数器 1 事件 +1
    input  wire                          cnt2_inc,               // 计数器 2 事件 +1
    input  wire                          cnt3_inc,               // 计数器 3 事件 +1
    input  wire                          cnt4_inc,               // 计数器 4 事件 +1

    // ==================== MIB 读口（SNMP 查询） ====================
    input  wire [ADDR_WIDTH-1:0]         rd_addr,                // 查询的 VL 条目索引
    input  wire                          rd_en,                  // 读使能
    output wire [5*CNT_WIDTH-1:0]        rd_data                 // 读回的 5 个计数器
);                                                          // 端口声明或模块例化结束

    // 计数器 0..4 的语义由例化处解释：
    // u_mib_rx: cnt0=接收成功帧数 cnt1=接收错误帧数 cnt2=SN 错误帧数 cnt3=RM 丢弃帧数 cnt4=接收字节数
    // u_mib_tx: cnt0=发送成功帧数 cnt1=发送字节数   cnt2=发送错误帧数 cnt3=分片次数     cnt4=BAG 违反次数

    // ==================== 事件累积参数 ====================
    localparam DELTA_WIDTH = 16;                                // 每个计数器一帧最多数千次 +1，16bit 足够
    localparam EV_WIDTH    = 5 * DELTA_WIDTH;                   // 一个地址上 5 个计数器的增量
    localparam BIN_DEPTH   = 8;                                 // 最多同时缓存 8 个不同地址的事件

    wire [5*CNT_WIDTH-1:0] cnt_word;                            // 维护口读回整字（读-改-写用）
    wire [5*CNT_WIDTH-1:0] cnt_next;                            // 本拍事件累加后的计数
    wire                   cnt_wr;                              // 写回使能

    // ==================== 事件输入打包 ====================
    wire [EV_WIDTH-1:0] event_vec = {                       // 五个 MIB 计数事件扩展为各自的增量位段
        {DELTA_WIDTH-1{1'b0}}, cnt4_inc,                    // 将计数事件 4 扩展为独立增量位段
        {DELTA_WIDTH-1{1'b0}}, cnt3_inc,                    // 将计数事件 3 扩展为独立增量位段
        {DELTA_WIDTH-1{1'b0}}, cnt2_inc,                    // 将计数事件 2 扩展为独立增量位段
        {DELTA_WIDTH-1{1'b0}}, cnt1_inc,                    // 将计数事件 1 扩展为独立增量位段
        {DELTA_WIDTH-1{1'b0}}, cnt0_inc                     // 将计数事件 0 扩展为独立增量位段
    };                                                          // 5 路 +1 事件拼成一个增量字
    wire inc_any = cnt0_inc | cnt1_inc | cnt2_inc | cnt3_inc | cnt4_inc; // 是否有事件

    // ==================== 多地址事件缓存 ====================
    reg [BIN_DEPTH-1:0]         bin_valid;                     // 每个缓存槽是否有待处理事件
    reg [ADDR_WIDTH-1:0]        bin_addr [0:BIN_DEPTH-1];      // 缓存槽对应 VL 地址
    reg [EV_WIDTH-1:0]          bin_delta [0:BIN_DEPTH-1];     // 缓存槽累积的增量

    wire [BIN_DEPTH-1:0] match_bit;                            // 与 inc_addr 地址匹配的缓存槽
    wire [BIN_DEPTH-1:0] empty_bit;                            // 空缓存槽
    genvar match_i;                                         // 声明参数化生成循环的索引
    generate                                                // 按参数生成对应硬件结构
        for (match_i = 0; match_i < BIN_DEPTH; match_i = match_i + 1) begin : g_match  // 依次处理指定范围内的表项或位段
            assign match_bit[match_i] = bin_valid[match_i] && (bin_addr[match_i] == inc_addr);  // 设置或组合计算与 inc_addr 地址匹配的缓存槽
            assign empty_bit[match_i] = !bin_valid[match_i];  // 设置或组合计算空缓存槽
        end                                                 // 当前语句组结束
    endgenerate                                             // 参数化生成结构结束

    wire match_hit = |match_bit;                                // 当前事件与已有缓存同地址
    wire empty_hit = |empty_bit;                                // 存在空缓存槽

    reg [2:0] match_idx;                                        // 地址匹配缓存槽的优先索引
    reg [2:0] empty_idx;                                        // 空缓存槽的优先索引
    reg [2:0] sel_idx;                                          // 待处理缓存槽的优先索引

    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        // 固定优先级 casez 选最低编号，避免综合器对 always 内 for 的迭代次数限制。
        casez (match_bit)                                   // 例化子模块并连接数据通路
            8'b???????1: match_idx = 3'd0;                  // 继续计算empty_hit
            8'b??????1?: match_idx = 3'd1;                  // 继续计算empty_hit
            8'b?????1??: match_idx = 3'd2;                  // 继续计算empty_hit
            8'b????1???: match_idx = 3'd3;                  // 继续计算empty_hit
            8'b???1????: match_idx = 3'd4;                  // 继续计算empty_hit
            8'b??1?????: match_idx = 3'd5;                  // 继续计算empty_hit
            8'b?1??????: match_idx = 3'd6;                  // 继续计算empty_hit
            8'b1???????: match_idx = 3'd7;                  // 继续计算empty_hit
            default:      match_idx = 3'd0;                 // 未匹配有效分支时采用默认处理
        endcase                                             // 当前分支选择结束

        casez (empty_bit)                                   // 例化子模块并连接数据通路
            8'b???????1: empty_idx = 3'd0;                  // 继续计算empty_hit
            8'b??????1?: empty_idx = 3'd1;                  // 继续计算empty_hit
            8'b?????1??: empty_idx = 3'd2;                  // 继续计算empty_hit
            8'b????1???: empty_idx = 3'd3;                  // 继续计算empty_hit
            8'b???1????: empty_idx = 3'd4;                  // 继续计算empty_hit
            8'b??1?????: empty_idx = 3'd5;                  // 继续计算empty_hit
            8'b?1??????: empty_idx = 3'd6;                  // 继续计算empty_hit
            8'b1???????: empty_idx = 3'd7;                  // 继续计算empty_hit
            default:      empty_idx = 3'd0;                 // 未匹配有效分支时采用默认处理
        endcase                                             // 当前分支选择结束

        casez (bin_valid)                                   // 例化子模块并连接数据通路
            8'b???????1: sel_idx = 3'd0;                    // 继续计算empty_hit
            8'b??????1?: sel_idx = 3'd1;                    // 继续计算empty_hit
            8'b?????1??: sel_idx = 3'd2;                    // 继续计算empty_hit
            8'b????1???: sel_idx = 3'd3;                    // 继续计算empty_hit
            8'b???1????: sel_idx = 3'd4;                    // 继续计算empty_hit
            8'b??1?????: sel_idx = 3'd5;                    // 继续计算empty_hit
            8'b?1??????: sel_idx = 3'd6;                    // 继续计算empty_hit
            8'b1???????: sel_idx = 3'd7;                    // 继续计算empty_hit
            default:      sel_idx = 3'd0;                   // 未匹配有效分支时采用默认处理
        endcase                                             // 当前分支选择结束
    end                                                     // 当前语句组结束

    wire sel_any = |bin_valid;                                  // 是否有待处理缓存

    // ==================== 读-改-写状态机 ====================
    localparam S_IDLE  = 2'd0;                                  // 选择缓存并给 RAM 地址
    localparam S_READ  = 2'd1;                                  // 等 RAM 读延迟第一拍
    localparam S_READ2 = 2'd3;                                  // 等 RAM 读延迟第二拍（地址寄存 + 输出寄存）
    localparam S_WRITE = 2'd2;                                  // 累加增量并写回

    reg [1:0]          state;                                   // 维护口状态
    reg [2:0]          op_bin;                                  // 正在处理的缓存槽
    reg [ADDR_WIDTH-1:0] op_addr;                               // 正在处理的 VL 地址
    reg [EV_WIDTH-1:0] op_delta;                                // 已从缓存取出的增量快照

    wire event_matches_op = (state != S_IDLE) &&            // 当前事件地址是否等于正在读改写的条目
                            bin_valid[op_bin] &&            // 继续计算当前事件地址是否等于正在读改写的条目
                            (bin_addr[op_bin] == inc_addr);     // 新事件属于正在处理的地址

    // ==================== 状态机：第二段（组合，算次态） ====================
    reg [1:0] nxt_state;                                        // 次态，由本段组合算出

    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        nxt_state = state;                                      // 默认保持当前状态

        case (state)                                        // 根据维护口状态选择处理分支
            S_IDLE: begin                                   // 处理选择缓存并给 RAM 地址阶段
                if (sel_any)                                // 检查是否有待处理缓存的条件
                    nxt_state = S_READ;                         // 有缓存待处理：发起读-改-写
            end                                             // 当前语句组结束

            S_READ: begin                                   // 处理等 RAM 读延迟第一拍阶段
                nxt_state = S_READ2;                            // 地址已经给出，再等一拍数据才回
            end                                             // 当前语句组结束

            S_READ2: begin                                  // 处理等 RAM 读延迟第二拍阶段
                nxt_state = S_WRITE;                            // 读回数据已稳定，下一拍写回
            end                                             // 当前语句组结束

            S_WRITE: begin                                  // 处理累加增量并写回阶段
                nxt_state = S_IDLE;                             // 写回后回空闲，重新选择缓存
            end                                             // 当前语句组结束

            default: begin                                  // 未匹配有效分支时采用默认处理
                nxt_state = S_IDLE;                             // 异常状态回空闲
            end                                             // 当前语句组结束
        endcase                                             // 当前分支选择结束
    end                                                     // 当前语句组结束

    // ==================== 状态机：第一段（时序，状态寄存器与缓存数据通路） ====================
    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            bin_addr[0]  <= {ADDR_WIDTH{1'b0}};             // 时钟沿更新缓存槽对应 VL 地址
            bin_addr[1]  <= {ADDR_WIDTH{1'b0}};             // 时钟沿更新缓存槽对应 VL 地址
            bin_addr[2]  <= {ADDR_WIDTH{1'b0}};             // 时钟沿更新缓存槽对应 VL 地址
            bin_addr[3]  <= {ADDR_WIDTH{1'b0}};             // 时钟沿更新缓存槽对应 VL 地址
            bin_addr[4]  <= {ADDR_WIDTH{1'b0}};             // 时钟沿更新缓存槽对应 VL 地址
            bin_addr[5]  <= {ADDR_WIDTH{1'b0}};             // 时钟沿更新缓存槽对应 VL 地址
            bin_addr[6]  <= {ADDR_WIDTH{1'b0}};             // 时钟沿更新缓存槽对应 VL 地址
            bin_addr[7]  <= {ADDR_WIDTH{1'b0}};             // 时钟沿更新缓存槽对应 VL 地址
            bin_delta[0] <= {EV_WIDTH{1'b0}};               // 时钟沿更新缓存槽累积的增量
            bin_delta[1] <= {EV_WIDTH{1'b0}};               // 时钟沿更新缓存槽累积的增量
            bin_delta[2] <= {EV_WIDTH{1'b0}};               // 时钟沿更新缓存槽累积的增量
            bin_delta[3] <= {EV_WIDTH{1'b0}};               // 时钟沿更新缓存槽累积的增量
            bin_delta[4] <= {EV_WIDTH{1'b0}};               // 时钟沿更新缓存槽累积的增量
            bin_delta[5] <= {EV_WIDTH{1'b0}};               // 时钟沿更新缓存槽累积的增量
            bin_delta[6] <= {EV_WIDTH{1'b0}};               // 时钟沿更新缓存槽累积的增量
            bin_delta[7] <= {EV_WIDTH{1'b0}};               // 时钟沿更新缓存槽累积的增量
            bin_valid <= {BIN_DEPTH{1'b0}};                 // 时钟沿更新每个缓存槽是否有待处理事件
            state     <= S_IDLE;                            // 时钟沿更新维护口状态
            op_bin    <= 3'd0;                              // 时钟沿更新正在处理的缓存槽
            op_addr   <= {ADDR_WIDTH{1'b0}};                // 时钟沿更新正在处理的 VL 地址
            op_delta  <= {EV_WIDTH{1'b0}};                  // 时钟沿更新已从缓存取出的增量快照
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            case (state)                                    // 根据维护口状态选择处理分支
                S_IDLE: begin                               // 处理选择缓存并给 RAM 地址阶段
                    if (sel_any) begin                      // 检查是否有待处理缓存的条件
                        op_bin  <= sel_idx;                 // 时钟沿更新正在处理的缓存槽
                        op_addr <= bin_addr[sel_idx];       // 时钟沿更新正在处理的 VL 地址
                        // 若同一拍新事件也落在被选缓存上，则直接并入本次快照，不留在缓存里。
                        if (inc_any && match_hit && (match_idx == sel_idx))  // 检查是否有事件、当前事件与已有缓存同地址、地址匹配缓存槽的优先索引的条件
                            op_delta <= bin_delta[sel_idx] + event_vec;  // 时钟沿更新已从缓存取出的增量快照
                        else                                // 采用前一条件未满足时的处理
                            op_delta <= bin_delta[sel_idx];  // 时钟沿更新已从缓存取出的增量快照
                        bin_delta[sel_idx] <= {EV_WIDTH{1'b0}};  // 时钟沿更新缓存槽累积的增量

                        // 不同地址的新事件仍按普通事件缓存。
                        if (inc_any && !(match_hit && (match_idx == sel_idx))) begin  // 检查是否有事件、当前事件与已有缓存同地址、地址匹配缓存槽的优先索引的条件
                            if (match_hit)                  // 检查当前事件与已有缓存同地址的条件
                                bin_delta[match_idx] <= bin_delta[match_idx] + event_vec;  // 时钟沿更新缓存槽累积的增量
                            else if (empty_hit) begin       // 检查存在空缓存槽的条件
                                bin_valid[empty_idx] <= 1'b1;  // 时钟沿更新每个缓存槽是否有待处理事件
                                bin_addr[empty_idx]  <= inc_addr;  // 时钟沿更新缓存槽对应 VL 地址
                                bin_delta[empty_idx] <= event_vec;  // 时钟沿更新缓存槽累积的增量
                            end                             // 当前语句组结束
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                    else if (inc_any) begin                 // 检查是否有事件的条件
                        if (match_hit)                      // 检查当前事件与已有缓存同地址的条件
                            bin_delta[match_idx] <= bin_delta[match_idx] + event_vec;  // 时钟沿更新缓存槽累积的增量
                        else if (empty_hit) begin           // 检查存在空缓存槽的条件
                            bin_valid[empty_idx] <= 1'b1;   // 时钟沿更新每个缓存槽是否有待处理事件
                            bin_addr[empty_idx]  <= inc_addr;  // 时钟沿更新缓存槽对应 VL 地址
                            bin_delta[empty_idx] <= event_vec;  // 时钟沿更新缓存槽累积的增量
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_READ: begin                               // 处理等 RAM 读延迟一拍阶段
                    // 地址已在上一拍给出，本拍 RAM 正在更新 qA；期间的事件继续并入该缓存。
                    if (inc_any) begin                      // 检查是否有事件的条件
                        if (event_matches_op)               // 检查event_matches_op的条件
                            bin_delta[op_bin] <= bin_delta[op_bin] + event_vec;  // 时钟沿更新缓存槽累积的增量
                        else if (match_hit)                 // 检查当前事件与已有缓存同地址的条件
                            bin_delta[match_idx] <= bin_delta[match_idx] + event_vec;  // 时钟沿更新缓存槽累积的增量
                        else if (empty_hit) begin           // 检查存在空缓存槽的条件
                            bin_valid[empty_idx] <= 1'b1;   // 时钟沿更新每个缓存槽是否有待处理事件
                            bin_addr[empty_idx]  <= inc_addr;  // 时钟沿更新缓存槽对应 VL 地址
                            bin_delta[empty_idx] <= event_vec;  // 时钟沿更新缓存槽累积的增量
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_WRITE: begin                              // 处理累加增量并写回阶段
                    // 写回快照；同地址新事件保留为残余增量，下一轮继续累加。
                    if (inc_any && event_matches_op) begin  // 检查是否有事件、event_matches_op的条件
                        bin_valid[op_bin]  <= 1'b1;         // 时钟沿更新每个缓存槽是否有待处理事件
                        bin_delta[op_bin] <= bin_delta[op_bin] + event_vec;  // 时钟沿更新缓存槽累积的增量
                    end                                     // 当前语句组结束
                    else begin                              // 前一条件不满足时执行本分支
                        if (inc_any) begin                  // 检查是否有事件的条件
                            if (match_hit)                  // 检查当前事件与已有缓存同地址的条件
                                bin_delta[match_idx] <= bin_delta[match_idx] + event_vec;  // 时钟沿更新缓存槽累积的增量
                            else if (empty_hit) begin       // 检查存在空缓存槽的条件
                                bin_valid[empty_idx] <= 1'b1;  // 时钟沿更新每个缓存槽是否有待处理事件
                                bin_addr[empty_idx]  <= inc_addr;  // 时钟沿更新缓存槽对应 VL 地址
                                bin_delta[empty_idx] <= event_vec;  // 时钟沿更新缓存槽累积的增量
                            end                             // 当前语句组结束
                        end                                 // 当前语句组结束
                        if (bin_delta[op_bin] == {EV_WIDTH{1'b0}})  // 检查缓存槽累积的增量、正在处理的缓存槽、一个地址上 5 个计数器的增量的条件
                            bin_valid[op_bin] <= 1'b0;      // 时钟沿更新每个缓存槽是否有待处理事件
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                default: ;                                       // 其余状态没有数据通路动作
            endcase                                         // 当前分支选择结束

            state <= nxt_state;                                 // 状态寄存器只在第一段更新
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    // ==================== 累加与写回 ====================
    wire [CNT_WIDTH-1:0] cnt0_next = cnt_word[1*CNT_WIDTH-1:0*CNT_WIDTH] +  // 计数器 0 的原值与本次待处理增量之和
                                     {16'd0, op_delta[1*DELTA_WIDTH-1:0*DELTA_WIDTH]};  // 继续计算计数器 0 的原值与本次待处理增量之和
    wire [CNT_WIDTH-1:0] cnt1_next = cnt_word[2*CNT_WIDTH-1:1*CNT_WIDTH] +  // 计数器 1 的原值与本次待处理增量之和
                                     {16'd0, op_delta[2*DELTA_WIDTH-1:1*DELTA_WIDTH]};  // 继续计算计数器 1 的原值与本次待处理增量之和
    wire [CNT_WIDTH-1:0] cnt2_next = cnt_word[3*CNT_WIDTH-1:2*CNT_WIDTH] +  // 计数器 2 的原值与本次待处理增量之和
                                     {16'd0, op_delta[3*DELTA_WIDTH-1:2*DELTA_WIDTH]};  // 继续计算计数器 2 的原值与本次待处理增量之和
    wire [CNT_WIDTH-1:0] cnt3_next = cnt_word[4*CNT_WIDTH-1:3*CNT_WIDTH] +  // 计数器 3 的原值与本次待处理增量之和
                                     {16'd0, op_delta[4*DELTA_WIDTH-1:3*DELTA_WIDTH]};  // 继续计算计数器 3 的原值与本次待处理增量之和
    wire [CNT_WIDTH-1:0] cnt4_next = cnt_word[5*CNT_WIDTH-1:4*CNT_WIDTH] +  // 计数器 4 的原值与本次待处理增量之和
                                     {16'd0, op_delta[5*DELTA_WIDTH-1:4*DELTA_WIDTH]};  // 继续计算计数器 4 的原值与本次待处理增量之和

    assign cnt_next = {cnt4_next, cnt3_next, cnt2_next, cnt1_next, cnt0_next}; // 更新后的 5 个计数器
    assign cnt_wr   = (state == S_WRITE);                       // 读回数据已稳定，本拍写回

    // 真双端口 M4K IP：端口 A 做计数维护，端口 B 供 SNMP 读
    // IP 生成时位宽被限成 255，实际是 256 位，只有低 160 位放 5 个计数器，
    // 高 96 位保留（写 0、读忽略），全字写回保证保留位始终为 0
    localparam IP_WIDTH = 256;                                  // mib_rx_ip/mib_tx_ip 的实际位宽
    localparam RSRV     = IP_WIDTH - 5*CNT_WIDTH;                // 保留位数（96）

    wire [IP_WIDTH-1:0] cnt_word_ip;                            // 维护口读回整字（含保留位）
    wire [IP_WIDTH-1:0] cnt_next_ip;                            // 维护口写回整字（保留位恒 0）
    wire [IP_WIDTH-1:0] rd_data_ip;                             // SNMP 读回整字（含保留位）

    assign cnt_word    = cnt_word_ip[5*CNT_WIDTH-1:0];          // 只用低 160 位
    assign cnt_next_ip = {{RSRV{1'b0}}, cnt_next};              // 保留位补 0
    assign rd_data     = rd_data_ip[5*CNT_WIDTH-1:0];           // 只用低 160 位

    generate                                                // 按参数生成对应硬件结构
        if (IS_RX) begin : g_mib_rx                         // 检查1=接收侧计数（mib_rx_ip） 0=发送侧（mib_tx_ip）、g_mib_rx的条件
            mib_rx_ip u_mib_ip (                            // 例化子模块并连接数据通路
                .clock_a    (clk),                              // input  [0:0]
                .aclr_a     (~rst_b),                           // input  [0:0]  高有效异步清零
                .address_a  (op_addr),                          // input  [11:0] 维护口使用读-改-写地址
                .data_a     (cnt_next_ip),                      // input  [255:0]
                .wren_a     (cnt_wr),                           // input  [0:0]
                .q_a        (cnt_word_ip),                      // output [255:0]
                .clock_b    (clk),                              // input  [0:0]
                .aclr_b     (~rst_b),                           // input  [0:0]
                .address_b  (rd_addr),                          // input  [11:0]
                .data_b     ({IP_WIDTH{1'b0}}),                 // input  [255:0]
                .wren_b     (1'b0),                             // input  [0:0]
                .q_b        (rd_data_ip)                        // output [255:0]
            );                                              // 端口声明或模块例化结束
        end else begin : g_mib_tx                           // 前一条件不满足时执行本分支
            mib_tx_ip u_mib_ip (                            // 例化子模块并连接数据通路
                .clock_a    (clk),                              // input  [0:0]
                .aclr_a     (~rst_b),                           // input  [0:0]  高有效异步清零
                .address_a  (op_addr),                          // input  [11:0] 维护口使用读-改-写地址
                .data_a     (cnt_next_ip),                      // input  [255:0]
                .wren_a     (cnt_wr),                           // input  [0:0]
                .q_a        (cnt_word_ip),                      // output [255:0]
                .clock_b    (clk),                              // input  [0:0]
                .aclr_b     (~rst_b),                           // input  [0:0]
                .address_b  (rd_addr),                          // input  [11:0]
                .data_b     ({IP_WIDTH{1'b0}}),                 // input  [255:0]
                .wren_b     (1'b0),                             // input  [0:0]
                .q_b        (rd_data_ip)                        // output [255:0]
            );                                              // 端口声明或模块例化结束
        end                                                 // 当前语句组结束
    endgenerate                                             // 参数化生成结构结束

endmodule                                                   // 模块定义结束

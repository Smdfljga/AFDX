// afdx_tx : AFDX 输出模块
// 按 BAG 对每条 VL 做发送整形（两帧间隔不小于 BAG），从发送端口缓冲取载荷，
// 组装 UDP/IP/以太网帧并写入 SN 序列号，按 Lmax 限长（超限丢弃，不分片），输出到 MAC 发送接口，
// 同时更新 MIB 计数与 VL 状态表里的 SN / 发送时刻
// 注：内部调度、组帧与发送状态机已实现（两段式：组合算次态、时序存状态与数据通路），
// RAM（配置表 / 状态表 / 端口缓冲）读延迟按 1 拍处理
module afdx_tx #(                                           // 声明模块及其参数接口
    parameter DATA_WIDTH        = 8,        // 数据位宽，MAC 侧 1 字节/拍
    parameter VLID_WIDTH        = 16,       // VLID 位宽
    parameter VL_ADDR_WIDTH     = 12,       // VL 表地址位宽（IP 已生成 4096 深）
    parameter VL_INDEX_WIDTH    = 4,        // 端口缓冲 VL 索引位宽
    parameter BYTE_OFFSET_WIDTH = 11,       // 端口缓冲字节偏移位宽
    parameter CNT_WIDTH         = 32,       // MIB 计数器位宽
    parameter STATE_WIDTH       = 64,       // VL 运行期状态字位宽
    parameter VL_INDEX_SNMP     = 4'd1,     // SNMP 代理占用的槽位
    parameter VL_INDEX_615A     = 4'd2,     // 615A 代理占用的槽位
    parameter VL_INDEX_RTC      = 4'd3      // RTC 代理占用的槽位
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 系统时间戳（BAG 整形用） ====================
    input  wire [31:0]                   sys_ts,                 // 自由运行时间戳（1us 计数），来自 local_rtc 低 32bit

    // ==================== MAC 发送侧 ====================
    output wire [DATA_WIDTH-1:0]         ff_tx_data,             // MAC 发送数据
    output wire                          ff_tx_wren,             // MAC 发送数据写使能
    output wire                          ff_tx_sop,              // MAC 发送包起始
    output wire                          ff_tx_eop,              // MAC 发送包结束
    output wire                          ff_tx_err,              // MAC 发送错误（BAG 违反等内部错误上报）
    input  wire                          ff_tx_rdy,              // MAC 发送准备

    // ==================== 槽位到 VLID 映射 ====================
    input  wire [(1<<VL_INDEX_WIDTH)*VLID_WIDTH-1:0] slot_vlid,  // 每槽位对应的完整 VLID

    // ==================== VL 配置表读（端口 B） ====================
    output wire [VL_ADDR_WIDTH-1:0]      cfg_addr,               // 配置表读地址 = vlid[VL_ADDR_WIDTH-1:0]（直接映射）
    output wire                          cfg_rd_en,              // 配置表读使能
    input  wire [VLID_WIDTH-1:0]         cfg_tag,                // 读回 VLID
    input  wire                          cfg_valid,              // 条目有效标志
    input  wire [1:0]                    cfg_port_type,          // 端口类型
    input  wire [15:0]                   cfg_udp_port,           // UDP 目的端口
    input  wire [15:0]                   cfg_bag,                // BAG，两帧最小间隔
    input  wire [15:0]                   cfg_lmax,               // Lmax，单帧最大长度（超限即丢弃本帧）
    input  wire                          cfg_rm_en,              // RM 使能，1=该 VL 需要双网冗余发送

    // ==================== VL 运行期状态读写（vl_state_ram 端口 B） ====================
    output wire [VL_ADDR_WIDTH-1:0]      st_addr,                // 状态表地址，与查表地址相同（= vlid 低位）
    output wire                          st_rd_en,               // 状态读使能（读 SN / 上次发送时刻）
    input  wire [STATE_WIDTH-1:0]        st_rd_data,             // 状态读数据
    output wire                          st_wr_en,               // 状态写使能（帧发完写回 SN/时间戳）
    output wire [STATE_WIDTH-1:0]        st_wr_data,             // 状态写数据

    // ==================== 发送端口缓冲读侧 ====================
    output wire                          port_rd_en,             // 端口缓冲读使能
    output wire [VL_INDEX_WIDTH-1:0]     port_rd_vl_index,       // 端口缓冲读 VL 索引
    output wire [BYTE_OFFSET_WIDTH-1:0]  port_rd_byte_offset,    // 端口缓冲读字节偏移
    input  wire [DATA_WIDTH-1:0]         port_rd_data,           // 端口缓冲读数据
    input  wire                          port_rd_valid,          // 端口缓冲读数据有效
    input  wire [15:0]                   port_payload_len,       // 该 VL 待发载荷长度（字节）
    output wire [15:0]                   abort_vl,               // 丢弃本帧时撤销该槽位（清忙标志与长度）

    // ==================== 发送请求（应用与三个协议代理） ====================
    input  wire                          tx_valid_app,           // 应用发送请求
    input  wire                          tx_valid_snmp,          // SNMP 发送请求
    input  wire                          tx_valid_615a,          // 615A 发送请求
    input  wire                          tx_valid_rtc,           // RTC 发送请求

    // ==================== MIB 计数 ====================
    output wire [VL_ADDR_WIDTH-1:0]      mib_addr,               // 计数事件所属 VL（= vlid[VL_ADDR_WIDTH-1:0]）
    output wire                          mib_tx_frame_inc,       // 发送成功帧数 +1
    output wire                          mib_tx_byte_inc,        // 发送字节数 +1（每个发送字节一拍）
    output wire                          mib_tx_error_inc,       // 发送错误帧数 +1
    output wire                          mib_tx_frag_inc,        // 超 Lmax 被丢弃帧数 +1（原"分片次数"）
    output wire                          mib_tx_bag_inc,         // BAG 违反次数 +1

    // ==================== 中断 ====================
    output wire                          irq_tx_done             // 中断：一帧发送完成
);                                                          // 端口声明或模块例化结束

    // ==================== 状态机 ====================
    localparam S_IDLE        = 4'd0;                             // 调度扫描
    localparam S_SCAN        = 4'd1;                             // 应用请求后的槽位扫描
    localparam S_CFG_READ    = 4'd2;                             // 等配置表读回
    localparam S_STATE_READ  = 4'd3;                             // 等状态表读回
    localparam S_DECIDE      = 4'd4;                             // 长度/BAG 判决
    localparam S_WAIT        = 4'd5;                             // 等 BAG 到期
    localparam S_PAYLOAD_RD  = 4'd6;                             // 预取第一个载荷字节
    localparam S_BUILD       = 4'd7;                             // 逐字节组帧发送
    localparam S_FINISH      = 4'd8;                             // 更新状态与计数

    // ==================== 本端固定字段 ====================
    localparam [31:0] SRC_IP        = 32'h04000001;             // 本端源 IP（04 + User_Defined_ID 占位）

    // ==================== 待发队列与调度寄存器 ====================
    reg [15:0] pending;                                         // 每槽位一个待发标志
    reg        app_scan;                                        // 应用帧尾后需要扫描所有槽位
    reg [VL_INDEX_WIDTH-1:0] scan_idx;                          // 应用扫描当前槽位
    reg [VL_INDEX_WIDTH-1:0] sched_idx;                         // 当前调度的槽位
    reg [VLID_WIDTH-1:0]    vlid_r;                             // 当前调度的完整 VLID

    // ==================== 配置与状态锁存 ====================
    reg [15:0] cfg_udp_r;                                       // UDP 目的端口
    reg [15:0] cfg_bag_r;                                       // BAG（ms）
    reg [15:0] payload_len_r;                                   // 待发应用数据实际长度
    reg [15:0] data_len_r;                                      // 补齐 17 字节后的载荷长度
    reg [15:0] ip_total_r;                                      // IP 总长度
    reg [15:0] udp_len_r;                                       // UDP 长度
    reg [15:0] frame_total_r;                                   // 组帧后总长度（含最后填充）
    reg [15:0] ip_cksum_r;                                      // IP 首部校验和
    reg [31:0] dst_ip_r;                                        // 目的多播 IP
    reg [31:0] start_ts_r;                                      // 本帧开始发送时刻
    reg [7:0]  sn_r;                                            // 本帧 SN
    reg [7:0]  next_sn_r;                                       // 成功后写回最近已发 SN，寄存器名称沿用原接口工程
    reg [15:0] ip_id_cnt;                                       // IP 标识跨帧递增

    // ==================== 发送流水寄存器 ====================
    reg [3:0]  state;                                           // 当前状态
    reg [15:0] tx_byte_pos;                                     // 当前输出字节位置
    reg [7:0]  pay_buf [0:3];                               // 载荷预取循环缓冲（4 字节）
    reg [2:0]  pay_wr;                                      // 预取缓冲写指针（累计到达字节数）
    reg [2:0]  pay_rd;                                      // 预取缓冲读指针（累计送出字节数）
    reg [15:0] pay_req_ix;                                  // 下一个要请求的载荷偏移
    reg        pay_iss_d1;                                  // 读地址已发出第一拍
    reg        pay_iss_d2;                                  // 读地址已发出第二拍（数据本拍到达）
    reg [23:0] wait_cnt;                                        // BAG 等待超时计数器
    reg        bag_pulse;                                       // BAG 违反单拍计数
    reg [1:0]  finish_kind;                                     // 0=成功 1=错误 2=空帧跳过
    reg        frag_error;                                      // 本帧因超 Lmax 被丢弃

    // ==================== 分片发送上下文 ====================
    // 一条应用消息可能超过 Lmax，按 Lmax-43 切片、每片自成以太网帧；
    // 非末片的片内数据取 8n+7 字节，使“8B UDP + 数据 + 1B SN”恰好 8 字节对齐，
    // IP 片偏移字段才是整数。
    reg [15:0] msg_len_r;                                       // 本条消息总字节数
    reg [15:0] msg_off_r;                                       // 本片起始的消息内字节偏移
    reg [4:0]  frag_cnt_r;                                      // 本条消息已发出的帧数（算 IP 片偏移用）
    reg        frag_more_r;                                     // 本帧之后还有分片（IP MF）
    reg        frag_active;                                     // 该槽位消息正处于分片发送中
    reg [15:0] flg_off_r;                                       // 本帧 IP 标志/片偏移字（无分片时为 0x4000）

    // ==================== 组合调度与计时 ====================
    reg [VL_INDEX_WIDTH-1:0] pending_idx;                       // 待发槽位最低编号，不用函数循环以保证工具兼容
    reg [15:0]               bag_skip;                          // 本轮 BAG 未到期的槽位（跳过它们，避免队头阻塞）
    wire [15:0]              pending_mask = frag_active ? (16'd1 << sched_idx) : 16'hFFFF; // 分片续发期间只调度同一条消息
    wire [15:0]              pending_ready = pending & ~bag_skip & pending_mask; // 待发且本轮还没被跳过（或已到期）的槽位
    reg [VL_INDEX_WIDTH-1:0] pending_idx_ready;                 // 未被跳过的待发槽位里编号最小的那个
    always @(*) begin                                       // 组合选择最低编号的"未跳过"待发槽位
        casez (pending_ready)                               // 与下面 pending_idx 相同的优先级编码
        16'b???????????????1: pending_idx_ready = 4'd0;      // 槽位 0
        16'b??????????????1?: pending_idx_ready = 4'd1;      // 槽位 1
        16'b?????????????1??: pending_idx_ready = 4'd2;      // 槽位 2
        16'b????????????1???: pending_idx_ready = 4'd3;      // 槽位 3
        16'b???????????1????: pending_idx_ready = 4'd4;      // 槽位 4
        16'b??????????1?????: pending_idx_ready = 4'd5;      // 槽位 5
        16'b?????????1??????: pending_idx_ready = 4'd6;      // 槽位 6
        16'b????????1???????: pending_idx_ready = 4'd7;      // 槽位 7
        16'b???????1????????: pending_idx_ready = 4'd8;      // 槽位 8
        16'b??????1?????????: pending_idx_ready = 4'd9;      // 槽位 9
        16'b?????1??????????: pending_idx_ready = 4'd10;     // 槽位 10
        16'b????1???????????: pending_idx_ready = 4'd11;     // 槽位 11
        16'b???1????????????: pending_idx_ready = 4'd12;     // 槽位 12
        16'b??1?????????????: pending_idx_ready = 4'd13;     // 槽位 13
        16'b?1??????????????: pending_idx_ready = 4'd14;     // 槽位 14
        16'b1???????????????: pending_idx_ready = 4'd15;     // 槽位 15
        default:              pending_idx_ready = 4'd0;      // 默认槽位 0
        endcase                                             // 编码结束
    end                                                     // 组合结束
    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        casez (pending)                                     // 例化子模块并连接数据通路
            16'b???????????????1: pending_idx = 4'd0;       // 选择最低编号的待发槽位 0
            16'b??????????????1?: pending_idx = 4'd1;       // 选择最低编号的待发槽位 1
            16'b?????????????1??: pending_idx = 4'd2;       // 选择最低编号的待发槽位 2
            16'b????????????1???: pending_idx = 4'd3;       // 选择最低编号的待发槽位 3
            16'b???????????1????: pending_idx = 4'd4;       // 选择最低编号的待发槽位 4
            16'b??????????1?????: pending_idx = 4'd5;       // 选择最低编号的待发槽位 5
            16'b?????????1??????: pending_idx = 4'd6;       // 选择最低编号的待发槽位 6
            16'b????????1???????: pending_idx = 4'd7;       // 选择最低编号的待发槽位 7
            16'b???????1????????: pending_idx = 4'd8;       // 选择最低编号的待发槽位 8
            16'b??????1?????????: pending_idx = 4'd9;       // 选择最低编号的待发槽位 9
            16'b?????1??????????: pending_idx = 4'd10;      // 选择最低编号的待发槽位 10
            16'b????1???????????: pending_idx = 4'd11;      // 选择最低编号的待发槽位 11
            16'b???1????????????: pending_idx = 4'd12;      // 选择最低编号的待发槽位 12
            16'b??1?????????????: pending_idx = 4'd13;      // 选择最低编号的待发槽位 13
            16'b?1??????????????: pending_idx = 4'd14;      // 选择最低编号的待发槽位 14
            16'b1???????????????: pending_idx = 4'd15;      // 选择最低编号的待发槽位 15
            default:              pending_idx = 4'd0;       // 未匹配有效分支时采用默认处理
        endcase                                             // 当前分支选择结束
    end                                                     // 当前语句组结束

    wire [15:0] bag_cfg_now = (state == S_DECIDE) ? cfg_bag : cfg_bag_r; // 当前判决所用的 BAG 配置
    wire [31:0] bag_us = {16'd0, bag_cfg_now} * 32'd1000;       // BAG 从 ms 换算到 us
    wire [31:0] elapsed = sys_ts - st_rd_data[63:32];           // 距离上一帧的无符号时间差
    wire bag_due = !st_rd_data[24] || (bag_us == 32'd0) || (elapsed >= bag_us); // BAG 已到期

    // ==================== 分片尺寸计算 ====================
    // 每帧最多承载 Lmax-43 字节应用数据（43 = 14 MAC + 20 IP + 8 UDP + 1 SN）；
    // 非末片再向下取到 8n+7，保证 IP 片偏移以 8 字节为单位仍然成立。
    wire [15:0] frag_cap   = (cfg_lmax > 16'd43) ? (cfg_lmax - 16'd43) : 16'd1; // 单片承载上限
    wire [15:0] frag_capc  = (frag_cap > 16'd1471) ? 16'd1471 : frag_cap;  // 再受 1471 字节上限约束
    wire [15:0] frag_base  = (frag_capc > 16'd16) ? frag_capc : 16'd16;    // 防止下面减 7 时下溢
    wire [15:0] frag_t     = frag_base - 16'd7;                            // 8 字节对齐中间量
    wire [15:0] frag_chunk = {frag_t[15:3], 3'b000} + 16'd7;               // 非末片数据字节数 = 8n+7

    wire [15:0] msg_len_sel  = frag_active ? msg_len_r : port_payload_len; // 本条消息总长
    wire [15:0] msg_left     = msg_len_sel - msg_off_r;                    // 本片还能取多少字节
    wire        frag_more_sel = (msg_left > frag_chunk);                   // 装不下=后面还有分片
    wire [15:0] frag_len_sel = frag_more_sel ? frag_chunk : msg_left;      // 本片实际承载的数据字节数
    // 每片都自带 8 字节 UDP 头与 1 字节 SN，所以片 i 的 IP 载荷起点是 Σ(数据+9)；
    // 非末片数据取 8n+7 时每片正好推进 8 的倍数，片偏移字段是整数。
    wire [15:0] frag_ipoff   = (frag_cnt_r == 5'd0) ? 16'd0 :               // 首片偏移为零
                               ((msg_off_r + {frag_cnt_r, 3'b000} + {11'd0, frag_cnt_r}) >> 3); // (数据累计+9×片号)/8
    wire        frag_hdr     = frag_more_sel || (frag_cnt_r != 5'd0);      // 本帧是否属于被分片的报文
    wire [15:0] flg_off_sel  = frag_hdr ? {3'b000, frag_more_sel, frag_ipoff[12:0]} : 16'h4000; // DF/MF+片偏移
    // 只有“未分片的单帧”才把短载荷补零到 17 字节；分片的最后一片不能补，
    // 否则接收侧按片长累加会多出填充字节。
    wire        pad_to_17    = !frag_more_sel && (frag_cnt_r == 5'd0);     // 未分片单帧才补零
    wire [15:0] frame_data_len = (pad_to_17 && (frag_len_sel < 16'd17)) ? 16'd17 : frag_len_sel; // 本帧发出的载荷长度

    // ==================== 查表与读缓冲输出 ====================
    assign cfg_addr = vlid_r[VL_ADDR_WIDTH-1:0];                // output [11:0]
    assign cfg_rd_en = (state == S_CFG_READ);                   // output [0:0]
    assign st_addr  = vlid_r[VL_ADDR_WIDTH-1:0];                // output [11:0]
    // 配置表与状态表在同一拍发起读（地址都是 vlid_r），两拍后一起在判决阶段使用
    assign st_rd_en = (state == S_CFG_READ);                    // output [0:0]

    assign port_rd_vl_index = (state == S_SCAN) ? scan_idx : sched_idx; // output [3:0]
    wire [15:0] payload_pos = (tx_byte_pos >= 16'd42) ? tx_byte_pos - 16'd42 : 16'd0; // 当前载荷内偏移
    wire [7:0] payload_data = (pay_wr == pay_rd) ? port_rd_data : pay_buf[pay_rd[1:0]]; // 缓存空时直接用当拍到来的字节
    wire build_active = (state == S_BUILD) && ff_tx_rdy;         // 当前拍真正发出一个字节
    // 端口缓冲 RAM 读延迟两拍：4 项循环缓冲吸收返回延迟与 MAC 停顿，按顺序请求 0,1,2,... 的偏移
    wire pay_arr   = pay_iss_d2;                                 // 两拍前发出的地址，数据本拍到达
    wire [2:0] pay_used = (pay_wr - pay_rd) + {2'b00, pay_arr} + {2'b00, pay_iss_d1}; // 已用 + 在途
    wire pay_room  = (pay_used < 3'd4);                          // 4 项容量扣除在途后还有空位
    wire pay_issue = (state == S_BUILD) &&                       // 组帧阶段才发读地址
                     pay_room && (pay_req_ix < payload_len_r);   // 还有没取的载荷字节
    wire pay_pop   = build_active && (tx_byte_pos >= 16'd42) &&  // 本拍真正发出一个载荷字节
                     (payload_pos < payload_len_r);              // 只对真实应用数据出队
    wire pay_clr   = (state == S_PAYLOAD_RD);                    // 新帧开始，清空预取缓存
    assign port_rd_en = pay_issue;                              // output [0:0]
    assign port_rd_byte_offset = (msg_off_r + pay_req_ix);      // output [10:0]：消息内偏移（分片时从片起点算）

    // 载荷预取循环缓冲：写指针收返回字节，读指针给发送字节，两个指针之差就是缓存占用
    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            pay_wr <= 3'd0;                                 // 清写指针
            pay_rd <= 3'd0;                                 // 清读指针
        end                                                 // 当前语句组结束
        else if (pay_clr) begin                             // 新帧开始：清空缓存
            pay_wr <= 3'd0;                                 // 清写指针
            pay_rd <= 3'd0;                                 // 清读指针
        end                                                 // 清空结束
        else begin                                          // 正常运行分支
            if (pay_arr) begin                              // 数据到达：写入写指针位置
                pay_buf[pay_wr[1:0]] <= port_rd_data;       // 返回字节按写指针入缓冲
                pay_wr <= pay_wr + 3'd1;                    // 写指针前进
            end                                             // 写入结束
            if (pay_pop)                                    // 字节送出：读指针前进
                pay_rd <= pay_rd + 3'd1;                    // 读指针前进，与送出字节同拍
        end                                                 // 正常运行分支结束
    end                                                     // 载荷预取缓存结束

    // 判决阶段丢弃本帧（配置无效 / 超 Lmax）或 BAG 等待超时时撤销该槽位：
    // 否则槽位的忙标志与长度会一直留着，槽位再也写不进新帧，而且每次发送请求都会重复计一次错误
    assign abort_vl = ((state == S_FINISH) && (finish_kind == 2'd1)) ?  // output [15:0]
                      (16'd1 << sched_idx) : 16'd0;          // 丢弃本帧的那一拍给出槽位号

    // ==================== IP 首部校验和函数 ====================
    function [15:0] calc_ip_cksum;                          // 声明纯组合运算函数
        input [15:0] total_len;                             // 函数输入的 IP 总长度，单位为字节
        input [15:0] ident;                                 // 函数输入的 IP 标识字段
        input [31:0] src_ip;                                // 函数输入的源 IPv4 地址
        input [31:0] dst_ip;                                // 函数输入的目的 IPv4 地址
        input [15:0] flg_off;                               // 函数输入的标志/片偏移字（未分片为 0x4000）
        reg [19:0] sum;                                     // 加宽的组合累加结果，保留最高进位
        begin                                               // 开始执行当前条件或循环的语句组
            sum = 20'd0;                                    // 设置或组合计算sum
            sum = sum + 16'h4500;                           // 设置或组合计算sum
            sum = sum + total_len;                          // 设置或组合计算sum
            sum = sum + ident;                              // 设置或组合计算sum
            sum = sum + flg_off;                            // 标志位与片偏移参与校验和
            sum = sum + 16'h0111;                           // 设置或组合计算sum
            sum = sum + src_ip[31:16];                      // 设置或组合计算sum
            sum = sum + src_ip[15:0];                       // 设置或组合计算sum
            sum = sum + dst_ip[31:16];                      // 设置或组合计算sum
            sum = sum + dst_ip[15:0];                       // 设置或组合计算sum
            sum = {1'b0, sum[15:0]} + sum[19:16];               // 回卷进位
            sum = {1'b0, sum[15:0]} + sum[19:16];               // 再回卷首轮可能产生的进位，覆盖和为 0x1FFFF 的边界
            calc_ip_cksum = ~sum[15:0];                     // 设置或组合计算calc_ip_cksum
        end                                                 // 当前语句组结束
    endfunction                                             // 组合运算函数定义结束

    // ==================== 状态机：第二段（组合，算次态） ====================
    reg [3:0] nxt_state;                                        // 次态，由本段组合算出

    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        nxt_state = state;                                      // 默认保持当前状态

        case (state)                                        // 根据当前状态选择处理分支
            S_IDLE: begin                                   // 处理调度扫描阶段
                if (app_scan)                               // 检查应用帧尾后需要扫描所有槽位的条件
                    nxt_state = S_SCAN;                         // 先扫出哪些应用槽位确实有帧
                else if (pending_ready != 16'd0)            // 有未被跳过（BAG 已到期）的待发槽位
                    nxt_state = S_CFG_READ;                     // 有待发槽位，读配置表
            end                                             // 当前语句组结束

            S_SCAN: begin                                   // 处理应用请求后的槽位扫描阶段
                nxt_state = S_IDLE;                             // 每拍扫一个槽位，扫完回调度
            end                                             // 当前语句组结束

            S_CFG_READ: begin                               // 处理等配置表读回阶段
                nxt_state = S_STATE_READ;                       // 配置表读延迟第一拍
            end                                             // 当前语句组结束

            S_STATE_READ: begin                             // 处理等状态表读回阶段
                nxt_state = S_DECIDE;                           // 两拍读延迟走完，下一拍判决
            end                                             // 当前语句组结束

            S_DECIDE: begin                                 // 处理长度/BAG 判决阶段
                if (!(cfg_valid && (cfg_tag == vlid_r)))    // 检查条目有效标志、读回 VLID、当前调度的完整 VLID的条件
                    nxt_state = S_FINISH;                       // 配置无效，丢弃本帧
                else if (port_payload_len == 16'd0)         // 检查该 VL 待发载荷长度（字节）的条件
                    nxt_state = S_FINISH;                       // 空帧跳过
                else if ((port_payload_len > cfg_lmax) || (port_payload_len > 16'd1471))  // 检查该 VL 待发载荷长度（字节）、Lmax、该 VL 待发载荷长度（字节）的条件
                    nxt_state = S_PAYLOAD_RD;                   // 超 Lmax 或超 1471 字节：改为分片发送
                else if (!bag_due)                          // 检查BAG 已到期的条件
                    nxt_state = S_IDLE;                         // BAG 未到期：跳过这条 VL，回去看别的槽位
                else                                        // 采用前一条件未满足时的处理
                    nxt_state = S_PAYLOAD_RD;                   // BAG 已到期，可以发送
            end                                             // 当前语句组结束

            S_WAIT: begin                                   // 处理等 BAG 到期阶段
                if (bag_due)                                // 检查BAG 已到期的条件
                    nxt_state = S_PAYLOAD_RD;                   // BAG 到期，开始发送
                else if (wait_cnt == 24'hFFFFFF)            // 检查BAG 等待超时计数器的条件
                    nxt_state = S_FINISH;                       // 等待超时，按发送错误处理
            end                                             // 当前语句组结束

            S_PAYLOAD_RD: begin                             // 处理预取第一个载荷字节阶段
                nxt_state = S_BUILD;                            // 预取首个载荷字节后组帧
            end                                             // 当前语句组结束

            S_BUILD: begin                                  // 处理逐字节组帧发送阶段
                if (ff_tx_rdy && (tx_byte_pos == frame_total_r - 16'd1))  // MAC 接受当前字节时推进发送数据通路
                    nxt_state = S_FINISH;                       // 最后一字节发出，本帧结束
            end                                             // 当前语句组结束

            S_FINISH: begin                                 // 处理更新状态与计数阶段
                nxt_state = S_IDLE;                             // 清待发标志后回调度
            end                                             // 当前语句组结束

            default: begin                                  // 未匹配有效分支时采用默认处理
                nxt_state = S_IDLE;                             // 异常状态回空闲
            end                                             // 当前语句组结束
        endcase                                             // 当前分支选择结束
    end                                                     // 当前语句组结束

    // ==================== 状态机：第一段（时序，状态寄存器与数据通路） ====================
    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            state         <= S_IDLE;                        // 时钟沿更新当前状态
            pending       <= 16'd0;                         // 时钟沿更新每槽位一个待发标志
            bag_skip      <= 16'd0;                         // 时钟沿清掉跳过标记
            app_scan      <= 1'b0;                          // 时钟沿更新应用帧尾后需要扫描所有槽位
            scan_idx      <= {VL_INDEX_WIDTH{1'b0}};        // 时钟沿更新应用扫描当前槽位
            sched_idx     <= {VL_INDEX_WIDTH{1'b0}};        // 时钟沿更新当前调度的槽位
            vlid_r        <= {VLID_WIDTH{1'b0}};            // 时钟沿更新当前调度的完整 VLID
            cfg_udp_r     <= 16'd0;                         // 时钟沿更新UDP 目的端口
            cfg_bag_r     <= 16'd0;                         // 时钟沿更新BAG（ms）
            payload_len_r <= 16'd0;                         // 时钟沿更新待发应用数据实际长度
            data_len_r    <= 16'd0;                         // 时钟沿更新补齐 17 字节后的载荷长度
            ip_total_r    <= 16'd0;                         // 时钟沿更新IP 总长度
            udp_len_r     <= 16'd0;                         // 时钟沿更新UDP 长度
            frame_total_r <= 16'd0;                         // 时钟沿更新组帧后总长度（含最后填充）
            ip_cksum_r    <= 16'd0;                         // 时钟沿更新IP 首部校验和
            dst_ip_r      <= 32'd0;                         // 时钟沿更新目的多播 IP
            start_ts_r    <= 32'd0;                         // 时钟沿更新本帧开始发送时刻
            sn_r          <= 8'd0;                          // 时钟沿更新本帧 SN
            next_sn_r     <= 8'd0;                          // 时钟沿更新成功后写回最近已发 SN
            ip_id_cnt     <= 16'd0;                         // 时钟沿更新IP 标识跨帧递增
            tx_byte_pos   <= 16'd0;                         // 时钟沿更新当前输出字节位置
            pay_req_ix    <= 16'd0;                         // 复位下一个要请求的载荷偏移
            pay_iss_d1    <= 1'b0;                          // 复位在途读第一拍
            pay_iss_d2    <= 1'b0;                          // 复位在途读第二拍
            wait_cnt      <= 24'd0;                         // 时钟沿更新BAG 等待超时计数器
            bag_pulse     <= 1'b0;                          // 时钟沿更新BAG 违反单拍计数
            finish_kind   <= 2'd0;                          // 时钟沿更新0=成功 1=错误 2=空帧跳过
            frag_error    <= 1'b0;                          // 时钟沿更新本帧因超 Lmax 被丢弃
            msg_len_r     <= 16'd0;                         // 复位消息总长
            msg_off_r     <= 16'd0;                         // 复位消息内偏移
            frag_cnt_r    <= 5'd0;                          // 复位已发分片数
            frag_more_r   <= 1'b0;                          // 复位后续分片标志
            frag_active   <= 1'b0;                          // 复位分片状态
            flg_off_r     <= 16'h4000;                      // 复位为不分片（DF=1）
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            bag_pulse <= 1'b0;                              // 时钟沿更新BAG 违反单拍计数
            pay_iss_d1 <= pay_issue;                        // 读地址发出第一拍
            pay_iss_d2 <= pay_iss_d1;                       // 读地址发出第二拍，数据本拍到达
            if (pay_issue) pay_req_ix <= pay_req_ix + 16'd1; // 发过一个载荷地址就指向下一字节

            // 四路发送请求先落成待发标志；应用只有 1bit 触发，因此扫描非空槽位。
            if (tx_valid_snmp) begin                        // 检查SNMP 发送请求的条件
                pending[VL_INDEX_SNMP]  <= 1'b1;            // 时钟沿更新每槽位一个待发标志
                bag_skip[VL_INDEX_SNMP] <= 1'b0;            // 新帧进来，清掉跳过标记
            end                                             // 分支结束
            if (tx_valid_615a) begin                        // 检查615A 发送请求的条件
                pending[VL_INDEX_615A]  <= 1'b1;            // 时钟沿更新每槽位一个待发标志
                bag_skip[VL_INDEX_615A] <= 1'b0;            // 新帧进来，清掉跳过标记
            end                                             // 分支结束
            if (tx_valid_rtc) begin                         // 检查RTC 发送请求的条件
                pending[VL_INDEX_RTC]  <= 1'b1;             // 时钟沿更新每槽位一个待发标志
                bag_skip[VL_INDEX_RTC] <= 1'b0;             // 新帧进来，清掉跳过标记
            end                                             // 分支结束
            if (tx_valid_app && !app_scan) begin            // 检查应用发送请求、应用帧尾后需要扫描所有槽位的条件
                app_scan <= 1'b1;                           // 时钟沿更新应用帧尾后需要扫描所有槽位
                scan_idx <= {VL_INDEX_WIDTH{1'b0}};         // 时钟沿更新应用扫描当前槽位
            end                                             // 当前语句组结束

            case (state)                                    // 根据当前状态选择处理分支
                S_IDLE: begin                               // 处理调度扫描阶段
                    if (!app_scan && (pending_ready != 16'd0)) begin  // 有未被跳过的待发槽位
                        sched_idx <= pending_idx_ready;         // 取下一条未被跳过的待发槽位
                        vlid_r    <= slot_vlid[pending_idx_ready*VLID_WIDTH +: VLID_WIDTH];  // 时钟沿更新当前调度的完整 VLID
                    end                                     // 当前语句组结束
                    else if (!app_scan && (pending != 16'd0)) begin  // 全部待发槽位本轮都被跳过
                        bag_skip  <= 16'd0;                     // 开新一轮扫描，清掉跳过标记
                    end                                     // 新一轮分支结束
                end                                         // 当前语句组结束

                S_SCAN: begin                               // 处理应用请求后的槽位扫描阶段
                    // port_payload_len 是本拍给出的槽位长度，非 0 才置待发标志。
                    if (port_payload_len != 16'd0) begin    // 检查该 VL 待发载荷长度（字节）的条件
                        pending[scan_idx]  <= 1'b1;         // 时钟沿更新每槽位一个待发标志
                        bag_skip[scan_idx] <= 1'b0;         // 新帧进来，清掉跳过标记
                    end                                     // 分支结束
                    if (scan_idx == ((1<<VL_INDEX_WIDTH)-1))  // 检查应用扫描当前槽位、端口缓冲 VL 索引位宽的条件
                        app_scan <= 1'b0;                   // 时钟沿更新应用帧尾后需要扫描所有槽位
                    else                                    // 采用前一条件未满足时的处理
                        scan_idx <= scan_idx + 1'b1;        // 时钟沿更新应用扫描当前槽位并推进至下一项
                end                                         // 当前语句组结束

                S_CFG_READ: begin                           // 处理等配置表读回阶段
                    // 只等配置表读回，本状态没有数据通路动作
                end                                         // 当前语句组结束

                S_STATE_READ: begin                         // 处理等状态表读回阶段
                    // 只等状态表读回，本状态没有数据通路动作
                end                                         // 当前语句组结束

                S_DECIDE: begin                             // 处理长度/BAG 判决阶段
                    cfg_udp_r    <= cfg_udp_port;           // 时钟沿更新UDP 目的端口
                    cfg_bag_r    <= cfg_bag;                // 时钟沿更新BAG（ms）

                    if (!(cfg_valid && (cfg_tag == vlid_r))) begin  // 检查条目有效标志、读回 VLID、当前调度的完整 VLID的条件
                        finish_kind <= 2'd1;                    // 配置无效
                        frag_error  <= 1'b0;                // 时钟沿更新本帧因超 Lmax 被丢弃
                    end                                     // 当前语句组结束
                    else if (port_payload_len == 16'd0) begin  // 检查该 VL 待发载荷长度（字节）的条件
                        finish_kind <= 2'd2;                    // 空帧跳过
                        frag_error  <= 1'b0;                // 时钟沿更新本帧因超 Lmax 被丢弃
                    end                                     // 当前语句组结束
                    // 有效帧（含超 Lmax 需要分片的消息）统一在这里算本帧长度与首部
                    if (cfg_valid && (cfg_tag == vlid_r) && (port_payload_len != 16'd0)) begin  // 有效且非空帧
                        frag_error    <= 1'b0;                  // 分片不算错误
                        if (!frag_active) msg_len_r <= port_payload_len;  // 首片锁存整条消息长度
                        payload_len_r <= frag_len_sel;          // 本帧实际承载的应用数据字节数
                        data_len_r    <= frame_data_len;        // 本帧发出的载荷长度（未分片单帧补零到 17）
                        ip_total_r    <= 16'd29 + frame_data_len;   // IP 总长度
                        udp_len_r     <= 16'd9  + frame_data_len;   // UDP 长度
                        frame_total_r <= ((16'd43 + frame_data_len) < 16'd64)  // 以太网最小帧 64 字节
                                          ? 16'd64          // 不足 64 字节按 64 字节补
                                          : (16'd43 + frame_data_len);  // 否则按实际长度
                        flg_off_r     <= flg_off_sel;           // IP 标志/片偏移字
                        dst_ip_r      <= 32'hE0E00000 | {16'd0, vlid_r};  // 目的多播 IP
                        ip_cksum_r    <= calc_ip_cksum(     // IP 首部校验和
                                             16'd29 + frame_data_len,  // IP 总长度
                                             ip_id_cnt, SRC_IP, 32'hE0E00000 | {16'd0, vlid_r}, flg_off_sel);  // 其余字段
                        frag_more_r   <= frag_more_sel;         // 本帧后面还有分片
                        sn_r <= st_rd_data[24] ?            // 每帧一个新的 SN
                                ((st_rd_data[23:16] == 8'd255) ? 8'd1 : st_rd_data[23:16] + 8'd1) : 8'd0;  // 继续计算sn_r
                         next_sn_r <= st_rd_data[24] ?      // 状态表保存最近成功发送的 SN，与生成规则保持一致
                                      ((st_rd_data[23:16] == 8'd255) ? 8'd1 : st_rd_data[23:16] + 8'd1)  // 继续计算next_sn_r
                                      : 8'd0;               // 首帧回写 0，下帧由已有 SN 生成公式递增到 1
                        start_ts_r <= sys_ts;                    // 时钟沿更新本帧开始发送时刻

                        if (!bag_due && !frag_active) begin  // 未分片的消息：本轮跳过这条 VL，让别的 VL 先发
                            bag_skip[sched_idx] <= 1'b1;    // 设置跳过标记
                            if (!bag_skip[sched_idx])       // 第一次被跳过才计一次整形等待
                                bag_pulse <= 1'b1;          // BAG 违反只计一次
                        end                                 // 当前语句组结束
                        // 分片续片遇到 BAG 未到期：只回 S_IDLE 轮询，不设跳过标记，
                        // 否则不会再有任何新帧请求来清除标记，这条消息就永远发不完了。
                        else if (bag_due)                   // BAG 已到期
                            wait_cnt <= 24'd0;              // 时钟沿更新BAG 等待超时计数器
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_WAIT: begin                               // 处理等 BAG 到期阶段
                    if (bag_due)                            // 检查BAG 已到期的条件
                        start_ts_r <= sys_ts;                    // 真正开始发送的时刻
                    else if (wait_cnt != 24'hFFFFFF)        // 检查BAG 等待超时计数器的条件
                        wait_cnt <= wait_cnt + 24'd1;       // 时钟沿更新BAG 等待超时计数器并推进至下一项
                    else begin                              // 前一条件不满足时执行本分支
                        finish_kind <= 2'd1;                    // 等待超时
                        frag_error  <= 1'b0;                // 时钟沿更新本帧因超 Lmax 被丢弃
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_PAYLOAD_RD: begin                         // 处理预取第一个载荷字节阶段
                    tx_byte_pos  <= 16'd0;                  // 时钟沿更新当前输出字节位置
                    pay_req_ix   <= 16'd0;                  // 从载荷偏移零开始请求
                // 载荷读请求从下一状态开始按偏移顺序发出，两拍后落到预取缓存。
                end                                         // 当前语句组结束

                S_BUILD: begin                              // 处理逐字节组帧发送阶段
                    // 载荷字节来自预取缓存，MAC 停顿时不取出，缓存内容原样保留。

                    if (ff_tx_rdy) begin                    // MAC 接受当前字节时推进发送数据通路
                        if (tx_byte_pos != frame_total_r - 16'd1)  // 检查当前输出字节位置、组帧后总长度（含最后填充）的条件
                            tx_byte_pos <= tx_byte_pos + 16'd1;  // 时钟沿更新当前输出字节位置并推进至下一项
                        else                                // 采用前一条件未满足时的处理
                            finish_kind <= 2'd0;                 // 本帧完整发出
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_FINISH: begin                             // 处理更新状态与计数阶段
                    if ((finish_kind == 2'd0) && frag_more_r) begin  // 成功且还有后续分片
                        // 保留待发标志：下一片的 BAG 由状态表时间戳自然节流；
                        // 清掉 bag_skip 让这条 VL 重新参与本轮调度。
                        msg_off_r  <= msg_off_r + payload_len_r;  // 下一片的消息内起始偏移
                        frag_cnt_r <= frag_cnt_r + 5'd1;          // 已发帧数加一
                        frag_active <= 1'b1;                      // 消息仍在发送中
                        bag_skip[sched_idx] <= 1'b0;              // 允许下一片参与调度
                    end                                     // 当前语句组结束
                    else begin                              // 消息结束（成功末片 / 错误 / 空帧）
                        pending[sched_idx]  <= 1'b0;            // 清该槽位待发标志
                        bag_skip[sched_idx] <= 1'b0;            // 本帧收尾，清掉该槽位的跳过标记
                        msg_off_r   <= 16'd0;                   // 消息偏移归零
                        frag_cnt_r  <= 5'd0;                    // 帧计数归零
                        frag_active <= 1'b0;                    // 退出分片发送
                    end                                     // 当前语句组结束
                    if (finish_kind == 2'd0)                // 检查0=成功 1=错误 2=空帧跳过的条件
                        ip_id_cnt <= ip_id_cnt + 16'd1;         // 只对实际发出的帧递增标识
                end                                         // 当前语句组结束

                default: ;                                       // 其余状态没有数据通路动作
            endcase                                         // 当前分支选择结束

            state <= nxt_state;                                 // 状态寄存器只在第一段更新
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    // ==================== 帧字节生成 ====================
    reg [7:0] tx_byte;                                          // 当前输出字节
    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        tx_byte = 8'h00;                                    // 设置或组合计算当前输出字节
        if (tx_byte_pos <= 16'd3)                           // 检查当前输出字节位置的条件
            case (tx_byte_pos[1:0])                         // 根据当前输出字节位置选择处理分支
                2'd0: tx_byte = 8'h01;                      // 当前字节或字段索引对应的数据选择
                2'd1: tx_byte = 8'h00;                      // 当前字节或字段索引对应的数据选择
                2'd2: tx_byte = 8'h00;                      // 当前字节或字段索引对应的数据选择
                default: tx_byte = 8'h00;                   // 未匹配有效分支时采用默认处理
            endcase                                         // 当前分支选择结束
        else if (tx_byte_pos == 16'd4)                      // 检查当前输出字节位置的条件
            tx_byte = vlid_r[15:8];                         // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd5)                      // 检查当前输出字节位置的条件
            tx_byte = vlid_r[7:0];                          // 设置或组合计算当前输出字节
        else if ((tx_byte_pos >= 16'd6) && (tx_byte_pos <= 16'd11))  // 检查当前输出字节位置、当前输出字节位置的条件
            case (tx_byte_pos - 16'd6)                      // 根据当前输出字节位置、d6选择处理分支
                16'd0: tx_byte = 8'h02;                     // 当前字节或字段索引对应的数据选择
                16'd5: tx_byte = 8'h01;                     // 当前字节或字段索引对应的数据选择
                default: tx_byte = 8'h00;                   // 未匹配有效分支时采用默认处理
            endcase                                         // 当前分支选择结束
        else if (tx_byte_pos == 16'd12)                     // 检查当前输出字节位置的条件
            tx_byte = 8'h08;                                // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd13)                     // 检查当前输出字节位置的条件
            tx_byte = 8'h00;                                    // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd14)                     // 检查当前输出字节位置的条件
            tx_byte = 8'h45;                                // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd15)                     // 检查当前输出字节位置的条件
            tx_byte = 8'h00;                                    // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd16)                     // 检查当前输出字节位置的条件
            tx_byte = ip_total_r[15:8];                     // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd17)                     // 检查当前输出字节位置的条件
            tx_byte = ip_total_r[7:0];                      // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd18)                     // 检查当前输出字节位置的条件
            tx_byte = ip_id_cnt[15:8];                      // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd19)                     // 检查当前输出字节位置的条件
            tx_byte = ip_id_cnt[7:0];                       // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd20)                     // 检查当前输出字节位置的条件
            tx_byte = flg_off_r[15:8];                      // IP 标志 + 片偏移高字节（分片时 MF 置位）
        else if (tx_byte_pos == 16'd21)                     // 检查当前输出字节位置的条件
            tx_byte = flg_off_r[7:0];                       // IP 片偏移低字节
        else if (tx_byte_pos == 16'd22)                     // 检查当前输出字节位置的条件
            tx_byte = 8'h01;                                // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd23)                     // 检查当前输出字节位置的条件
            tx_byte = 8'h11;                                // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd24)                     // 检查当前输出字节位置的条件
            tx_byte = ip_cksum_r[15:8];                     // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd25)                     // 检查当前输出字节位置的条件
            tx_byte = ip_cksum_r[7:0];                      // 设置或组合计算当前输出字节
        else if ((tx_byte_pos >= 16'd26) && (tx_byte_pos <= 16'd29))  // 检查当前输出字节位置、当前输出字节位置的条件
            case (tx_byte_pos - 16'd26)                     // 根据当前输出字节位置、d26选择处理分支
                16'd0: tx_byte = 8'h04;                     // 当前字节或字段索引对应的数据选择
                16'd1: tx_byte = 8'h00;                     // 当前字节或字段索引对应的数据选择
                16'd2: tx_byte = 8'h00;                     // 当前字节或字段索引对应的数据选择
                default: tx_byte = 8'h01;                   // 未匹配有效分支时采用默认处理
            endcase                                         // 当前分支选择结束
        else if ((tx_byte_pos >= 16'd30) && (tx_byte_pos <= 16'd33))  // 检查当前输出字节位置、当前输出字节位置的条件
            case (tx_byte_pos - 16'd30)                     // 根据当前输出字节位置、d30选择处理分支
                16'd0: tx_byte = dst_ip_r[31:24];           // 当前字节或字段索引对应的数据选择
                16'd1: tx_byte = dst_ip_r[23:16];           // 当前字节或字段索引对应的数据选择
                16'd2: tx_byte = dst_ip_r[15:8];            // 当前字节或字段索引对应的数据选择
                default: tx_byte = dst_ip_r[7:0];           // 未匹配有效分支时采用默认处理
            endcase                                         // 当前分支选择结束
        else if (tx_byte_pos == 16'd34)                     // 检查当前输出字节位置的条件
            tx_byte = 8'h00;                                    // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd35)                     // 检查当前输出字节位置的条件
            tx_byte = 8'hA1;                                // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd36)                     // 检查当前输出字节位置的条件
            tx_byte = cfg_udp_r[15:8];                      // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd37)                     // 检查当前输出字节位置的条件
            tx_byte = cfg_udp_r[7:0];                       // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd38)                     // 检查当前输出字节位置的条件
            tx_byte = udp_len_r[15:8];                      // 设置或组合计算当前输出字节
        else if (tx_byte_pos == 16'd39)                     // 检查当前输出字节位置的条件
            tx_byte = udp_len_r[7:0];                       // 设置或组合计算当前输出字节
        else if ((tx_byte_pos >= 16'd40) && (tx_byte_pos <= 16'd41))  // 检查当前输出字节位置、当前输出字节位置的条件
            tx_byte = 8'h00;                                    // 设置或组合计算当前输出字节
        else if ((tx_byte_pos >= 16'd42) && (tx_byte_pos < 16'd42 + data_len_r)) begin  // 检查当前输出字节位置、当前输出字节位置的条件
            if (payload_pos < payload_len_r)                // 检查当前载荷内偏移、待发应用数据实际长度的条件
                tx_byte = payload_data;                     // 设置或组合计算当前输出字节
            else                                            // 采用前一条件未满足时的处理
                tx_byte = 8'h00;                                // AFDX 载荷不足 17 字节时补零
        end                                                 // 当前语句组结束
        else if (tx_byte_pos == 16'd42 + data_len_r)        // 检查当前输出字节位置、补齐 17 字节后的载荷长度的条件
            tx_byte = sn_r;                                     // SN 在应用数据之后
        else                                                // 采用前一条件未满足时的处理
            tx_byte = 8'h00;                                    // 以太网最小帧填充在 SN 之后
    end                                                     // 当前语句组结束

    // ==================== MAC 发送输出 ====================
    assign ff_tx_data = tx_byte;                                // output [7:0]
    assign ff_tx_wren = build_active;                           // output [0:0]
    assign ff_tx_sop  = build_active && (tx_byte_pos == 16'd0); // output [0:0]
    assign ff_tx_eop  = build_active && (tx_byte_pos == frame_total_r - 16'd1); // output [0:0]

    // ==================== MIB / 状态写回 / 中断 ====================
    wire finish_success = (state == S_FINISH) && (finish_kind == 2'd0);  // 发送完成且结果为成功时的单拍条件
    wire finish_error   = (state == S_FINISH) && (finish_kind == 2'd1);  // 发送完成且结果为错误时的单拍条件
    assign mib_addr         = vlid_r[VL_ADDR_WIDTH-1:0];        // output [11:0]
    assign mib_tx_frame_inc = finish_success;                   // output [0:0]
    assign mib_tx_byte_inc  = build_active && (tx_byte_pos >= 16'd42) &&  // 设置或组合计算发送字节数 +1（每个发送字节一拍）
                              (tx_byte_pos < 16'd42 + payload_len_r); // output [0:0]：只计实际应用数据
    assign mib_tx_error_inc = finish_error;                     // output [0:0]
    assign mib_tx_frag_inc  = finish_success && frag_more_r;    // output [0:0]：本帧是分片帧（还有后续分片）
    assign mib_tx_bag_inc   = bag_pulse;                        // output [0:0]

    assign st_wr_en = finish_success;                           // output [0:0]
    assign st_wr_data = {start_ts_r,                        // 设置或组合计算状态写数据
                         st_rd_data[31:25],                 // 继续计算st_wr_data
                         1'b1,                              // 继续计算st_wr_data
                         next_sn_r,                         // 继续计算st_wr_data
                         st_rd_data[15:0]};                     // output [63:0]：只更新 TX 位段，保留 RX 位段

    assign irq_tx_done = finish_success;                        // output [0:0]
    assign ff_tx_err   = finish_error;                          // output [0:0]：内部错误上报一拍

endmodule                                                   // 模块定义结束

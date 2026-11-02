// afdx_rx : AFDX 接收模块
// 从 MAC 接收字节流解析以太网/IP/UDP 头，取出 VLID 查配置表，完成
// 长度/端口过滤、完整性检查（IC，序列号）、冗余管理（RM，重复帧剔除），
// 把载荷写入接收端口缓冲，并更新 MIB 计数与就绪通知
// 注：内部状态机与数据通路已实现（两段式：组合算次态与转移请求、时序存状态与数据通路），
// RAM（配置表 / 状态表 / 端口缓冲）读延迟按 1 拍处理
module afdx_rx #(                                           // 声明模块及其参数接口
    parameter DATA_WIDTH        = 8,        // 数据位宽，MAC 侧 1 字节/拍
    parameter VLID_WIDTH        = 16,       // VLID 位宽
    parameter VL_ADDR_WIDTH     = 12,       // VL 表地址位宽（IP 已生成 4096 深）
    parameter VL_INDEX_WIDTH    = 4,        // 端口缓冲 VL 索引位宽
    parameter BYTE_OFFSET_WIDTH = 11,       // 端口缓冲字节偏移位宽
    parameter CNT_WIDTH         = 32,       // MIB 计数器位宽
    parameter STATE_WIDTH       = 64,       // VL 运行期状态字宽
    parameter VL_INDEX_SNMP     = 4'd1,     // SNMP 代理占用的 VL 索引（用于产生 rx_ready_snmp）
    parameter VL_INDEX_615A     = 4'd2,     // 615A 代理占用的 VL 索引（用于产生 rx_ready_615a）
    parameter VL_INDEX_RTC      = 4'd3      // RTC 代理占用的 VL 索引（用于产生 rx_ready_rtc）
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== MAC 接收侧 ====================
    input  wire [DATA_WIDTH-1:0]         ff_rx_data,             // MAC 接收数据
    input  wire                          ff_rx_data_vld,         // MAC 接收数据有效
    input  wire                          ff_rx_sop,              // MAC 接收包起始
    input  wire                          ff_rx_eop,              // MAC 接收包结束
    input  wire                          ff_rx_err,              // MAC 接收错误
    output wire                          ff_rx_rdy,              // MAC 接收准备

    // ==================== 本帧来自哪张网 ====================
    input  wire                          frame_net,              // 0=网络 A 1=网络 B；单网口硬件下恒为 0

    // ==================== VL 配置表读（端口 A） ====================
    output wire [VL_ADDR_WIDTH-1:0]      cfg_addr,               // 配置表读地址 = vlid[VL_ADDR_WIDTH-1:0]（直接映射）
    output wire                          cfg_rd_en,              // 配置表读使能
    input  wire [VLID_WIDTH-1:0]         cfg_tag,                // 读回 VLID，用于判断查表命中
    input  wire                          cfg_valid,              // 条目有效标志
    input  wire [1:0]                    cfg_port_type,          // 端口类型：0=采样 1=队列
    input  wire [15:0]                   cfg_udp_port,           // UDP 目的端口，用于端口过滤
    input  wire [15:0]                   cfg_bag,                // BAG（接收侧用于流量监控）
    input  wire [15:0]                   cfg_lmax,               // Lmax，用于帧长合法性检查
    input  wire                          cfg_rm_en,              // RM 使能，1=做双网重复帧剔除
    input  wire                          cfg_ic_mode,            // IC 模式：0=序列号检查 1=奇偶校验

    // ==================== VL 运行期状态读写（vl_state_ram 端口 A） ====================
    output wire [VL_ADDR_WIDTH-1:0]      st_addr,                // 状态表地址，与查表地址相同（= vlid 低位）
    output wire                          st_rd_en,               // 状态读使能（帧首读 PSN）
    input  wire [STATE_WIDTH-1:0]        st_rd_data,             // 状态读数据（rx_last_sn/rx_sn_valid）
    output wire                          st_wr_en,               // 状态写使能（帧尾写回新状态）
    output wire [STATE_WIDTH-1:0]        st_wr_data,             // 状态写数据

    // ==================== 接收端口缓冲写侧 ====================
    output wire                          port_wr_en,             // 端口缓冲写使能
    output wire [VL_INDEX_WIDTH-1:0]     port_wr_vl_index,       // 端口缓冲写槽位号 = vlid[VL_INDEX_WIDTH-1:0]
    output wire [BYTE_OFFSET_WIDTH-1:0]  port_wr_byte_offset,    // 端口缓冲写字节偏移
    output wire [DATA_WIDTH-1:0]         port_wr_data,           // 端口缓冲写数据
    output wire [1:0]                    port_type,              // 本帧端口类型，供上层区分采样/队列端口

    // ==================== 协议代理就绪通知 ====================
    output wire                          rx_ready_app,           // 应用端口一帧接收完成
    output wire                          rx_ready_snmp,          // SNMP 端口一帧接收完成
    output wire                          rx_ready_615a,          // 615A 端口一帧接收完成
    output wire                          rx_ready_rtc,           // RTC 端口一帧接收完成

    // ==================== 端口缓冲队列控制（采样 / 队列 / SAP 语义） ====================
    output wire                          port_wr_frame_done,     // 帧尾脉冲：提交本帧（登记长度/入队）
    output wire [15:0]                   port_wr_frame_len,      // 本帧应用数据长度（与帧尾同拍）
    output wire                          port_wr_queue_mode,     // 0=采样端口(覆盖) 1=队列/SAP端口(入队)，由 cfg_port_type 决定
    input  wire                          port_wr_full,           // 该槽位队列已满：本帧应丢弃并计 rx_error_count

    // ==================== MIB 计数（计数事件 + 所属条目地址） ====================
    output wire [VL_ADDR_WIDTH-1:0]      mib_addr,               // 计数事件所属 VL（= vlid[VL_ADDR_WIDTH-1:0]）
    output wire                          mib_rx_frame_inc,       // 接收成功帧数 +1
    output wire                          mib_rx_error_inc,       // 接收错误帧数 +1（长度/端口/RM 不合法）
    output wire                          mib_sn_error_inc,       // SN（序列号）错误帧数 +1
    output wire                          mib_rm_drop_inc,        // RM 重复帧丢弃数 +1
    output wire                          mib_rx_byte_inc,        // 接收字节数 +1（每个有效字节一拍）

    // ==================== 中断 ====================
    output wire                          irq_rx_frame,           // 中断：有效帧接收完成
    output wire                          irq_error               // 中断：接收错误
);                                                          // 端口声明或模块例化结束

    // ==================== 接收状态机状态 ====================
    localparam S_IDLE        = 5'd0;                             // 空闲
    localparam S_MAC_DA      = 5'd1;                             // 解析目的 MAC
    localparam S_MAC_SA      = 5'd2;                             // 解析源 MAC
    localparam S_MAC_TYPE    = 5'd3;                             // 解析以太网类型
    localparam S_VL_LOOKUP   = 5'd4;                             // 等待并判断 VL 配置命中
    localparam S_IP_PARSE    = 5'd5;                             // 解析 IP 头
    localparam S_FRAG_CHECK  = 5'd6;                             // 判断分片帧
    localparam S_UDP_PARSE   = 5'd7;                             // 解析 UDP 头
    localparam S_PORT_CHECK  = 5'd8;                             // 端口过滤
    localparam S_PAYLOAD     = 5'd9;                             // 接收应用数据
    localparam S_SN_RECV     = 5'd10;                            // 取载荷末字节 SN
    localparam S_IC_CHECK    = 5'd11;                            // 完整性检查
    localparam S_RM_SINGLE   = 5'd12;                            // 冗余管理
    localparam S_DISPATCH    = 5'd13;                            // 提交帧并更新计数
    localparam S_MIB_BYTES   = 5'd14;                            // 已提交帧的字节计数回放
    localparam S_DROP        = 5'd15;                            // 丢弃并消费剩余字节
    localparam S_DONE        = 5'd16;                            // 一帧处理结束

    reg [4:0] state;                                            // 当前接收状态

    // ==================== 帧解析寄存器 ====================
    reg [47:0] da_acc;                                          // 目的 MAC 移位寄存器
    reg [2:0]  da_cnt;                                          // 已收到目的 MAC 字节数
    reg [2:0]  sa_cnt;                                          // 已收到源 MAC 字节数
    reg [1:0]  type_cnt;                                        // 已收到以太网类型字节数
    reg [15:0] type_acc;                                        // 以太网类型
    reg [VLID_WIDTH-1:0] vlid_r;                                // 本帧 VLID
    reg        prefix_ok;                                       // 目的 MAC 前 32bit 是否为 AFDX 前缀
    reg        frame_net_r;                                     // 本帧来源网络

    // ==================== 配置查表锁存 ====================
    reg [1:0]  cfg_port_type_r;                                 // 命中条目的端口类型
    reg [15:0] cfg_udp_port_r;                                  // 命中条目的 UDP 目的端口
    reg [15:0] cfg_lmax_r;                                      // 命中条目的 Lmax
    reg        cfg_rm_en_r;                                     // 命中条目的 RM 使能
    reg        cfg_ic_mode_r;                                   // 命中条目的 IC 模式

    // ==================== IP / UDP 解析寄存器 ====================
    reg [4:0]  ip_cnt;                                          // IP 头字节计数 0~19
    reg [7:0]  ip_prev;                                         // IP 校验和奇字节暂存
    reg [16:0] ip_cksum;                                        // IP 头反码和累加器
    reg        ip_cksum_ok;                                     // IP 首部校验和是否合法
    reg        ip_header_ok;                                    // 版本/IHL/协议是否合法
    reg [15:0] ip_total_len_r;                                  // IP 总长度
    reg [4:0]  ip_flags_lo;                                     // 片偏移高 5bit
    reg        ip_mf;                                           // MF 分片标志
    reg [12:0] ip_frag_off;                                     // 片偏移
    reg [3:0]  udp_cnt;                                         // UDP 头字节计数 0~7
    reg [15:0] udp_dst_r;                                       // UDP 目的端口
    reg [15:0] udp_len_r;                                       // UDP 长度

    // ==================== 载荷与 IC/RM 寄存器 ====================
    reg [15:0] pay_cnt;                                         // 当前帧已接收应用数据字节数
    reg [7:0]  sn_r;                                            // 载荷末字节 SN
    reg        psn_write_en;                                    // 本帧是否需要写回新 PSN
    reg [7:0]  psn_write_val;                                   // 要写回的新 PSN
    reg        drop_sn_err;                                     // 丢弃原因含 SN 错误
    reg        drop_rm_drop;                                    // 丢弃原因仅为 RM 冗余副本
    reg        ic_cross_dup;                                    // IC 判为跨网重复
    reg        err_counted;                                     // 本帧是否已计过一次错误
    reg        drop_entry;                                      // 第一次进入 DROP 的单拍脉冲
    reg [15:0] byte_left;                                       // 提交帧后还需回放的字节计数
    reg        eop_seen_r;                                      // 本帧帧尾是否已被状态机消费（载荷末字节即帧尾时为 1）

    // 双网 RM 需要记住最近一次接受 SN 来自哪张网；按 16 个缓冲槽位保存即可。
    reg last_net_valid [(1<<VL_INDEX_WIDTH)-1:0];               // 对应槽位是否已有网络来源记录
    reg last_net       [(1<<VL_INDEX_WIDTH)-1:0];               // 对应槽位最近接受帧的网络来源
    integer rx_i;                                               // 复位遍历寄存器

    // ==================== 组合判决 ====================
    wire [15:0] data_len_w = ip_total_len_r - 16'd29;           // 应用数据长度，不含 SN
    wire [15:0] frame_core = 16'd14 + ip_total_len_r;           // 不含以太网填充的帧长
    wire config_hit = cfg_valid && (cfg_tag == vlid_r) && prefix_ok; // 配置命中
    wire udp_len_ok = (udp_len_r == ip_total_len_r - 16'd20);   // UDP 长度与 IP 总长自洽
    wire data_len_ok = ip_header_ok && ip_cksum_ok && udp_len_ok &&  // IP/UDP 长度、校验和与载荷范围共同合法
                       (ip_total_len_r >= 16'd29) &&        // IP 总长度至少容纳头部与序列号
                       (ip_total_len_r <= 16'd1504) &&      // IP 总长度不得超过当前接口允许的上限
                       (data_len_w >= 16'd17) &&            // 应用载荷满足既有状态机规定的最小长度
                       (data_len_w <= 16'd1471) &&          // 应用载荷不超过当前组帧允许的最大长度
                       (data_len_w <= cfg_lmax_r);              // 长度与 Lmax 均合法
    wire port_ok = (udp_dst_r == cfg_udp_port_r);               // UDP 端口过滤

    wire [VL_ADDR_WIDTH-1:0] vl_addr = vlid_r[VL_ADDR_WIDTH-1:0]; // 表地址与 MIB 地址
    wire [7:0] psn = st_rd_data[7:0];                           // 状态表中的最近接收 SN
    wire       psn_valid = st_rd_data[8];                       // 状态表 PSN 是否已初始化
    wire [8:0] expected9 = (psn == 8'd255) ? 9'd1 : {1'b0, psn} + 9'd1; // 1~255 环上的期望 SN
    wire       sn_expect = psn_valid && (sn_r == expected9[7:0]); // SN 正常递增
    wire [VL_INDEX_WIDTH-1:0] vl_slot = vlid_r[VL_INDEX_WIDTH-1:0]; // 本帧端口缓冲槽位
    wire       same_net_last = last_net_valid[vl_slot] ?    // 当前帧与上次有效帧是否来自同一网络
                               (frame_net_r == last_net[vl_slot]) : 1'b1; // 与上次接受帧同网
    wire       same_dup   = psn_valid && (sn_r == psn) && same_net_last; // 同网重复
    wire       cross_dup  = psn_valid && (sn_r == psn) && !same_net_last; // 跨网重复
    wire       sn_zero_bad = psn_valid && (sn_r == 8'd0) &&  // 已有历史序列号时本帧零序列号是否非法
                            !same_dup && !cross_dup;            // 非首帧收到 SN=0
    wire       sn_jump = psn_valid && (sn_r != 8'd0) && !sn_expect &&  // 本帧是否为需要重新同步的跳跃序列号
                        !same_dup && !cross_dup;                // SN 跳变/回退

    wire [16:0] cksum_add = ip_cnt[0] ? {1'b0, ip_prev, ff_rx_data} : 17'd0; // 本拍 16bit 字
    wire [16:0] cksum_sum = ip_cksum + cksum_add;               // 反码和临时结果
    wire [16:0] cksum_fold = {1'b0, cksum_sum[15:0]} + {16'b0, cksum_sum[16]}; // 回卷进位
    wire        cksum_now_ok = (cksum_fold[15:0] == 16'hFFFF);  // 含校验和字段的反码和为全 1
    wire [47:0] da_new = {da_acc[39:0], ff_rx_data};             // 本拍更新后的完整目的 MAC

    // ==================== 查表/状态表地址与读使能 ====================
    assign cfg_addr = vl_addr;                                  // output [11:0]
    assign st_addr  = vl_addr;                                  // output [11:0]
    assign cfg_rd_en = (state == S_MAC_DA) && (da_cnt == 3'd5); // 收到 VLID 当拍发起查表
    assign st_rd_en  = (state == S_MAC_DA) && (da_cnt == 3'd5); // 同拍发起状态表读

    // ==================== 端口缓冲写输出 ====================
    assign port_wr_en = (state == S_PAYLOAD) && ff_rx_data_vld &&  // 设置或组合计算端口缓冲写使能
                        (pay_cnt < data_len_w);                 // 只写应用数据，不写 SN
    assign port_wr_vl_index = vlid_r[VL_INDEX_WIDTH-1:0];       // output [3:0]
    assign port_wr_byte_offset = pay_cnt[BYTE_OFFSET_WIDTH-1:0]; // output [10:0]
    assign port_wr_data = ff_rx_data;                           // output [7:0]
    assign port_type    = cfg_port_type_r;                      // output [1:0]
    assign port_wr_queue_mode = (cfg_port_type_r != 2'd0);      // output [0:0]
    assign port_wr_frame_done = (state == S_DISPATCH) && !port_wr_full; // output [0:0]
    assign port_wr_frame_len = data_len_w;                      // output [15:0]

    // ==================== MIB / 中断 ====================
    assign mib_addr         = vl_addr;                          // output [11:0]
    assign mib_rx_frame_inc = (state == S_DISPATCH) && !port_wr_full; // output [0:0]
    assign mib_rx_error_inc = drop_entry && !drop_rm_drop;      // output [0:0]
    assign mib_sn_error_inc = drop_entry && drop_sn_err;        // output [0:0]
    assign mib_rm_drop_inc  = drop_entry && drop_rm_drop;       // output [0:0]
    assign mib_rx_byte_inc  = (state == S_MIB_BYTES) && (byte_left != 16'd0); // output [0:0]

    assign irq_rx_frame = (state == S_DISPATCH) && !port_wr_full; // output [0:0]
    assign irq_error    = drop_entry;                           // output [0:0]
    assign ff_rx_rdy    = (state == S_IDLE);                    // output [0:0]：处理整帧期间拉低

    // ==================== 就绪通知 ====================
    wire dispatch_ok = (state == S_DISPATCH) && !port_wr_full;  // 本帧确实被提交
    wire is_snmp_slot = (vlid_r[VL_INDEX_WIDTH-1:0] == VL_INDEX_SNMP[VL_INDEX_WIDTH-1:0]);  // 当前载荷是否发给 SNMP 代理槽位
    wire is_615a_slot = (vlid_r[VL_INDEX_WIDTH-1:0] == VL_INDEX_615A[VL_INDEX_WIDTH-1:0]);  // 当前载荷是否发给 615A 代理槽位
    wire is_rtc_slot  = (vlid_r[VL_INDEX_WIDTH-1:0] == VL_INDEX_RTC[VL_INDEX_WIDTH-1:0]);  // 当前载荷是否发给 RTC 代理槽位
    assign rx_ready_snmp = dispatch_ok && is_snmp_slot;         // output [0:0]
    assign rx_ready_615a = dispatch_ok && is_615a_slot;         // output [0:0]
    assign rx_ready_rtc  = dispatch_ok && is_rtc_slot;          // output [0:0]
    assign rx_ready_app  = dispatch_ok && !is_snmp_slot &&  // 设置或组合计算应用端口一帧接收完成
                           !is_615a_slot && !is_rtc_slot;       // output [0:0]

    // ==================== 状态写回 ====================
    // DISPATCH 正常提交，或 SN 跳变丢弃后第一次进入 DROP 时写回新 PSN。
    assign st_wr_en = ((state == S_DISPATCH) && psn_write_en && !port_wr_full) ||  // 设置或组合计算状态写使能（帧尾写回新状态）
                      ((state == S_DROP) && psn_write_en && drop_entry); // output [0:0]：DROP 首拍写回重同步 PSN
    assign st_wr_data = {st_rd_data[STATE_WIDTH-1:9], 1'b1, psn_write_val}; // output [63:0]

    // ==================== 状态机：第二段（组合，算次态与转移请求） ====================
    reg [4:0] nxt_state;                                        // 次态，由本段组合算出
    reg       drop_req;                                         // 本拍申请丢弃本帧（组合）
    reg       drop_sn_err_req;                                  // 申请丢弃的原因含 SN 错误（组合）
    reg       drop_rm_drop_req;                                 // 申请丢弃的原因是 RM 冗余副本（组合）

    wire drop_accept = drop_req && (state != S_DROP) && (state != S_DONE); // 本拍丢弃申请被采纳

    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        nxt_state        = state;                               // 默认保持当前状态
        drop_req         = 1'b0;                                // 默认不丢弃
        drop_sn_err_req  = 1'b0;                                // 默认不是 SN 错误
        drop_rm_drop_req = 1'b0;                                // 默认不是 RM 冗余副本

        // MAC 层错误全局优先：任一非 IDLE/DROP/DONE 状态出错都丢弃本帧
        if (ff_rx_err && (state != S_IDLE) && (state != S_DROP) && (state != S_DONE))  // 检查MAC 接收错误、当前接收状态、空闲的条件
            drop_req = 1'b1;                                // 设置或组合计算本拍申请丢弃本帧（组合）

        case (state)                                        // 根据当前接收状态选择处理分支
            S_IDLE: begin                                   // 处理空闲阶段
                if (ff_rx_data_vld && ff_rx_sop)            // 输入字节有效时更新帧解析数据通路
                    nxt_state = S_MAC_DA;                       // 收到帧起始，开始解析目的 MAC
            end                                             // 当前语句组结束

            S_MAC_DA: begin                                 // 处理解析目的 MAC阶段
                if (ff_rx_data_vld) begin                   // 输入字节有效时更新帧解析数据通路
                    if (ff_rx_eop)                          // 检查MAC 接收包结束的条件
                        drop_req = 1'b1;                        // 目的 MAC 未收满 6 字节即结束
                    else if (da_cnt == 3'd5)                // 检查已收到目的 MAC 字节数的条件
                        nxt_state = S_MAC_SA;                   // 目的 MAC 收满（含 VLID）
                end                                         // 当前语句组结束
            end                                             // 当前语句组结束

            S_MAC_SA: begin                                 // 处理解析源 MAC阶段
                if (ff_rx_data_vld) begin                   // 输入字节有效时更新帧解析数据通路
                    if (ff_rx_eop)                          // 检查MAC 接收包结束的条件
                        drop_req = 1'b1;                        // 源 MAC 未收满 6 字节
                    else if (sa_cnt == 3'd5)                // 检查已收到源 MAC 字节数的条件
                        nxt_state = S_MAC_TYPE;             // 设置或组合计算次态
                end                                         // 当前语句组结束
            end                                             // 当前语句组结束

            S_MAC_TYPE: begin                               // 处理解析以太网类型阶段
                if (ff_rx_data_vld) begin                   // 输入字节有效时更新帧解析数据通路
                    if (ff_rx_eop)                          // 检查MAC 接收包结束的条件
                        drop_req = 1'b1;                        // 以太网类型未收满 2 字节
                    else if (type_cnt == 2'd1) begin        // 检查已收到以太网类型字节数的条件
                        if ({type_acc[7:0], ff_rx_data} == 16'h0800)  // 检查以太网类型、MAC 接收数据的条件
                            nxt_state = S_VL_LOOKUP;            // 只接受 IPv4
                        else                                // 采用前一条件未满足时的处理
                            drop_req = 1'b1;                    // 非 IPv4 以太网类型
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束
            end                                             // 当前语句组结束

            S_VL_LOOKUP: begin                              // 处理等待并判断 VL 配置命中阶段
                if (config_hit) begin                       // 检查配置命中的条件
                    if (ff_rx_data_vld && ff_rx_eop)        // 输入字节有效时更新帧解析数据通路
                        drop_req = 1'b1;                        // IP 头未完整
                    else                                    // 采用前一条件未满足时的处理
                        nxt_state = S_IP_PARSE;                 // 配置命中，进入 IP 解析
                end                                         // 当前语句组结束
                else                                        // 采用前一条件未满足时的处理
                    drop_req = 1'b1;                            // 未配置 VL 或 tag 冲突
            end                                             // 当前语句组结束

            S_IP_PARSE: begin                               // 处理解析 IP 头阶段
                if (ff_rx_data_vld) begin                   // 输入字节有效时更新帧解析数据通路
                    if (ff_rx_eop)                          // 检查MAC 接收包结束的条件
                        drop_req = 1'b1;                        // IP 头未收满 20 字节
                    else if (ip_cnt == 5'd19) begin         // 检查IP 头字节计数 0~19的条件
                        if (ip_mf || (ip_frag_off != 13'd0))  // 检查MF 分片标志、片偏移的条件
                            drop_req = 1'b1;                    // 分片帧直接丢弃，不做重组
                        else                                // 采用前一条件未满足时的处理
                            nxt_state = S_UDP_PARSE;        // 设置或组合计算次态
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束
            end                                             // 当前语句组结束

            S_UDP_PARSE: begin                              // 处理解析 UDP 头阶段
                if (ff_rx_data_vld) begin                   // 输入字节有效时更新帧解析数据通路
                    if (ff_rx_eop)                          // 检查MAC 接收包结束的条件
                        drop_req = 1'b1;                        // UDP 头未收满 8 字节
                    else if (udp_cnt == 4'd7) begin         // 检查UDP 头字节计数 0~7的条件
                        if (port_ok && data_len_ok && !port_wr_full)  // 检查UDP 端口过滤ta_len_ok、该槽位队列已满：本帧应丢弃并计 rx_error_count的条件
                            nxt_state = S_PAYLOAD;              // 端口/长度合法且缓冲可接收
                        else                                // 采用前一条件未满足时的处理
                            drop_req = 1'b1;                    // 端口、长度或缓冲检查不通过
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束
            end                                             // 当前语句组结束

            S_PAYLOAD: begin                                // 处理接收应用数据阶段
                if (ff_rx_data_vld) begin                   // 输入字节有效时更新帧解析数据通路
                    if (ff_rx_eop)                          // 检查MAC 接收包结束的条件
                        drop_req = 1'b1;                        // 应用数据未收满 data_len
                    else if (pay_cnt == data_len_w - 16'd1)  // 检查当前帧已接收应用数据字节数、应用数据长度的条件
                        nxt_state = S_SN_RECV;                  // 应用数据收完，下一字节是 SN
                end                                         // 当前语句组结束
            end                                             // 当前语句组结束

            S_SN_RECV: begin                                // 处理取载荷末字节 SN阶段
                if (ff_rx_data_vld)                         // 输入字节有效时更新帧解析数据通路
                    nxt_state = S_IC_CHECK;                     // 取到载荷末字节 SN
                else if (ff_rx_eop)                         // 检查MAC 接收包结束的条件
                    drop_req = 1'b1;                            // 载荷末字节缺失
            end                                             // 当前语句组结束

            S_IC_CHECK: begin                               // 处理完整性检查阶段
                if (!psn_valid || sn_expect)                // 检查状态表 PSN 是否已初始化、SN 正常递增的条件
                    nxt_state = S_RM_SINGLE;                    // 首帧或 SN 正常递增
                else if (cross_dup)                         // 检查跨网重复的条件
                    nxt_state = S_RM_SINGLE;                    // 跨网重复交 RM 判决
                else begin                                  // 前一条件不满足时执行本分支
                    drop_sn_err_req = 1'b1;                     // 同网重复、SN 跳变、非首帧收到 0
                    drop_req        = 1'b1;                 // 设置或组合计算本拍申请丢弃本帧（组合）
                end                                         // 当前语句组结束
            end                                             // 当前语句组结束

            S_RM_SINGLE: begin                              // 处理冗余管理阶段
                if (ic_cross_dup) begin                     // 检查IC 判为跨网重复的条件
                    if (cfg_rm_en_r) begin                  // 检查命中条目的 RM 使能的条件
                        drop_rm_drop_req = 1'b1;                // 开 RM：按冗余副本丢弃
                        drop_req         = 1'b1;            // 设置或组合计算本拍申请丢弃本帧（组合）
                    end                                     // 当前语句组结束
                    else begin                              // 前一条件不满足时执行本分支
                        drop_sn_err_req = 1'b1;                 // 未开 RM：按同网 SN 错误处理
                        drop_req        = 1'b1;             // 设置或组合计算本拍申请丢弃本帧（组合）
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束
                else                                        // 采用前一条件未满足时的处理
                    nxt_state = S_DISPATCH;                     // IC/RM 均通过
            end                                             // 当前语句组结束

            S_DISPATCH: begin                               // 处理提交帧并更新计数阶段
                if (!port_wr_full)                          // 检查该槽位队列已满：本帧应丢弃并计 rx_error_count的条件
                    nxt_state = S_MIB_BYTES;                    // 提交本帧，随后回放字节计数
                else                                        // 采用前一条件未满足时的处理
                    drop_req = 1'b1;                            // 队列缓冲满，丢弃本帧
            end                                             // 当前语句组结束

            S_MIB_BYTES: begin                              // 处理已提交帧的字节计数回放阶段
                if (byte_left <= 16'd1)                     // 检查提交帧后还需回放的字节计数的条件
                    nxt_state = S_DONE;                         // 字节计数回放完毕
            end                                             // 当前语句组结束

            S_DROP: begin                                   // 处理丢弃并消费剩余字节阶段
                if (ff_rx_eop || eop_seen_r)                // 检查MAC 接收包结束、本帧帧尾是否已被状态机消费（载荷末字节即帧尾时为 1）的条件
                    nxt_state = S_DONE;                         // 消费到帧尾（或帧尾已在前面被消费）后收尾
            end                                             // 当前语句组结束

            S_DONE: begin                                   // 处理一帧处理结束阶段
                nxt_state = S_IDLE;                             // 一帧处理结束
            end                                             // 当前语句组结束

            default: begin                                  // 未匹配有效分支时采用默认处理
                nxt_state = S_IDLE;                             // 异常状态回到空闲
            end                                             // 当前语句组结束
        endcase                                             // 当前分支选择结束

        // 统一处理丢弃请求：非 DROP/DONE 状态提出丢弃即强制转 DROP
        if (drop_req && (state != S_DROP) && (state != S_DONE))  // 检查本拍申请丢弃本帧（组合）、当前接收状态、丢弃并消费剩余字节的条件
            nxt_state = S_DROP;                             // 设置或组合计算次态
    end                                                     // 当前语句组结束

    // ==================== 状态机：第一段（时序，状态寄存器与数据通路） ====================

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            state           <= S_IDLE;                      // 时钟沿更新当前接收状态
            da_acc          <= 48'd0;                       // 时钟沿更新目的 MAC 移位寄存器
            da_cnt          <= 3'd0;                        // 时钟沿更新已收到目的 MAC 字节数
            sa_cnt          <= 3'd0;                        // 时钟沿更新已收到源 MAC 字节数
            type_cnt        <= 2'd0;                        // 时钟沿更新已收到以太网类型字节数
            type_acc        <= 16'd0;                       // 时钟沿更新以太网类型
            vlid_r          <= {VLID_WIDTH{1'b0}};          // 时钟沿更新本帧 VLID
            prefix_ok       <= 1'b0;                        // 时钟沿更新目的 MAC 前 32bit 是否为 AFDX 前缀
            frame_net_r     <= 1'b0;                        // 时钟沿更新本帧来源网络
            cfg_port_type_r <= 2'd0;                        // 时钟沿更新命中条目的端口类型
            cfg_udp_port_r  <= 16'd0;                       // 时钟沿更新命中条目的 UDP 目的端口
            cfg_lmax_r      <= 16'd0;                       // 时钟沿更新命中条目的 Lmax
            cfg_rm_en_r     <= 1'b0;                        // 时钟沿更新命中条目的 RM 使能
            cfg_ic_mode_r   <= 1'b0;                        // 时钟沿更新命中条目的 IC 模式
            ip_cnt          <= 5'd0;                        // 时钟沿更新IP 头字节计数 0~19
            ip_prev         <= 8'd0;                        // 时钟沿更新IP 校验和奇字节暂存
            ip_cksum        <= 17'd0;                       // 时钟沿更新IP 头反码和累加器
            ip_cksum_ok     <= 1'b0;                        // 时钟沿更新IP 首部校验和是否合法
            ip_header_ok    <= 1'b0;                        // 时钟沿更新版本/IHL/协议是否合法
            ip_total_len_r  <= 16'd0;                       // 时钟沿更新IP 总长度
            ip_flags_lo     <= 5'd0;                        // 时钟沿更新片偏移高 5bit
            ip_mf           <= 1'b0;                        // 时钟沿更新MF 分片标志
            ip_frag_off     <= 13'd0;                       // 时钟沿更新片偏移
            udp_cnt         <= 4'd0;                        // 时钟沿更新UDP 头字节计数 0~7
            udp_dst_r       <= 16'd0;                       // 时钟沿更新UDP 目的端口
            udp_len_r       <= 16'd0;                       // 时钟沿更新UDP 长度
            pay_cnt         <= 16'd0;                       // 时钟沿更新当前帧已接收应用数据字节数
            sn_r            <= 8'd0;                        // 时钟沿更新载荷末字节 SN
            psn_write_en    <= 1'b0;                        // 时钟沿更新本帧是否需要写回新 PSN
            psn_write_val   <= 8'd0;                        // 时钟沿更新要写回的新 PSN
            drop_sn_err     <= 1'b0;                        // 时钟沿更新丢弃原因含 SN 错误
            drop_rm_drop    <= 1'b0;                        // 时钟沿更新丢弃原因仅为 RM 冗余副本
            ic_cross_dup    <= 1'b0;                        // 时钟沿更新IC 判为跨网重复
            err_counted     <= 1'b0;                        // 时钟沿更新本帧是否已计过一次错误
            drop_entry      <= 1'b0;                        // 时钟沿更新第一次进入 DROP 的单拍脉冲
            byte_left       <= 16'd0;                       // 时钟沿更新提交帧后还需回放的字节计数
            eop_seen_r      <= 1'b0;                        // 时钟沿更新本帧帧尾是否已被状态机消费（载荷末字节即帧尾时为 1）
            for (rx_i = 0; rx_i < (1<<VL_INDEX_WIDTH); rx_i = rx_i + 1) begin  // 依次处理指定范围内的表项或位段
                last_net_valid[rx_i] <= 1'b0;               // 时钟沿更新对应槽位是否已有网络来源记录
                last_net[rx_i]       <= 1'b0;               // 时钟沿更新对应槽位最近接受帧的网络来源
            end                                             // 当前语句组结束
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            drop_entry <= 1'b0;                                 // 进入 DROP 的首拍给出单拍脉冲

            // 丢弃请求只在首次进入 DROP 时计一次错，并锁存丢弃原因供 MIB 计数使用
            if (drop_accept && !err_counted) begin          // 检查本拍丢弃申请被采纳、本帧是否已计过一次错误的条件
                drop_entry   <= 1'b1;                       // 时钟沿更新第一次进入 DROP 的单拍脉冲
                err_counted  <= 1'b1;                       // 时钟沿更新本帧是否已计过一次错误
                drop_sn_err  <= drop_sn_err_req;            // 时钟沿更新丢弃原因含 SN 错误
                drop_rm_drop <= drop_rm_drop_req;           // 时钟沿更新丢弃原因仅为 RM 冗余副本
            end                                             // 当前语句组结束

            // 记录帧尾是否已被消费：载荷末字节就是帧尾时，S_DROP 不能再等一个已经过去的 eop
            if (ff_rx_data_vld && ff_rx_eop)                // 输入字节有效时更新帧解析数据通路
                eop_seen_r <= 1'b1;                         // 时钟沿更新本帧帧尾是否已被状态机消费（载荷末字节即帧尾时为 1）

            case (state)                                    // 根据当前接收状态选择处理分支
                S_IDLE: begin                               // 处理空闲阶段
                    if (ff_rx_data_vld && ff_rx_sop) begin  // 输入字节有效时更新帧解析数据通路
                        da_acc       <= {40'd0, ff_rx_data};  // 时钟沿更新目的 MAC 移位寄存器
                        da_cnt       <= 3'd1;               // 时钟沿更新已收到目的 MAC 字节数
                        sa_cnt       <= 3'd0;               // 时钟沿更新已收到源 MAC 字节数
                        type_cnt     <= 2'd0;               // 时钟沿更新已收到以太网类型字节数
                        type_acc     <= 16'd0;              // 时钟沿更新以太网类型
                        vlid_r       <= {VLID_WIDTH{1'b0}};  // 时钟沿更新本帧 VLID
                        prefix_ok    <= 1'b0;               // 时钟沿更新目的 MAC 前 32bit 是否为 AFDX 前缀
                        frame_net_r  <= frame_net;          // 时钟沿更新本帧来源网络
                        ip_cnt       <= 5'd0;               // 时钟沿更新IP 头字节计数 0~19
                        ip_cksum     <= 17'd0;              // 时钟沿更新IP 头反码和累加器
                        ip_cksum_ok  <= 1'b0;               // 时钟沿更新IP 首部校验和是否合法
                        ip_header_ok <= 1'b1;               // 时钟沿更新版本/IHL/协议是否合法
                        ip_total_len_r <= 16'd0;            // 时钟沿更新IP 总长度
                        ip_mf        <= 1'b0;               // 时钟沿更新MF 分片标志
                        ip_frag_off  <= 13'd0;              // 时钟沿更新片偏移
                        udp_cnt      <= 4'd0;               // 时钟沿更新UDP 头字节计数 0~7
                        udp_dst_r    <= 16'd0;              // 时钟沿更新UDP 目的端口
                        udp_len_r    <= 16'd0;              // 时钟沿更新UDP 长度
                        pay_cnt      <= 16'd0;              // 时钟沿更新当前帧已接收应用数据字节数
                        sn_r         <= 8'd0;               // 时钟沿更新载荷末字节 SN
                        psn_write_en <= 1'b0;                    // 时钟沿更新本帧是否需要写回新 PSN
                        drop_sn_err  <= 1'b0;               // 时钟沿更新丢弃原因含 SN 错误
                        drop_rm_drop <= 1'b0;               // 时钟沿更新丢弃原因仅为 RM 冗余副本
                        ic_cross_dup <= 1'b0;               // 时钟沿更新IC 判为跨网重复
                        err_counted  <= 1'b0;               // 时钟沿更新本帧是否已计过一次错误
                        byte_left    <= 16'd0;              // 时钟沿更新提交帧后还需回放的字节计数
                        eop_seen_r   <= 1'b0;               // 时钟沿更新本帧帧尾是否已被状态机消费（载荷末字节即帧尾时为 1）
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_MAC_DA: begin                             // 处理解析目的 MAC阶段
                    if (ff_rx_data_vld && !ff_rx_eop) begin  // 输入字节有效时更新帧解析数据通路
                        da_acc <= {da_acc[39:0], ff_rx_data};  // 时钟沿更新目的 MAC 移位寄存器
                        if (da_cnt == 3'd5) begin           // 检查已收到目的 MAC 字节数的条件
                            vlid_r    <= da_new[15:0];      // 时钟沿更新本帧 VLID
                            prefix_ok <= (da_new[47:16] == 32'h01000000);  // 时钟沿更新目的 MAC 前 32bit 是否为 AFDX 前缀
                            da_cnt    <= 3'd0;              // 时钟沿更新已收到目的 MAC 字节数
                        end                                 // 当前语句组结束
                        else                                // 采用前一条件未满足时的处理
                            da_cnt <= da_cnt + 3'd1;        // 时钟沿更新已收到目的 MAC 字节数并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_MAC_SA: begin                             // 处理解析源 MAC阶段
                    if (ff_rx_data_vld && !ff_rx_eop) begin  // 输入字节有效时更新帧解析数据通路
                        if (sa_cnt == 3'd5)                 // 检查已收到源 MAC 字节数的条件
                            sa_cnt <= 3'd0;                      // 源 MAC 收满，清计数
                        else                                // 采用前一条件未满足时的处理
                            sa_cnt <= sa_cnt + 3'd1;        // 时钟沿更新已收到源 MAC 字节数并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_MAC_TYPE: begin                           // 处理解析以太网类型阶段
                    if (ff_rx_data_vld && !ff_rx_eop) begin  // 输入字节有效时更新帧解析数据通路
                        type_acc <= {type_acc[7:0], ff_rx_data};  // 时钟沿更新以太网类型
                        if (type_cnt == 2'd1)               // 检查已收到以太网类型字节数的条件
                            type_cnt <= 2'd0;               // 时钟沿更新已收到以太网类型字节数
                        else                                // 采用前一条件未满足时的处理
                            type_cnt <= type_cnt + 2'd1;    // 时钟沿更新已收到以太网类型字节数并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_VL_LOOKUP: begin                          // 处理等待并判断 VL 配置命中阶段
                    // 地址在 DA 最后一字节给出，本拍 q 已稳定。
                    if (config_hit) begin                   // 检查配置命中的条件
                        cfg_port_type_r <= cfg_port_type;   // 时钟沿更新命中条目的端口类型
                        cfg_udp_port_r  <= cfg_udp_port;    // 时钟沿更新命中条目的 UDP 目的端口
                        cfg_lmax_r      <= cfg_lmax;        // 时钟沿更新命中条目的 Lmax
                        cfg_rm_en_r     <= cfg_rm_en;       // 时钟沿更新命中条目的 RM 使能
                        cfg_ic_mode_r   <= cfg_ic_mode;     // 时钟沿更新命中条目的 IC 模式
                        if (ff_rx_data_vld && !ff_rx_eop) begin  // 输入字节有效时更新帧解析数据通路
                            // 查表这一拍仍要消费数据，因此本拍顺带吃掉 IP 首字节。
                            ip_header_ok <= ((ff_rx_data[7:4] == 4'd4) &&  // 时钟沿更新版本/IHL/协议是否合法
                                            (ff_rx_data[3:0] == 4'd5));  // 继续计算ip_header_ok
                            ip_prev      <= ff_rx_data;     // 时钟沿更新IP 校验和奇字节暂存
                            ip_cnt       <= 5'd1;           // 时钟沿更新IP 头字节计数 0~19
                        end                                 // 当前语句组结束
                        else if (!ff_rx_data_vld)           // 输入字节有效时更新帧解析数据通路
                            ip_cnt <= 5'd0;                      // 时钟沿更新IP 头字节计数 0~19
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_IP_PARSE: begin                           // 处理解析 IP 头阶段
                    if (ff_rx_data_vld && !ff_rx_eop) begin  // 输入字节有效时更新帧解析数据通路
                        case (ip_cnt)                       // 根据IP 头字节计数 0~19选择处理分支
                            5'd0:  ip_header_ok <= ((ff_rx_data[7:4] == 4'd4) &&  // 当前字节或字段索引对应的数据选择
                                                    (ff_rx_data[3:0] == 4'd5));  // 继续计算ip_cnt
                            5'd2:  ip_total_len_r[15:8] <= ff_rx_data;  // 当前字节或字段索引对应的数据选择
                            5'd3:  ip_total_len_r[7:0]  <= ff_rx_data;  // 当前字节或字段索引对应的数据选择
                            5'd6:  begin                    // 当前字节或字段索引对应的数据选择
                                       ip_flags_lo <= ff_rx_data[4:0];  // 时钟沿更新片偏移高 5bit
                                       ip_mf       <= ff_rx_data[5];  // 时钟沿更新MF 分片标志
                                   end                      // 当前语句组结束
                            5'd7:  ip_frag_off <= {ip_flags_lo, ff_rx_data};  // 当前字节或字段索引对应的数据选择
                            5'd9:  if (ff_rx_data != 8'h11) ip_header_ok <= 1'b0;  // 当前字节或字段索引对应的数据选择
                            default: ;                      // 未匹配有效分支时采用默认处理
                        endcase                             // 当前分支选择结束

                        // 每两个字节组成一个大端 16bit 字，累加到反码和。
                        if (!ip_cnt[0])                     // 检查IP 头字节计数 0~19的条件
                            ip_prev <= ff_rx_data;          // 时钟沿更新IP 校验和奇字节暂存
                        else begin                          // 前一条件不满足时执行本分支
                            ip_cksum <= cksum_fold;         // 每个字累加后回卷进位，避免下一字使 17 位累加器溢出
                            if (ip_cnt == 5'd19)            // 检查IP 头字节计数 0~19的条件
                                ip_cksum_ok <= cksum_now_ok;  // 时钟沿更新IP 首部校验和是否合法
                        end                                 // 当前语句组结束

                        if (ip_cnt == 5'd19)                // 检查IP 头字节计数 0~19的条件
                            ip_cnt <= 5'd0;                      // IP 头收满 20 字节
                        else                                // 采用前一条件未满足时的处理
                            ip_cnt <= ip_cnt + 5'd1;        // 时钟沿更新IP 头字节计数 0~19并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_UDP_PARSE: begin                          // 处理解析 UDP 头阶段
                    if (ff_rx_data_vld && !ff_rx_eop) begin  // 输入字节有效时更新帧解析数据通路
                        case (udp_cnt)                      // 根据UDP 头字节计数 0~7选择处理分支
                            4'd2: udp_dst_r[15:8] <= ff_rx_data;  // 当前字节或字段索引对应的数据选择
                            4'd3: udp_dst_r[7:0]  <= ff_rx_data;  // 当前字节或字段索引对应的数据选择
                            4'd4: udp_len_r[15:8] <= ff_rx_data;  // 当前字节或字段索引对应的数据选择
                            4'd5: udp_len_r[7:0]  <= ff_rx_data;  // 当前字节或字段索引对应的数据选择
                            default: ;                      // 未匹配有效分支时采用默认处理
                        endcase                             // 当前分支选择结束

                        if (udp_cnt == 4'd7) begin          // 检查UDP 头字节计数 0~7的条件
                            udp_cnt <= 4'd0;                     // UDP 头收满 8 字节
                            if (port_ok && data_len_ok && !port_wr_full)  // 检查UDP 端口过滤ta_len_ok、该槽位队列已满：本帧应丢弃并计 rx_error_count的条件
                                pay_cnt <= 16'd0;                // 只清写指针，提交仍等 S_DISPATCH
                        end                                 // 当前语句组结束
                        else                                // 采用前一条件未满足时的处理
                            udp_cnt <= udp_cnt + 4'd1;      // 时钟沿更新UDP 头字节计数 0~7并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_PAYLOAD: begin                            // 处理接收应用数据阶段
                    if (ff_rx_data_vld && !ff_rx_eop) begin  // 输入字节有效时更新帧解析数据通路
                        if (pay_cnt == data_len_w - 16'd1)  // 检查当前帧已接收应用数据字节数、应用数据长度的条件
                            pay_cnt <= 16'd0;                    // 应用数据收完，下一字节是 SN
                        else                                // 采用前一条件未满足时的处理
                            pay_cnt <= pay_cnt + 16'd1;     // 时钟沿更新当前帧已接收应用数据字节数并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_SN_RECV: begin                            // 处理取载荷末字节 SN阶段
                    if (ff_rx_data_vld)                     // 输入字节有效时更新帧解析数据通路
                        sn_r <= ff_rx_data;                      // 锁存载荷末字节 SN
                end                                         // 当前语句组结束

                S_IC_CHECK: begin                           // 处理完整性检查阶段
                    psn_write_val <= sn_r;                       // 待写回的 PSN 默认取本帧 SN
                    if (!psn_valid || sn_expect)            // 检查状态表 PSN 是否已初始化、SN 正常递增的条件
                        psn_write_en <= 1'b1;                    // 首帧或 SN 正常递增
                    else if (cross_dup) begin               // 检查跨网重复的条件
                        psn_write_en <= 1'b0;                    // 跨网副本不改 PSN
                        ic_cross_dup <= 1'b1;               // 时钟沿更新IC 判为跨网重复
                    end                                     // 当前语句组结束
                    else                                    // 采用前一条件未满足时的处理
                        psn_write_en <= sn_jump;                 // SN 跳变时虽丢弃，但需重同步 PSN
                end                                         // 当前语句组结束

                S_DISPATCH: begin                           // 处理提交帧并更新计数阶段
                    if (!port_wr_full)                      // 检查该槽位队列已满：本帧应丢弃并计 rx_error_count的条件
                        byte_left <= data_len_w;                 // 字节数在 MIB_BYTES 回放
                end                                         // 当前语句组结束

                S_MIB_BYTES: begin                          // 处理已提交帧的字节计数回放阶段
                    if (byte_left > 16'd1)                  // 检查提交帧后还需回放的字节计数的条件
                        byte_left <= byte_left - 16'd1;          // 提交帧按应用数据字节数计数
                end                                         // 当前语句组结束

                default: ;                                       // 其余状态只做状态转移
            endcase                                         // 当前分支选择结束

            state <= nxt_state;                                 // 状态寄存器只在第一段更新

            // PSN 更新：正常提交或 SN 跳变重同步时，记录当前帧的网络来源。
            if (((state == S_DISPATCH) && psn_write_en && !port_wr_full) ||  // 检查当前接收状态、提交帧并更新计数、本帧是否需要写回新 PSN的条件
                ((state == S_DROP) && psn_write_en && drop_entry)) begin  // 继续计算state
                last_net[vl_slot]       <= frame_net_r;     // 时钟沿更新对应槽位最近接受帧的网络来源
                last_net_valid[vl_slot] <= 1'b1;            // 时钟沿更新对应槽位是否已有网络来源记录
            end                                             // 当前语句组结束
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

endmodule                                                   // 模块定义结束

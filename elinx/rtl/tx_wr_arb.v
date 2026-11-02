// tx_wr_arb : 发送端口缓冲写仲裁
// 发送端口缓冲只有一个写口，应用与 SNMP / 615A / RTC 三个协议代理都要写它，
// 这层仲裁把 4 路写请求合成一路
// 仲裁策略：固定优先级 app > snmp > 615a > rtc；帧尾脉冲（frame_done）优先于数据写，
// 避免一拍的帧尾信号被别的写请求挤掉，导致该 VL 的载荷长度登记不进去
// 注：各写入方约定的字节偏移从 0 开始连续递增，帧长度按「末字节偏移 + 1」得出
module tx_wr_arb #(                                         // 声明模块及其参数接口
    parameter VL_INDEX_WIDTH    = 7,        // 发送 VL 索引位宽（最多 128 个发送 VL）
    parameter SLOT_WIDTH        = 4,        // 数据槽位位宽（16 槽 × 2KB，槽位按 VLID 低 4 位映射）
    parameter BYTE_OFFSET_WIDTH = 11,       // 字节偏移位宽
    parameter DATA_WIDTH        = 8         // 数据位宽
)(                                                          // 参数声明结束，开始端口声明
    // 时钟与复位
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 应用写请求（优先级最高） ====================
    input  wire                          app_wr_req,             // 应用写请求（写一字节）
    input  wire [VL_INDEX_WIDTH-1:0]     app_wr_vl_index,        // 应用写 VL 索引
    input  wire [BYTE_OFFSET_WIDTH-1:0]  app_wr_byte_offset,     // 应用写字节偏移
    input  wire [DATA_WIDTH-1:0]         app_wr_data,            // 应用写数据
    input  wire                          app_frame_done,         // 应用帧尾（写完一帧后的发送请求）

    // ==================== SNMP 写请求 ====================
    input  wire                          snmp_wr_req,            // SNMP 写请求
    input  wire [VL_INDEX_WIDTH-1:0]     snmp_wr_vl_index,       // SNMP 写 VL 索引（固定为其分配的 VL）
    input  wire [BYTE_OFFSET_WIDTH-1:0]  snmp_wr_byte_offset,    // SNMP 写字节偏移
    input  wire [DATA_WIDTH-1:0]         snmp_wr_data,           // SNMP 写数据
    input  wire                          snmp_frame_done,        // SNMP 帧尾（响应编码完成）

    // ==================== 615A 写请求 ====================
    input  wire                          dl_wr_req,              // 615A 写请求
    input  wire [VL_INDEX_WIDTH-1:0]     dl_wr_vl_index,         // 615A 写 VL 索引
    input  wire [BYTE_OFFSET_WIDTH-1:0]  dl_wr_byte_offset,      // 615A 写字节偏移
    input  wire [DATA_WIDTH-1:0]         dl_wr_data,             // 615A 写数据
    input  wire                          dl_frame_done,          // 615A 帧尾

    // ==================== RTC 写请求 ====================
    input  wire                          rtc_wr_req,             // RTC 写请求
    input  wire [VL_INDEX_WIDTH-1:0]     rtc_wr_vl_index,        // RTC 写 VL 索引
    input  wire [BYTE_OFFSET_WIDTH-1:0]  rtc_wr_byte_offset,     // RTC 写字节偏移
    input  wire [DATA_WIDTH-1:0]         rtc_wr_data,            // RTC 写数据
    input  wire                          rtc_frame_done,         // RTC 帧尾

    // ==================== 到发送端口缓冲的写口 ====================
    output wire                          buf_wr_en,              // 缓冲写使能
    output wire [SLOT_WIDTH-1:0]         buf_wr_vl_index,        // 缓冲写槽位号 = VL 索引低 4 位
    output wire [BYTE_OFFSET_WIDTH-1:0]  buf_wr_byte_offset,     // 缓冲写字节偏移
    output wire [DATA_WIDTH-1:0]         buf_wr_data,            // 缓冲写数据
    output wire                          buf_len_wr_en,          // 帧长度登记使能（帧尾那一拍）
    output wire [SLOT_WIDTH-1:0]         buf_len_vl_index,       // 帧长度登记的槽位号 = VL 索引低 4 位
    output wire [BYTE_OFFSET_WIDTH-1:0]  buf_len_byte_offset,    // 帧尾字节偏移（长度 = 该值 + 1）

    // ==================== 授权回执（写入方据此推进自己的字节指针） ====================
    output wire                          app_wr_gnt,             // 应用写请求已被接受（当拍有效）
    output wire                          snmp_wr_gnt,            // SNMP 写请求已被接受
    output wire                          dl_wr_gnt,              // 615A 写请求已被接受
    output wire                          rtc_wr_gnt,             // RTC 写请求已被接受

    // ==================== 槽位忙标志（来自 tx_port_buf） ====================
    input  wire [15:0]                   vl_busy                 // 每槽位忙标志：1=上一帧未发完，该槽位暂不授权写入
);                                                          // 端口声明或模块例化结束

    // ==================== 帧尾事件 FIFO ====================
    localparam FD_DEPTH = 8;                                    // 帧尾事件 FIFO 深度，4 路同拍到达也不会溢出

    reg [VL_INDEX_WIDTH-1:0]     fd_vl [0:FD_DEPTH-1];          // 帧尾事件所属 VL 索引
    reg [BYTE_OFFSET_WIDTH-1:0]  fd_off [0:FD_DEPTH-1];         // 帧尾末字节偏移
    reg [2:0]                    fd_wr_ptr;                     // 帧尾 FIFO 写指针
    reg [2:0]                    fd_rd_ptr;                     // 帧尾 FIFO 读指针
    reg [4:0]                    fd_cnt;                        // 当前帧尾事件数
    integer fd_i;                                               // 复位遍历 FIFO

    wire any_fd = app_frame_done | snmp_frame_done | dl_frame_done | rtc_frame_done; // 本拍是否有帧尾
    wire [2:0] fd_event_cnt =                               // 三位可表示四路同时到达的四个事件
        {2'b0, app_frame_done} + {2'b0, snmp_frame_done} +  // 应用与 SNMP 帧尾各占一个事件
        {2'b0, dl_frame_done}  + {2'b0, rtc_frame_done};    // 615A 与 RTC 帧尾合计最大为四
    wire fd_empty = (fd_cnt == 5'd0);                           // 帧尾 FIFO 空
    wire fd_pop   = !fd_empty;                                  // 本拍输出一个已排队帧尾

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            for (fd_i = 0; fd_i < FD_DEPTH; fd_i = fd_i + 1) begin  // 依次处理指定范围内的表项或位段
                fd_vl[fd_i]  <= {VL_INDEX_WIDTH{1'b0}};     // 时钟沿更新帧尾事件所属 VL 索引
                fd_off[fd_i] <= {BYTE_OFFSET_WIDTH{1'b0}};  // 时钟沿更新帧尾末字节偏移
            end                                             // 当前语句组结束
            fd_wr_ptr <= 3'd0;                              // 时钟沿更新帧尾 FIFO 写指针
            fd_rd_ptr <= 3'd0;                              // 时钟沿更新帧尾 FIFO 读指针
            fd_cnt    <= 5'd0;                              // 时钟沿更新当前帧尾事件数
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            // 同拍最多 4 路帧尾，按固定优先级依次入队；写指针低 3bit 自然回绕。
            if (app_frame_done) begin                       // 检查应用帧尾（写完一帧后的发送请求）的条件
                fd_vl[fd_wr_ptr]  <= app_wr_vl_index;       // 时钟沿更新帧尾事件所属 VL 索引
                fd_off[fd_wr_ptr] <= app_wr_byte_offset;    // 时钟沿更新帧尾末字节偏移
            end                                             // 当前语句组结束
            if (snmp_frame_done) begin                      // 检查SNMP 帧尾（响应编码完成）的条件
                fd_vl[fd_wr_ptr + app_frame_done]  <= snmp_wr_vl_index;  // 时钟沿更新帧尾事件所属 VL 索引
                fd_off[fd_wr_ptr + app_frame_done] <= snmp_wr_byte_offset;  // 时钟沿更新帧尾末字节偏移
            end                                             // 当前语句组结束
            if (dl_frame_done) begin                        // 检查615A 帧尾的条件
                fd_vl[fd_wr_ptr + app_frame_done + snmp_frame_done]  <= dl_wr_vl_index;  // 时钟沿更新帧尾事件所属 VL 索引
                fd_off[fd_wr_ptr + app_frame_done + snmp_frame_done] <= dl_wr_byte_offset;  // 时钟沿更新帧尾末字节偏移
            end                                             // 当前语句组结束
            if (rtc_frame_done) begin                       // 检查RTC 帧尾的条件
                fd_vl[fd_wr_ptr + app_frame_done + snmp_frame_done + dl_frame_done]  <= rtc_wr_vl_index;  // 时钟沿更新帧尾事件所属 VL 索引
                fd_off[fd_wr_ptr + app_frame_done + snmp_frame_done + dl_frame_done] <= rtc_wr_byte_offset;  // 时钟沿更新帧尾末字节偏移
            end                                             // 当前语句组结束

            fd_wr_ptr <= fd_wr_ptr + fd_event_cnt;          // 三位指针自然回绕，四事件也正确推进
            fd_rd_ptr <= fd_rd_ptr + {2'b0, fd_pop};        // 时钟沿更新帧尾 FIFO 读指针
            fd_cnt    <= fd_cnt - {4'b0, fd_pop} + {2'b0, fd_event_cnt};  // 同拍出队与四路入队合并计数
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    // 帧尾优先于数据写：FIFO 非空或本拍有新帧尾时，暂停普通数据授权。
    assign buf_len_wr_en       = !fd_empty;                     // output [0:0]
    assign buf_len_vl_index    = fd_vl[fd_rd_ptr][SLOT_WIDTH-1:0]; // output [3:0]：帧尾事件取低 4 位当槽位
    assign buf_len_byte_offset = fd_off[fd_rd_ptr];             // output [10:0]

    // ==================== 普通数据写授权 ====================
    wire [SLOT_WIDTH-1:0] app_slot  = app_wr_vl_index[SLOT_WIDTH-1:0];  // 应用目标槽位 = VL 索引低 4 位
    wire [SLOT_WIDTH-1:0] snmp_slot = snmp_wr_vl_index[SLOT_WIDTH-1:0]; // SNMP 目标槽位
    wire [SLOT_WIDTH-1:0] dl_slot   = dl_wr_vl_index[SLOT_WIDTH-1:0];   // 615A 目标槽位
    wire [SLOT_WIDTH-1:0] rtc_slot  = rtc_wr_vl_index[SLOT_WIDTH-1:0];  // RTC 目标槽位
    wire app_ok  = !vl_busy[app_slot];                          // 应用目标槽位空闲
    wire snmp_ok = !vl_busy[snmp_slot];                         // SNMP 目标槽位空闲
    wire dl_ok   = !vl_busy[dl_slot];                           // 615A 目标槽位空闲
    wire rtc_ok  = !vl_busy[rtc_slot];                          // RTC 目标槽位空闲
    wire grant_ok = fd_empty;                                   // 已排队帧尾优先；当拍帧尾与末字节写可同拍收下

    wire app_gnt  = grant_ok && app_ok  && app_wr_req;          // 应用写授权
    wire snmp_gnt = grant_ok && !app_gnt && snmp_ok && snmp_wr_req; // SNMP 写授权
    wire dl_gnt   = grant_ok && !app_gnt && !snmp_gnt && dl_ok && dl_wr_req; // 615A 写授权
    wire rtc_gnt  = grant_ok && !app_gnt && !snmp_gnt && !dl_gnt && rtc_ok && rtc_wr_req; // RTC 写授权

    assign buf_wr_en          = app_gnt | snmp_gnt | dl_gnt | rtc_gnt; // output [0:0]
    assign buf_wr_vl_index    = app_gnt ? app_slot :         // 设置或组合计算缓冲写槽位号
                                snmp_gnt ? snmp_slot :      // 继续计算 buf_wr_vl_index
                                dl_gnt ? dl_slot : rtc_slot; // output [3:0]
    assign buf_wr_byte_offset = app_gnt ? app_wr_byte_offset :  // 设置或组合计算缓冲写字节偏移
                                snmp_gnt ? snmp_wr_byte_offset :  // 继续计算buf_wr_byte_offset
                                dl_gnt ? dl_wr_byte_offset : rtc_wr_byte_offset; // output [10:0]
    assign buf_wr_data        = app_gnt ? app_wr_data :     // 设置或组合计算缓冲写数据
                                snmp_gnt ? snmp_wr_data :   // 继续计算buf_wr_data
                                dl_gnt ? dl_wr_data : rtc_wr_data; // output [7:0]

    assign app_wr_gnt         = app_gnt;                       // output [0:0]
    assign snmp_wr_gnt        = snmp_gnt;                      // output [0:0]
    assign dl_wr_gnt          = dl_gnt;                        // output [0:0]
    assign rtc_wr_gnt         = rtc_gnt;                       // output [0:0]

endmodule                                                   // 模块定义结束

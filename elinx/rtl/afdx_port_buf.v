// afdx_port_buf : 输入输出缓冲模块
// 把收发两个端口缓冲与两个仲裁器收在一起，顶层只挂这一个模块：
// rx_port_buf   接收端口缓冲（32768 × 8）
// tx_port_buf   发送端口缓冲（32768 × 8）+ 每 VL 帧长度寄存器
// rx_rd_arb     接收读口仲裁：应用 / SNMP / 615A / RTC（固定优先级）
// tx_wr_arb     发送写口仲裁：应用 / SNMP / 615A / RTC（帧尾优先）
// 三个协议代理的 VL 索引由参数给出，模块内部直接用，不再往上引端口
module afdx_port_buf #(                                     // 声明模块及其参数接口
    parameter DATA_WIDTH        = 8,        // 数据位宽
    parameter VL_INDEX_WIDTH    = 4,        // VL 索引位宽
    parameter BYTE_OFFSET_WIDTH = 11,       // 字节偏移位宽（2KB/VL）
    parameter VL_IND_WIDTH      = 7,        // 逻辑发送 VL 索引位宽（最多 128 个发送 VL）
    parameter VL_INDEX_SNMP     = 4'd1,     // SNMP 代理占用的 VL 索引
    parameter VL_INDEX_615A     = 4'd2,     // 615A 代理占用的 VL 索引
    parameter VL_INDEX_RTC      = 4'd3      // RTC 代理占用的 VL 索引
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 接收缓冲写侧（RX 状态机） ====================
    input  wire                          rx_wr_en,               // 接收缓冲写使能
    input  wire [VL_INDEX_WIDTH-1:0]     rx_wr_vl_index,         // 接收缓冲写槽位号 = vlid 低位
    input  wire [BYTE_OFFSET_WIDTH-1:0]  rx_wr_byte_offset,      // 接收缓冲写字节偏移（帧内，从 0 递增）
    input  wire [DATA_WIDTH-1:0]         rx_wr_data,             // 接收缓冲写数据
    input  wire                          rx_wr_frame_done,       // 帧尾脉冲：提交本帧（登记长度/入队）
    input  wire [15:0]                   rx_wr_frame_len,        // 本帧数据长度（与帧尾同拍）
    input  wire                          rx_wr_queue_mode,       // 0=采样端口（覆盖） 1=队列/SAP 端口（入队）
    output wire                          rx_wr_full,             // 该槽位队列已满：RX 应丢弃新帧并计错

    // ==================== 接收缓冲读请求（应用） ====================
    input  wire                          app_rd_req,             // 应用读请求
    input  wire [VL_INDEX_WIDTH-1:0]     app_rd_vl_index,        // 应用读 VL 索引
    input  wire [BYTE_OFFSET_WIDTH-1:0]  app_rd_byte_offset,     // 应用读字节偏移
    output wire                          app_rd_valid,           // 应用读数据有效

    // ==================== 接收缓冲读请求（SNMP / 615A / RTC） ====================
    input  wire                          snmp_rd_req,            // SNMP 读请求
    input  wire [BYTE_OFFSET_WIDTH-1:0]  snmp_rd_byte_offset,    // SNMP 读字节偏移
    output wire                          snmp_rd_valid,          // SNMP 读数据有效
    input  wire                          dl_rd_req,              // 615A 读请求
    input  wire [BYTE_OFFSET_WIDTH-1:0]  dl_rd_byte_offset,      // 615A 读字节偏移
    output wire                          dl_rd_valid,            // 615A 读数据有效
    input  wire                          rtc_rd_req,             // RTC 读请求
    input  wire [BYTE_OFFSET_WIDTH-1:0]  rtc_rd_byte_offset,     // RTC 读字节偏移
    output wire                          rtc_rd_valid,           // RTC 读数据有效

    // ==================== 接收缓冲读数据（仲裁后共享） ====================
    output wire [DATA_WIDTH-1:0]         rx_rd_data,             // 接收缓冲读数据，与对应的 *_rd_valid 同拍

    // ==================== 接收缓冲读状态（按各消费者自己的槽位号切片） ====================
    output wire [15:0]                   app_rd_frame_len,       // 应用槽位当前待读帧长度
    output wire [3:0]                    app_rd_frame_cnt,       // 应用槽位待读帧数（0=无数据）
    output wire [15:0]                   snmp_rd_frame_len,      // SNMP 槽位当前待读帧长度
    output wire [3:0]                    snmp_rd_frame_cnt,      // SNMP 槽位待读帧数
    output wire [15:0]                   dl_rd_frame_len,        // 615A 槽位当前待读帧长度
    output wire [3:0]                    dl_rd_frame_cnt,        // 615A 槽位待读帧数
    output wire [15:0]                   rtc_rd_frame_len,       // RTC 槽位当前待读帧长度
    output wire [3:0]                    rtc_rd_frame_cnt,       // RTC 槽位待读帧数

    // ==================== 发送缓冲写请求（应用） ====================
    input  wire                          app_wr_req,             // 应用写请求（写一字节）
    input  wire [VL_IND_WIDTH-1:0]       app_wr_vl_index,        // 应用写 VL 索引（7 位，最多 128 个发送 VL）
    input  wire [BYTE_OFFSET_WIDTH-1:0]  app_wr_byte_offset,     // 应用写字节偏移（从 0 连续递增）
    input  wire [DATA_WIDTH-1:0]         app_wr_data,            // 应用写数据
    input  wire                          app_frame_done,         // 应用帧尾（写完一帧的发送请求）

    // ==================== 发送缓冲写请求（SNMP / 615A / RTC） ====================
    input  wire                          snmp_wr_req,            // SNMP 写请求
    input  wire [BYTE_OFFSET_WIDTH-1:0]  snmp_wr_byte_offset,    // SNMP 写字节偏移
    input  wire [DATA_WIDTH-1:0]         snmp_wr_data,           // SNMP 写数据
    input  wire                          snmp_frame_done,        // SNMP 帧尾
    input  wire                          dl_wr_req,              // 615A 写请求
    input  wire [BYTE_OFFSET_WIDTH-1:0]  dl_wr_byte_offset,      // 615A 写字节偏移
    input  wire [DATA_WIDTH-1:0]         dl_wr_data,             // 615A 写数据
    input  wire                          dl_frame_done,          // 615A 帧尾
    input  wire                          rtc_wr_req,             // RTC 写请求
    input  wire [BYTE_OFFSET_WIDTH-1:0]  rtc_wr_byte_offset,     // RTC 写字节偏移
    input  wire [DATA_WIDTH-1:0]         rtc_wr_data,            // RTC 写数据
    input  wire                          rtc_frame_done,         // RTC 帧尾

    // ==================== 发送缓冲读侧（TX 状态机） ====================
    input  wire                          tx_rd_en,               // 发送缓冲读使能
    input  wire [VL_INDEX_WIDTH-1:0]     tx_rd_vl_index,         // 发送缓冲读 VL 索引
    input  wire [BYTE_OFFSET_WIDTH-1:0]  tx_rd_byte_offset,      // 发送缓冲读字节偏移
    output wire [DATA_WIDTH-1:0]         tx_rd_data,             // 发送缓冲读数据
    output wire                          tx_rd_valid,            // 发送缓冲读数据有效
    input  wire [15:0]                   tx_payload_len,         // 该 VL 待发载荷长度（字节）
    input  wire [15:0]                   abort_vl,               // 每槽位撤销：1=丢弃该槽位待发帧（清忙标志与长度）

    // ==================== 发送写授权的回执（给应用与三个代理） ====================
    output wire                          app_wr_gnt,             // 应用写请求已被接受
    output wire                          snmp_wr_gnt,            // SNMP 写请求已被接受
    output wire                          dl_wr_gnt,              // 615A 写请求已被接受
    output wire                          rtc_wr_gnt              // RTC 写请求已被接受
);                                                          // 端口声明或模块例化结束

    wire                      rx_buf_rd_en;                     // 接收缓冲读使能（仲裁输出）
    wire [VL_INDEX_WIDTH-1:0] rx_buf_rd_vl_index;               // 接收缓冲读 VL 索引
    wire [BYTE_OFFSET_WIDTH-1:0] rx_buf_rd_byte_offset;         // 接收缓冲读字节偏移
    wire [DATA_WIDTH-1:0]     rx_buf_rd_data;                   // 接收缓冲读数据

    wire                      tx_buf_wr_en;                     // 发送缓冲写使能（仲裁输出）
    wire [VL_INDEX_WIDTH-1:0] tx_buf_wr_vl_index;               // 发送缓冲写 VL 索引
    wire [BYTE_OFFSET_WIDTH-1:0] tx_buf_wr_byte_offset;         // 发送缓冲写字节偏移
    wire [DATA_WIDTH-1:0]     tx_buf_wr_data;                   // 发送缓冲写数据
    wire                      tx_buf_len_wr_en;                 // 帧长度登记使能
    wire [VL_INDEX_WIDTH-1:0] tx_buf_len_vl_index;              // 长度登记 VL 索引
    wire [BYTE_OFFSET_WIDTH-1:0] tx_buf_len_byte_offset;        // 长度登记末字节偏移

    wire [(1<<VL_INDEX_WIDTH)*16-1:0] rx_frame_len_all;         // 每槽位待读帧长（接收缓冲输出）
    wire [(1<<VL_INDEX_WIDTH)*4-1:0]  rx_frame_cnt_all;         // 每槽位待读帧数（接收缓冲输出）

    wire [15:0]               tx_buf_vl_busy;                   // 每槽位忙标志（发送缓冲输出）

    // ==================== 接收端口缓冲例化 ====================
    rx_port_buf #(                                          // 例化子模块并连接数据通路
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             // 连接子模块对应端口
        .FRAME_LEN_WIDTH   (16),                            // 连接子模块对应端口
        .FRAME_CNT_WIDTH   (3)                              // 连接子模块对应端口
    ) u_rx_port_buf (                                       // 参数绑定结束，开始连接实例端口
        .clk           (clk),                                  // input  [0:0]
        .rst_b         (rst_b),                                // input  [0:0]
        .wr_en         (rx_wr_en),                             // input  [0:0]
        .wr_vl_index   (rx_wr_vl_index),                       // input  [3:0]
        .wr_byte_offset(rx_wr_byte_offset),                    // input  [10:0]
        .wr_data       (rx_wr_data),                           // input  [7:0]
        .wr_frame_done (rx_wr_frame_done),                     // input  [0:0]
        .wr_frame_len  (rx_wr_frame_len),                      // input  [15:0]
        .wr_queue_mode (rx_wr_queue_mode),                     // input  [0:0]
        .wr_full       (rx_wr_full),                           // output [0:0]
        .rd_en         (rx_buf_rd_en),                         // input  [0:0]
        .rd_vl_index   (rx_buf_rd_vl_index),                   // input  [3:0]
        .rd_byte_offset(rx_buf_rd_byte_offset),                // input  [10:0]
        .rd_data       (rx_buf_rd_data),                       // output [7:0]
        .rd_valid      (),                                     // output [0:0]  读有效由仲裁器按授权产生
        .rd_frame_len_all(rx_frame_len_all),                   // output [255:0]
        .rd_frame_cnt_all(rx_frame_cnt_all)                    // output [63:0]
    );                                                      // 端口声明或模块例化结束

    // 按槽位号切片：代理的槽位号是参数（常量选择）；应用读的是动态槽位（可变基址的索引位选，2001 合法）
    assign app_rd_frame_len  = rx_frame_len_all[{app_rd_vl_index, 4'b0} +: 16];      // 应用当前读槽位帧长
    assign app_rd_frame_cnt  = rx_frame_cnt_all[{app_rd_vl_index, 2'b0} +: 4];       // 应用当前读槽位帧数
    assign snmp_rd_frame_len = rx_frame_len_all[VL_INDEX_SNMP*16 +: 16];             // SNMP 槽位帧长
    assign snmp_rd_frame_cnt = rx_frame_cnt_all[VL_INDEX_SNMP*4  +: 4];              // SNMP 槽位帧数
    assign dl_rd_frame_len   = rx_frame_len_all[VL_INDEX_615A*16 +: 16];             // 615A 槽位帧长
    assign dl_rd_frame_cnt   = rx_frame_cnt_all[VL_INDEX_615A*4  +: 4];              // 615A 槽位帧数
    assign rtc_rd_frame_len  = rx_frame_len_all[VL_INDEX_RTC *16 +: 16];             // RTC 槽位帧长
    assign rtc_rd_frame_cnt  = rx_frame_cnt_all[VL_INDEX_RTC *4  +: 4];              // RTC 槽位帧数

    // ==================== 接收缓冲读仲裁例化 ====================
    rx_rd_arb #(                                            // 例化子模块并连接数据通路
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH)              // 连接子模块对应端口
    ) u_rx_rd_arb (                                         // 参数绑定结束，开始连接实例端口
        .clk               (clk),                              // input  [0:0]
        .rst_b             (rst_b),                            // input  [0:0]
        .app_rd_req        (app_rd_req),                       // input  [0:0]
        .app_rd_vl_index   (app_rd_vl_index),                  // input  [3:0]
        .app_rd_byte_offset(app_rd_byte_offset),               // input  [10:0]
        .app_rd_valid      (app_rd_valid),                     // output [0:0]
        .snmp_rd_req       (snmp_rd_req),                      // input  [0:0]
        .snmp_rd_vl_index  (VL_INDEX_SNMP),                    // input  [3:0]
        .snmp_rd_byte_offset(snmp_rd_byte_offset),             // input  [10:0]
        .snmp_rd_valid     (snmp_rd_valid),                    // output [0:0]
        .dl_rd_req         (dl_rd_req),                        // input  [0:0]
        .dl_rd_vl_index    (VL_INDEX_615A),                    // input  [3:0]
        .dl_rd_byte_offset (dl_rd_byte_offset),                // input  [10:0]
        .dl_rd_valid       (dl_rd_valid),                      // output [0:0]
        .rtc_rd_req        (rtc_rd_req),                       // input  [0:0]
        .rtc_rd_vl_index   (VL_INDEX_RTC),                     // input  [3:0]
        .rtc_rd_byte_offset(rtc_rd_byte_offset),               // input  [10:0]
        .rtc_rd_valid      (rtc_rd_valid),                     // output [0:0]
        .buf_rd_en         (rx_buf_rd_en),                     // output [0:0]
        .buf_rd_vl_index   (rx_buf_rd_vl_index),               // output [3:0]
        .buf_rd_byte_offset(rx_buf_rd_byte_offset),            // output [10:0]
        .buf_rd_data       (rx_buf_rd_data),                   // input  [7:0]
        .rd_data           (rx_rd_data)                        // output [7:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== 发送端口缓冲例化 ====================
    tx_port_buf #(                                          // 例化子模块并连接数据通路
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH)              // 连接子模块对应端口
    ) u_tx_port_buf (                                       // 参数绑定结束，开始连接实例端口
        .clk               (clk),                              // input  [0:0]
        .rst_b             (rst_b),                            // input  [0:0]
        .wr_en             (tx_buf_wr_en),                     // input  [0:0]
        .wr_vl_index       (tx_buf_wr_vl_index),               // input  [3:0]
        .wr_byte_offset    (tx_buf_wr_byte_offset),            // input  [10:0]
        .wr_data           (tx_buf_wr_data),                   // input  [7:0]
        .len_wr_en         (tx_buf_len_wr_en),                 // input  [0:0]
        .len_vl_index      (tx_buf_len_vl_index),              // input  [3:0]
        .len_byte_offset   (tx_buf_len_byte_offset),           // input  [10:0]
        .rd_en             (tx_rd_en),                         // input  [0:0]
        .rd_vl_index       (tx_rd_vl_index),                   // input  [3:0]
        .rd_byte_offset    (tx_rd_byte_offset),                // input  [10:0]
        .rd_data           (tx_rd_data),                       // output [7:0]
        .rd_valid          (tx_rd_valid),                      // output [0:0]
        .payload_len       (tx_payload_len),                   // output [15:0]
        .vl_busy           (tx_buf_vl_busy),                    // output [15:0]
        .abort_vl          (abort_vl)                           // input  [15:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== 发送缓冲写仲裁例化 ====================
    tx_wr_arb #(                                            // 例化子模块并连接数据通路
        .VL_INDEX_WIDTH    (VL_IND_WIDTH),                  // 发送 VL 索引位宽（7）
        .SLOT_WIDTH        (VL_INDEX_WIDTH),                // 数据槽位位宽（4）
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             // 连接子模块对应端口
        .DATA_WIDTH        (DATA_WIDTH)                     // 连接子模块对应端口
    ) u_tx_wr_arb (                                         // 参数绑定结束，开始连接实例端口
        .clk                  (clk),                           // input  [0:0]
        .rst_b                (rst_b),                         // input  [0:0]
        .app_wr_req           (app_wr_req),                    // input  [0:0]
        .app_wr_vl_index      (app_wr_vl_index),               // input  [6:0]
        .app_wr_byte_offset   (app_wr_byte_offset),            // input  [10:0]
        .app_wr_data          (app_wr_data),                   // input  [7:0]
        .app_frame_done       (app_frame_done),                // input  [0:0]
        .snmp_wr_req          (snmp_wr_req),                   // input  [0:0]
        .snmp_wr_vl_index     ({{(VL_IND_WIDTH-4){1'b0}}, VL_INDEX_SNMP}), // input  [6:0]：代理槽位号高位补零
        .snmp_wr_byte_offset  (snmp_wr_byte_offset),           // input  [10:0]
        .snmp_wr_data         (snmp_wr_data),                  // input  [7:0]
        .snmp_frame_done      (snmp_frame_done),               // input  [0:0]
        .dl_wr_req            (dl_wr_req),                     // input  [0:0]
        .dl_wr_vl_index       ({{(VL_IND_WIDTH-4){1'b0}}, VL_INDEX_615A}), // input  [6:0]：代理槽位号高位补零
        .dl_wr_byte_offset    (dl_wr_byte_offset),             // input  [10:0]
        .dl_wr_data           (dl_wr_data),                    // input  [7:0]
        .dl_frame_done        (dl_frame_done),                 // input  [0:0]
        .rtc_wr_req           (rtc_wr_req),                    // input  [0:0]
        .rtc_wr_vl_index      ({{(VL_IND_WIDTH-4){1'b0}}, VL_INDEX_RTC}),  // input  [6:0]：代理槽位号高位补零
        .rtc_wr_byte_offset   (rtc_wr_byte_offset),            // input  [10:0]
        .rtc_wr_data          (rtc_wr_data),                   // input  [7:0]
        .rtc_frame_done       (rtc_frame_done),                // input  [0:0]
        .buf_wr_en            (tx_buf_wr_en),                  // output [0:0]
        .buf_wr_vl_index      (tx_buf_wr_vl_index),            // output [3:0]
        .buf_wr_byte_offset   (tx_buf_wr_byte_offset),         // output [10:0]
        .buf_wr_data          (tx_buf_wr_data),                // output [7:0]
        .buf_len_wr_en        (tx_buf_len_wr_en),              // output [0:0]
        .buf_len_vl_index     (tx_buf_len_vl_index),           // output [3:0]
        .buf_len_byte_offset  (tx_buf_len_byte_offset),        // output [10:0]
        .app_wr_gnt           (app_wr_gnt),                    // output [0:0]
        .snmp_wr_gnt          (snmp_wr_gnt),                   // output [0:0]
        .dl_wr_gnt            (dl_wr_gnt),                     // output [0:0]
        .rtc_wr_gnt           (rtc_wr_gnt),                    // output [0:0]
        .vl_busy              (tx_buf_vl_busy)                 // input  [15:0]
    );                                                      // 端口声明或模块例化结束

endmodule                                                   // 模块定义结束

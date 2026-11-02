// rtc_sync : ARINC 664 时钟同步
// 从同步端口提取主时钟时间戳与链路延迟，做延迟补偿后校正本地 RTC；
// 作为主时钟时按周期把本地时间戳经发送端口广播出去
// 接收读请求经 rx_rd_arb 仲裁，同步报文经 tx_wr_arb 写入发送端口缓冲
// 注：本代理固定在 VL_INDEX_SELF 这条 VL 上收发（设计期分配）
module rtc_sync #(                                          // 声明模块及其参数接口
    parameter DATA_WIDTH        = 8,        // 数据位宽
    parameter VL_INDEX_WIDTH    = 4,        // VL 索引位宽
    parameter BYTE_OFFSET_WIDTH = 11,       // 字节偏移位宽
    parameter RTC_WIDTH         = 48,       // RTC 计数器位宽
    parameter CNT_WIDTH         = 32,       // MIB 计数器位宽
    parameter VL_INDEX_SELF     = 4'd3      // 本代理占用的 VL 索引（设计期分配）
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 接收侧（经 rx_rd_arb 访问接收端口缓冲） ====================
    input  wire                          rx_ready_rtc,           // 本 VL 一帧接收完成（来自 RX 状态机）
    output wire                          rx_rd_req,              // 读请求，送 rx_rd_arb 仲裁
    output wire [BYTE_OFFSET_WIDTH-1:0]  rx_rd_byte_offset,      // 读字节偏移（提取进度）
    input  wire [DATA_WIDTH-1:0]         rx_rd_data,             // 读数据
    input  wire                          rx_rd_valid,            // 读数据有效（被仲裁授权后拉高）
    input  wire [15:0]                   rx_frame_len,           // 本槽位当前待读帧长度（来自接收缓冲）

    // ==================== 发送侧（经 tx_wr_arb 写入发送端口缓冲） ====================
    output wire                          tx_wr_en,               // 写使能（同步报文一字节）
    output wire [BYTE_OFFSET_WIDTH-1:0]  tx_wr_byte_offset,      // 写字节偏移
    output wire [DATA_WIDTH-1:0]         tx_wr_data,             // 写数据
    output wire                          tx_frame_done,          // 帧尾脉冲：登记长度并请求 TX 发送
    input  wire                          tx_wr_gnt,              // 写请求已被 tx_wr_arb 接受的当拍回执

    // ==================== RTC 状态与配置 ====================
    output wire [RTC_WIDTH-1:0]          local_rtc,              // 本地 RTC 当前值（同时作为 TX 的 BAG 时间基准）
    output wire                          rtc_sync_valid,         // 一次同步校正完成
    input  wire                          master_mode,            // 1=主时钟（主动广播），0=从时钟
    input  wire [15:0]                   sync_period_ms,         // 主时钟广播周期（ms）
    input  wire [31:0]                   rx_process_delay        // 接收处理延迟（ns），用于延迟补偿
);                                                          // 端口声明或模块例化结束

    wire [RTC_WIDTH-1:0] master_ts;                             // 从同步报文提取的主时钟时间戳
    wire [31:0]          delay_val;                             // 同步报文携带的链路延迟计数值
    wire                 rtc_rx_valid;                          // 时间戳提取完成
    wire [RTC_WIDTH-1:0] corrected_ts;                          // 延迟补偿后的时间戳
    wire                 calc_done;                             // 补偿计算完成
    wire [RTC_WIDTH-1:0] rtc_value;                             // 本地 RTC 当前值
    wire                 rtc_tick;                              // 同步节拍脉冲（每 sync_period_ms 一拍）

    // ==================== 本地 RTC 例化 ====================
    local_rtc #(                                            // 例化子模块并连接数据通路
        .RTC_WIDTH (RTC_WIDTH)                              // 连接子模块对应端口
    ) u_local_rtc (                                         // 参数绑定结束，开始连接实例端口
        .clk         (clk),                                     // input  [0:0]
        .rst_b       (rst_b),                                   // input  [0:0]
        .sync_en     (calc_done),                               // input  [0:0]
        .sync_value  (corrected_ts),                            // input  [47:0]
        .sync_period_ms(sync_period_ms),                        // input  [15:0] 同步节拍周期
        .rtc_value   (rtc_value),                               // output [47:0]
        .rtc_tick    (rtc_tick)                                 // output [0:0]
    );                                                      // 端口声明或模块例化结束
    assign local_rtc = rtc_value;                               // output [47:0]：本地 RTC 值引出

    // ==================== 同步报文接收例化 ====================
    // 帧尾脉冲与接收缓冲长度 FIFO 的写入同拍，rx_frame_len 要到下一拍才给出完整帧长，
    // 因此把 start 打一拍再送 rtc_rx：否则 rtc_rx 在帧尾那一拍读到长度 0，整帧被当作截断报文丢弃
    reg rx_ready_d;                                             // 接收完成打一拍，与帧长可见同拍
    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) rx_ready_d <= 1'b0;                     // 检查复位或正常运行条件
        else        rx_ready_d <= rx_ready_rtc;             // 采用前一条件未满足时的处理
    end                                                     // 当前语句组结束

    rtc_rx #(                                               // 例化子模块并连接数据通路
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .RTC_WIDTH         (RTC_WIDTH),                     // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH)              // 连接子模块对应端口
    ) u_rtc_rx (                                            // 参数绑定结束，开始连接实例端口
        .clk               (clk),                               // input  [0:0]
        .rst_b             (rst_b),                             // input  [0:0]
        .start             (rx_ready_d),                        // input  [0:0]  一帧到达触发提取
        .rx_frame_len      (rx_frame_len),                      // input  [15:0] 当前报文长度
        .rx_rd_req         (rx_rd_req),                         // output [0:0]
        .rx_rd_byte_offset (rx_rd_byte_offset),                 // output [10:0]
        .rx_rd_data        (rx_rd_data),                        // input  [7:0]
        .rx_rd_valid       (rx_rd_valid),                       // input  [0:0]
        .master_ts         (master_ts),                         // output [47:0]
        .delay_val         (delay_val),                         // output [31:0]
        .rx_valid          (rtc_rx_valid)                       // output [0:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== 延迟补偿例化 ====================
    delay_comp #(                                           // 例化子模块并连接数据通路
        .RTC_WIDTH (RTC_WIDTH)                              // 连接子模块对应端口
    ) u_delay_comp (                                        // 参数绑定结束，开始连接实例端口
        .clk              (clk),                                // input  [0:0]
        .rst_b            (rst_b),                              // input  [0:0]
        .master_ts        (master_ts),                          // input  [47:0]
        .delay_val        (delay_val),                          // input  [31:0]
        .rx_process_delay (rx_process_delay),                   // input  [31:0]
        .calc_req         (rtc_rx_valid),                       // input  [0:0]
        .corrected_ts     (corrected_ts),                       // output [47:0]
        .calc_done        (calc_done)                           // output [0:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== 同步报文发送例化 ====================
    rtc_tx #(                                               // 例化子模块并连接数据通路
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .RTC_WIDTH         (RTC_WIDTH),                     // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH)              // 连接子模块对应端口
    ) u_rtc_tx (                                            // 参数绑定结束，开始连接实例端口
        .clk               (clk),                               // input  [0:0]
        .rst_b             (rst_b),                             // input  [0:0]
        .tx_req            (master_mode & rtc_tick),            // input  [0:0]  仅主时钟按节拍发送
        .local_ts          (rtc_value),                         // input  [47:0]
        .tx_wr_gnt         (tx_wr_gnt),                         // input  [0:0]  写授权回执
        .tx_wr_en          (tx_wr_en),                          // output [0:0]
        .tx_wr_byte_offset (tx_wr_byte_offset),                 // output [10:0]
        .tx_wr_data        (tx_wr_data),                        // output [7:0]
        .tx_frame_done     (tx_frame_done)                      // output [0:0]
    );                                                      // 端口声明或模块例化结束

    assign rtc_sync_valid = calc_done;                          // output [0:0]：一次校正完成

endmodule                                                   // 模块定义结束

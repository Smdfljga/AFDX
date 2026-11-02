// snmp_agent : SNMP 代理
// 接收 SNMP 请求报文 → 解出 OID → 查 MIB 计数 → 编码响应 → 写入发送端口缓冲并请求发送
// 接收读请求经 rx_rd_arb 仲裁后访问接收端口缓冲，MIB 通过专用读口查询
// 注：本代理固定在 VL_INDEX_SELF 这条 VL 上收发（设计期分配）
module snmp_agent #(                                        // 声明模块及其参数接口
    parameter DATA_WIDTH        = 8,        // 数据位宽
    parameter VL_INDEX_WIDTH    = 4,        // VL 索引位宽
    parameter BYTE_OFFSET_WIDTH = 11,       // 字节偏移位宽
    parameter CNT_WIDTH         = 32,       // MIB 计数器位宽
    parameter VL_ADDR_WIDTH     = 12,       // VL 表地址位宽（与配置表同索引）
    parameter OID_WIDTH         = 16,       // 内部对象索引位宽（1 位表选 + VL_ADDR_WIDTH + 3 位计数选）
    parameter VL_INDEX_SELF     = 4'd1      // 本代理占用的 VL 索引（设计期分配）
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 接收侧（经 rx_rd_arb 访问接收端口缓冲） ====================
    input  wire                          rx_ready_snmp,          // 本 VL 一帧接收完成（来自 RX 状态机）
    output wire                          rx_rd_req,              // 读请求，送 rx_rd_arb 仲裁
    output wire [BYTE_OFFSET_WIDTH-1:0]  rx_rd_byte_offset,      // 读字节偏移（请求报文的字节位置）
    input  wire [DATA_WIDTH-1:0]         rx_rd_data,             // 读数据
    input  wire                          rx_rd_valid,            // 读数据有效（被仲裁授权后拉高）
    input  wire [15:0]                   rx_frame_len,           // 本槽位当前待读帧长度（来自接收缓冲）

    // ==================== 发送侧（经 tx_wr_arb 写入发送端口缓冲） ====================
    output wire                          tx_wr_en,               // 写使能（响应报文一字节）
    output wire [BYTE_OFFSET_WIDTH-1:0]  tx_wr_byte_offset,      // 写字节偏移
    output wire [DATA_WIDTH-1:0]         tx_wr_data,             // 写数据
    output wire                          tx_frame_done,          // 帧尾脉冲：登记长度并请求 TX 发送
    input  wire                          tx_wr_gnt,              // 写请求已被 tx_wr_arb 接受的当拍回执

    // ==================== MIB 读口（接 mib_ram 读口） ====================
    output wire                          mib_sel,                // 0=读 RX 计数表 1=读 TX 计数表
    output wire [VL_ADDR_WIDTH-1:0]      mib_addr,               // 要查询的 VL 条目索引
    output wire                          mib_rd_en,              // MIB 读使能
    input  wire [5*CNT_WIDTH-1:0]        mib_rd_data             // MIB 读回的 5 个计数器
);                                                          // 端口声明或模块例化结束

    wire         pdu_valid;                                     // PDU 关键字段解析完成
    wire [1:0]   pdu_type;                                      // PDU 类型（GET/GETNEXT/SET...）
    wire [OID_WIDTH-1:0] oid;                                   // 请求的目标对象索引
    wire         decode_done;                                   // 解码完成
    wire         query_done;                                    // MIB 查询完成
    wire [CNT_WIDTH-1:0] query_value;                           // 查询到的计数值
    wire         enc_done;                                      // 响应编码完成

    // ==================== SNMP 请求解码例化 ====================
    snmp_decoder #(                                         // 例化子模块并连接数据通路
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             // 连接子模块对应端口
        .OID_WIDTH         (OID_WIDTH)                      // 连接子模块对应端口
    ) u_snmp_decoder (                                      // 参数绑定结束，开始连接实例端口
        .clk               (clk),                               // input  [0:0]
        .rst_b             (rst_b),                             // input  [0:0]
        .start             (rx_ready_snmp),                     // input  [0:0]  一帧到达触发解码
        .rx_frame_len      (rx_frame_len),                      // input  [15:0] 当前报文长度
        .rx_rd_req         (rx_rd_req),                         // output [0:0]
        .rx_rd_byte_offset (rx_rd_byte_offset),                 // output [10:0]
        .rx_rd_valid       (rx_rd_valid),                       // input  [0:0]
        .rx_rd_data        (rx_rd_data),                        // input  [7:0]
        .pdu_valid         (pdu_valid),                         // output [0:0]
        .pdu_type          (pdu_type),                          // output [1:0]
        .oid               (oid),                               // output [15:0]
        .decode_done       (decode_done)                        // output [0:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== MIB 查询例化 ====================
    mib_query #(                                            // 例化子模块并连接数据通路
        .CNT_WIDTH     (CNT_WIDTH),                         // 连接子模块对应端口
        .VL_ADDR_WIDTH (VL_ADDR_WIDTH),                     // 连接子模块对应端口
        .OID_WIDTH     (OID_WIDTH)                          // 连接子模块对应端口
    ) u_mib_query (                                         // 参数绑定结束，开始连接实例端口
        .clk         (clk),                                     // input  [0:0]
        .rst_b       (rst_b),                                   // input  [0:0]
        .query_req   (pdu_valid),                               // input  [0:0]
        .oid         (oid),                                     // input  [15:0]
        .mib_sel     (mib_sel),                                 // output [0:0]
        .mib_addr    (mib_addr),                                // output [11:0]
        .mib_rd_en   (mib_rd_en),                               // output [0:0]
        .mib_rd_data (mib_rd_data),                             // input  [159:0]
        .query_done  (query_done),                              // output [0:0]
        .query_value (query_value)                              // output [31:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== SNMP 响应编码例化 ====================
    snmp_encoder #(                                         // 例化子模块并连接数据通路
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             // 连接子模块对应端口
        .OID_WIDTH         (OID_WIDTH)                      // 连接子模块对应端口
    ) u_snmp_encoder (                                      // 参数绑定结束，开始连接实例端口
        .clk               (clk),                               // input  [0:0]
        .rst_b             (rst_b),                             // input  [0:0]
        .enc_req           (query_done),                        // input  [0:0]
        .oid         (oid),                                     // input  [15:0]
        .value             (query_value),                       // input  [31:0]
        .tx_wr_gnt         (tx_wr_gnt),                         // input  [0:0]  写授权回执
        .tx_wr_en          (tx_wr_en),                          // output [0:0]
        .tx_wr_byte_offset (tx_wr_byte_offset),                 // output [10:0]
        .tx_wr_data        (tx_wr_data),                        // output [7:0]
        .enc_done          (enc_done)                           // output [0:0]
    );                                                      // 端口声明或模块例化结束

    // 帧尾脉冲直接来自编码完成：写完整帧后登记长度并触发发送
    assign tx_frame_done = enc_done;                            // output [0:0]

endmodule                                                   // 模块定义结束

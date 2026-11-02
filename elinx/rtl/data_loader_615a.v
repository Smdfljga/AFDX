// data_loader_615a : ARINC 615A 数据加载代理
// TFTP 解析 → 文件缓冲 → Flash 写入 → 文件表登记，并把 TFTP 应答报文发回
// 接收读请求经 rx_rd_arb 仲裁，应答报文经 tx_wr_arb 写入发送端口缓冲
// 注：本代理固定在 VL_INDEX_SELF 这条 VL 上收发（设计期分配）
module data_loader_615a #(                                  // 声明模块及其参数接口
    parameter DATA_WIDTH        = 8,        // 数据位宽
    parameter VL_INDEX_WIDTH    = 4,        // VL 索引位宽
    parameter BYTE_OFFSET_WIDTH = 11,       // 字节偏移位宽
    parameter VL_INDEX_SELF     = 4'd2      // 本代理占用的 VL 索引（设计期分配）
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 接收侧（经 rx_rd_arb 访问接收端口缓冲） ====================
    input  wire                          rx_ready_615a,          // 本 VL 一帧接收完成（来自 RX 状态机）
    output wire                          rx_rd_req,              // 读请求，送 rx_rd_arb 仲裁
    output wire [BYTE_OFFSET_WIDTH-1:0]  rx_rd_byte_offset,      // 读字节偏移
    input  wire [DATA_WIDTH-1:0]         rx_rd_data,             // 读数据
    input  wire                          rx_rd_valid,            // 读数据有效（被仲裁授权后拉高）
    input  wire [15:0]                   rx_frame_len,           // 本槽位当前待读帧长度（来自接收缓冲）

    // ==================== 发送侧（经 tx_wr_arb 写入发送端口缓冲） ====================
    output wire                          tx_wr_en,               // 写使能（应答报文一字节）
    output wire [BYTE_OFFSET_WIDTH-1:0]  tx_wr_byte_offset,      // 写字节偏移
    output wire [DATA_WIDTH-1:0]         tx_wr_data,             // 写数据
    output wire                          tx_frame_done,          // 帧尾脉冲：登记长度并请求 TX 发送
    input  wire                          tx_wr_gnt,              // 写请求已被 tx_wr_arb 接受的当拍回执

    // ==================== 加载状态 ====================
    output wire                          load_busy,              // 加载进行中
    output wire                          load_done,              // 加载完成
    output wire                          load_error              // 加载失败
);                                                          // 端口声明或模块例化结束

    wire         tftp_op_valid;                                 // TFTP 操作有效
    wire [1:0]   tftp_op_type;                                  // TFTP 操作类型（RRQ/WRQ/DATA/ACK）
    wire [15:0]  tftp_block_num;                                // TFTP 块号
    wire [15:0]  tftp_data_len;                                 // TFTP 数据长度
    wire         buf_wr_en;                                     // 文件缓冲写使能
    wire [DATA_WIDTH-1:0] buf_wr_data;                          // 文件缓冲写数据
    wire         buf_rd_en;                                     // 文件缓冲读使能
    wire [DATA_WIDTH-1:0] buf_rd_data;                          // 文件缓冲读数据
    wire         fifo_rdempty;                                  // 文件缓冲空标志
    wire         buf_rd_valid;                                  // 文件缓冲读数据有效
    wire         flash_wr_req;                                  // Flash 写请求
    wire [23:0]  flash_wr_addr;                                 // Flash 写地址
    wire         flash_wr_done;                                 // Flash 写完成

    // ==================== TFTP 协议模块例化 ====================
    tftp #(                                                 // 例化子模块并连接数据通路
        .DATA_WIDTH        (DATA_WIDTH),                    // 连接子模块对应端口
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH)              // 连接子模块对应端口
    ) u_tftp (                                              // 参数绑定结束，开始连接实例端口
        .clk               (clk),                               // input  [0:0]
        .rst_b             (rst_b),                             // input  [0:0]
        .start             (rx_ready_615a),                     // input  [0:0]  一帧到达触发解析
        .rx_frame_len      (rx_frame_len),                      // input  [15:0] 当前报文长度
        .rx_rd_req         (rx_rd_req),                         // output [0:0]
        .rx_rd_byte_offset (rx_rd_byte_offset),                 // output [10:0]
        .rx_rd_data        (rx_rd_data),                        // input  [7:0]
        .rx_rd_valid       (rx_rd_valid),                       // input  [0:0]
        .tftp_op_valid     (tftp_op_valid),                     // output [0:0]
        .tftp_op_type      (tftp_op_type),                      // output [1:0]
        .tftp_block_num    (tftp_block_num),                    // output [15:0]
        .tftp_data_len     (tftp_data_len),                     // output [15:0]
        .buf_wr_en         (buf_wr_en),                         // output [0:0]
        .buf_wr_data       (buf_wr_data),                       // output [7:0]
        .buf_rd_en         (buf_rd_en),                         // output [0:0]
        .buf_rd_data       (buf_rd_data),                       // input  [7:0]
        .buf_rd_valid      (buf_rd_valid),                      // input  [0:0]
        .flash_wr_req      (flash_wr_req),                      // output [0:0]
        .flash_wr_addr     (flash_wr_addr),                     // output [23:0]
        .flash_wr_done     (flash_wr_done),                     // input  [0:0]
        .tx_wr_en          (tx_wr_en),                          // output [0:0]
        .tx_wr_byte_offset (tx_wr_byte_offset),                 // output [10:0]
        .tx_wr_data        (tx_wr_data),                        // output [7:0]
        .tx_frame_done     (tx_frame_done),                     // output [0:0]
        .tx_wr_gnt         (tx_wr_gnt),                         // input  [0:0]  写授权回执
        .load_busy         (load_busy),                         // output [0:0]
        .load_done         (load_done),                         // output [0:0]
        .load_error        (load_error)                         // output [0:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== 文件缓冲例化（file_buffer_ip） ====================
    file_buffer #(                                          // 例化子模块并连接数据通路
        .DATA_WIDTH (DATA_WIDTH),                           // 连接子模块对应端口
        .FIFO_DEPTH (512)                                   // 连接子模块对应端口
    ) u_file_buffer (                                       // 参数绑定结束，开始连接实例端口
        .clk       (clk),                                       // input  [0:0]
        .rst_b     (rst_b),                                     // input  [0:0]
        .wr_req    (buf_wr_en),                                 // input  [0:0]
        .data      (buf_wr_data),                               // input  [7:0]
        .rd_req    (buf_rd_en),                                 // input  [0:0]
        .q         (buf_rd_data),                               // output [7:0]
        .rdempty   (fifo_rdempty),                              // output [0:0]
        .rdfull    (),                                          // output [0:0]  （暂未使用）
        .wrusedw   ()                                           // output [8:0]  （暂未使用）
    );                                                      // 端口声明或模块例化结束
    // ==================== 非预读 FIFO 的一拍读返回标志 ====================
    reg fifo_rd_valid_r;                                    // 已接受读请求延迟一拍后对应 q 有效
    always @(posedge clk or negedge rst_b) begin            // 与 FIFO 的同步读时钟保持一致
        if (!rst_b) begin                                   // 异步复位返回有效标志
            fifo_rd_valid_r <= 1'b0;                        // 复位期间没有读返回
        end                                                 // 结束复位分支
        else begin                                          // 正常工作时记录实际被接受的读请求
            fifo_rd_valid_r <= buf_rd_en && !fifo_rdempty;  // 读空后 q 仍有效，不能再用非空判断返回
        end                                                 // 结束读请求采样分支
    end                                                     // 结束一拍返回标志寄存
    assign buf_rd_valid = fifo_rd_valid_r;                  // 有效标志与同步 FIFO 的 q 同拍返回

    // ==================== Flash 写控制例化 ====================
    flash_ctrl #(                                           // 例化子模块并连接数据通路
        .DATA_WIDTH (DATA_WIDTH)                            // 连接子模块对应端口
    ) u_flash_ctrl (                                        // 参数绑定结束，开始连接实例端口
        .clk          (clk),                                    // input  [0:0]
        .rst_b        (rst_b),                                  // input  [0:0]
        .wr_req       (flash_wr_req),                           // input  [0:0]
        .wr_addr      (flash_wr_addr),                          // input  [23:0]
        .wr_data      (buf_rd_data),                            // input  [7:0]
        .wr_done      (flash_wr_done),                          // output [0:0]
        .flash_wr_en  (),                                       // output [0:0]  （暂未引出到顶层）
        .flash_wr_addr(),                                       // output [23:0] （暂未引出到顶层）
        .flash_wr_data(),                                       // output [7:0]  （暂未引出到顶层）
        .flash_erase  ()                                        // output [0:0]  （暂未引出到顶层）
    );                                                      // 端口声明或模块例化结束

    // ==================== 文件表例化（M4K SimpleDualPort IP） ====================
    file_table #(                                           // 例化子模块并连接数据通路
        .FILE_NAME_WIDTH (64),                              // 连接子模块对应端口
        .FILE_SIZE_WIDTH (32)                               // 连接子模块对应端口
    ) u_file_table (                                        // 参数绑定结束，开始连接实例端口
        .clk      (clk),                                        // input  [0:0]
        .rst_b    (rst_b),                                      // input  [0:0]
        .wr_en    (tftp_op_valid),                              // input  [0:0]  DATA 写入完成即登记一条
        .wr_index (tftp_block_num[3:0]),                         // input  [3:0]  按块号分条目，便于回读
        .wr_name ( {tftp_block_num, tftp_data_len, 32'd0} ),    // input  [63:0]  文件名占位，后续由软件登记
        .wr_size ( {16'd0, tftp_data_len} ),                    // input  [31:0]  本块载荷长度
        .wr_crc  ( 32'd0 ),                                     // input  [31:0]  CRC 预留给软件登记，当前硬件路径填 0
        .rd_en   (1'b1),                                        // input  [0:0]  常读，供 615A 查询
        .rd_index(tftp_block_num[3:0]),                          // input  [3:0]  查询当前块号对应条目
        .rd_name (),                                            // output [63:0]
        .rd_size (),                                            // output [31:0]
        .rd_crc  ()                                             // output [31:0]
    );                                                      // 端口声明或模块例化结束

endmodule                                                   // 模块定义结束

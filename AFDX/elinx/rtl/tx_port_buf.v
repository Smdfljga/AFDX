// tx_port_buf : 发送端口缓冲
// 按 {VL 槽位号, 字节偏移} 寻址的 32KB 简单双端口 RAM（16 个槽位 × 2KB），
// 应用与三个协议代理通过 tx_wr_arb 仲裁后写入待发数据，TX 状态机按 VL 读出组帧；
// 另有一组长度寄存器记录每个槽位待发帧的数据长度，供 TX 取长度
// 每槽位一个 busy 标志：帧尾登记长度时置位，TX 读走该帧最后一字节时清零；
// busy 期间 tx_wr_arb 不授权该槽位的写入 → 写入方自然等待上一帧发完（避免半帧被覆盖）
module tx_port_buf #(                                       // 声明模块及其参数接口
    parameter DATA_WIDTH        = 8,        // 数据位宽
    parameter VL_INDEX_WIDTH    = 4,        // VL 索引位宽
    parameter BYTE_OFFSET_WIDTH = 11        // 字节偏移位宽（2KB/VL）
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（读写同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 写侧（来自 tx_wr_arb） ====================
    input  wire                          wr_en,                  // 写使能（写一字节）
    input  wire [VL_INDEX_WIDTH-1:0]     wr_vl_index,            // 写 VL 索引
    input  wire [BYTE_OFFSET_WIDTH-1:0]  wr_byte_offset,         // 写字节偏移，VL 缓冲内地址
    input  wire [DATA_WIDTH-1:0]         wr_data,                // 写数据

    // ==================== 帧长度登记（帧尾那一拍，由 tx_wr_arb 给出） ====================
    input  wire                          len_wr_en,              // 长度登记使能
    input  wire [VL_INDEX_WIDTH-1:0]     len_vl_index,           // 长度所属 VL 索引
    input  wire [BYTE_OFFSET_WIDTH-1:0]  len_byte_offset,        // 该帧末字节偏移（长度 = 该值 + 1）

    // ==================== 读侧（TX 状态机） ====================
    input  wire                          rd_en,                  // 读使能
    input  wire [VL_INDEX_WIDTH-1:0]     rd_vl_index,            // 读 VL 索引
    input  wire [BYTE_OFFSET_WIDTH-1:0]  rd_byte_offset,         // 读字节偏移
    output wire [DATA_WIDTH-1:0]         rd_data,                // 读数据（同步读，M4K 地址寄存 + 输出寄存，地址稳定后两拍有效）
    output wire                          rd_valid,               // 读数据有效，比 rd_en 晚两拍
    output wire [15:0]                   payload_len,            // 该 VL 待发数据长度（字节）
    output wire [15:0]                   vl_busy,                // 每槽位忙标志：1=上一帧还没发完，暂不接受新帧
    input  wire [15:0]                   abort_vl                // 每槽位撤销：1=本拍丢弃该槽位待发帧（清忙标志与长度）
);                                                          // 端口声明或模块例化结束

    wire [VL_INDEX_WIDTH+BYTE_OFFSET_WIDTH-1:0] wr_addr =   // 写入物理地址，由槽位与字节偏移拼接
        {wr_vl_index, wr_byte_offset};                          // 写地址：VL 索引在高位，按 VL 分段
    wire [VL_INDEX_WIDTH+BYTE_OFFSET_WIDTH-1:0] rd_addr =   // 读取物理地址，由槽位与字节偏移拼接
        {rd_vl_index, rd_byte_offset};                          // 读地址：与写地址拼接方式保持一致

    // 简单双端口 M4K IP（8bit × 32768 = 32KB/端口），与 rx_port_buf_ip 同规格
    tx_port_buf_ip u_tx_port_buf_ip (                       // 例化子模块并连接数据通路
        .inclock    (clk),                                      // input  [0:0]
        .in_aclr    (~rst_b),                                   // input  [0:0]  高有效异步清零
        .wraddress  (wr_addr),                                  // input  [14:0]
        .data       (wr_data),                                  // input  [7:0]
        .wren       (wr_en),                                    // input  [0:0]
        .outclock   (clk),                                      // input  [0:0]
        .out_aclr   (~rst_b),                                   // input  [0:0]
        .rdaddress  (rd_addr),                                  // input  [14:0]
        .rden       (rd_en),                                    // input  [0:0]
        .q          (rd_data)                                   // output [7:0]
    );                                                      // 端口声明或模块例化结束

    // 长度按「帧尾字节偏移 + 1」登记：只在帧尾那一拍更新，帧中间读数不会拿到半截长度；
    // 前提是写入方从偏移 0 开始连续写（见 tx_wr_arb 的约定）
    reg [15:0] payload_len_reg [0:(1<<VL_INDEX_WIDTH)-1];       // 每个 VL 的待发载荷长度
    integer init_len;                                           // 复位时遍历长度寄存器

    assign payload_len = payload_len_reg[rd_vl_index];          // output [15:0]：读侧 VL 对应的长度

    // 本拍读请求是否到达发送载荷末字节：读完即该槽位这一帧已经发出去
    wire       read_last = rd_en && (payload_len != 16'd0) &&  // 本拍读请求是否到达发送载荷末字节
                           (rd_byte_offset == payload_len - 16'd1); // 正在读待发帧最后一字节

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            for (init_len = 0; init_len < (1<<VL_INDEX_WIDTH); init_len = init_len + 1)  // 依次处理指定范围内的表项或位段
                payload_len_reg[init_len] <= 16'd0;         // 时钟沿更新每个 VL 的待发载荷长度
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            if (len_wr_en) begin                            // 检查长度登记使能的条件
                payload_len_reg[len_vl_index] <= {5'b0, len_byte_offset} + 16'd1; // 帧长 = 末字节偏移 + 1
            end                                             // 当前语句组结束
            // 帧读完把长度清零：否则 TX 扫描会把「已经发过的旧长度」当成待发帧，
            // 应用再次触发 app_tx_req 时重复发送上一帧
            if (read_last) begin                            // 检查本拍是否读完待发帧末字节的条件
                payload_len_reg[rd_vl_index] <= 16'd0;      // 该槽位已无待发帧
            end                                             // 当前语句组结束
            // 本帧被丢弃（超 Lmax / 配置无效）：撤销该槽位，长度清零后可重新写新帧
            for (init_len = 0; init_len < (1<<VL_INDEX_WIDTH); init_len = init_len + 1)  // 依次处理指定范围内的表项或位段
                if (abort_vl[init_len])                     // 检查该槽位是否被撤销
                    payload_len_reg[init_len] <= 16'd0;     // 丢弃的帧不再待发
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

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

    // ==================== 忙标志 ====================
    // 置位：len_wr_en 那一拍（帧尾登记长度，表示该槽位已有一帧待发）
    // 清零：TX 读走该帧最后一字节，或该帧被判决丢弃（abort_vl）。busy 期间 tx_wr_arb 不授权该槽位的写入。
    reg [15:0] busy_r;                                          // 每槽位忙标志寄存器
    integer    init_busy;                                       // 复位时遍历忙标志

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            for (init_busy = 0; init_busy < (1<<VL_INDEX_WIDTH); init_busy = init_busy + 1)  // 依次处理指定范围内的表项或位段
                busy_r[init_busy] <= 1'b0;                  // 时钟沿更新每槽位忙标志寄存器
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            if (len_wr_en)                                  // 检查长度登记使能的条件
                busy_r[len_vl_index] <= 1'b1;                   // 新帧登记，置忙
            if (read_last)                                  // 检查read_last的条件
                busy_r[rd_vl_index] <= 1'b0;                    // 旧帧读完，释放槽位
            for (init_busy = 0; init_busy < (1<<VL_INDEX_WIDTH); init_busy = init_busy + 1)  // 依次处理指定范围内的表项或位段
                if (abort_vl[init_busy])                    // 检查该槽位是否被撤销
                    busy_r[init_busy] <= 1'b0;              // 帧已丢弃，释放槽位
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    assign vl_busy = busy_r;                                    // output [15:0]：每槽位忙标志

endmodule                                                   // 模块定义结束

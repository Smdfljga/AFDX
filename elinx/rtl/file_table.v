// file_table : 615A 文件表
// 记录每个已加载文件的名称、大小与 CRC，供 615A 查询与校验
module file_table #(                                        // 声明模块及其参数接口
    parameter FILE_NAME_WIDTH = 64,         // 文件名位宽
    parameter FILE_SIZE_WIDTH = 32          // 文件大小位宽
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 写侧 ====================
    input  wire                          wr_en,                  // 写使能
    input  wire [3:0]                    wr_index,               // 写文件索引（最多 16 个文件）
    input  wire [FILE_NAME_WIDTH-1:0]    wr_name,                // 文件名
    input  wire [FILE_SIZE_WIDTH-1:0]    wr_size,                // 文件大小
    input  wire [31:0]                   wr_crc,                 // 文件 CRC

    // ==================== 读侧 ====================
    input  wire                          rd_en,                  // 读使能
    input  wire [3:0]                    rd_index,               // 读文件索引
    output wire [FILE_NAME_WIDTH-1:0]    rd_name,                // 文件名
    output wire [FILE_SIZE_WIDTH-1:0]    rd_size,                // 文件大小
    output wire [31:0]                   rd_crc                  // 文件 CRC
);                                                          // 端口声明或模块例化结束

    wire [127:0] q_0;                                           // BRAM 读数据 {CRC, 大小, 名称}

    // 简单双端口 M4K IP（128bit × 16）：文件名 + 大小 + CRC
    file_table_ip u_file_table_ip (                         // 例化子模块并连接数据通路
        .inclock    (clk),                                      // input  [0:0]
        .in_aclr    (~rst_b),                                   // input  [0:0]  高有效异步清零
        .wraddress  (wr_index),                                 // input  [3:0]
        .data       ({wr_crc, wr_size, wr_name}),               // input  [127:0]
        .wren       (wr_en),                                    // input  [0:0]
        .outclock   (clk),                                      // input  [0:0]
        .out_aclr   (~rst_b),                                   // input  [0:0]
        .rdaddress  (rd_index),                                 // input  [3:0]
        .rden       (rd_en),                                    // input  [0:0]
        .q          (q_0)                                       // output [127:0]
    );                                                      // 端口声明或模块例化结束

    assign rd_name = q_0[63:0];                                 // output [63:0]：文件名
    assign rd_size = q_0[95:64];                                // output [31:0]：文件大小
    assign rd_crc  = q_0[127:96];                               // output [31:0]：文件 CRC

endmodule                                                   // 模块定义结束

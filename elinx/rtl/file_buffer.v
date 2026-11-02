// file_buffer : 615A 文件数据缓冲
// 单时钟 FIFO 封装（eLinx FIFO IP：file_buffer_ip），用于 TFTP 报文与 Flash 写节奏解耦
module file_buffer #(                                       // 声明模块及其参数接口
    parameter DATA_WIDTH = 8,               // 数据位宽
    parameter FIFO_DEPTH = 512              // FIFO 深度（字数）
)(                                                          // 参数声明结束，开始端口声明
    // 时钟与复位
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // 写侧
    input  wire                          wr_req,                 // 写请求
    input  wire [DATA_WIDTH-1:0]         data,                   // 写数据

    // 读侧
    input  wire                          rd_req,                 // 读请求
    output wire [DATA_WIDTH-1:0]         q,                      // 读数据
    output wire                          rdempty,                // 读空标志
    output wire                          rdfull,                 // 写满标志（FIFO IP 的 full 输出）
    output wire [8:0]                    wrusedw                 // 已用字数
);                                                          // 端口声明或模块例化结束

    // 单时钟 FIFO IP（8bit × 512，eLinx 的 FIFO 生成器，非 show-ahead 模式）
    // 读延时 1 拍：rdreq 被采样后下一拍 q 有效
    file_buffer_ip u_file_buffer_ip (                       // 例化子模块并连接数据通路
        .clock       (clk),                                     // input  [0:0]
        .aclr        (~rst_b),                                  // input  [0:0]  高有效异步清零
        .sclr        (1'b0),                                    // input  [0:0]  不使用同步清零
        .data        (data),                                    // input  [7:0]
        .wrreq       (wr_req),                                  // input  [0:0]
        .rdreq       (rd_req),                                  // input  [0:0]
        .q           (q),                                       // output [7:0]
        .full        (rdfull),                                  // output [0:0]
        .empty       (rdempty),                                 // output [0:0]
        .usedw       (wrusedw),                                 // output [8:0]
        .almost_full (),                                        // output [0:0]  （暂未使用）
        .almost_empty()                                         // output [0:0]  （暂未使用）
    );                                                      // 端口声明或模块例化结束

endmodule                                                   // 模块定义结束

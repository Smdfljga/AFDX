// rx_rd_arb : 接收端口缓冲读仲裁
// 接收端口缓冲只有一个读口，但应用与 SNMP / 615A / RTC 三个协议代理都要读它，
// 这层仲裁把 4 路读请求合成一路，并把读回的数据送回被授权的那一路
// 仲裁策略：固定优先级 app > snmp > 615a > rtc
// （应用数据路径延迟要求最紧；改轮转仲裁会更公平但延迟不确定，航电里一般不这么做）
// 注：被例化的缓冲是同步读（地址给出后下一拍出数据），被授权的那一路要使地址稳定保持到数据被取走
module rx_rd_arb #(                                         // 声明模块及其参数接口
    parameter DATA_WIDTH        = 8,        // 数据位宽
    parameter VL_INDEX_WIDTH    = 4,        // VL 索引位宽
    parameter BYTE_OFFSET_WIDTH = 11        // 字节偏移位宽
)(                                                          // 参数声明结束，开始端口声明
    // 时钟与复位
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 应用读请求（优先级最高） ====================
    input  wire                          app_rd_req,             // 应用读请求
    input  wire [VL_INDEX_WIDTH-1:0]     app_rd_vl_index,        // 应用读 VL 索引
    input  wire [BYTE_OFFSET_WIDTH-1:0]  app_rd_byte_offset,     // 应用读字节偏移
    output wire                          app_rd_valid,           // 应用读数据有效

    // ==================== SNMP 读请求 ====================
    input  wire                          snmp_rd_req,            // SNMP 读请求
    input  wire [VL_INDEX_WIDTH-1:0]     snmp_rd_vl_index,       // SNMP 读 VL 索引（固定为其分配的 VL）
    input  wire [BYTE_OFFSET_WIDTH-1:0]  snmp_rd_byte_offset,    // SNMP 读字节偏移
    output wire                          snmp_rd_valid,          // SNMP 读数据有效

    // ==================== 615A 读请求 ====================
    input  wire                          dl_rd_req,              // 615A 读请求
    input  wire [VL_INDEX_WIDTH-1:0]     dl_rd_vl_index,         // 615A 读 VL 索引
    input  wire [BYTE_OFFSET_WIDTH-1:0]  dl_rd_byte_offset,      // 615A 读字节偏移
    output wire                          dl_rd_valid,            // 615A 读数据有效

    // ==================== RTC 读请求 ====================
    input  wire                          rtc_rd_req,             // RTC 读请求
    input  wire [VL_INDEX_WIDTH-1:0]     rtc_rd_vl_index,        // RTC 读 VL 索引
    input  wire [BYTE_OFFSET_WIDTH-1:0]  rtc_rd_byte_offset,     // RTC 读字节偏移
    output wire                          rtc_rd_valid,           // RTC 读数据有效

    // ==================== 到接收端口缓冲的读口 ====================
    output wire                          buf_rd_en,              // 缓冲读使能（任一请求被授权）
    output wire [VL_INDEX_WIDTH-1:0]     buf_rd_vl_index,        // 缓冲读 VL 索引
    output wire [BYTE_OFFSET_WIDTH-1:0]  buf_rd_byte_offset,     // 缓冲读字节偏移
    input  wire [DATA_WIDTH-1:0]         buf_rd_data,            // 缓冲读数据

    // ==================== 共享读数据（只有被授权者当拍有效） ====================
    output wire [DATA_WIDTH-1:0]         rd_data                 // 读数据总线，与被授权的 *_rd_valid 同拍
);                                                          // 端口声明或模块例化结束

    // ==================== 固定优先级授权（组合逻辑） ====================
    reg app_v;                                                  // 应用授权延迟一拍，应用仍可逐拍流水读
    reg snmp_v;                                                 // SNMP 授权延迟一拍并禁止响应拍重复授权
    reg dl_v;                                                   // 615A 授权延迟一拍并禁止响应拍重复授权
    reg rtc_v;                                                  // RTC 授权延迟一拍并禁止响应拍重复授权
    wire app_gnt  = app_rd_req;                                 // 应用优先级最高
    wire snmp_gnt = ~app_rd_req && snmp_rd_req && !snmp_v;  // SNMP 响应拍不重复授权尚未更新的旧偏移
    wire dl_gnt   = ~app_rd_req && ~snmp_rd_req && dl_rd_req && !dl_v;  // 615A 等响应推进，响应拍暂停重发
    wire rtc_gnt  = ~app_rd_req && ~snmp_rd_req && ~dl_rd_req && rtc_rd_req && !rtc_v;  // RTC 同样每个等待请求只取一次
    // 应用接口允许逐拍给出新地址，因此应用授权保持原来的一字节每拍吞吐。

    // ==================== 选通到缓冲读口的地址 ====================
    assign buf_rd_en          = app_gnt | snmp_gnt | dl_gnt | rtc_gnt; // output [0:0]：任一请求被接受
    assign buf_rd_vl_index    = app_gnt ? app_rd_vl_index :  // 设置或组合计算缓冲读 VL 索引
                                snmp_gnt ? snmp_rd_vl_index :  // 继续计算buf_rd_vl_index
                                dl_gnt ? dl_rd_vl_index : rtc_rd_vl_index; // output [3:0]
    assign buf_rd_byte_offset = app_gnt ? app_rd_byte_offset :  // 设置或组合计算缓冲读字节偏移
                                snmp_gnt ? snmp_rd_byte_offset :  // 继续计算buf_rd_byte_offset
                                dl_gnt ? dl_rd_byte_offset : rtc_rd_byte_offset; // output [10:0]

    // 共享数据总线由四个消费者自己用 *_rd_valid 区分，硬件上只有被授权者当拍采样
    assign rd_data = buf_rd_data;                               // output [7:0]

    // ==================== 授权结果打一拍 ====================
    // M4K 简双口读延迟 1 拍：本拍授权给 RAM，下一拍数据回来，valid 与数据同拍输出。

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            app_v  <= 1'b0;                                 // 时钟沿更新应用授权延迟一拍
            snmp_v <= 1'b0;                                 // 时钟沿更新SNMP 授权延迟一拍并禁止响应拍重复授权
            dl_v   <= 1'b0;                                 // 时钟沿更新615A 授权延迟一拍并禁止响应拍重复授权
            rtc_v  <= 1'b0;                                 // 时钟沿更新RTC 授权延迟一拍并禁止响应拍重复授权
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            app_v  <= app_gnt;                              // 时钟沿更新应用授权延迟一拍
            snmp_v <= snmp_gnt;                             // 时钟沿更新SNMP 授权延迟一拍并禁止响应拍重复授权
            dl_v   <= dl_gnt;                               // 时钟沿更新615A 授权延迟一拍并禁止响应拍重复授权
            rtc_v  <= rtc_gnt;                              // 时钟沿更新RTC 授权延迟一拍并禁止响应拍重复授权
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    assign app_rd_valid  = app_v;                               // output [0:0]：应用读数据有效
    assign snmp_rd_valid = snmp_v;                              // output [0:0]：SNMP 读数据有效
    assign dl_rd_valid   = dl_v;                                // output [0:0]：615A 读数据有效
    assign rtc_rd_valid  = rtc_v;                               // output [0:0]：RTC 读数据有效

endmodule                                                   // 模块定义结束

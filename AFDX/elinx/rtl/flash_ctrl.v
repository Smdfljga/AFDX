// flash_ctrl : Flash 写控制
// 把缓冲中的数据按 24bit 地址写入外部 Flash（擦除、页编程时序）
// 注：单字节 Flash 写与扇区擦除状态机已实现
module flash_ctrl #(                                        // 声明模块及其参数接口
    parameter DATA_WIDTH = 8                // 数据位宽
)(                                                          // 参数声明结束，开始端口声明
    // 时钟与复位
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // 写请求
    input  wire                          wr_req,                 // 写请求
    input  wire [23:0]                   wr_addr,                // 写地址
    input  wire [DATA_WIDTH-1:0]         wr_data,                // 写数据
    output wire                          wr_done,                // 写完成

    // 到 Flash 器件的接口
    output wire                          flash_wr_en,            // Flash 写使能
    output wire [23:0]                   flash_wr_addr,          // Flash 写地址
    output wire [DATA_WIDTH-1:0]         flash_wr_data,          // Flash 写数据
    output wire                          flash_erase             // Flash 扇区擦除
);                                                          // 端口声明或模块例化结束

    // ==================== 状态机 ====================
    localparam S_IDLE  = 2'd0;                                  // 空闲，等待写请求
    localparam S_ERASE = 2'd1;                                  // 首次跨扇区时输出擦除脉冲
    localparam S_WRITE = 2'd2;                                  // 输出一字节写脉冲

    reg [1:0]          state;                                   // 当前状态
    reg [23:0]         addr_r;                                  // 已锁存写地址
    reg [DATA_WIDTH-1:0] data_r;                                // 已锁存写数据
    reg [11:0]         erased_sector;                           // 已擦除扇区号（地址[23:12]）
    reg                erased_valid;                            // 已擦除扇区是否有效

    // ==================== 状态机：第二段（组合，算次态） ====================
    reg [1:0] nxt_state;                                        // 次态，由本段组合算出

    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        nxt_state = state;                                      // 默认保持当前状态

        case (state)                                        // 根据当前状态选择处理分支
            S_IDLE: begin                                   // 处理空闲阶段
                if (wr_req) begin                           // 检查写请求的条件
                    // 同一扇区只擦除一次；换扇区时先进入擦除状态
                    if (erased_valid && (erased_sector == wr_addr[23:12]))  // 检查已擦除扇区是否有效、已擦除扇区号（地址[23:12]）、写地址的条件
                        nxt_state = S_WRITE;                // 设置或组合计算次态
                    else                                    // 采用前一条件未满足时的处理
                        nxt_state = S_ERASE;                // 设置或组合计算次态
                end                                         // 当前语句组结束
            end                                             // 当前语句组结束

            S_ERASE: begin                                  // 处理首次跨扇区时输出擦除脉冲阶段
                nxt_state = S_WRITE;                            // 擦除脉冲一拍后写数据
            end                                             // 当前语句组结束

            S_WRITE: begin                                  // 处理输出一字节写脉冲阶段
                nxt_state = S_IDLE;                             // 写脉冲一拍后回空闲
            end                                             // 当前语句组结束

            default: begin                                  // 未匹配有效分支时采用默认处理
                nxt_state = S_IDLE;                             // 异常状态回空闲
            end                                             // 当前语句组结束
        endcase                                             // 当前分支选择结束
    end                                                     // 当前语句组结束

    // ==================== 状态机：第一段（时序，状态寄存器与数据通路） ====================
    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            state         <= S_IDLE;                        // 时钟沿更新当前状态
            addr_r        <= 24'd0;                         // 时钟沿更新已锁存写地址
            data_r        <= {DATA_WIDTH{1'b0}};            // 时钟沿更新已锁存写数据
            erased_sector <= 12'd0;                         // 时钟沿更新已擦除扇区号（地址[23:12]）
            erased_valid  <= 1'b0;                          // 时钟沿更新已擦除扇区是否有效
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            case (state)                                    // 根据当前状态选择处理分支
                S_IDLE: begin                               // 处理空闲阶段
                    if (wr_req) begin                       // 检查写请求的条件
                        addr_r <= wr_addr;                      // 锁存本次写地址与数据
                        data_r <= wr_data;                  // 时钟沿更新已锁存写数据
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_ERASE: begin                              // 处理首次跨扇区时输出擦除脉冲阶段
                    erased_sector <= addr_r[23:12];             // 记录已擦除扇区
                    erased_valid  <= 1'b1;                  // 时钟沿更新已擦除扇区是否有效
                end                                         // 当前语句组结束

                default: ;                                      // 其余状态没有数据通路动作
            endcase                                         // 当前分支选择结束

            state <= nxt_state;                                 // 状态寄存器只在第一段更新
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    assign flash_erase    = (state == S_ERASE);                 // output [0:0]：扇区擦除脉冲
    assign flash_wr_en    = (state == S_WRITE);                 // output [0:0]：写使能脉冲
    assign flash_wr_addr  = addr_r;                             // output [23:0]
    assign flash_wr_data  = data_r;                             // output [7:0]
    assign wr_done        = (state == S_WRITE);                 // output [0:0]：写完成脉冲

endmodule                                                   // 模块定义结束

// mib_query : MIB 计数查询
// 把 OID 映射成「查哪张表（RX/TX）+ 哪个 VL + 哪个计数器」，驱动 mib_ram 读口，
// 再把读回的 5 个计数器按索引选出一个返回
// 注：OID 拆解与 MIB 读延迟两拍（与厂商 M4K IP 一致）的流水在本模块内完成
module mib_query #(                                         // 声明模块及其参数接口
    parameter CNT_WIDTH     = 32,           // MIB 计数器位宽
    parameter VL_ADDR_WIDTH = 12,           // VL 表地址位宽（IP 已生成 4096 深）
    parameter OID_WIDTH     = 16            // 内部对象索引位宽（1 表选 + 12 地址 + 3 计数选）
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 查询请求 ====================
    input  wire                          query_req,              // 查询请求，单拍有效
    input  wire [OID_WIDTH-1:0]          oid,                    // 目标对象索引：[15]表选 [14:3]VL条目号 [2:0]计数器号

    // ==================== MIB 读口（接 mib_ram 读口） ====================
    output wire                          mib_sel,                // 0=读 RX 计数表 1=读 TX 计数表
    output wire [VL_ADDR_WIDTH-1:0]      mib_addr,               // 要查询的 VL 条目索引
    output wire                          mib_rd_en,              // MIB 读使能
    input  wire [5*CNT_WIDTH-1:0]        mib_rd_data,            // MIB 读回的 5 个计数器

    // ==================== 查询结果 ====================
    output wire                          query_done,             // 查询完成
    output wire [CNT_WIDTH-1:0]          query_value             // 查询到的计数值
);                                                          // 端口声明或模块例化结束

    // ==================== OID 位段拆解 ====================
    wire [2:0]               cnt_sel = oid[2:0];                // 计数器编号 0~4
    wire [VL_ADDR_WIDTH-1:0] vl_addr = oid[OID_WIDTH-2:3];      // VL 表条目地址
    wire                     tbl_sel = oid[OID_WIDTH-1];        // 0=RX 表 1=TX 表

    // ==================== 请求位段流水 ====================
    // RAM 读延迟两拍，请求位段（表选/计数器号）必须跟着同一流水走，
    // 连续查询时每笔各自带自己的位段，不会互相覆盖。
    reg                  rq_d1, rq_d2, rq_d3;               // 请求有效延迟 1/2/3 拍
    reg [2:0]            cnt_d1, cnt_d2;                    // 计数器编号延迟 1/2 拍
    reg                  tbl_d1, tbl_d2;                    // 表选择延迟 1/2 拍
    reg [VL_ADDR_WIDTH-1:0] addr_r;                         // 最近一次查询地址，请求撤销后继续保持
    reg [CNT_WIDTH-1:0]  value_r;                           // 已完成查询的返回值，直到下一次完成前保持

    // RX/TX 两表共享地址且持续同步读，两张表的读使能同时拉高（读口只读，多读一次不改变内容），
    // 表选择延迟两拍后选出本次请求返回的数据；允许相邻时钟接受不同表的查询。
    assign mib_sel   = tbl_d2;                              // output [0:0]：表选择（两拍前的请求）
    assign mib_addr  = query_req ? vl_addr : addr_r;        // output [11:0]：VL 条目索引
    assign mib_rd_en = query_req;                               // output [0:0]：查询读使能

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            rq_d1  <= 1'b0;                                 // 复位清请求流水
            rq_d2  <= 1'b0;                                 // 复位清请求流水
            rq_d3  <= 1'b0;                                 // 复位清请求流水
            cnt_d1 <= 3'd0;                                 // 复位清计数器编号流水
            cnt_d2 <= 3'd0;                                 // 复位清计数器编号流水
            tbl_d1 <= 1'b0;                                 // 复位清表选择流水
            tbl_d2 <= 1'b0;                                 // 复位清表选择流水
            addr_r <= {VL_ADDR_WIDTH{1'b0}};                // 复位清除保持地址
            value_r <= {CNT_WIDTH{1'b0}};                   // 复位清除返回值
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            rq_d1  <= query_req;                            // 请求有效延迟第一拍
            rq_d2  <= rq_d1;                                // 请求有效延迟第二拍（数据本拍返回）
            rq_d3  <= rq_d2;                                // 请求有效延迟第三拍（与返回值同拍给出完成）
            cnt_d1 <= cnt_sel;                              // 计数器编号延迟第一拍
            cnt_d2 <= cnt_d1;                               // 计数器编号延迟第二拍
            tbl_d1 <= tbl_sel;                              // 表选择延迟第一拍
            tbl_d2 <= tbl_d1;                               // 表选择延迟第二拍
            if (query_req)                                  // 请求拍保存地址，空闲时保持读地址
                addr_r <= vl_addr;                          // 保存地址，空闲时保持 RAM 读地址
            if (rq_d2) begin                                // 两拍后数据已返回
                if (cnt_d2 < 3'd5)                          // 仅允许访问已定义的五个计数器
                    value_r <= mib_rd_data[cnt_d2*CNT_WIDTH +: CNT_WIDTH];  // 锁存本次返回的计数值
                else                                        // 无效计数器编号返回确定值
                    value_r <= {CNT_WIDTH{1'b0}};           // 避免动态越界切片产生不定态
            end                                             // 返回值锁存结束
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    assign query_done = rq_d3;                                  // output [0:0]：与读回数据同拍有效

    // 按计数器编号从 5 个 32bit 计数器中选出一个；+： 是 Verilog-2001 的索引位选。
    assign query_value = value_r;                           // output [31:0]

endmodule                                                   // 模块定义结束

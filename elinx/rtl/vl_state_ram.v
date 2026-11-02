// vl_state_ram : VL 运行期状态表
// 每条 VL 的动态状态：接收侧最近接受的 SN（IC/RM 用）、发送侧当前 SN、
// 发送侧上一帧发送时刻（BAG 整形用）；随收发包实时更新，掉电/复位即清空
// 端口 A 归 RX 状态机，端口 B 归 TX 状态机，各自独立读写
// 注：与 vl_config_ram 分开存放的原因见 REVIEW.md（静态配置与动态状态不能同字）
module vl_state_ram #(                                      // 声明模块及其参数接口
    parameter VL_ADDR_WIDTH = 12,           // 地址位宽（深度 4096，必须与生成的 IP 一致）
    parameter STATE_WIDTH   = 64            // 状态字位宽
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 端口 A（RX：IC/RM 状态） ====================
    input  wire                          clk_a,                  // 端口 A 时钟
    input  wire                          rst_a,                  // 端口 A 复位（高有效异步清零）
    input  wire [VL_ADDR_WIDTH-1:0]      addr_a,                 // 端口 A 地址，VL 条目索引
    input  wire                          rd_en_a,                // 端口 A 读使能（帧首读状态）
    output wire [STATE_WIDTH-1:0]        rd_data_a,              // 端口 A 读数据
    input  wire                          wr_en_a,                // 端口 A 写使能（帧尾写回新状态）
    input  wire [STATE_WIDTH-1:0]        wr_data_a,              // 端口 A 写数据

    // ==================== 端口 B（TX：SN / BAG 计时） ====================
    input  wire                          clk_b,                  // 端口 B 时钟
    input  wire                          rst_b,                  // 端口 B 复位（高有效异步清零）
    input  wire [VL_ADDR_WIDTH-1:0]      addr_b,                 // 端口 B 地址，VL 条目索引
    input  wire                          rd_en_b,                // 端口 B 读使能
    output wire [STATE_WIDTH-1:0]        rd_data_b,              // 端口 B 读数据
    input  wire                          wr_en_b,                // 端口 B 写使能
    input  wire [STATE_WIDTH-1:0]        wr_data_b               // 端口 B 写数据
);                                                          // 端口声明或模块例化结束

    // ==================== 收发字段独立存储 ====================
    // 两个控制器持有的状态快照可能过期，整字回写即使错开时钟也会覆盖另一方的新值。
    // 使用两片同规格既有 IP：RX 只维护低十六位，TX 只维护高四十八位，再在读口拼回原接口。
    // 两片 RAM 仍各自一拍同步读；额外消耗一片四千零九十六乘六十四位 RAM，不改变外部时序。
    wire [63:0] rx_word_a;                                  // RX 字段存储在端口 A 的一拍读结果
    wire [63:0] rx_word_b;                                  // RX 字段存储在端口 B 的一拍读结果
    wire [63:0] tx_word_a;                                  // TX 字段存储在端口 A 的一拍读结果
    wire [63:0] tx_word_b;                                  // TX 字段存储在端口 B 的一拍读结果
    vl_state_ip u_vl_state_ip_rx (                          // RX 字段独占第一片 RAM 的写端口
        .clock_a    (clk_a),                                    // input  [0:0]
        .aclr_a     (rst_a),                                    // input  [0:0]  高有效异步清零
        .address_a  (addr_a),                                   // input  [11:0] VL 条目索引
        .data_a     ({48'd0, wr_data_a[15:0]}),             // input [63:0] RX 只写自己的低十六位
        .wren_a     (wr_en_a),                                  // input  [0:0]
        .q_a        (rx_word_a),                            // output [63:0] RX 字段在端口 A 的一拍读结果
        .clock_b    (clk_b),                                    // input  [0:0]
        .aclr_b     (rst_b),                                    // input  [0:0]
        .address_b  (addr_b),                                   // input  [11:0]
        .data_b     (64'd0),                                // input [63:0] TX 端口不修改 RX 字段
        .wren_b     (1'b0),                                 // input [0:0] RX 字段只有一个写入方
        .q_b        (rx_word_b)                             // output [63:0] RX 字段在端口 B 的一拍读结果
    );                                                      // 结束 RX 字段 RAM 例化
    vl_state_ip u_vl_state_ip_tx (                          // TX 字段独占第二片 RAM 的写端口
        .clock_a    (clk_a),                                    // input [0:0] RX 读口时钟
        .aclr_a     (rst_a),                                    // input [0:0] RX 读口高有效复位
        .address_a  (addr_a),                                   // input [11:0] RX 查询同一 VL 的 TX 字段
        .data_a     (64'd0),                                // input [63:0] RX 端口不修改 TX 字段
        .wren_a     (1'b0),                                 // input [0:0] TX 字段只有一个写入方
        .q_a        (tx_word_a),                            // output [63:0] TX 字段在端口 A 的一拍读结果
        .clock_b    (clk_b),                                    // input [0:0] TX 读写口时钟
        .aclr_b     (rst_b),                                    // input [0:0] TX 读写口高有效复位
        .address_b  (addr_b),                                   // input [11:0] TX 当前 VL 地址
        .data_b     ({wr_data_b[63:16], 16'd0}),            // input [63:0] TX 只写自己的高四十八位
        .wren_b     (wr_en_b),                                  // input [0:0] 保持原有 TX 写使能驱动
        .q_b        (tx_word_b)                             // output [63:0] TX 字段在端口 B 的一拍读结果
    );                                                      // 结束 TX 字段 RAM 例化

    // ==================== 热复位有效位与一拍读对齐 ====================
    // IP 的 aclr 清除输出寄存器，不清除存储阵列；有效位复位后屏蔽所有旧状态，直至各方重新写入。
    reg [(1<<VL_ADDR_WIDTH)-1:0] rx_initialized;            // 每个 VL 的 RX 字段是否已在本轮复位后更新
    reg [(1<<VL_ADDR_WIDTH)-1:0] tx_initialized;            // 每个 VL 的 TX 字段是否已在本轮复位后更新
    reg rx_valid_a;                                         // 与端口 A 同步读结果对齐的 RX 有效位
    reg tx_valid_a;                                         // 与端口 A 同步读结果对齐的 TX 有效位
    reg rx_valid_b;                                         // 与端口 B 同步读结果对齐的 RX 有效位
    reg tx_valid_b;                                         // 与端口 B 同步读结果对齐的 TX 有效位
    always @(posedge clk_a or posedge rst_a) begin          // RX 写方维护自己的有效位与端口 A 读标记
        if (rst_a) begin                                    // 高有效异步复位不扫描 RAM
            rx_initialized <= {(1<<VL_ADDR_WIDTH){1'b0}};   // 清除全部 RX 字段有效位
            rx_valid_a <= 1'b0;                             // 复位时屏蔽端口 A 的 RX 旧数据
            tx_valid_a <= 1'b0;                             // 复位时屏蔽端口 A 的 TX 旧数据
        end else begin                                      // 正常 RX 时钟周期
            if (wr_en_a) rx_initialized[addr_a] <= 1'b1;    // RX 完成一次写入后该条字段重新有效
            rx_valid_a <= rx_initialized[addr_a];           // 有效位与 RAM 对同一地址采样
            tx_valid_a <= tx_initialized[addr_a];           // TX 有效位与端口 A 的 TX 数据同拍
        end                                                 // 结束 RX 时钟周期
    end                                                     // 结束 RX 有效位维护
    always @(posedge clk_b or posedge rst_b) begin          // TX 写方维护自己的有效位与端口 B 读标记
        if (rst_b) begin                                    // 高有效异步复位不扫描 RAM
            tx_initialized <= {(1<<VL_ADDR_WIDTH){1'b0}};   // 清除全部 TX 字段有效位
            rx_valid_b <= 1'b0;                             // 复位时屏蔽端口 B 的 RX 旧数据
            tx_valid_b <= 1'b0;                             // 复位时屏蔽端口 B 的 TX 旧数据
        end else begin                                      // 正常 TX 时钟周期
            if (wr_en_b) tx_initialized[addr_b] <= 1'b1;    // TX 完成一次写入后该条字段重新有效
            rx_valid_b <= rx_initialized[addr_b];           // RX 有效位与端口 B 的 RX 数据同拍
            tx_valid_b <= tx_initialized[addr_b];           // 有效位与 RAM 对同一地址采样
        end                                                 // 结束 TX 时钟周期
    end                                                     // 结束 TX 有效位维护
    assign rd_data_a = {tx_valid_a ? tx_word_a[63:16] : 48'd0,  // 端口 A 按各字段有效位屏蔽热复位残留
                        rx_valid_a ? rx_word_a[15:0] : 16'd0};  // 拼回原六十四位状态字
    assign rd_data_b = {tx_valid_b ? tx_word_b[63:16] : 48'd0,  // 端口 B 按各字段有效位屏蔽热复位残留
                        rx_valid_b ? rx_word_b[15:0] : 16'd0};  // 保持原一拍同步读取接口

    // ==================== 状态字布局 ====================
    // [7:0]   rx_last_sn    接收侧最近被接受的 SN（IC/RM 判重与乱序窗口的依据）
    // [8]     rx_sn_valid   该 VL 是否已收到过有效帧，0 时首帧无条件接受
    // [15:9]  reserved
    // [23:16] tx_sn         发送侧最近成功发送的 SN；首帧 0，随后 1..255 回绕
    // [24]    tx_sn_valid   发送侧 SN 是否已初始化
    // [25]    reserved
    // [63:32] tx_last_ts    上一帧发送时刻（系统时间戳低 32bit，用于 BAG 间隔整形）
    // 注：rd_en_a/rd_en_b 保留接口兼容；IP 持续读地址，M4K 读是同步的，读地址需提前一拍给出

endmodule                                                   // 模块定义结束

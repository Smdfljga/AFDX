// vl_config_ram : VL 静态配置表
// 设计期/加载期写入的静态配置：VLID、目的端口、端口类型、BAG、Lmax、RM 使能、IC 模式
// 端口 A 给 RX 状态机查表，端口 B 给 TX 状态机查表
// 寻址：地址 = vlid[VL_ADDR_WIDTH-1:0]（直接映射随机查表），读回的 tag 与帧内 VLID 比较判命中
// 注：运行期状态（PSN/SN/BAG 时间戳）放在 vl_state_ram，MIB 计数放在 mib_ram，
// 两者都不再和配置字挤在同一个存储字里（详见 REVIEW.md）
module vl_config_ram #(                                     // 声明模块及其参数接口
    parameter VLID_WIDTH    = 16,           // VLID 位宽
    parameter VL_ADDR_WIDTH = 12            // 地址位宽（深度 4096，必须与生成的 IP 一致）
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 端口 A（RX 查表） ====================
    input  wire                          clk_a,                  // 端口 A 时钟
    input  wire                          rst_a,                  // 端口 A 复位（高有效异步清零）
    input  wire [VL_ADDR_WIDTH-1:0]      addr_a,                 // 端口 A 读地址，VL 条目索引
    input  wire                          rd_en_a,                // 端口 A 读使能
    output wire [VLID_WIDTH-1:0]         tag_a,                  // 读回 VLID，与帧内解析出的 VLID 比对
    output wire                          valid_a,                // 条目有效标志，1=该 VL 已配置
    output wire [1:0]                    port_type_a,            // 端口类型：0=采样端口 1=队列端口
    output wire [15:0]                   udp_port_a,             // UDP 目的端口，用于端口过滤
    output wire [15:0]                   bag_a,                  // BAG，带宽分配间隔（接收侧用于监控）
    output wire [15:0]                   lmax_a,                 // Lmax，最大帧长；接收侧据此做长度检查
    output wire                          rm_en_a,                // RM 使能，1=该 VL 双网冗余
    output wire                          ic_mode_a,              // IC 模式：0=序列号检查 1=奇偶校验

    // ==================== 端口 B（TX 查表） ====================
    input  wire                          clk_b,                  // 端口 B 时钟
    input  wire                          rst_b,                  // 端口 B 复位（高有效异步清零）
    input  wire [VL_ADDR_WIDTH-1:0]      addr_b,                 // 端口 B 读地址，VL 条目索引
    input  wire                          rd_en_b,                // 端口 B 读使能
    output wire [VLID_WIDTH-1:0]         tag_b,                  // 读回 VLID
    output wire                          valid_b,                // 条目有效标志
    output wire [1:0]                    port_type_b,            // 端口类型
    output wire [15:0]                   udp_port_b,             // UDP 目的端口
    output wire [15:0]                   bag_b,                  // BAG，发送侧据此做发送间隔整形
    output wire [15:0]                   lmax_b,                 // Lmax，发送侧据此做分片与长度检查
    output wire                          rm_en_b,                // RM 使能
    output wire                          ic_mode_b,              // IC 模式

    // ==================== 配置写入（来自 config_wr） ====================
    input  wire                          cfg_wr_en,              // 配置写使能，单拍有效写一条
    input  wire [VL_ADDR_WIDTH-1:0]      cfg_wr_addr,            // 配置写地址
    input  wire [VLID_WIDTH-1:0]         cfg_wr_vlid,            // 配置 VLID
    input  wire [15:0]                   cfg_wr_udp_port,        // 配置 UDP 目的端口
    input  wire [1:0]                    cfg_wr_port_type,       // 配置端口类型
    input  wire [15:0]                   cfg_wr_bag,             // 配置 BAG
    input  wire [15:0]                   cfg_wr_lmax,            // 配置 Lmax
    input  wire                          cfg_wr_rm_en,           // 配置 RM 使能
    input  wire                          cfg_wr_ic_mode          // 配置 IC 模式
);                                                          // 端口声明或模块例化结束

    wire [127:0] q_a;                                           // 端口 A 读数据（128bit 配置字）
    wire [127:0] q_b;                                           // 端口 B 读数据（128bit 配置字）

    // 真双端口 M4K IP（128bit × 4096）：端口 A 供 RX 查表、写入走端口 A，端口 B 供 TX 查表
    // 由 eLinx 的 Local Memory IP 生成，固定 128 位宽 / 4096 深（12 位地址），
    // 所以 VL_ADDR_WIDTH 必须保持 12，改动前先确认 IP 已重新生成
    vl_config_ip u_vl_config_ip (                           // 例化子模块并连接数据通路
        .clock_a    (clk_a),                                    // input  [0:0]
        .aclr_a     (rst_a),                                    // input  [0:0]  高有效异步清零
        .address_a  (cfg_wr_en ? cfg_wr_addr : addr_a),         // input  [11:0] 写配置时用写地址，其余时间供 RX 查表
        // 写数据字段顺序与下方读侧解析一一对应，共 128bit
        .data_a     ({cfg_wr_vlid, 1'b1, cfg_wr_port_type, cfg_wr_udp_port,  // input [127:0] 连接子模块对应端口
                      cfg_wr_bag, cfg_wr_lmax, cfg_wr_rm_en, cfg_wr_ic_mode,  // 拼入 BAG、Lmax、RM 与完整性检查模式
                      59'd0}),                                  // input  [127:0]
        .wren_a     (cfg_wr_en),                                // input  [0:0]
        .q_a        (q_a),                                      // output [127:0]
        .clock_b    (clk_b),                                    // input  [0:0]
        .aclr_b     (rst_b),                                    // input  [0:0]
        .address_b  (addr_b),                                   // input  [11:0]
        .data_b     (128'd0),                                   // input  [127:0]
        .wren_b     (1'b0),                                     // input  [0:0]
        .q_b        (q_b)                                       // output [127:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== 配置字布局 ====================
    // [127:112] VLID   [111] valid   [110:109] port_type   [108:93] udp_port
    // [92:77]   BAG    [76:61] Lmax  [60] rm_en           [59] ic_mode
    // [58:0]    reserved（保留，后续加字段时从这里分配）
    assign tag_a       = q_a[127:112];                          // 端口 A：VLID
    assign valid_a     = q_a[111];                              // 端口 A：条目有效
    assign port_type_a = q_a[110:109];                          // 端口 A：端口类型
    assign udp_port_a  = q_a[108:93];                           // 端口 A：UDP 目的端口
    assign bag_a       = q_a[92:77];                            // 端口 A：BAG
    assign lmax_a      = q_a[76:61];                            // 端口 A：Lmax
    assign rm_en_a     = q_a[60];                               // 端口 A：RM 使能
    assign ic_mode_a   = q_a[59];                               // 端口 A：IC 模式

    assign tag_b       = q_b[127:112];                          // 端口 B：VLID
    assign valid_b     = q_b[111];                              // 端口 B：条目有效
    assign port_type_b = q_b[110:109];                          // 端口 B：端口类型
    assign udp_port_b  = q_b[108:93];                           // 端口 B：UDP 目的端口
    assign bag_b       = q_b[92:77];                            // 端口 B：BAG
    assign lmax_b      = q_b[76:61];                            // 端口 B：Lmax
    assign rm_en_b     = q_b[60];                               // 端口 B：RM 使能
    assign ic_mode_b   = q_b[59];                               // 端口 B：IC 模式

endmodule                                                   // 模块定义结束

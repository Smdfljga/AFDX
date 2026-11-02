// afdx_vl_cfg : VL 配置模块
// 把 VL 相关的三张表和配置写入逻辑收在一起，顶层只挂这一个模块：
// config_wr       配置写入时序
// vl_config_ram   静态配置表（VLID/端口/BAG/Lmax/RM/IC）
// vl_state_ram    运行期状态表（PSN/SN/BAG 时间戳）
// mib_ram ×2      RX/TX 每 VL 计数（SNMP 查询，RX/TX 状态机累加）
// 对外只提供：配置写入口、RX/TX 两张表的读口、状态表读写口、计数事件口、MIB 读口
module afdx_vl_cfg #(                                       // 声明模块及其参数接口
    parameter VLID_WIDTH    = 16,           // VLID 位宽
    parameter VL_ADDR_WIDTH = 12,           // VL 表地址位宽（三张表同一索引，4096 条）
    parameter VL_INDEX_WIDTH = 4,           // 端口缓冲槽位号位宽（供 TX 做槽位→VLID 映射）
    parameter CNT_WIDTH     = 32,           // MIB 计数器位宽
    parameter STATE_WIDTH   = 64            // VL 运行期状态字位宽
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 配置写入口（外部 CPU） ====================
    input  wire                          cfg_wr_en,              // 配置写使能，单拍有效写一条 VL
    input  wire [VL_ADDR_WIDTH-1:0]      cfg_wr_addr,            // 配置写地址，VL 表条目索引
    input  wire [VLID_WIDTH-1:0]         cfg_wr_vlid,            // 配置写入的 VLID
    input  wire [15:0]                   cfg_wr_udp_port,        // 配置项：UDP 目的端口
    input  wire [1:0]                    cfg_wr_port_type,       // 配置项：端口类型（0=采样 1=队列）
    input  wire [15:0]                   cfg_wr_bag,             // 配置项：BAG，带宽分配间隔
    input  wire [15:0]                   cfg_wr_lmax,            // 配置项：Lmax，最大帧长（字节）
    input  wire                          cfg_wr_rm_en,           // 配置项：冗余管理使能
    input  wire                          cfg_wr_ic_mode,         // 配置项：完整性检查模式
    output wire                          cfg_done,               // 配置完成，全部条目写完后拉高

    // ==================== RX 侧配置表读口 ====================
    input  wire [VL_ADDR_WIDTH-1:0]      rx_cfg_addr,            // RX 查表地址
    input  wire                          rx_cfg_rd_en,           // RX 查表读使能
    output wire [VLID_WIDTH-1:0]         rx_cfg_tag,             // 读回 VLID，用于判断查表命中
    output wire                          rx_cfg_valid,           // 条目有效标志
    output wire [1:0]                    rx_cfg_port_type,       // 端口类型
    output wire [15:0]                   rx_cfg_udp_port,        // UDP 目的端口
    output wire [15:0]                   rx_cfg_bag,             // BAG
    output wire [15:0]                   rx_cfg_lmax,            // Lmax，接收侧帧长检查依据
    output wire                          rx_cfg_rm_en,           // RM 使能
    output wire                          rx_cfg_ic_mode,         // IC 模式

    // ==================== TX 侧配置表读口 ====================
    input  wire [VL_ADDR_WIDTH-1:0]      tx_cfg_addr,            // TX 查表地址
    input  wire                          tx_cfg_rd_en,           // TX 查表读使能
    output wire [VLID_WIDTH-1:0]         tx_cfg_tag,             // 读回 VLID
    output wire                          tx_cfg_valid,           // 条目有效标志
    output wire [1:0]                    tx_cfg_port_type,       // 端口类型
    output wire [15:0]                   tx_cfg_udp_port,        // UDP 目的端口
    output wire [15:0]                   tx_cfg_bag,             // BAG，发送整形依据
    output wire [15:0]                   tx_cfg_lmax,            // Lmax，分片依据
    output wire                          tx_cfg_rm_en,           // RM 使能

    // ==================== RX 侧状态表读写口 ====================
    input  wire [VL_ADDR_WIDTH-1:0]      rx_st_addr,             // 状态表地址
    input  wire                          rx_st_rd_en,            // 状态读使能（帧首读 PSN）
    output wire [STATE_WIDTH-1:0]        rx_st_rd_data,          // 状态读数据
    input  wire                          rx_st_wr_en,            // 状态写使能（帧尾写回）
    input  wire [STATE_WIDTH-1:0]        rx_st_wr_data,          // 状态写数据

    // ==================== TX 侧状态表读写口 ====================
    input  wire [VL_ADDR_WIDTH-1:0]      tx_st_addr,             // 状态表地址
    input  wire                          tx_st_rd_en,            // 状态读使能
    output wire [STATE_WIDTH-1:0]        tx_st_rd_data,          // 状态读数据
    input  wire                          tx_st_wr_en,            // 状态写使能
    input  wire [STATE_WIDTH-1:0]        tx_st_wr_data,          // 状态写数据

    // ==================== RX 侧 MIB 计数事件 ====================
    input  wire [VL_ADDR_WIDTH-1:0]      rx_mib_addr,            // 计数事件所属 VL 索引
    input  wire                          mib_rx_frame_inc,       // 接收成功帧数 +1
    input  wire                          mib_rx_error_inc,       // 接收错误帧数 +1
    input  wire                          mib_sn_error_inc,       // SN 错误帧数 +1
    input  wire                          mib_rm_drop_inc,        // RM 重复帧丢弃数 +1
    input  wire                          mib_rx_byte_inc,        // 接收字节数 +1

    // ==================== TX 侧 MIB 计数事件 ====================
    input  wire [VL_ADDR_WIDTH-1:0]      tx_mib_addr,            // 计数事件所属 VL 索引
    input  wire                          mib_tx_frame_inc,       // 发送成功帧数 +1
    input  wire                          mib_tx_byte_inc,        // 发送字节数 +1
    input  wire                          mib_tx_error_inc,       // 发送错误帧数 +1
    input  wire                          mib_tx_frag_inc,        // 超 Lmax 被丢弃帧数 +1
    input  wire                          mib_tx_bag_inc,         // BAG 违反次数 +1

    // ==================== MIB 读口（SNMP 查询） ====================
    input  wire                          mib_sel,                // 0=读 RX 计数表 1=读 TX 计数表
    input  wire [VL_ADDR_WIDTH-1:0]      mib_rd_addr,            // 要查询的 VL 条目索引
    input  wire                          mib_rd_en,              // MIB 读使能
    output wire [5*CNT_WIDTH-1:0]        mib_rd_data,            // 读回的 5 个计数器

    // ==================== TX 侧槽位到 VLID 映射 ====================
    // 发送调度只拿到 4bit 槽位号，这里把配置写入时的完整 VLID 按低 4bit 建一张 16 项映射表。
    output wire [(1<<VL_INDEX_WIDTH)*VLID_WIDTH-1:0] slot_vlid   // 每槽位对应的完整 VLID
);                                                          // 端口声明或模块例化结束

    wire                      bram_wr_en;                       // 配置表写使能（config_wr 输出）
    wire [VL_ADDR_WIDTH-1:0]  bram_wr_addr;                     // 配置表写地址
    wire [5*CNT_WIDTH-1:0]    mib_rx_rd_data;                   // RX 计数表读数据
    wire [5*CNT_WIDTH-1:0]    mib_tx_rd_data;                   // TX 计数表读数据

    reg [(1<<VL_INDEX_WIDTH)*VLID_WIDTH-1:0] slot_vlid_r;        // 槽位→VLID 映射寄存器
    integer slot_i;                                             // 复位遍历映射表

    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            for (slot_i = 0; slot_i < (1<<VL_INDEX_WIDTH); slot_i = slot_i + 1)  // 依次处理指定范围内的表项或位段
                slot_vlid_r[slot_i*VLID_WIDTH +: VLID_WIDTH] <= {VLID_WIDTH{1'b0}};  // 时钟沿更新槽位→VLID 映射寄存器
        end                                                 // 当前语句组结束
        else if (cfg_wr_en && (cfg_wr_vlid != 16'hFFFF)) begin  // 检查配置写使能、配置写入的 VLID的条件
            slot_vlid_r[cfg_wr_vlid[VL_INDEX_WIDTH-1:0]*VLID_WIDTH +: VLID_WIDTH] <= cfg_wr_vlid;  // 继续计算slot_vlid_r
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束
    assign slot_vlid = slot_vlid_r;                             // output [255:0]

    // ==================== 配置写入例化 ====================
    config_wr #(                                            // 例化子模块并连接数据通路
        .VLID_WIDTH    (VLID_WIDTH),                        // 连接子模块对应端口
        .VL_ADDR_WIDTH (VL_ADDR_WIDTH)                      // 连接子模块对应端口
    ) u_config_wr (                                         // 参数绑定结束，开始连接实例端口
        .clk             (clk),                                // input  [0:0]
        .rst_b           (rst_b),                              // input  [0:0]
        .cfg_wr_en       (cfg_wr_en),                          // input  [0:0]
        .cfg_wr_addr     (cfg_wr_addr),                        // input  [11:0]
        .cfg_wr_vlid     (cfg_wr_vlid),                        // input  [15:0]
        .cfg_wr_udp_port (cfg_wr_udp_port),                    // input  [15:0]
        .cfg_wr_port_type(cfg_wr_port_type),                   // input  [1:0]
        .cfg_wr_bag      (cfg_wr_bag),                         // input  [15:0]
        .cfg_wr_lmax     (cfg_wr_lmax),                        // input  [15:0]
        .cfg_wr_rm_en    (cfg_wr_rm_en),                       // input  [0:0]
        .cfg_wr_ic_mode  (cfg_wr_ic_mode),                     // input  [0:0]
        .bram_wr_en      (bram_wr_en),                         // output [0:0]
        .bram_wr_addr    (bram_wr_addr),                       // output [11:0]
        .cfg_done        (cfg_done)                            // output [0:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== VL 静态配置表例化 ====================
    vl_config_ram #(                                        // 例化子模块并连接数据通路
        .VLID_WIDTH    (VLID_WIDTH),                        // 连接子模块对应端口
        .VL_ADDR_WIDTH (VL_ADDR_WIDTH)                      // 连接子模块对应端口
    ) u_vl_config_ram (                                     // 参数绑定结束，开始连接实例端口
        .clk_a           (clk),                                // input  [0:0]
        .rst_a           (~rst_b),                             // input  [0:0]  M4K aclr 高有效
        .addr_a          (rx_cfg_addr),                        // input  [11:0]
        .rd_en_a         (rx_cfg_rd_en),                       // input  [0:0]
        .tag_a           (rx_cfg_tag),                         // output [15:0]
        .valid_a         (rx_cfg_valid),                       // output [0:0]
        .port_type_a     (rx_cfg_port_type),                   // output [1:0]
        .udp_port_a      (rx_cfg_udp_port),                    // output [15:0]
        .bag_a           (rx_cfg_bag),                         // output [15:0]
        .lmax_a          (rx_cfg_lmax),                        // output [15:0]
        .rm_en_a         (rx_cfg_rm_en),                       // output [0:0]
        .ic_mode_a       (rx_cfg_ic_mode),                     // output [0:0]
        .clk_b           (clk),                                // input  [0:0]
        .rst_b           (~rst_b),                             // input  [0:0]  M4K aclr 高有效
        .addr_b          (tx_cfg_addr),                        // input  [11:0]
        .rd_en_b         (tx_cfg_rd_en),                       // input  [0:0]
        .tag_b           (tx_cfg_tag),                         // output [15:0]
        .valid_b         (tx_cfg_valid),                       // output [0:0]
        .port_type_b     (tx_cfg_port_type),                   // output [1:0]
        .udp_port_b      (tx_cfg_udp_port),                    // output [15:0]
        .bag_b           (tx_cfg_bag),                         // output [15:0]
        .lmax_b          (tx_cfg_lmax),                        // output [15:0]
        .rm_en_b         (tx_cfg_rm_en),                       // output [0:0]
        .ic_mode_b       (),                                   // output [0:0]  发送侧不用 IC 模式
        .cfg_wr_en       (bram_wr_en),                         // input  [0:0]
        .cfg_wr_addr     (bram_wr_addr),                       // input  [11:0]
        .cfg_wr_vlid     (cfg_wr_vlid),                        // input  [15:0]
        .cfg_wr_udp_port (cfg_wr_udp_port),                    // input  [15:0]
        .cfg_wr_port_type(cfg_wr_port_type),                   // input  [1:0]
        .cfg_wr_bag      (cfg_wr_bag),                         // input  [15:0]
        .cfg_wr_lmax     (cfg_wr_lmax),                        // input  [15:0]
        .cfg_wr_rm_en    (cfg_wr_rm_en),                       // input  [0:0]
        .cfg_wr_ic_mode  (cfg_wr_ic_mode)                      // input  [0:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== VL 运行期状态表例化 ====================
    vl_state_ram #(                                         // 例化子模块并连接数据通路
        .VL_ADDR_WIDTH (VL_ADDR_WIDTH),                     // 连接子模块对应端口
        .STATE_WIDTH   (STATE_WIDTH)                        // 连接子模块对应端口
    ) u_vl_state_ram (                                      // 参数绑定结束，开始连接实例端口
        .clk_a      (clk),                                     // input  [0:0]
        .rst_a      (~rst_b),                                  // input  [0:0]  M4K aclr 高有效
        .addr_a     (rx_st_addr),                              // input  [11:0]
        .rd_en_a    (rx_st_rd_en),                             // input  [0:0]
        .rd_data_a  (rx_st_rd_data),                           // output [63:0]
        .wr_en_a    (rx_st_wr_en),                             // input  [0:0]
        .wr_data_a  (rx_st_wr_data),                           // input  [63:0]
        .clk_b      (clk),                                     // input  [0:0]
        .rst_b      (~rst_b),                                  // input  [0:0]  M4K aclr 高有效
        .addr_b     (tx_st_addr),                              // input  [11:0]
        .rd_en_b    (tx_st_rd_en),                             // input  [0:0]
        .rd_data_b  (tx_st_rd_data),                           // output [63:0]
        .wr_en_b    (tx_st_wr_en),                             // input  [0:0]
        .wr_data_b  (tx_st_wr_data)                            // input  [63:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== RX MIB 计数表例化 ====================
    // 计数器语义：cnt0=接收成功帧数 cnt1=接收错误帧数 cnt2=SN 错误帧数 cnt3=RM 丢弃帧数 cnt4=接收字节数
    mib_ram #(                                              // 例化子模块并连接数据通路
        .CNT_WIDTH  (CNT_WIDTH),                            // 连接子模块对应端口
        .ADDR_WIDTH (VL_ADDR_WIDTH),                        // 连接子模块对应端口
        .IS_RX      (1'b1)                                  // 连接子模块对应端口
    ) u_mib_rx (                                            // 参数绑定结束，开始连接实例端口
        .clk        (clk),                                     // input  [0:0]
        .rst_b      (rst_b),                                   // input  [0:0]
        .inc_addr   (rx_mib_addr),                             // input  [11:0]
        .cnt0_inc   (mib_rx_frame_inc),                        // input  [0:0]
        .cnt1_inc   (mib_rx_error_inc),                        // input  [0:0]
        .cnt2_inc   (mib_sn_error_inc),                        // input  [0:0]
        .cnt3_inc   (mib_rm_drop_inc),                         // input  [0:0]
        .cnt4_inc   (mib_rx_byte_inc),                         // input  [0:0]
        .rd_addr    (mib_rd_addr),                             // input  [11:0]
        .rd_en      (mib_rd_en),                               // input  [0:0]  两张表都读，输出端再按表选择取用
        .rd_data    (mib_rx_rd_data)                           // output [159:0]
    );                                                      // 端口声明或模块例化结束

    // ==================== TX MIB 计数表例化 ====================
    // 计数器语义：cnt0=发送成功帧数 cnt1=发送字节数（应用数据字节）cnt2=发送错误帧数
    // cnt3=超过 Lmax 被丢弃的帧数（原名"分片次数"：不分片后语义变更）cnt4=BAG 违反次数
    mib_ram #(                                              // 例化子模块并连接数据通路
        .CNT_WIDTH  (CNT_WIDTH),                            // 连接子模块对应端口
        .ADDR_WIDTH (VL_ADDR_WIDTH),                        // 连接子模块对应端口
        .IS_RX      (1'b0)                                  // 连接子模块对应端口
    ) u_mib_tx (                                            // 参数绑定结束，开始连接实例端口
        .clk        (clk),                                     // input  [0:0]
        .rst_b      (rst_b),                                   // input  [0:0]
        .inc_addr   (tx_mib_addr),                             // input  [11:0]
        .cnt0_inc   (mib_tx_frame_inc),                        // input  [0:0]
        .cnt1_inc   (mib_tx_byte_inc),                         // input  [0:0]
        .cnt2_inc   (mib_tx_error_inc),                        // input  [0:0]
        .cnt3_inc   (mib_tx_frag_inc),                         // input  [0:0]
        .cnt4_inc   (mib_tx_bag_inc),                          // input  [0:0]
        .rd_addr    (mib_rd_addr),                             // input  [11:0]
        .rd_en      (mib_rd_en),                               // input  [0:0]  两张表都读，输出端再按表选择取用
        .rd_data    (mib_tx_rd_data)                           // output [159:0]
    );                                                      // 端口声明或模块例化结束

    assign mib_rd_data = mib_sel ? mib_tx_rd_data : mib_rx_rd_data;  // RX/TX 计数表二选一

endmodule                                                   // 模块定义结束

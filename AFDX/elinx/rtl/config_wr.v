// config_wr : VL 配置写入控制
// 把外部逐条送入的配置（VLID/端口/BAG/Lmax/RM 等）转换成配置表写时序，
// 全部条目写完后给出 cfg_done
// 实现约定（详见 doc/modules/03_afdx_vl_cfg.md）：
// - 写地址 = cfg_wr_vlid[VL_ADDR_WIDTH-1:0]（直接映射），cfg_wr_addr 端口保留
// - 哨兵：写入 cfg_wr_vlid == 16'hFFFF 表示配置结束，该次不落表，只给 cfg_done
module config_wr #(                                         // 声明模块及其参数接口
    parameter VLID_WIDTH    = 16,           // VLID 位宽
    parameter VL_ADDR_WIDTH = 12            // VL 配置表地址位宽（IP 已生成 4096 深）
)(                                                          // 参数声明结束，开始端口声明
    // 时钟与复位
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // 来自外部的配置写请求
    input  wire                          cfg_wr_en,              // 配置写使能，单拍有效
    input  wire [VL_ADDR_WIDTH-1:0]      cfg_wr_addr,            // 配置写地址（软件给值应等于 vlid 低位，实现可直接用 vlid 低位）
    input  wire [VLID_WIDTH-1:0]         cfg_wr_vlid,            // 配置写入的 VLID
    input  wire [15:0]                   cfg_wr_udp_port,        // 配置项：UDP 目的端口
    input  wire [1:0]                    cfg_wr_port_type,       // 配置项：端口类型
    input  wire [15:0]                   cfg_wr_bag,             // 配置项：BAG
    input  wire [15:0]                   cfg_wr_lmax,            // 配置项：Lmax
    input  wire                          cfg_wr_rm_en,           // 配置项：RM 使能
    input  wire                          cfg_wr_ic_mode,         // 配置项：完整性检查模式

    // 配置表 BRAM 写端口
    output wire                          bram_wr_en,             // BRAM 写使能
    output wire [VL_ADDR_WIDTH-1:0]      bram_wr_addr,           // BRAM 写地址

    // 状态
    output wire                          cfg_done                // 配置完成，全部条目写完
);                                                          // 端口声明或模块例化结束

    // ==================== 配置完成哨兵 ====================
    wire is_sentinel = cfg_wr_en && (cfg_wr_vlid == 16'hFFFF);   // 哨兵 VLID：只结束配置，不写表

    reg done_r;                                                 // 配置完成锁存，哨兵后保持到复位或重新配置
    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b)                                         // 检查复位或正常运行条件
            done_r <= 1'b0;                                 // 时钟沿更新配置完成锁存
        else if (is_sentinel)                               // 检查哨兵 VLID：只结束配置的条件
            done_r <= 1'b1;                                 // 时钟沿更新配置完成锁存
    end                                                     // 当前语句组结束

    // ==================== 直接映射写地址 ====================
    // 软件可能同时给 cfg_wr_addr，但为与 afdx.xlsx 的“地址 = vlid 低位”一致，这里固定用 VLID 生成。
    wire [VL_ADDR_WIDTH-1:0] wr_addr = cfg_wr_vlid[VL_ADDR_WIDTH-1:0];  // 配置写地址直接取完整 VLID 的低位，与收发表寻址一致

    assign bram_wr_en   = cfg_wr_en & ~is_sentinel;             // output [0:0]：哨兵不落表
    assign bram_wr_addr = wr_addr;                              // output [11:0]：VL 表条目索引
    assign cfg_done     = done_r | is_sentinel;                 // output [0:0]：哨兵当拍与之后均有效

endmodule                                                   // 模块定义结束

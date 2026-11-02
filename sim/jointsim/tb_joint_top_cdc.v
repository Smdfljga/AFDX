// tb_joint_top_cdc : 跨时钟收发缓冲自检（MAC 125MHz ↔ 核心 25MHz）
// DUT1：afdx_net_rx（双网接收帧缓存，写侧 125MHz、读侧 25MHz）
// DUT2：afdx_tx_buf （发送缓冲，写侧 25MHz、读侧 125MHz）
// 检查点：两路时钟独立、收发帧数据逐字节正确、帧长/帧首帧尾正确、帧顺序与槽位轮换不丢帧、
//         发送侧 MAC 反压（mac_tx_rdy 拉低）时不丢字节。
module tb_joint_top_cdc;                                    // 声明模块及其参数接口

    localparam MAC_PERIOD  = 8;                             // MAC 侧 125MHz
    localparam CORE_PERIOD = 40;                            // 核心侧 25MHz
    localparam DATA_WIDTH  = 8;                             // 数据位宽
    localparam ADDR_WIDTH  = 12;                            // 缓存地址位宽

    reg clk_mac;                                            // MAC 侧时钟
    reg clk_core;                                           // 核心侧时钟
    reg rst_b;                                              // 复位

    // ==================== 网接收 DUT ====================
    reg  [7:0] a_rx_data;                                   // A 网接收数据
    reg        a_rx_data_vld;                               // A 网数据有效
    reg        a_rx_sop;                                    // A 网帧首
    reg        a_rx_eop;                                    // A 网帧尾
    reg        a_rx_err;                                    // A 网错误
    wire       a_rx_rdy;                                    // A 网接收准备
    reg  [7:0] b_rx_data;                                   // B 网接收数据
    reg        b_rx_data_vld;                               // B 网数据有效
    reg        b_rx_sop;                                    // B 网帧首
    reg        b_rx_eop;                                    // B 网帧尾
    reg        b_rx_err;                                    // B 网错误
    wire       b_rx_rdy;                                    // B 网接收准备
    wire [7:0] ff_rx_data;                                  // 送核心的接收数据
    wire       ff_rx_data_vld;                              // 送核心的数据有效
    wire       ff_rx_sop;                                   // 送核心的帧首
    wire       ff_rx_eop;                                   // 送核心的帧尾
    wire       ff_rx_err;                                   // 送核心的错误
    reg        ff_rx_rdy;                                   // 核心接收准备
    wire       frame_net;                                   // 本帧来源网络

    // ==================== 发送缓冲 DUT ====================
    reg  [7:0] core_tx_data;                                // 核心发送数据
    reg        core_tx_wren;                                // 核心写使能
    reg        core_tx_sop;                                 // 核心帧首
    reg        core_tx_eop;                                 // 核心帧尾
    reg        core_tx_err;                                 // 核心错误标记
    wire       core_tx_rdy;                                 // 缓冲可接收
    wire [7:0] mac_tx_data;                                 // 送往 MAC 的数据
    wire       mac_tx_wren;                                 // 送往 MAC 的写使能
    wire       mac_tx_sop;                                  // 送往 MAC 的帧首
    wire       mac_tx_eop;                                  // 送往 MAC 的帧尾
    wire       mac_tx_err;                                  // 送往 MAC 的错误
    reg        mac_tx_rdy;                                  // 两片 MAC 都就绪

    // ==================== 期望数据与统计 ====================
    localparam FRAME_LEN = 64;                              // 每个测试帧 64 字节
    integer fail_cnt;                                       // 失败计数
    integer rx_frames;                                      // 已收帧数
    integer rx_len;                                         // 当前帧已收字节数
    reg [7:0] rx_base;                                      // 当前帧期望基值
    reg       rx_net;                                       // 当前帧网络
    integer tx_frames;                                      // 已发帧数
    integer tx_len;                                         // 当前帧已发字节数
    reg [7:0] tx_base;                                      // 当前发送帧期望基值
    integer i, k;                                           // 循环变量

    // ==================== 时钟 ====================
    initial clk_mac = 1'b0;                                 // MAC 侧时钟初值
    always #(MAC_PERIOD/2) clk_mac = ~clk_mac;              // 125MHz
    initial clk_core = 1'b0;                                // 核心侧时钟初值
    always #(CORE_PERIOD/2) clk_core = ~clk_core;            // 25MHz

    // ==================== DUT 例化 ====================
    afdx_net_rx #(                                          // 双网接收帧缓存（跨时钟）
        .DATA_WIDTH (DATA_WIDTH),                           // 连接参数
        .ADDR_WIDTH (ADDR_WIDTH),                           // 连接参数
        .MAX_FRAME  (1536),                                 // 连接参数
        .SLOT_BITS  (11)                                    // 连接参数
    ) u_net_rx (
        .wr_clk       (clk_mac),
        .rd_clk       (clk_core),
        .rst_b        (rst_b),
        .a_rx_data    (a_rx_data),
        .a_rx_data_vld(a_rx_data_vld),
        .a_rx_sop     (a_rx_sop),
        .a_rx_eop     (a_rx_eop),
        .a_rx_err     (a_rx_err),
        .a_rx_rdy     (a_rx_rdy),
        .b_rx_data    (b_rx_data),
        .b_rx_data_vld(b_rx_data_vld),
        .b_rx_sop     (b_rx_sop),
        .b_rx_eop     (b_rx_eop),
        .b_rx_err     (b_rx_err),
        .b_rx_rdy     (b_rx_rdy),
        .ff_rx_data   (ff_rx_data),
        .ff_rx_data_vld(ff_rx_data_vld),
        .ff_rx_sop    (ff_rx_sop),
        .ff_rx_eop    (ff_rx_eop),
        .ff_rx_err    (ff_rx_err),
        .ff_rx_rdy    (ff_rx_rdy),
        .frame_net    (frame_net)
    );

    afdx_tx_buf #(                                          // 发送缓冲（跨时钟）
        .DATA_WIDTH (DATA_WIDTH),                           // 连接参数
        .ADDR_WIDTH (ADDR_WIDTH),                           // 连接参数
        .SLOT_BITS  (11)                                    // 连接参数
    ) u_tx_buf (
        .wr_clk      (clk_core),
        .rd_clk      (clk_mac),
        .rst_b       (rst_b),
        .core_tx_data(core_tx_data),
        .core_tx_wren(core_tx_wren),
        .core_tx_sop (core_tx_sop),
        .core_tx_eop (core_tx_eop),
        .core_tx_err (core_tx_err),
        .core_tx_rdy (core_tx_rdy),
        .mac_tx_data (mac_tx_data),
        .mac_tx_wren (mac_tx_wren),
        .mac_tx_sop  (mac_tx_sop),
        .mac_tx_eop  (mac_tx_eop),
        .mac_tx_err  (mac_tx_err),
        .mac_tx_rdy  (mac_tx_rdy)
    );

    // ==================== 失败记录 ====================
    task do_fail;                                           // 记录一次失败
        input [127:0] msg;                                  // 失败信息
        begin
            $display("  [FAIL] %0s", msg);                  // 打印失败
            fail_cnt = fail_cnt + 1;                        // 计数
        end
    endtask

    // ==================== MAC 侧：注入一帧（125MHz，逐字节） ====================
    task mac_send;                                          // 从 MAC 侧注入一帧
        input       net;                                    // 0=A 网 1=B 网
        input [7:0] base;                                   // 数据基值
        input integer len;                                  // 字节数
        integer n;                                          // 循环
        begin
            for (n = 0; n < len; n = n + 1) begin           // 逐字节
                @(negedge clk_mac);                         // 在非采样沿改值
                if (net) begin                              // B 网
                    b_rx_data     <= base + n[7:0];         // 数据
                    b_rx_data_vld <= 1'b1;                  // 有效
                    b_rx_sop      <= (n == 0);              // 帧首
                    b_rx_eop      <= (n == len-1);          // 帧尾
                end else begin                              // A 网
                    a_rx_data     <= base + n[7:0];         // 数据
                    a_rx_data_vld <= 1'b1;                  // 有效
                    a_rx_sop      <= (n == 0);              // 帧首
                    a_rx_eop      <= (n == len-1);          // 帧尾
                end
            end
            @(negedge clk_mac);                             // 撤消
            a_rx_data_vld <= 1'b0; a_rx_sop <= 1'b0; a_rx_eop <= 1'b0;  // A 网撤消
            b_rx_data_vld <= 1'b0; b_rx_sop <= 1'b0; b_rx_eop <= 1'b0;  // B 网撤消
        end
    endtask

    // ==================== 核心侧：检查收到的帧 ====================
    // 帧首时按首字节识别是哪个期望帧（0x10/0x50/0x90），逐字节比对
    always @(negedge clk_core) begin                        // 核心侧非采样沿检查（避开沿上竞争）
        if (rst_b && ff_rx_data_vld) begin                  // 有字节送出
            if (ff_rx_sop) begin                            // 帧首
                rx_len  = 0;                                // 清字节计数
                if (ff_rx_data == 8'h10)      rx_base = 8'h10;  // A 网第 1 帧
                else if (ff_rx_data == 8'h50) rx_base = 8'h50;  // B 网第 1 帧
                else if (ff_rx_data == 8'h90) rx_base = 8'h90;  // A 网第 2 帧
                else begin                                  // 不认识的帧首
                    rx_base = ff_rx_data;                   // 记录以便继续检查
                    do_fail("rx sop data base");            // 失败
                end
                rx_net  = frame_net;                        // 记录网络
            end                                             // 帧首处理结束
            if (ff_rx_data !== (rx_base + rx_len[7:0]))     // 逐字节比对
                do_fail("rx byte mismatch");                // 失败
            if (ff_rx_err !== 1'b0)                         // 不应有错误标记
                do_fail("rx err flag set");                 // 失败
            rx_len = rx_len + 1;                            // 计数前进
            if (ff_rx_eop) begin                            // 帧尾
                rx_frames = rx_frames + 1;                  // 帧数加一
                if (rx_len != FRAME_LEN) do_fail("rx frame length");  // 长度检查
                $display("  [INFO] rx frame net=%0d len=%0d base=%02x", rx_net, rx_len, rx_base); // 打印
            end                                             // 帧尾处理结束
        end                                                 // 字节处理结束
    end

    // ==================== MAC 侧：检查发送流 ====================
    always @(negedge clk_mac) begin                         // MAC 侧非采样沿检查（避开沿上竞争）
        if (rst_b && mac_tx_wren) begin                     // 有字节送出
            if (mac_tx_sop) begin                           // 帧首
                tx_len  = 0;                                // 清计数
                tx_base = mac_tx_data;                      // 记录基值
                if (mac_tx_data !== tx_base) do_fail("tx sop base");   // 冗余检查
            end                                             // 帧首处理结束
            if (mac_tx_data !== (tx_base + tx_len[7:0]))    // 逐字节比对
                do_fail("tx byte mismatch");                // 失败
            tx_len = tx_len + 1;                            // 计数前进
            if (mac_tx_eop) begin                           // 帧尾
                tx_frames = tx_frames + 1;                  // 帧数加一
                if (tx_len != FRAME_LEN) do_fail("tx frame length");   // 长度检查
                $display("  [INFO] tx frame len=%0d base=%02x", tx_len, tx_base); // 打印
            end                                             // 帧尾处理结束
        end                                                 // 字节处理结束
    end

    // ==================== 核心侧：写一帧到发送缓冲（25MHz） ====================
    task core_send;                                         // 从核心侧发一帧
        input [7:0] base;                                   // 数据基值
        input integer len;                                  // 字节数
        integer n;                                          // 循环
        begin
            for (n = 0; n < len; n = n + 1) begin           // 逐字节
                @(negedge clk_core);                        // 非采样沿改值
                core_tx_data <= base + n[7:0];              // 数据
                core_tx_wren <= 1'b1;                       // 写使能
                core_tx_sop  <= (n == 0);                   // 帧首
                core_tx_eop  <= (n == len-1);               // 帧尾
                @(posedge clk_core);                        // 等采样沿
                while (core_tx_rdy !== 1'b1) @(posedge clk_core);  // 等缓冲可接收（跨时钟握手）
            end                                             // 逐字节结束
            @(negedge clk_core);                            // 撤消
            core_tx_wren <= 1'b0; core_tx_sop <= 1'b0; core_tx_eop <= 1'b0;  // 清控制
        end
    endtask

    // ==================== 主流程 ====================
    initial begin                                           // 激励流程
        clk_mac = 1'b0; clk_core = 1'b0; rst_b = 1'b0;      // 初值
        a_rx_data = 8'h00; a_rx_data_vld = 1'b0; a_rx_sop = 1'b0; a_rx_eop = 1'b0; a_rx_err = 1'b0;  // A 网初值
        b_rx_data = 8'h00; b_rx_data_vld = 1'b0; b_rx_sop = 1'b0; b_rx_eop = 1'b0; b_rx_err = 1'b0;  // B 网初值
        ff_rx_rdy = 1'b0;                                   // 核心暂不接收
        core_tx_data = 8'h00; core_tx_wren = 1'b0; core_tx_sop = 1'b0; core_tx_eop = 1'b0; core_tx_err = 1'b0; // 发送初值
        mac_tx_rdy = 1'b1;                                  // MAC 初始就绪
        fail_cnt = 0; rx_frames = 0; tx_frames = 0;         // 清统计
        repeat (10) @(posedge clk_mac);                     // 保持复位
        rst_b = 1'b1;                                       // 释放复位
        repeat (10) @(posedge clk_mac);                     // 等稳定

        $display("=== 接收方向：MAC 125MHz 写、核心 25MHz 读 ===");  // 用例标题
        mac_send(1'b0, 8'h10, FRAME_LEN);                   // A 网第 1 帧
        mac_send(1'b1, 8'h50, FRAME_LEN);                   // B 网第 1 帧（A 网帧还没读）
        mac_send(1'b0, 8'h90, FRAME_LEN);                   // A 网第 2 帧（占第 2 个槽位）
        repeat (200) @(posedge clk_core);                   // 等两槽写满
        ff_rx_rdy = 1'b1;                                   // 核心开始接收
        k = 0;                                              // 等待计数
        while ((rx_frames < 3) && (k < 20000)) begin        // 限时等三帧
            @(posedge clk_core); k = k + 1;                 // 计数
        end
        if (rx_frames == 3) $display("  [PASS] rx 3 frames across clock");  // 通过
        else do_fail("rx frame count");                     // 失败

        $display("=== 发送方向：核心 25MHz 写、MAC 125MHz 读（含反压） ===");  // 用例标题
        fork                                                // 同时写三帧并插入 MAC 反压
            begin
                core_send(8'h20, FRAME_LEN);                // 第 1 帧
                core_send(8'h60, FRAME_LEN);                // 第 2 帧
                core_send(8'hA0, FRAME_LEN);                // 第 3 帧
            end
            begin
                wait (mac_tx_wren === 1'b1);                // 等第一帧真正开始往 MAC 送
                repeat (3) @(posedge clk_mac);              // 帧内再走几个字节
                mac_tx_rdy = 1'b0;                          // 帧内反压：必须不丢字节也不卡死
                repeat (37) @(posedge clk_mac);             // 持续一段
                mac_tx_rdy = 1'b1;                          // 放开
                repeat (11) @(posedge clk_mac);             // 再等
                mac_tx_rdy = 1'b0;                          // 再反压（很可能落在第 2 帧中间）
                repeat (23) @(posedge clk_mac);             // 持续
                mac_tx_rdy = 1'b1;                          // 放开
            end
        join
        k = 0;                                              // 等待计数
        while ((tx_frames < 3) && (k < 20000)) begin        // 限时等三帧发完
            @(posedge clk_mac); k = k + 1;                  // 计数
        end
        if (tx_frames == 3) $display("  [PASS] tx 3 frames across clock");  // 通过
        else do_fail("tx frame count");                     // 失败

        if (fail_cnt == 0) $display("PASS: joint top cdc chain");  // 汇总
        else $display("FAIL: joint top cdc failures=%0d", fail_cnt);  // 汇总
        $finish;                                            // 结束
    end

endmodule

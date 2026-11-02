// tb_afdx_net_rx : 双网接收帧缓存自检（跨时钟：MAC 侧 125MHz 写、核心侧 25MHz 读）
// 检查点：两网整帧与网络标记、核心未就绪时不送字节、每网 2 槽位乒乓、
//         两槽占满时第 3 帧整帧丢弃且不破坏已有帧、丢弃后槽位可重新使用、MAC 侧 rx_rdy 恒为 1。
module tb_afdx_net_rx;                                      // 声明模块及其参数接口

    localparam MAC_PERIOD  = 8;                             // MAC 侧 125MHz
    localparam CORE_PERIOD = 40;                            // 核心侧 25MHz
    localparam FRAME_LEN   = 64;                            // 测试帧字节数

    reg clk_mac;                                            // MAC 侧时钟
    reg clk_core;                                           // 核心侧时钟
    reg rst_b;                                              // 复位

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

    integer fail_cnt;                                       // 失败计数
    integer rx_frames;                                      // 已收帧数
    integer rx_len;                                         // 当前帧已收字节数
    reg [7:0] rx_base;                                      // 当前帧期望基值
    reg       rx_net;                                       // 当前帧网络
    integer i;                                              // 循环变量

    initial clk_mac = 1'b0;                                 // MAC 时钟初值
    always #(MAC_PERIOD/2) clk_mac = ~clk_mac;              // 125MHz
    initial clk_core = 1'b0;                                // 核心时钟初值
    always #(CORE_PERIOD/2) clk_core = ~clk_core;            // 25MHz

    afdx_net_rx #(                                          // 被测模块
        .DATA_WIDTH (8), .ADDR_WIDTH (12), .MAX_FRAME (1536), .SLOT_BITS (11)
    ) dut (
        .wr_clk        (clk_mac),                           // MAC 侧时钟
        .rd_clk        (clk_core),                          // 核心侧时钟
        .rst_b         (rst_b),                             // 复位
        .a_rx_data     (a_rx_data),                         // A 网
        .a_rx_data_vld (a_rx_data_vld),
        .a_rx_sop      (a_rx_sop),
        .a_rx_eop      (a_rx_eop),
        .a_rx_err      (a_rx_err),
        .a_rx_rdy      (a_rx_rdy),
        .b_rx_data     (b_rx_data),                         // B 网
        .b_rx_data_vld (b_rx_data_vld),
        .b_rx_sop      (b_rx_sop),
        .b_rx_eop      (b_rx_eop),
        .b_rx_err      (b_rx_err),
        .b_rx_rdy      (b_rx_rdy),
        .ff_rx_data    (ff_rx_data),                        // 核心侧
        .ff_rx_data_vld(ff_rx_data_vld),
        .ff_rx_sop     (ff_rx_sop),
        .ff_rx_eop     (ff_rx_eop),
        .ff_rx_err     (ff_rx_err),
        .ff_rx_rdy     (ff_rx_rdy),
        .frame_net     (frame_net)
    );

    task do_fail;                                           // 记录失败
        input [511:0] msg;
        begin
            $display("  [FAIL] %0s", msg);
            fail_cnt = fail_cnt + 1;
        end
    endtask

    task mac_send;                                          // MAC 侧注入一帧
        input       net;                                    // 0=A 1=B
        input [7:0] base;                                   // 数据基值
        input integer len;                                  // 字节数
        integer n;                                          // 循环
        begin
            for (n = 0; n < len; n = n + 1) begin           // 逐字节
                @(negedge clk_mac);
                if (net) begin
                    b_rx_data <= base + n[7:0]; b_rx_data_vld <= 1'b1;
                    b_rx_sop <= (n == 0); b_rx_eop <= (n == len-1);
                end else begin
                    a_rx_data <= base + n[7:0]; a_rx_data_vld <= 1'b1;
                    a_rx_sop <= (n == 0); a_rx_eop <= (n == len-1);
                end
            end
            @(negedge clk_mac);                             // 撤消
            a_rx_data_vld <= 1'b0; a_rx_sop <= 1'b0; a_rx_eop <= 1'b0;
            b_rx_data_vld <= 1'b0; b_rx_sop <= 1'b0; b_rx_eop <= 1'b0;
        end
    endtask

    always @(negedge clk_core) begin                        // 核心侧接收检查
        if (rst_b && ff_rx_data_vld) begin
            if (ff_rx_sop) begin                            // 帧首
                rx_len  = 0;
                rx_base = ff_rx_data;                       // 帧首字节即基值
                rx_net  = frame_net;
            end
            if (ff_rx_data !== (rx_base + rx_len[7:0])) do_fail("rx byte mismatch");
            if (ff_rx_err !== 1'b0) do_fail("rx err flag");
            rx_len = rx_len + 1;
            if (ff_rx_eop) begin                            // 帧尾
                rx_frames = rx_frames + 1;
                if (rx_len != FRAME_LEN) do_fail("rx frame length");
                $display("  [INFO] frame %0d: net=%0d base=%02x len=%0d", rx_frames, rx_net, rx_base, rx_len);
            end
        end
    end

    initial begin                                           // 主流程
        clk_mac = 1'b0; clk_core = 1'b0; rst_b = 1'b0;      // 初值
        a_rx_data = 8'h00; a_rx_data_vld = 1'b0; a_rx_sop = 1'b0; a_rx_eop = 1'b0; a_rx_err = 1'b0;
        b_rx_data = 8'h00; b_rx_data_vld = 1'b0; b_rx_sop = 1'b0; b_rx_eop = 1'b0; b_rx_err = 1'b0;
        ff_rx_rdy = 1'b0;                                   // 核心暂不接收
        fail_cnt = 0; rx_frames = 0;                        // 清统计
        repeat (10) @(posedge clk_mac);                     // 保持复位
        rst_b = 1'b1;                                       // 释放复位
        repeat (10) @(posedge clk_mac);                     // 等稳定

        $display("=== 1) two nets, core not ready ===");
        if (a_rx_rdy !== 1'b1 || b_rx_rdy !== 1'b1) do_fail("rx_rdy not always high");
        mac_send(1'b0, 8'h00, FRAME_LEN);                   // A 网帧
        mac_send(1'b1, 8'h80, FRAME_LEN);                   // B 网帧
        repeat (100) @(posedge clk_core);                   // 等写侧落缓存
        if (rx_frames != 0) do_fail("frame sent while core not ready");
        ff_rx_rdy = 1'b1;                                   // 核心开始接收
        i = 0;
        while ((rx_frames < 2) && (i < 5000)) begin @(posedge clk_core); i = i + 1; end
        if (rx_frames == 2) $display("  [PASS] two nets served across clock");
        else do_fail("two frame count");

        $display("=== 2) two slots ping-pong, 3rd frame dropped ===");
        ff_rx_rdy = 1'b0;                                   // 先不让核心读，把两槽填满
        mac_send(1'b0, 8'h20, FRAME_LEN);                   // A 网第 2 帧
        mac_send(1'b0, 8'h30, FRAME_LEN);                   // A 网第 3 帧
        mac_send(1'b0, 8'h40, FRAME_LEN);                   // A 网第 4 帧：两槽都占 → 丢弃
        repeat (100) @(posedge clk_core);
        $display("  [DBG] a_wr_tog=%b a_rd_tog=%b a_avail=%b b_avail=%b rx_frames=%0d", dut.a_wr_tog, dut.a_rd_tog, dut.a_avail, dut.b_avail, rx_frames);
        ff_rx_rdy = 1'b1;
        i = 0;
        while ((rx_frames < 4) && (i < 8000)) begin @(posedge clk_core); i = i + 1; end
        repeat (400) @(posedge clk_core);                   // 多等，确认没有 0x40 这帧
        if (rx_frames == 4) $display("  [PASS] two slots ping-pong, 3rd frame dropped");
        else do_fail("slot overflow handling");

        $display("=== 3) slot reusable after drop ===");
        mac_send(1'b0, 8'h50, FRAME_LEN);                   // A 网新帧
        i = 0;
        while ((rx_frames < 5) && (i < 8000)) begin @(posedge clk_core); i = i + 1; end
        if (rx_frames == 5) $display("  [PASS] slot reusable after drop");
        else do_fail("slot not reusable");

        if (fail_cnt == 0) $display("PASS: afdx_net_rx dual clock chain");
        else $display("FAIL: afdx_net_rx failures=%0d", fail_cnt);
        $finish;
    end

endmodule

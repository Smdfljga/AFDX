// ip_sim_models : eLinx IP 的行为级仿真模型
// 用于 ModelSim/功能仿真；模块名、端口名与 eLinx 生成的真 IP 完全一致。
// 所有 RAM 均按“读地址被采样后下一拍 q 有效”建模，不参与 FPGA 综合。

// ==================== VL 配置表：128bit × 4096 ====================
module vl_config_ip (                                       // 声明模块及其参数接口
    aclr_a, aclr_b, clock_a, clock_b, data_a, data_b,       // 继续计算当前组合结果
    address_a, address_b, wren_a, wren_b, q_a, q_b          // 继续计算当前组合结果
);                                                          // 端口声明或模块例化结束
    input  clock_a, clock_b;                                // 声明input、clock_a、clock_b所需的信号或常量
    input  aclr_a, aclr_b;                                  // 声明input、aclr_a、aclr_b所需的信号或常量
    input  [127:0] data_a, data_b;                          // 声明input、data_a、data_b所需的信号或常量
    input  [11:0]  address_a, address_b;                    // 声明input、address_a、address_b所需的信号或常量
    input  wren_a, wren_b;                                  // 声明input、wren_a、wren_b所需的信号或常量
    output reg [127:0] q_a, q_b;                            // 声明output、q_a、q_b所需的信号或常量
    reg [127:0] q_a_d, q_b_d;            // 输出寄存第一级

    reg [127:0] mem [0:4095];                               // 声明mem所需的信号或常量
    integer i;                                              // 声明integer、i所需的信号或常量
    initial begin                                           // 仿真初始化或激励流程
        for (i = 0; i < 4096; i = i + 1) mem[i] = 128'd0;   // 依次处理指定范围内的表项或位段
        q_a = 128'd0;                                       // 设置或组合计算q_a
        q_a_d = 128'd0;
        q_b = 128'd0;                                       // 设置或组合计算q_b
        q_b_d = 128'd0;
    end                                                     // 当前语句组结束
    always @(posedge clock_a) begin                         // 按时钟沿更新寄存器，并响应声明的异步复位
        if (wren_a) mem[address_a] <= data_a;               // 检查wren_a、mem、address_a的条件
        q_a_d <= mem[address_a];                // 输出寄存第一级，对齐厂商 IP 的 2 拍读延迟
        q_a <= q_a_d;                    // 输出寄存第二级
    end                                                     // 当前语句组结束
    always @(posedge clock_b) begin                         // 按时钟沿更新寄存器，并响应声明的异步复位
        if (wren_b) mem[address_b] <= data_b;               // 检查wren_b、mem、address_b的条件
        q_b_d <= mem[address_b];                // 输出寄存第一级，对齐厂商 IP 的 2 拍读延迟
        q_b <= q_b_d;                    // 输出寄存第二级
    end                                                     // 当前语句组结束
endmodule                                                   // 模块定义结束

// ==================== VL 状态表：64bit × 4096 ====================
module vl_state_ip (                                        // 声明模块及其参数接口
    aclr_a, aclr_b, clock_a, clock_b, data_a, data_b,       // 继续计算q_b
    address_a, address_b, wren_a, wren_b, q_a, q_b          // 继续计算q_b
);                                                          // 端口声明或模块例化结束
    input  clock_a, clock_b;                                // 声明input、clock_a、clock_b所需的信号或常量
    input  aclr_a, aclr_b;                                  // 声明input、aclr_a、aclr_b所需的信号或常量
    input  [63:0] data_a, data_b;                           // 声明input、data_a、data_b所需的信号或常量
    input  [11:0] address_a, address_b;                     // 声明input、address_a、address_b所需的信号或常量
    input  wren_a, wren_b;                                  // 声明input、wren_a、wren_b所需的信号或常量
    output reg [63:0] q_a, q_b;                             // 声明output、q_a、q_b所需的信号或常量
    reg [63:0] q_a_d, q_b_d;            // 输出寄存第一级

    reg [63:0] mem [0:4095];                                // 声明mem所需的信号或常量
    integer i;                                              // 声明integer、i所需的信号或常量
    initial begin                                           // 仿真初始化或激励流程
        for (i = 0; i < 4096; i = i + 1) mem[i] = 64'd0;    // 依次处理指定范围内的表项或位段
        q_a = 64'd0;                                        // 设置或组合计算q_a
        q_a_d = 64'd0;
        q_b = 64'd0;                                        // 设置或组合计算q_b
        q_b_d = 64'd0;
    end                                                     // 当前语句组结束
    always @(posedge clock_a) begin                         // 按时钟沿更新寄存器，并响应声明的异步复位
        if (wren_a) mem[address_a] <= data_a;               // 检查wren_a、mem、address_a的条件
        q_a_d <= mem[address_a];                // 输出寄存第一级，对齐厂商 IP 的 2 拍读延迟
        q_a <= q_a_d;                    // 输出寄存第二级
    end                                                     // 当前语句组结束
    always @(posedge clock_b) begin                         // 按时钟沿更新寄存器，并响应声明的异步复位
        if (wren_b) mem[address_b] <= data_b;               // 检查wren_b、mem、address_b的条件
        q_b_d <= mem[address_b];                // 输出寄存第一级，对齐厂商 IP 的 2 拍读延迟
        q_b <= q_b_d;                    // 输出寄存第二级
    end                                                     // 当前语句组结束
endmodule                                                   // 模块定义结束

// ==================== MIB RX 计数表：256bit × 4096 ====================
module mib_rx_ip (                                          // 声明模块及其参数接口
    aclr_a, aclr_b, clock_a, clock_b, data_a, data_b,       // 继续计算q_b
    address_a, address_b, wren_a, wren_b, q_a, q_b          // 继续计算q_b
);                                                          // 端口声明或模块例化结束
    input  clock_a, clock_b;                                // 声明input、clock_a、clock_b所需的信号或常量
    input  aclr_a, aclr_b;                                  // 声明input、aclr_a、aclr_b所需的信号或常量
    input  [255:0] data_a, data_b;                          // 声明input、data_a、data_b所需的信号或常量
    input  [11:0]  address_a, address_b;                    // 声明input、address_a、address_b所需的信号或常量
    input  wren_a, wren_b;                                  // 声明input、wren_a、wren_b所需的信号或常量
    output reg [255:0] q_a, q_b;                            // 声明output、q_a、q_b所需的信号或常量
    reg [255:0] q_a_d, q_b_d;            // 输出寄存第一级

    reg [255:0] mem [0:4095];                               // 声明mem所需的信号或常量
    integer i;                                              // 声明integer、i所需的信号或常量
    initial begin                                           // 仿真初始化或激励流程
        for (i = 0; i < 4096; i = i + 1) mem[i] = 256'd0;   // 依次处理指定范围内的表项或位段
        q_a = 256'd0;                                       // 设置或组合计算q_a
        q_a_d = 256'd0;
        q_b = 256'd0;                                       // 设置或组合计算q_b
        q_b_d = 256'd0;
    end                                                     // 当前语句组结束
    always @(posedge clock_a) begin                         // 按时钟沿更新寄存器，并响应声明的异步复位
        if (wren_a) mem[address_a] <= data_a;               // 检查wren_a、mem、address_a的条件
        q_a_d <= mem[address_a];                // 输出寄存第一级，对齐厂商 IP 的 2 拍读延迟
        q_a <= q_a_d;                    // 输出寄存第二级
    end                                                     // 当前语句组结束
    always @(posedge clock_b) begin                         // 按时钟沿更新寄存器，并响应声明的异步复位
        if (wren_b) mem[address_b] <= data_b;               // 检查wren_b、mem、address_b的条件
        q_b_d <= mem[address_b];                // 输出寄存第一级，对齐厂商 IP 的 2 拍读延迟
        q_b <= q_b_d;                    // 输出寄存第二级
    end                                                     // 当前语句组结束
endmodule                                                   // 模块定义结束

// ==================== MIB TX 计数表：256bit × 4096 ====================
module mib_tx_ip (                                          // 声明模块及其参数接口
    aclr_a, aclr_b, clock_a, clock_b, data_a, data_b,       // 继续计算q_b
    address_a, address_b, wren_a, wren_b, q_a, q_b          // 继续计算q_b
);                                                          // 端口声明或模块例化结束
    input  clock_a, clock_b;                                // 声明input、clock_a、clock_b所需的信号或常量
    input  aclr_a, aclr_b;                                  // 声明input、aclr_a、aclr_b所需的信号或常量
    input  [255:0] data_a, data_b;                          // 声明input、data_a、data_b所需的信号或常量
    input  [11:0]  address_a, address_b;                    // 声明input、address_a、address_b所需的信号或常量
    input  wren_a, wren_b;                                  // 声明input、wren_a、wren_b所需的信号或常量
    output reg [255:0] q_a, q_b;                            // 声明output、q_a、q_b所需的信号或常量
    reg [255:0] q_a_d, q_b_d;            // 输出寄存第一级

    reg [255:0] mem [0:4095];                               // 声明mem所需的信号或常量
    integer i;                                              // 声明integer、i所需的信号或常量
    initial begin                                           // 仿真初始化或激励流程
        for (i = 0; i < 4096; i = i + 1) mem[i] = 256'd0;   // 依次处理指定范围内的表项或位段
        q_a = 256'd0;                                       // 设置或组合计算q_a
        q_a_d = 256'd0;
        q_b = 256'd0;                                       // 设置或组合计算q_b
        q_b_d = 256'd0;
    end                                                     // 当前语句组结束
    always @(posedge clock_a) begin                         // 按时钟沿更新寄存器，并响应声明的异步复位
        if (wren_a) mem[address_a] <= data_a;               // 检查wren_a、mem、address_a的条件
        q_a_d <= mem[address_a];                // 输出寄存第一级，对齐厂商 IP 的 2 拍读延迟
        q_a <= q_a_d;                    // 输出寄存第二级
    end                                                     // 当前语句组结束
    always @(posedge clock_b) begin                         // 按时钟沿更新寄存器，并响应声明的异步复位
        if (wren_b) mem[address_b] <= data_b;               // 检查wren_b、mem、address_b的条件
        q_b_d <= mem[address_b];                // 输出寄存第一级，对齐厂商 IP 的 2 拍读延迟
        q_b <= q_b_d;                    // 输出寄存第二级
    end                                                     // 当前语句组结束
endmodule                                                   // 模块定义结束

// ==================== RX 端口缓冲：8bit × 32768，简单双口 ====================
module rx_port_buf_ip (                                     // 声明模块及其参数接口
    in_aclr, out_aclr, inclock, outclock, data, rdaddress, wraddress,  // 继续计算q_b
    wren, rden, q                                           // 继续计算q_b
);                                                          // 端口声明或模块例化结束
    input in_aclr, out_aclr, inclock, outclock;             // 声明input、in_aclr、out_aclr所需的信号或常量
    input [7:0]  data;                                      // 声明input、data所需的信号或常量
    input [14:0] rdaddress, wraddress;                      // 声明input、rdaddress、wraddress所需的信号或常量
    input wren, rden;                                       // 声明input、wren、rden所需的信号或常量
    output reg [7:0] q;                                     // 声明output、q所需的信号或常量
    reg [7:0] q_d;                     // 输出寄存第一级

    reg [7:0] mem [0:32767];                                // 声明mem所需的信号或常量
    integer i;                                              // 声明integer、i所需的信号或常量
    initial begin                                           // 仿真初始化或激励流程
        for (i = 0; i < 32768; i = i + 1) mem[i] = 8'd0;    // 依次处理指定范围内的表项或位段
        q = 8'd0;                                           // 设置或组合计算q
        q_d = 8'd0;
    end                                                     // 当前语句组结束
    always @(posedge inclock)                               // 按时钟沿更新寄存器，并响应声明的异步复位
        if (wren) mem[wraddress] <= data;                   // 检查wren、mem、wraddress的条件
    always @(posedge outclock) begin
        q_d <= rden ? mem[rdaddress] : q_d;         // 输出寄存第一级，对齐厂商 IP 的 2 拍读延迟
        q <= q_d;                                  // 输出寄存第二级
    end
endmodule                                                   // 模块定义结束

// ==================== TX 端口缓冲：8bit × 32768，简单双口 ====================
module tx_port_buf_ip (                                     // 声明模块及其参数接口
    in_aclr, out_aclr, inclock, outclock, data, rdaddress, wraddress,  // 继续计算q
    wren, rden, q                                           // 继续计算q
);                                                          // 端口声明或模块例化结束
    input in_aclr, out_aclr, inclock, outclock;             // 声明input、in_aclr、out_aclr所需的信号或常量
    input [7:0]  data;                                      // 声明input、data所需的信号或常量
    input [14:0] rdaddress, wraddress;                      // 声明input、rdaddress、wraddress所需的信号或常量
    input wren, rden;                                       // 声明input、wren、rden所需的信号或常量
    output reg [7:0] q;                                     // 声明output、q所需的信号或常量
    reg [7:0] q_d;                     // 输出寄存第一级

    reg [7:0] mem [0:32767];                                // 声明mem所需的信号或常量
    integer i;                                              // 声明integer、i所需的信号或常量
    initial begin                                           // 仿真初始化或激励流程
        for (i = 0; i < 32768; i = i + 1) mem[i] = 8'd0;    // 依次处理指定范围内的表项或位段
        q = 8'd0;                                           // 设置或组合计算q
        q_d = 8'd0;
    end                                                     // 当前语句组结束
    always @(posedge inclock)                               // 按时钟沿更新寄存器，并响应声明的异步复位
        if (wren) mem[wraddress] <= data;                   // 检查wren、mem、wraddress的条件
    always @(posedge outclock) begin
        q_d <= rden ? mem[rdaddress] : q_d;         // 输出寄存第一级，对齐厂商 IP 的 2 拍读延迟
        q <= q_d;                                  // 输出寄存第二级
    end
endmodule                                                   // 模块定义结束

// ==================== 615A 文件表：128bit × 16 ====================
module file_table_ip (                                      // 声明模块及其参数接口
    in_aclr, out_aclr, inclock, outclock, data, rdaddress, wraddress,  // 继续计算q
    wren, rden, q                                           // 继续计算q
);                                                          // 端口声明或模块例化结束
    input in_aclr, out_aclr, inclock, outclock;             // 声明input、in_aclr、out_aclr所需的信号或常量
    input [127:0] data;                                     // 声明input、data所需的信号或常量
    input [3:0]   rdaddress, wraddress;                     // 声明input、rdaddress、wraddress所需的信号或常量
    input wren, rden;                                       // 声明input、wren、rden所需的信号或常量
    output reg [127:0] q;                                   // 声明output、q所需的信号或常量
    reg [127:0] q_d;                     // 输出寄存第一级

    reg [127:0] mem [0:15];                                 // 声明mem所需的信号或常量
    integer i;                                              // 声明integer、i所需的信号或常量
    initial begin                                           // 仿真初始化或激励流程
        for (i = 0; i < 16; i = i + 1) mem[i] = 128'd0;     // 依次处理指定范围内的表项或位段
        q = 128'd0;                                         // 设置或组合计算q
        q_d = 128'd0;
    end                                                     // 当前语句组结束
    always @(posedge inclock)                               // 按时钟沿更新寄存器，并响应声明的异步复位
        if (wren) mem[wraddress] <= data;                   // 检查wren、mem、wraddress的条件
    always @(posedge outclock) begin
        q_d <= rden ? mem[rdaddress] : q_d;         // 输出寄存第一级，对齐厂商 IP 的 2 拍读延迟
        q <= q_d;                                  // 输出寄存第二级
    end
endmodule                                                   // 模块定义结束

// ==================== 双网接收帧缓存：8bit × 4096，简单双口 ====================
module rx_frame_buf (                                        // 声明模块及其参数接口
    rdclock, wrclock, data, rdaddress, wraddress, wren, rden, q  // 继续计算q
);                                                          // 端口声明或模块例化结束
    input  rdclock, wrclock;                               // 声明input、inclock、outclock所需的信号或常量
    input [7:0]  data;                                      // 声明input、data所需的信号或常量
    input [11:0] rdaddress, wraddress;                      // 声明input、rdaddress、wraddress所需的信号或常量
    input wren, rden;                                       // 声明input、wren、rden所需的信号或常量
    output reg [7:0] q;                                     // 声明output、q所需的信号或常量
    reg [7:0] q_d;                     // 输出寄存第一级

    reg [7:0] mem [0:4095];                                 // 声明mem所需的信号或常量
    integer i;                                              // 声明integer、i所需的信号或常量
    initial begin                                           // 仿真初始化或激励流程
        for (i = 0; i < 4096; i = i + 1) mem[i] = 8'd0;     // 依次处理指定范围内的表项或位段
        q = 8'd0;                                           // 设置或组合计算q
        q_d = 8'd0;
    end                                                     // 当前语句组结束
    always @(posedge wrclock)                               // 按时钟沿更新寄存器，并响应声明的异步复位
        if (wren) mem[wraddress] <= data;                   // 检查wren、mem、wraddress的条件
    always @(posedge rdclock) begin
        q_d <= rden ? mem[rdaddress] : q_d;         // 输出寄存第一级，对齐厂商 IP 的 2 拍读延迟
        q <= q_d;                                  // 输出寄存第二级
    end
endmodule                                                   // 模块定义结束

// ==================== 615A 文件 FIFO：8bit × 512，非 show-ahead ====================
module file_buffer_ip (                                     // 声明模块及其参数接口
    aclr, clock, data, rdreq, wrreq, sclr,                  // 继续计算q
    almost_empty, almost_full, empty, full, usedw, q        // 继续计算q
);                                                          // 端口声明或模块例化结束
    input aclr, clock, sclr;                                // 声明input、aclr、clock所需的信号或常量
    input [7:0] data;                                       // 声明input、data所需的信号或常量
    input rdreq, wrreq;                                     // 声明input、rdreq、wrreq所需的信号或常量
    output almost_empty, almost_full, empty, full;          // 声明output、almost_empty、almost_full所需的信号或常量
    output wire [8:0] usedw;                                // 已用数量低九位，满状态由 full 单独区分
    output reg [7:0] q;                                     // 声明output、q所需的信号或常量

    reg [7:0] mem [0:511];                                  // 声明mem所需的信号或常量
    reg [8:0] wr_ptr, rd_ptr;                               // 深度五百一十二对应九位循环地址
    reg [9:0] cnt;                                          // 计数必须能表示满容量五百一十二
    integer i;                                              // 声明integer、i所需的信号或常量
    initial begin                                           // 仿真初始化或激励流程
        for (i = 0; i < 512; i = i + 1) mem[i] = 8'd0;      // 依次处理指定范围内的表项或位段
    end                                                     // 当前语句组结束

    always @(posedge clock or posedge aclr) begin           // 按时钟沿更新寄存器，并响应声明的异步复位
        if (aclr || sclr) begin                             // 检查aclr、sclr的条件
            wr_ptr <= 9'd0;                                 // 时钟沿更新深度五百一十二对应九位循环地址
            rd_ptr <= 9'd0;                                 // 时钟沿更新rd_ptr
            cnt    <= 10'd0;                                // 复位实际存量计数
            q      <= 8'd0;                                 // 时钟沿更新q
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            if (wrreq && !full)                             // 检查wrreq、full的条件
                mem[wr_ptr[8:0]] <= data;                   // 继续计算q
            if (rdreq && !empty)                            // 检查rdreq、empty的条件
                q <= mem[rd_ptr[8:0]];                      // 时钟沿更新q
            if (wrreq && !full && !(rdreq && !empty))       // 检查wrreq、full、rdreq的条件
                cnt <= cnt + 10'd1;                         // 仅写被接受时存量增加
            else if (rdreq && !empty && !(wrreq && !full))  // 检查rdreq、empty、wrreq的条件
                cnt <= cnt - 10'd1;                         // 仅读被接受时存量减少
            if (wrreq && !full)                             // 检查wrreq、full的条件
                wr_ptr <= wr_ptr + 9'd1;                    // 时钟沿更新深度五百一十二对应九位循环地址并推进至下一项
            if (rdreq && !empty)                            // 检查rdreq、empty的条件
                rd_ptr <= rd_ptr + 9'd1;                    // 时钟沿更新rd_ptr并推进至下一项
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    assign usedw = cnt[8:0];                                // 数量与空满标志使用同一拍的实际存量
    assign empty = (cnt == 10'd0);                          // 没有已存数据时置空
    assign full  = (cnt == 10'd512);                        // 容量到五百一十二时置满
    assign almost_empty = (cnt <= 10'd1);                   // 剩余不超过一个数据字
    assign almost_full  = (cnt >= 10'd511);                 // 空余不超过一个数据字
endmodule                                                   // 模块定义结束

// snmp_encoder : 固定模板的 SNMP 响应编码
// 把 OID 与查询到的计数值编码成 BER 响应报文，逐字节写入发送端口缓冲
// 注：固定长度 GetResponse 编码状态机已实现
module snmp_encoder #(                                      // 声明模块及其参数接口
    parameter DATA_WIDTH        = 8,        // 数据位宽
    parameter BYTE_OFFSET_WIDTH = 11,       // 字节偏移位宽
    parameter OID_WIDTH         = 16        // 内部对象索引位宽（与 mib_query 一致）
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 编码请求与数据 ====================
    input  wire                          enc_req,                // 编码请求
    input  wire [OID_WIDTH-1:0]          oid,                    // 响应中回填的对象索引
    input  wire [31:0]                   value,                  // 响应中回填的计数值
    input  wire                          tx_wr_gnt,              // 写请求被 tx_wr_arb 接受的当拍回执

    // ==================== 输出字节流 ====================
    output wire                          tx_wr_en,               // 写使能（一字节）
    output wire [BYTE_OFFSET_WIDTH-1:0]  tx_wr_byte_offset,      // 写字节偏移，由编码器自身逐字节递增
    output wire [DATA_WIDTH-1:0]         tx_wr_data,             // 写数据
    output wire                          enc_done                // 编码完成（帧尾）
);                                                          // 端口声明或模块例化结束

    // ==================== 状态机 ====================
    localparam S_IDLE   = 1'b0;                                 // 空闲
    localparam S_ENCODE = 1'b1;                                 // 逐字节编码

    localparam RESP_LEN = 8'd51;                                // 固定 OID 长度时响应总长

    reg         state_r;                                        // 当前状态
    reg [7:0]   byte_cnt;                                       // 响应字节序号 0~50
    reg [OID_WIDTH-1:0] oid_r;                                  // 锁存的对象索引
    reg [31:0]  value_r;                                        // 锁存的查询值
    reg         done_r;                                         // 编码完成脉冲

    // ==================== 状态机：第二段（组合，算次态） ====================
    reg nxt_state;                                              // 次态，由本段组合算出

    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        nxt_state = state_r;                                    // 默认保持当前状态

        case (state_r)                                      // 根据当前状态选择处理分支
            S_IDLE: begin                                   // 处理空闲阶段
                if (enc_req)                                // 检查编码请求的条件
                    nxt_state = S_ENCODE;                       // 收到编码请求，逐字节输出响应
            end                                             // 当前语句组结束

            S_ENCODE: begin                                 // 处理逐字节编码阶段
                if (tx_wr_gnt && (byte_cnt == RESP_LEN - 8'd1))  // 发送缓冲授权后推进当前响应字节
                    nxt_state = S_IDLE;                         // 末字节写成功即结束
            end                                             // 当前语句组结束

            default: begin                                  // 未匹配有效分支时采用默认处理
                nxt_state = S_IDLE;                             // 异常状态回空闲
            end                                             // 当前语句组结束
        endcase                                             // 当前分支选择结束
    end                                                     // 当前语句组结束

    // ==================== 状态机：第一段（时序，状态寄存器与数据通路） ====================
    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            state_r  <= S_IDLE;                             // 时钟沿更新当前状态
            byte_cnt <= 8'd0;                               // 时钟沿更新响应字节序号 0~50
            oid_r    <= {OID_WIDTH{1'b0}};                  // 时钟沿更新锁存的对象索引
            value_r  <= 32'd0;                              // 时钟沿更新锁存的查询值
            done_r   <= 1'b0;                               // 时钟沿更新编码完成脉冲
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            done_r <= 1'b0;                                 // 时钟沿更新编码完成脉冲
            case (state_r)                                  // 根据当前状态选择处理分支
                S_IDLE: begin                               // 处理空闲阶段
                    if (enc_req) begin                      // 检查编码请求的条件
                        byte_cnt <= 8'd0;                   // 时钟沿更新响应字节序号 0~50
                        oid_r    <= oid;                         // 锁存本次编码所需字段
                        value_r  <= value;                  // 时钟沿更新锁存的查询值
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                S_ENCODE: begin                             // 处理逐字节编码阶段
                    if (tx_wr_gnt) begin                    // 发送缓冲授权后推进当前响应字节
                        if (byte_cnt == RESP_LEN - 8'd1) begin  // 检查响应字节序号 0~50、固定 OID 长度时响应总长的条件
                            done_r  <= 1'b1;                    // 末字节写成功，本拍就是帧尾
                        end                                 // 当前语句组结束
                        else                                // 采用前一条件未满足时的处理
                            byte_cnt <= byte_cnt + 8'd1;    // 时钟沿更新响应字节序号 0~50并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                default: ;                                       // 其余状态没有数据通路动作
            endcase                                         // 当前分支选择结束

            state_r <= nxt_state;                               // 状态寄存器只在第一段更新
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    // ==================== 字节生成 ====================
    reg [7:0] out_byte;                                         // 当前响应字节
    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        out_byte = 8'h00;                                       // 默认零，避免锁存器
        case (byte_cnt)                                     // 根据响应字节序号 0~50选择处理分支
            8'd0:  out_byte = 8'h30;                            // SEQUENCE
            8'd1:  out_byte = 8'h31;                            // 报文体长度 49
            8'd2:  out_byte = 8'h02;                            // version INTEGER
            8'd3:  out_byte = 8'h01;                        // 当前字节或字段索引对应的数据选择
            8'd4:  out_byte = 8'h01;                            // SNMPv2c version=1
            8'd5:  out_byte = 8'h04;                            // community OCTET STRING
            8'd6:  out_byte = 8'h06;                        // 当前字节或字段索引对应的数据选择
            8'd7:  out_byte = 8'h70;                            // 'p'
            8'd8:  out_byte = 8'h75;                            // 'u'
            8'd9:  out_byte = 8'h62;                            // 'b'
            8'd10: out_byte = 8'h6C;                            // 'l'
            8'd11: out_byte = 8'h69;                            // 'i'
            8'd12: out_byte = 8'h63;                            // 'c'
            8'd13: out_byte = 8'hA2;                            // GetResponse
            8'd14: out_byte = 8'h24;                            // PDU 长度 36
            8'd15: out_byte = 8'h02;                            // request-id INTEGER
            8'd16: out_byte = 8'h04;                        // 请求号整数长度为四字节
            8'd17: out_byte = 8'h00;                            // 请求号固定回 0
            8'd18: out_byte = 8'h00;                        // 固定请求号的第二字节为零
            8'd19: out_byte = 8'h00;                        // 固定请求号的第三字节为零
            8'd20: out_byte = 8'h00;                        // 固定请求号的末字节为零
            8'd21: out_byte = 8'h02;                            // error-status
            8'd22: out_byte = 8'h01;                        // 错误状态整数长度为一字节
            8'd23: out_byte = 8'h00;                        // 错误状态固定为零
            8'd24: out_byte = 8'h02;                            // error-index
            8'd25: out_byte = 8'h01;                        // 错误索引整数长度为一字节
            8'd26: out_byte = 8'h00;                        // 错误索引固定为零
            8'd27: out_byte = 8'h30;                            // VarBindList
            8'd28: out_byte = 8'h16;                        // VarBindList 内容长度为二十二字节
            8'd29: out_byte = 8'h30;                            // VarBind
            8'd30: out_byte = 8'h14;                        // VarBind 内容长度为二十字节
            8'd31: out_byte = 8'h06;                            // OID
            8'd32: out_byte = 8'h0C;                            // 固定 12 字节 OID
            8'd33: out_byte = 8'h2B;                            // 1.3
            8'd34: out_byte = 8'h06;                            // 6
            8'd35: out_byte = 8'h01;                            // 1
            8'd36: out_byte = 8'h04;                            // 4
            8'd37: out_byte = 8'h01;                            // 1
            8'd38: out_byte = 8'hCE;                            // 9999 高 7bit
            8'd39: out_byte = 8'h0F;                            // 9999 低 7bit
            8'd40: out_byte = 8'h01;                            // 项目私有 OID 根
            8'd41: out_byte = {7'b0000000, oid_r[OID_WIDTH-1]}; // 表选
            8'd42: out_byte = 8'h80 | ((oid_r[OID_WIDTH-2:3] >> 7) & 8'h7F);  // VL 地址高组，续字节标志必须位于第七位
            8'd43: out_byte = (oid_r >> 3) & 8'h7F;         // VL 地址低七位，与高组不重叠
            8'd44: out_byte = {5'b00000, oid_r[2:0]};           // 计数器号
            8'd45: out_byte = 8'h02;                            // Counter32 INTEGER
            8'd46: out_byte = 8'h04;                        // 计数值长度固定为四字节
            8'd47: out_byte = value_r[31:24];                   // 计数值大端
            8'd48: out_byte = value_r[23:16];               // 计数值的大端第二字节
            8'd49: out_byte = value_r[15:8];                // 计数值的大端第三字节
            8'd50: out_byte = value_r[7:0];                 // 计数值的大端末字节
            default: out_byte = 8'h00;                      // 未匹配有效分支时采用默认处理
        endcase                                             // 当前分支选择结束
    end                                                     // 当前语句组结束

    assign tx_wr_en          = (state_r == S_ENCODE);           // output [0:0]
    assign tx_wr_byte_offset = {3'b000, byte_cnt};              // output [10:0]
    assign tx_wr_data        = out_byte;                        // output [7:0]
    assign enc_done          = done_r;                          // output [0:0]：与末字节同拍

endmodule                                                   // 模块定义结束

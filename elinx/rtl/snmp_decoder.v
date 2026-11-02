// snmp_decoder : SNMP 请求解码
// 从接收端口缓冲逐字节读入，解析 BER/ASN.1 结构，取出 PDU 类型与目标 OID
// 读请求由本模块发出，经 rx_rd_arb 仲裁后取回数据
// 注：BER/ASN.1 状态机已实现
module snmp_decoder #(                                      // 声明模块及其参数接口
    parameter DATA_WIDTH        = 8,        // 数据位宽
    parameter BYTE_OFFSET_WIDTH = 11,       // 字节偏移位宽
    parameter OID_WIDTH         = 16        // 内部对象索引位宽（1 表选 + 12 地址 + 3 计数选）
)(                                                          // 参数声明结束，开始端口声明
    // ==================== 时钟与复位 ====================
    input  wire                          clk,                    // 时钟（与顶层 clk_sys 同源）
    input  wire                          rst_b,                  // 复位，低电平有效

    // ==================== 启动触发 ====================
    input  wire                          start,                  // 接收完成触发（来自 snmp_agent）
    input  wire [15:0]                   rx_frame_len,           // 当前 SNMP 报文长度，防止截断报文越界读

    // ==================== 输入字节流（经 rx_rd_arb） ====================
    output wire                          rx_rd_req,              // 读请求，送 rx_rd_arb
    output wire [BYTE_OFFSET_WIDTH-1:0]  rx_rd_byte_offset,      // 读字节偏移（解码进度）
    input  wire [DATA_WIDTH-1:0]         rx_rd_data,             // 读数据
    input  wire                          rx_rd_valid,            // 读数据有效

    // ==================== 解析结果 ====================
    output wire                          pdu_valid,              // PDU 关键字段解析完成
    output wire [1:0]                    pdu_type,               // PDU 类型（GET/GETNEXT/SET...）
    output wire [OID_WIDTH-1:0]          oid,                    // 目标对象索引（编码见 mib_query）
    output wire                          decode_done             // 整包解码完成
);                                                          // 端口声明或模块例化结束

    // ==================== 解析阶段 ====================
    localparam P_IDLE           = 6'd0;                          // 空闲
    localparam P_SEQ_TAG        = 6'd1;                          // 外层 SEQUENCE 标签
    localparam P_SEQ_LEN        = 6'd2;                          // 外层长度
    localparam P_VER_TAG        = 6'd3;                          // version INTEGER 标签
    localparam P_VER_LEN        = 6'd4;                          // version 长度
    localparam P_VER_VAL        = 6'd5;                          // version 值
    localparam P_COMM_TAG       = 6'd6;                          // community OCTET STRING 标签
    localparam P_COMM_LEN       = 6'd7;                          // community 长度
    localparam P_COMM_VAL       = 6'd8;                          // community 内容
    localparam P_PDU_TAG        = 6'd9;                          // PDU 标签
    localparam P_PDU_LEN        = 6'd10;                         // PDU 长度
    localparam P_REQ_TAG        = 6'd11;                         // request-id INTEGER 标签
    localparam P_REQ_LEN        = 6'd12;                         // request-id 长度
    localparam P_REQ_VAL        = 6'd13;                         // request-id 值
    localparam P_ERRSTAT_TAG    = 6'd14;                         // error-status INTEGER 标签
    localparam P_ERRSTAT_LEN    = 6'd15;                         // error-status 长度
    localparam P_ERRSTAT_VAL    = 6'd16;                         // error-status 值
    localparam P_ERRIDX_TAG     = 6'd17;                         // error-index INTEGER 标签
    localparam P_ERRIDX_LEN     = 6'd18;                         // error-index 长度
    localparam P_ERRIDX_VAL     = 6'd19;                         // error-index 值
    localparam P_VBL_TAG        = 6'd20;                         // VarBindList SEQUENCE 标签
    localparam P_VBL_LEN        = 6'd21;                         // VarBindList 长度
    localparam P_VB_TAG         = 6'd22;                         // VarBind SEQUENCE 标签
    localparam P_VB_LEN         = 6'd23;                         // VarBind 长度
    localparam P_OID_TAG        = 6'd24;                         // OID 标签
    localparam P_OID_LEN        = 6'd25;                         // OID 长度
    localparam P_OID_VAL        = 6'd26;                         // OID 内容
    localparam P_DONE           = 6'd27;                         // 解码完成

    reg [5:0]                 phase;                             // 当前解析阶段
    reg [BYTE_OFFSET_WIDTH-1:0] offset_r;                        // 输入字节偏移
    reg [15:0]                len_acc;                           // 当前 BER 长度累计值
    reg [2:0]                 len_more;                          // 长格式长度还剩几个后续字节
    reg [15:0]                remain;                            // 当前值域剩余字节数
    reg [1:0]                 pdu_type_r;                        // 解析出的 PDU 类型
    reg [OID_WIDTH-1:0]       oid_r;                             // 内部对象索引
    reg                       pdu_valid_r;                       // PDU 关键字段有效脉冲

    // OID 尾部三段解码用寄存器
    reg [15:0]                seg_a;                             // 倒数第三段
    reg [15:0]                seg_b;                             // 倒数第二段
    reg [15:0]                seg_c;                             // 倒数第一段
    reg [15:0]                arc_acc;                           // 当前 base128 子标识累计
    reg                       arc_valid;                         // 当前是否正在累积子标识
    reg                       first_oid;                         // 是否是 OID 首字节

    wire [15:0] final_seg = arc_valid ?                     // 当前 OID 子标识拼入最后七位后的数值
                            ((arc_acc << 7) | {9'd0, rx_rd_data[6:0]}) :  // 将 OID 高位累计值左移七位，再拼入当前数据
                            {9'd0, rx_rd_data[6:0]};            // OID 末字节解析出的最后一段

    // ==================== 读握手 ====================
    assign rx_rd_req          = (phase != P_IDLE) && (phase != P_DONE) &&  // 设置或组合计算读请求
                                (offset_r < rx_frame_len);       // output [0:0]
    assign rx_rd_byte_offset  = offset_r;                        // output [10:0]

    // ==================== 状态机：第二段（组合，算次态） ====================
    reg [5:0] nxt_phase;                                        // 次态，由本段组合算出

    always @(*) begin                                       // 组合计算当前条件下的次态或数据选择
        nxt_phase = phase;                                      // 默认保持当前解析阶段

        case (phase)                                        // 根据当前解析阶段选择处理分支
            P_IDLE: begin                                   // 处理空闲阶段
                if (start)                                  // 检查接收完成触发（来自 snmp_agent）的条件
                    nxt_phase = P_SEQ_TAG;                      // 收到报文，开始解析外层 SEQUENCE
            end                                             // 当前语句组结束

            P_SEQ_TAG: begin                                // 处理外层 SEQUENCE 标签阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = (rx_rd_data == 8'h30) ? P_SEQ_LEN : P_DONE; // 非 SEQUENCE 直接放弃
            end                                             // 当前语句组结束

            P_SEQ_LEN: begin                                // 处理外层长度阶段
                if (rx_rd_valid) begin                      // 读返回有效时消费当前输入字节
                    if (len_more == 3'd0) begin             // 检查长格式长度还剩几个后续字节的条件
                        if (!rx_rd_data[7])                 // 检查读数据的条件
                            nxt_phase = P_VER_TAG;              // 短格式长度，继续解析
                        else if (rx_rd_data[6:0] == 7'd0)   // 检查读数据的条件
                            nxt_phase = P_DONE;                 // 非法长度，放弃
                    end                                     // 当前语句组结束
                    else if (len_more == 3'd1)              // 检查长格式长度还剩几个后续字节的条件
                        nxt_phase = P_VER_TAG;                  // 长格式长度收尾
                end                                         // 当前语句组结束
            end                                             // 当前语句组结束

            P_VER_TAG: begin                                // 处理version INTEGER 标签阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = (rx_rd_data == 8'h02) ? P_VER_LEN : P_DONE;  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_VER_LEN: begin                                // 处理version 长度阶段
                if (rx_rd_valid && !rx_rd_data[7])          // 读返回有效时消费当前输入字节
                    nxt_phase = P_VER_VAL;                      // 短格式 version 长度
            end                                             // 当前语句组结束

            P_VER_VAL: begin                                // 处理version 值阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = (remain <= 16'd1) ? P_COMM_TAG : P_VER_VAL; // version 值消费完
            end                                             // 当前语句组结束

            P_COMM_TAG: begin                               // 处理community OCTET STRING 标签阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = (rx_rd_data == 8'h04) ? P_COMM_LEN : P_DONE;  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_COMM_LEN: begin                               // 处理community 长度阶段
                if (rx_rd_valid && !rx_rd_data[7])          // 读返回有效时消费当前输入字节
                    nxt_phase = (rx_rd_data == 8'd0) ? P_PDU_TAG : P_COMM_VAL;  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_COMM_VAL: begin                               // 处理community 内容阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = (remain <= 16'd1) ? P_PDU_TAG : P_COMM_VAL;  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_PDU_TAG: begin                                // 处理PDU 标签阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = ((rx_rd_data == 8'hA0) || (rx_rd_data == 8'hA1) ||  // 设置或组合计算次态
                                 (rx_rd_data == 8'hA2) || (rx_rd_data == 8'hA3))  // 继续计算nxt_phase
                                      ? P_PDU_LEN : P_DONE;      // 只接受 GET/GETNEXT/GETRESPONSE/SET
            end                                             // 当前语句组结束

            P_PDU_LEN: begin                                // 处理PDU 长度阶段
                if (rx_rd_valid && !rx_rd_data[7])          // 读返回有效时消费当前输入字节
                    nxt_phase = P_REQ_TAG;                      // 短格式 PDU 长度
            end                                             // 当前语句组结束

            P_REQ_TAG: begin                                // 处理request-id INTEGER 标签阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = (rx_rd_data == 8'h02) ? P_REQ_LEN : P_DONE;  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_REQ_LEN: begin                                // 处理request-id 长度阶段
                if (rx_rd_valid && !rx_rd_data[7])          // 读返回有效时消费当前输入字节
                    nxt_phase = P_REQ_VAL;                  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_REQ_VAL: begin                                // 处理request-id 值阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = (remain <= 16'd1) ? P_ERRSTAT_TAG : P_REQ_VAL;  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_ERRSTAT_TAG: begin                            // 处理error-status INTEGER 标签阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = (rx_rd_data == 8'h02) ? P_ERRSTAT_LEN : P_DONE;  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_ERRSTAT_LEN: begin                            // 处理error-status 长度阶段
                if (rx_rd_valid && !rx_rd_data[7])          // 读返回有效时消费当前输入字节
                    nxt_phase = P_ERRSTAT_VAL;              // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_ERRSTAT_VAL: begin                            // 处理error-status 值阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = (remain <= 16'd1) ? P_ERRIDX_TAG : P_ERRSTAT_VAL;  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_ERRIDX_TAG: begin                             // 处理error-index INTEGER 标签阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = (rx_rd_data == 8'h02) ? P_ERRIDX_LEN : P_DONE;  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_ERRIDX_LEN: begin                             // 处理error-index 长度阶段
                if (rx_rd_valid && !rx_rd_data[7])          // 读返回有效时消费当前输入字节
                    nxt_phase = P_ERRIDX_VAL;               // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_ERRIDX_VAL: begin                             // 处理error-index 值阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = (remain <= 16'd1) ? P_VBL_TAG : P_ERRIDX_VAL;  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_VBL_TAG: begin                                // 处理VarBindList SEQUENCE 标签阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = (rx_rd_data == 8'h30) ? P_VBL_LEN : P_DONE;  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_VBL_LEN: begin                                // 处理VarBindList 长度阶段
                if (rx_rd_valid && !rx_rd_data[7])          // 读返回有效时消费当前输入字节
                    nxt_phase = P_VB_TAG;                   // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_VB_TAG: begin                                 // 处理VarBind SEQUENCE 标签阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = (rx_rd_data == 8'h30) ? P_VB_LEN : P_DONE;  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_VB_LEN: begin                                 // 处理VarBind 长度阶段
                if (rx_rd_valid && !rx_rd_data[7])          // 读返回有效时消费当前输入字节
                    nxt_phase = P_OID_TAG;                  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_OID_TAG: begin                                // 处理OID 标签阶段
                if (rx_rd_valid)                            // 读返回有效时消费当前输入字节
                    nxt_phase = (rx_rd_data == 8'h06) ? P_OID_LEN : P_DONE;  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_OID_LEN: begin                                // 处理OID 长度阶段
                if (rx_rd_valid && !rx_rd_data[7])          // 读返回有效时消费当前输入字节
                    nxt_phase = (rx_rd_data == 8'd0) ? P_DONE : P_OID_VAL;  // 设置或组合计算次态
            end                                             // 当前语句组结束

            P_OID_VAL: begin                                // 处理OID 内容阶段
                if (rx_rd_valid && (remain <= 16'd1))       // 读返回有效时消费当前输入字节
                    nxt_phase = P_DONE;                         // OID 末字节解析完成后结束
            end                                             // 当前语句组结束

            P_DONE: begin                                   // 处理解码完成阶段
                nxt_phase = P_IDLE;                             // 单拍结束脉冲后回空闲
            end                                             // 当前语句组结束

            default: begin                                  // 未匹配有效分支时采用默认处理
                nxt_phase = P_IDLE;                             // 异常状态回空闲
            end                                             // 当前语句组结束
        endcase                                             // 当前分支选择结束

        // 报文已经耗尽但 TLV 还没闭合：输入被截断，直接结束避免挂死
        if ((phase != P_IDLE) && (phase != P_DONE) &&       // 检查当前解析阶段、空闲、当前解析阶段的条件
            (offset_r >= rx_frame_len) && (rx_frame_len != 16'd0))  // 继续计算nxt_phase
            nxt_phase = P_DONE;                             // 设置或组合计算次态
    end                                                     // 当前语句组结束

    // ==================== 状态机：第一段（时序，状态寄存器与数据通路） ====================
    always @(posedge clk or negedge rst_b) begin            // 按时钟沿更新寄存器，并响应声明的异步复位
        if (!rst_b) begin                                   // 检查复位或正常运行条件
            phase       <= P_IDLE;                          // 时钟沿更新当前解析阶段
            offset_r    <= {BYTE_OFFSET_WIDTH{1'b0}};       // 时钟沿更新输入字节偏移
            len_acc     <= 16'd0;                           // 时钟沿更新当前 BER 长度累计值
            len_more    <= 3'd0;                            // 时钟沿更新长格式长度还剩几个后续字节
            remain      <= 16'd0;                           // 时钟沿更新当前值域剩余字节数
            pdu_type_r  <= 2'd0;                            // 时钟沿更新解析出的 PDU 类型
            oid_r       <= {OID_WIDTH{1'b0}};               // 时钟沿更新内部对象索引
            pdu_valid_r <= 1'b0;                                // 时钟沿更新PDU 关键字段有效脉冲
            seg_a       <= 16'd0;                           // 时钟沿更新倒数第三段
            seg_b       <= 16'd0;                           // 时钟沿更新倒数第二段
            seg_c       <= 16'd0;                           // 时钟沿更新倒数第一段
            arc_acc     <= 16'd0;                           // 时钟沿更新当前 base128 子标识累计
            arc_valid   <= 1'b0;                            // 时钟沿更新当前是否正在累积子标识
            first_oid   <= 1'b1;                            // 时钟沿更新是否是 OID 首字节
        end                                                 // 当前语句组结束
        else begin                                          // 前一条件不满足时执行本分支
            pdu_valid_r <= 1'b0;                                // 默认单拍

            case (phase)                                    // 根据当前解析阶段选择处理分支
                P_IDLE: begin                               // 处理空闲阶段
                    if (start) begin                        // 检查接收完成触发（来自 snmp_agent）的条件
                        offset_r    <= {BYTE_OFFSET_WIDTH{1'b0}};  // 时钟沿更新输入字节偏移
                        len_acc     <= 16'd0;               // 时钟沿更新当前 BER 长度累计值
                        len_more    <= 3'd0;                // 时钟沿更新长格式长度还剩几个后续字节
                        pdu_type_r  <= 2'd0;                // 时钟沿更新解析出的 PDU 类型
                        oid_r       <= {OID_WIDTH{1'b0}};   // 时钟沿更新内部对象索引
                        seg_a       <= 16'd0;               // 时钟沿更新倒数第三段
                        seg_b       <= 16'd0;               // 时钟沿更新倒数第二段
                        seg_c       <= 16'd0;               // 时钟沿更新倒数第一段
                        arc_valid   <= 1'b0;                // 时钟沿更新当前是否正在累积子标识
                        first_oid   <= 1'b1;                // 时钟沿更新是否是 OID 首字节
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_SEQ_TAG: begin                            // 处理外层 SEQUENCE 标签阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_SEQ_LEN: begin                            // 处理外层长度阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (len_more == 3'd0) begin         // 检查长格式长度还剩几个后续字节的条件
                            if (!rx_rd_data[7]) begin       // 检查读数据的条件
                                len_acc <= {8'd0, rx_rd_data[6:0]};  // 时钟沿更新当前 BER 长度累计值
                            end                             // 当前语句组结束
                            else if (rx_rd_data[6:0] != 7'd0) begin  // 检查读数据的条件
                                len_more <= rx_rd_data[6:0] - 7'd1;  // 时钟沿更新长格式长度还剩几个后续字节
                                len_acc  <= 16'd0;          // 时钟沿更新当前 BER 长度累计值
                            end                             // 当前语句组结束
                        end                                 // 当前语句组结束
                        else begin                          // 前一条件不满足时执行本分支
                            len_acc <= (len_acc << 8) | {8'd0, rx_rd_data};  // 时钟沿更新当前 BER 长度累计值
                            len_more <= len_more - 3'd1;    // 时钟沿更新长格式长度还剩几个后续字节
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_VER_TAG: begin                            // 处理version INTEGER 标签阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_VER_LEN: begin                            // 处理version 长度阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (!rx_rd_data[7]) begin           // 检查读数据的条件
                            remain <= rx_rd_data;           // 时钟沿更新当前值域剩余字节数
                        end                                 // 当前语句组结束
                        else begin                          // 前一条件不满足时执行本分支
                            len_more <= rx_rd_data[6:0] - 7'd1;  // 时钟沿更新长格式长度还剩几个后续字节
                            len_acc  <= 16'd0;              // 时钟沿更新当前 BER 长度累计值
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_VER_VAL: begin                            // 处理version 值阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (remain > 16'd1)                 // 检查当前值域剩余字节数的条件
                            remain <= remain - 16'd1;       // 时钟沿更新当前值域剩余字节数
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_COMM_TAG: begin                           // 处理community OCTET STRING 标签阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_COMM_LEN: begin                           // 处理community 长度阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (!rx_rd_data[7]) begin           // 检查读数据的条件
                            remain <= rx_rd_data;           // 时钟沿更新当前值域剩余字节数
                        end                                 // 当前语句组结束
                        else begin                          // 前一条件不满足时执行本分支
                            len_more <= rx_rd_data[6:0] - 7'd1;  // 时钟沿更新长格式长度还剩几个后续字节
                            len_acc  <= 16'd0;              // 时钟沿更新当前 BER 长度累计值
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_COMM_VAL: begin                           // 处理community 内容阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (remain > 16'd1)                 // 检查当前值域剩余字节数的条件
                            remain <= remain - 16'd1;       // 时钟沿更新当前值域剩余字节数
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_PDU_TAG: begin                            // 处理PDU 标签阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        case (rx_rd_data)                   // 根据读数据选择处理分支
                            8'hA0: pdu_type_r <= 2'd0;           // GetRequest
                            8'hA1: pdu_type_r <= 2'd1;           // GetNextRequest
                            8'hA3: pdu_type_r <= 2'd2;           // SetRequest，由代理拒绝
                            default: pdu_type_r <= 2'd3;    // 未匹配有效分支时采用默认处理
                        endcase                             // 当前分支选择结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_PDU_LEN: begin                            // 处理PDU 长度阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (rx_rd_data[7]) begin            // 检查读数据的条件
                            len_more <= rx_rd_data[6:0] - 7'd1;  // 时钟沿更新长格式长度还剩几个后续字节
                            len_acc  <= 16'd0;              // 时钟沿更新当前 BER 长度累计值
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_REQ_TAG: begin                            // 处理request-id INTEGER 标签阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_REQ_LEN: begin                            // 处理request-id 长度阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (!rx_rd_data[7]) begin           // 检查读数据的条件
                            remain <= rx_rd_data;           // 时钟沿更新当前值域剩余字节数
                        end                                 // 当前语句组结束
                        else begin                          // 前一条件不满足时执行本分支
                            len_more <= rx_rd_data[6:0] - 7'd1;  // 时钟沿更新长格式长度还剩几个后续字节
                            len_acc  <= 16'd0;              // 时钟沿更新当前 BER 长度累计值
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_REQ_VAL: begin                            // 处理request-id 值阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (remain > 16'd1)                 // 检查当前值域剩余字节数的条件
                            remain <= remain - 16'd1;       // 时钟沿更新当前值域剩余字节数
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_ERRSTAT_TAG: begin                        // 处理error-status INTEGER 标签阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_ERRSTAT_LEN: begin                        // 处理error-status 长度阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (!rx_rd_data[7]) begin           // 检查读数据的条件
                            remain <= rx_rd_data;           // 时钟沿更新当前值域剩余字节数
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_ERRSTAT_VAL: begin                        // 处理error-status 值阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (remain > 16'd1)                 // 检查当前值域剩余字节数的条件
                            remain <= remain - 16'd1;       // 时钟沿更新当前值域剩余字节数
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_ERRIDX_TAG: begin                         // 处理error-index INTEGER 标签阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_ERRIDX_LEN: begin                         // 处理error-index 长度阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (!rx_rd_data[7]) begin           // 检查读数据的条件
                            remain <= rx_rd_data;           // 时钟沿更新当前值域剩余字节数
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_ERRIDX_VAL: begin                         // 处理error-index 值阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (remain > 16'd1)                 // 检查当前值域剩余字节数的条件
                            remain <= remain - 16'd1;       // 时钟沿更新当前值域剩余字节数
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_VBL_TAG: begin                            // 处理VarBindList SEQUENCE 标签阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_VBL_LEN: begin                            // 处理VarBindList 长度阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (rx_rd_data[7]) begin            // 检查读数据的条件
                            len_more <= rx_rd_data[6:0] - 7'd1;  // 时钟沿更新长格式长度还剩几个后续字节
                            len_acc  <= 16'd0;              // 时钟沿更新当前 BER 长度累计值
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_VB_TAG: begin                             // 处理VarBind SEQUENCE 标签阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_VB_LEN: begin                             // 处理VarBind 长度阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (rx_rd_data[7]) begin            // 检查读数据的条件
                            len_more <= rx_rd_data[6:0] - 7'd1;  // 时钟沿更新长格式长度还剩几个后续字节
                            len_acc  <= 16'd0;              // 时钟沿更新当前 BER 长度累计值
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_OID_TAG: begin                            // 处理OID 标签阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_OID_LEN: begin                            // 处理OID 长度阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项
                        if (!rx_rd_data[7]) begin           // 检查读数据的条件
                            remain    <= rx_rd_data;        // 时钟沿更新当前值域剩余字节数
                            first_oid <= 1'b1;              // 时钟沿更新是否是 OID 首字节
                        end                                 // 当前语句组结束
                        else begin                          // 前一条件不满足时执行本分支
                            len_more <= rx_rd_data[6:0] - 7'd1;  // 时钟沿更新长格式长度还剩几个后续字节
                            len_acc  <= 16'd0;              // 时钟沿更新当前 BER 长度累计值
                        end                                 // 当前语句组结束
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                P_OID_VAL: begin                            // 处理OID 内容阶段
                    if (rx_rd_valid) begin                  // 读返回有效时消费当前输入字节
                        offset_r <= offset_r + 1'b1;        // 时钟沿更新输入字节偏移并推进至下一项

                        if (first_oid) begin                // 检查是否是 OID 首字节的条件
                            first_oid <= 1'b0;              // 时钟沿更新是否是 OID 首字节
                            seg_c     <= {9'd0, rx_rd_data[7:0] / 8'd40}; // 首字节高位组合段
                            arc_acc   <= {9'd0, rx_rd_data[7:0] % 8'd40}; // 首字节第二段转入待处理
                            arc_valid <= 1'b1;              // 时钟沿更新当前是否正在累积子标识
                        end                                 // 当前语句组结束
                        else begin                          // 前一条件不满足时执行本分支
                            if (arc_valid) begin            // 检查当前是否正在累积子标识的条件
                                arc_acc <= (arc_acc << 7) | {9'd0, rx_rd_data[6:0]};  // 时钟沿更新当前 base128 子标识累计
                                if (!rx_rd_data[7]) begin   // 检查读数据的条件
                                    seg_a <= seg_b;         // 时钟沿更新倒数第三段
                                    seg_b <= seg_c;         // 时钟沿更新倒数第二段
                                    seg_c <= (arc_acc << 7) | {9'd0, rx_rd_data[6:0]};  // 时钟沿更新倒数第一段
                                    arc_valid <= 1'b0;      // 时钟沿更新当前是否正在累积子标识
                                end                         // 当前语句组结束
                            end                             // 当前语句组结束
                            else if (rx_rd_data[7]) begin   // 检查读数据的条件
                                arc_valid <= 1'b1;          // 时钟沿更新当前是否正在累积子标识
                                arc_acc   <= {9'd0, rx_rd_data[6:0]};  // 时钟沿更新当前 base128 子标识累计
                            end                             // 当前语句组结束
                            else begin                      // 前一条件不满足时执行本分支
                                seg_a <= seg_b;             // 时钟沿更新倒数第三段
                                seg_b <= seg_c;             // 时钟沿更新倒数第二段
                                seg_c <= {9'd0, rx_rd_data[6:0]};  // 时钟沿更新倒数第一段
                            end                             // 当前语句组结束
                        end                                 // 当前语句组结束

                        if (remain <= 16'd1) begin          // 检查当前值域剩余字节数的条件
                            // 使用 OID 最后三段拼内部索引：1bit 表选 + 12bit VL 地址 + 3bit 计数选。
                            oid_r <= {seg_b[0], seg_c[11:0], final_seg[2:0]};  // 时钟沿更新内部对象索引
                            pdu_valid_r <= ((pdu_type_r == 2'd0) || (pdu_type_r == 2'd1)) &&  // 时钟沿更新PDU 关键字段有效脉冲
                                           (final_seg[2:0] <= 3'd4);  // 继续计算pdu_valid_r
                        end                                 // 当前语句组结束
                        else                                // 采用前一条件未满足时的处理
                            remain <= remain - 16'd1;       // 时钟沿更新当前值域剩余字节数
                    end                                     // 当前语句组结束
                end                                         // 当前语句组结束

                default: ;                                       // 其余状态没有数据通路动作
            endcase                                         // 当前分支选择结束

            phase <= nxt_phase;                                 // 状态寄存器只在第一段更新
        end                                                 // 当前语句组结束
    end                                                     // 当前语句组结束

    assign pdu_valid   = pdu_valid_r;                            // output [0:0]
    assign pdu_type    = pdu_type_r;                             // output [1:0]
    assign oid         = oid_r;                                  // output [15:0]
    assign decode_done = pdu_valid_r;                            // output [0:0]：OID 取到即结束当前帧

endmodule                                                   // 模块定义结束

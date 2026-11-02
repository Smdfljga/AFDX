// snmp_decoder : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module snmp_decoder #(                                      
    parameter DATA_WIDTH        = 8,        
    parameter BYTE_OFFSET_WIDTH = 11,       
    parameter OID_WIDTH         = 16        
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          start,                  
    input  wire [15:0]                   rx_frame_len,           

    
    output wire                          rx_rd_req,              
    output wire [BYTE_OFFSET_WIDTH-1:0]  rx_rd_byte_offset,      
    input  wire [DATA_WIDTH-1:0]         rx_rd_data,             
    input  wire                          rx_rd_valid,            

    
    output wire                          pdu_valid,              
    output wire [1:0]                    pdu_type,               
    output wire [OID_WIDTH-1:0]          oid,                    
    output wire                          decode_done             
);
localparam P_IDLE           = 6'd0;                          
    localparam P_SEQ_TAG        = 6'd1;                          
    localparam P_SEQ_LEN        = 6'd2;                          
    localparam P_VER_TAG        = 6'd3;                          
    localparam P_VER_LEN        = 6'd4;                          
    localparam P_VER_VAL        = 6'd5;                          
    localparam P_COMM_TAG       = 6'd6;                          
    localparam P_COMM_LEN       = 6'd7;                          
    localparam P_COMM_VAL       = 6'd8;                          
    localparam P_PDU_TAG        = 6'd9;                          
    localparam P_PDU_LEN        = 6'd10;                         
    localparam P_REQ_TAG        = 6'd11;                         
    localparam P_REQ_LEN        = 6'd12;                         
    localparam P_REQ_VAL        = 6'd13;                         
    localparam P_ERRSTAT_TAG    = 6'd14;                         
    localparam P_ERRSTAT_LEN    = 6'd15;                         
    localparam P_ERRSTAT_VAL    = 6'd16;                         
    localparam P_ERRIDX_TAG     = 6'd17;                         
    localparam P_ERRIDX_LEN     = 6'd18;                         
    localparam P_ERRIDX_VAL     = 6'd19;                         
    localparam P_VBL_TAG        = 6'd20;                         
    localparam P_VBL_LEN        = 6'd21;                         
    localparam P_VB_TAG         = 6'd22;                         
    localparam P_VB_LEN         = 6'd23;                         
    localparam P_OID_TAG        = 6'd24;                         
    localparam P_OID_LEN        = 6'd25;                         
    localparam P_OID_VAL        = 6'd26;                         
    localparam P_DONE           = 6'd27;                         
    reg [5:0]                 phase;                             
    reg [BYTE_OFFSET_WIDTH-1:0] offset_r;                        
    reg [15:0]                len_acc;                           
    reg [2:0]                 len_more;                          
    reg [15:0]                remain;                            
    reg [1:0]                 pdu_type_r;                        
    reg [OID_WIDTH-1:0]       oid_r;                             
    reg                       pdu_valid_r;                       
    reg [15:0]                seg_a;                             
    reg [15:0]                seg_b;                             
    reg [15:0]                seg_c;                             
    reg [15:0]                arc_acc;                           
    reg                       arc_valid;                         
    reg                       first_oid;                         
    wire [15:0] final_seg = arc_valid ?                     
                            ((arc_acc << 7) | {9'd0, rx_rd_data[6:0]}) :  
                            {9'd0, rx_rd_data[6:0]};            
    reg [5:0] nxt_phase;

endmodule

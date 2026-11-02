// tftp : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module tftp #(                                              
    parameter DATA_WIDTH        = 8,        
    parameter BYTE_OFFSET_WIDTH = 11        
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          start,                  
    input  wire [15:0]                   rx_frame_len,           

    
    output wire                          rx_rd_req,              
    output wire [BYTE_OFFSET_WIDTH-1:0]  rx_rd_byte_offset,      
    input  wire [DATA_WIDTH-1:0]         rx_rd_data,             
    input  wire                          rx_rd_valid,            

    
    output wire                          tftp_op_valid,          
    output wire [1:0]                    tftp_op_type,           
    output wire [15:0]                   tftp_block_num,         
    output wire [15:0]                   tftp_data_len,          

    
    output wire                          buf_wr_en,              
    output wire [DATA_WIDTH-1:0]         buf_wr_data,            
    output wire                          buf_rd_en,              
    input  wire [DATA_WIDTH-1:0]         buf_rd_data,            
    input  wire                          buf_rd_valid,           

    
    output wire                          flash_wr_req,           
    output wire [23:0]                   flash_wr_addr,          
    input  wire                          flash_wr_done,          

    
    output wire                          tx_wr_en,               
    output wire [BYTE_OFFSET_WIDTH-1:0]  tx_wr_byte_offset,      
    output wire [DATA_WIDTH-1:0]         tx_wr_data,             
    output wire                          tx_frame_done,          
    input  wire                          tx_wr_gnt,              

    
    output wire                          load_busy,              
    output wire                          load_done,              
    output wire                          load_error              
);
localparam S_IDLE       = 5'd0;                              
    localparam S_RD_OP0     = 5'd1;                              
    localparam S_RD_OP1     = 5'd2;                              
    localparam S_DRAIN      = 5'd3;                              
    localparam S_RD_BLOCK0  = 5'd4;                              
    localparam S_RD_BLOCK1  = 5'd5;                              
    localparam S_RD_DATA    = 5'd6;                              
    localparam S_FIFO_RD    = 5'd7;                              
    localparam S_FIFO_WAIT  = 5'd8;                              
    localparam S_FLASH_REQ  = 5'd9;                              
    localparam S_FLASH_WAIT = 5'd10;                             
    localparam S_TX0        = 5'd11;                             
    localparam S_TX1        = 5'd12;                             
    localparam S_TX2        = 5'd13;                             
    localparam S_TX3        = 5'd14;                             
    localparam S_ERR        = 5'd15;                             
    reg [4:0]                  state;                            
    reg [BYTE_OFFSET_WIDTH-1:0] rd_ptr;                          
    reg [7:0]                 op_lo;                             
    reg [7:0]                 op_hi;                             
    reg [15:0]                block_r;                           
    reg [15:0]                data_len_r;                        
    reg [15:0]                remain_r;                          
    reg [15:0]                flash_idx_r;                       
    reg [1:0]                 post_action;                       
    reg                       busy_r;                            
    reg                       done_r;                            
    reg                       error_r;                           
    reg                       op_valid_r;                        
    wire [23:0] flash_base;
    wire reading = (state == S_RD_OP0)    || (state == S_RD_OP1) ||  
                   (state == S_DRAIN)     || (state == S_RD_BLOCK0) ||  
                   (state == S_RD_BLOCK1) || (state == S_RD_DATA); 
    wire writing_ack = (state == S_TX0) || (state == S_TX1) ||  
                       (state == S_TX2) || (state == S_TX3);     
    reg [4:0] nxt_state;                                        
    reg [7:0] ack_byte;

endmodule

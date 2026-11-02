// tx_wr_arb : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module tx_wr_arb #(                                         
    parameter VL_INDEX_WIDTH    = 7,        
    parameter SLOT_WIDTH        = 4,        
    parameter BYTE_OFFSET_WIDTH = 11,       
    parameter DATA_WIDTH        = 8         
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          app_wr_req,             
    input  wire [VL_INDEX_WIDTH-1:0]     app_wr_vl_index,        
    input  wire [BYTE_OFFSET_WIDTH-1:0]  app_wr_byte_offset,     
    input  wire [DATA_WIDTH-1:0]         app_wr_data,            
    input  wire                          app_frame_done,         

    
    input  wire                          snmp_wr_req,            
    input  wire [VL_INDEX_WIDTH-1:0]     snmp_wr_vl_index,       
    input  wire [BYTE_OFFSET_WIDTH-1:0]  snmp_wr_byte_offset,    
    input  wire [DATA_WIDTH-1:0]         snmp_wr_data,           
    input  wire                          snmp_frame_done,        

    
    input  wire                          dl_wr_req,              
    input  wire [VL_INDEX_WIDTH-1:0]     dl_wr_vl_index,         
    input  wire [BYTE_OFFSET_WIDTH-1:0]  dl_wr_byte_offset,      
    input  wire [DATA_WIDTH-1:0]         dl_wr_data,             
    input  wire                          dl_frame_done,          

    
    input  wire                          rtc_wr_req,             
    input  wire [VL_INDEX_WIDTH-1:0]     rtc_wr_vl_index,        
    input  wire [BYTE_OFFSET_WIDTH-1:0]  rtc_wr_byte_offset,     
    input  wire [DATA_WIDTH-1:0]         rtc_wr_data,            
    input  wire                          rtc_frame_done,         

    
    output wire                          buf_wr_en,              
    output wire [SLOT_WIDTH-1:0]         buf_wr_vl_index,        
    output wire [BYTE_OFFSET_WIDTH-1:0]  buf_wr_byte_offset,     
    output wire [DATA_WIDTH-1:0]         buf_wr_data,            
    output wire                          buf_len_wr_en,          
    output wire [SLOT_WIDTH-1:0]         buf_len_vl_index,       
    output wire [BYTE_OFFSET_WIDTH-1:0]  buf_len_byte_offset,    

    
    output wire                          app_wr_gnt,             
    output wire                          snmp_wr_gnt,            
    output wire                          dl_wr_gnt,              
    output wire                          rtc_wr_gnt,             

    
    input  wire [15:0]                   vl_busy                 
);
localparam FD_DEPTH = 8;                                    
    reg [VL_INDEX_WIDTH-1:0]     fd_vl [0:FD_DEPTH-1];          
    reg [BYTE_OFFSET_WIDTH-1:0]  fd_off [0:FD_DEPTH-1];         
    reg [2:0]                    fd_wr_ptr;                     
    reg [2:0]                    fd_rd_ptr;                     
    reg [4:0]                    fd_cnt;                        
    integer fd_i;                                               
    wire any_fd;
    wire [2:0] fd_event_cnt =                               
        {2'b0, app_frame_done} + {2'b0, snmp_frame_done} +  
        {2'b0, dl_frame_done}  + {2'b0, rtc_frame_done};    
    wire fd_empty;
    wire fd_pop;
    wire [SLOT_WIDTH-1:0] app_slot;
    wire [SLOT_WIDTH-1:0] snmp_slot;
    wire [SLOT_WIDTH-1:0] dl_slot;
    wire [SLOT_WIDTH-1:0] rtc_slot;
    wire app_ok;
    wire snmp_ok;
    wire dl_ok;
    wire rtc_ok;
    wire grant_ok;
    wire app_gnt;
    wire snmp_gnt;
    wire dl_gnt;
    wire rtc_gnt;

endmodule

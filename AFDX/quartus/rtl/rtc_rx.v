// rtc_rx : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module rtc_rx #(                                            
    parameter DATA_WIDTH        = 8,        
    parameter RTC_WIDTH         = 48,       
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

    
    output wire [RTC_WIDTH-1:0]          master_ts,              
    output wire [31:0]                   delay_val,              
    output wire                          rx_valid                
);
localparam S_IDLE = 2'd0;                                   
    localparam S_RD   = 2'd1;                                   
    localparam S_DONE = 2'd2;                                   
    reg [1:0]                 state;                            
    reg [BYTE_OFFSET_WIDTH-1:0] rd_ptr;                         
    reg [RTC_WIDTH-1:0]      master_r;                          
    reg [31:0]               delay_r;                           
    reg [1:0] nxt_state;

endmodule

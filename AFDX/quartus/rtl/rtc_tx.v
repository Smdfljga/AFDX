// rtc_tx : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module rtc_tx #(                                            
    parameter DATA_WIDTH        = 8,        
    parameter RTC_WIDTH         = 48,       
    parameter BYTE_OFFSET_WIDTH = 11        
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          tx_req,                 
    input  wire [RTC_WIDTH-1:0]          local_ts,               

    
    input  wire                          tx_wr_gnt,              

    
    output wire                          tx_wr_en,               
    output wire [BYTE_OFFSET_WIDTH-1:0]  tx_wr_byte_offset,      
    output wire [DATA_WIDTH-1:0]         tx_wr_data,             
    output wire                          tx_frame_done           
);
localparam S_IDLE = 2'd0;                                   
    localparam S_SEND = 2'd1;                                   
    reg [1:0]                 state;                            
    reg [BYTE_OFFSET_WIDTH-1:0] wr_ptr;                         
    reg [RTC_WIDTH-1:0]      ts_r;                              
    reg [1:0] nxt_state;                                        
    reg [7:0] out_data_r;

endmodule

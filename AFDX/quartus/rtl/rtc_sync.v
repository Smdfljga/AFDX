// rtc_sync : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module rtc_sync #(                                          
    parameter DATA_WIDTH        = 8,        
    parameter VL_INDEX_WIDTH    = 4,        
    parameter BYTE_OFFSET_WIDTH = 11,       
    parameter RTC_WIDTH         = 48,       
    parameter CNT_WIDTH         = 32,       
    parameter VL_INDEX_SELF     = 4'd3      
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          rx_ready_rtc,           
    output wire                          rx_rd_req,              
    output wire [BYTE_OFFSET_WIDTH-1:0]  rx_rd_byte_offset,      
    input  wire [DATA_WIDTH-1:0]         rx_rd_data,             
    input  wire                          rx_rd_valid,            
    input  wire [15:0]                   rx_frame_len,           

    
    output wire                          tx_wr_en,               
    output wire [BYTE_OFFSET_WIDTH-1:0]  tx_wr_byte_offset,      
    output wire [DATA_WIDTH-1:0]         tx_wr_data,             
    output wire                          tx_frame_done,          
    input  wire                          tx_wr_gnt,              

    
    output wire [RTC_WIDTH-1:0]          local_rtc,              
    output wire                          rtc_sync_valid,         
    input  wire                          master_mode,            
    input  wire [15:0]                   sync_period_ms,         
    input  wire [31:0]                   rx_process_delay        
);
wire [RTC_WIDTH-1:0] master_ts;                             
    wire [31:0]          delay_val;                             
    wire                 rtc_rx_valid;                          
    wire [RTC_WIDTH-1:0] corrected_ts;                          
    wire                 calc_done;                             
    wire [RTC_WIDTH-1:0] rtc_value;                             
    wire                 rtc_tick;                              
    local_rtc #(                                            
        .RTC_WIDTH (RTC_WIDTH)                              
    ) u_local_rtc (                                         
        .clk         (clk),                                     
        .rst_b       (rst_b),                                   
        .sync_en     (calc_done),                               
        .sync_value  (corrected_ts),                            
        .sync_period_ms(sync_period_ms),                        
        .rtc_value   (rtc_value),                               
        .rtc_tick    (rtc_tick)                                 
    );                                                      
    reg rx_ready_d;                                             
    rtc_rx #(                                               
        .DATA_WIDTH        (DATA_WIDTH),                    
        .RTC_WIDTH         (RTC_WIDTH),                     
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH)              
    ) u_rtc_rx (                                            
        .clk               (clk),                               
        .rst_b             (rst_b),                             
        .start             (rx_ready_d),                        
        .rx_frame_len      (rx_frame_len),                      
        .rx_rd_req         (rx_rd_req),                         
        .rx_rd_byte_offset (rx_rd_byte_offset),                 
        .rx_rd_data        (rx_rd_data),                        
        .rx_rd_valid       (rx_rd_valid),                       
        .master_ts         (master_ts),                         
        .delay_val         (delay_val),                         
        .rx_valid          (rtc_rx_valid)                       
    );                                                      
    delay_comp #(                                           
        .RTC_WIDTH (RTC_WIDTH)                              
    ) u_delay_comp (                                        
        .clk              (clk),                                
        .rst_b            (rst_b),                              
        .master_ts        (master_ts),                          
        .delay_val        (delay_val),                          
        .rx_process_delay (rx_process_delay),                   
        .calc_req         (rtc_rx_valid),                       
        .corrected_ts     (corrected_ts),                       
        .calc_done        (calc_done)                           
    );                                                      
    rtc_tx #(                                               
        .DATA_WIDTH        (DATA_WIDTH),                    
        .RTC_WIDTH         (RTC_WIDTH),                     
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH)              
    ) u_rtc_tx (                                            
        .clk               (clk),                               
        .rst_b             (rst_b),                             
        .tx_req            (master_mode & rtc_tick),            
        .local_ts          (rtc_value),                         
        .tx_wr_gnt         (tx_wr_gnt),                         
        .tx_wr_en          (tx_wr_en),                          
        .tx_wr_byte_offset (tx_wr_byte_offset),                 
        .tx_wr_data        (tx_wr_data),                        
        .tx_frame_done     (tx_frame_done)                      
    );

endmodule

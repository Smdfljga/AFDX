// afdx_port_buf : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module afdx_port_buf #(                                     
    parameter DATA_WIDTH        = 8,        
    parameter VL_INDEX_WIDTH    = 4,        
    parameter BYTE_OFFSET_WIDTH = 11,       
    parameter VL_IND_WIDTH      = 7,        
    parameter VL_INDEX_SNMP     = 4'd1,     
    parameter VL_INDEX_615A     = 4'd2,     
    parameter VL_INDEX_RTC      = 4'd3      
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          rx_wr_en,               
    input  wire [VL_INDEX_WIDTH-1:0]     rx_wr_vl_index,         
    input  wire [BYTE_OFFSET_WIDTH-1:0]  rx_wr_byte_offset,      
    input  wire [DATA_WIDTH-1:0]         rx_wr_data,             
    input  wire                          rx_wr_frame_done,       
    input  wire [15:0]                   rx_wr_frame_len,        
    input  wire                          rx_wr_queue_mode,       
    output wire                          rx_wr_full,             

    
    input  wire                          app_rd_req,             
    input  wire [VL_INDEX_WIDTH-1:0]     app_rd_vl_index,        
    input  wire [BYTE_OFFSET_WIDTH-1:0]  app_rd_byte_offset,     
    output wire                          app_rd_valid,           

    
    input  wire                          snmp_rd_req,            
    input  wire [BYTE_OFFSET_WIDTH-1:0]  snmp_rd_byte_offset,    
    output wire                          snmp_rd_valid,          
    input  wire                          dl_rd_req,              
    input  wire [BYTE_OFFSET_WIDTH-1:0]  dl_rd_byte_offset,      
    output wire                          dl_rd_valid,            
    input  wire                          rtc_rd_req,             
    input  wire [BYTE_OFFSET_WIDTH-1:0]  rtc_rd_byte_offset,     
    output wire                          rtc_rd_valid,           

    
    output wire [DATA_WIDTH-1:0]         rx_rd_data,             

    
    output wire [15:0]                   app_rd_frame_len,       
    output wire [3:0]                    app_rd_frame_cnt,       
    output wire [15:0]                   snmp_rd_frame_len,      
    output wire [3:0]                    snmp_rd_frame_cnt,      
    output wire [15:0]                   dl_rd_frame_len,        
    output wire [3:0]                    dl_rd_frame_cnt,        
    output wire [15:0]                   rtc_rd_frame_len,       
    output wire [3:0]                    rtc_rd_frame_cnt,       

    
    input  wire                          app_wr_req,             
    input  wire [VL_IND_WIDTH-1:0]       app_wr_vl_index,        
    input  wire [BYTE_OFFSET_WIDTH-1:0]  app_wr_byte_offset,     
    input  wire [DATA_WIDTH-1:0]         app_wr_data,            
    input  wire                          app_frame_done,         

    
    input  wire                          snmp_wr_req,            
    input  wire [BYTE_OFFSET_WIDTH-1:0]  snmp_wr_byte_offset,    
    input  wire [DATA_WIDTH-1:0]         snmp_wr_data,           
    input  wire                          snmp_frame_done,        
    input  wire                          dl_wr_req,              
    input  wire [BYTE_OFFSET_WIDTH-1:0]  dl_wr_byte_offset,      
    input  wire [DATA_WIDTH-1:0]         dl_wr_data,             
    input  wire                          dl_frame_done,          
    input  wire                          rtc_wr_req,             
    input  wire [BYTE_OFFSET_WIDTH-1:0]  rtc_wr_byte_offset,     
    input  wire [DATA_WIDTH-1:0]         rtc_wr_data,            
    input  wire                          rtc_frame_done,         

    
    input  wire                          tx_rd_en,               
    input  wire [VL_INDEX_WIDTH-1:0]     tx_rd_vl_index,         
    input  wire [BYTE_OFFSET_WIDTH-1:0]  tx_rd_byte_offset,      
    output wire [DATA_WIDTH-1:0]         tx_rd_data,             
    output wire                          tx_rd_valid,            
    input  wire [15:0]                   tx_payload_len,         
    input  wire [15:0]                   abort_vl,               

    
    output wire                          app_wr_gnt,             
    output wire                          snmp_wr_gnt,            
    output wire                          dl_wr_gnt,              
    output wire                          rtc_wr_gnt              
);
wire                      rx_buf_rd_en;                     
    wire [VL_INDEX_WIDTH-1:0] rx_buf_rd_vl_index;               
    wire [BYTE_OFFSET_WIDTH-1:0] rx_buf_rd_byte_offset;         
    wire [DATA_WIDTH-1:0]     rx_buf_rd_data;                   
    wire                      tx_buf_wr_en;                     
    wire [VL_INDEX_WIDTH-1:0] tx_buf_wr_vl_index;               
    wire [BYTE_OFFSET_WIDTH-1:0] tx_buf_wr_byte_offset;         
    wire [DATA_WIDTH-1:0]     tx_buf_wr_data;                   
    wire                      tx_buf_len_wr_en;                 
    wire [VL_INDEX_WIDTH-1:0] tx_buf_len_vl_index;              
    wire [BYTE_OFFSET_WIDTH-1:0] tx_buf_len_byte_offset;        
    wire [(1<<VL_INDEX_WIDTH)*16-1:0] rx_frame_len_all;         
    wire [(1<<VL_INDEX_WIDTH)*4-1:0]  rx_frame_cnt_all;         
    wire [15:0]               tx_buf_vl_busy;                   
    rx_port_buf #(                                          
        .DATA_WIDTH        (DATA_WIDTH),                    
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             
        .FRAME_LEN_WIDTH   (16),                            
        .FRAME_CNT_WIDTH   (3)                              
    ) u_rx_port_buf (                                       
        .clk           (clk),                                  
        .rst_b         (rst_b),                                
        .wr_en         (rx_wr_en),                             
        .wr_vl_index   (rx_wr_vl_index),                       
        .wr_byte_offset(rx_wr_byte_offset),                    
        .wr_data       (rx_wr_data),                           
        .wr_frame_done (rx_wr_frame_done),                     
        .wr_frame_len  (rx_wr_frame_len),                      
        .wr_queue_mode (rx_wr_queue_mode),                     
        .wr_full       (rx_wr_full),                           
        .rd_en         (rx_buf_rd_en),                         
        .rd_vl_index   (rx_buf_rd_vl_index),                   
        .rd_byte_offset(rx_buf_rd_byte_offset),                
        .rd_data       (rx_buf_rd_data),                       
        .rd_valid      (),                                     
        .rd_frame_len_all(rx_frame_len_all),                   
        .rd_frame_cnt_all(rx_frame_cnt_all)                    
    );                                                      
    rx_rd_arb #(                                            
        .DATA_WIDTH        (DATA_WIDTH),                    
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH)              
    ) u_rx_rd_arb (                                         
        .clk               (clk),                              
        .rst_b             (rst_b),                            
        .app_rd_req        (app_rd_req),                       
        .app_rd_vl_index   (app_rd_vl_index),                  
        .app_rd_byte_offset(app_rd_byte_offset),               
        .app_rd_valid      (app_rd_valid),                     
        .snmp_rd_req       (snmp_rd_req),                      
        .snmp_rd_vl_index  (VL_INDEX_SNMP),                    
        .snmp_rd_byte_offset(snmp_rd_byte_offset),             
        .snmp_rd_valid     (snmp_rd_valid),                    
        .dl_rd_req         (dl_rd_req),                        
        .dl_rd_vl_index    (VL_INDEX_615A),                    
        .dl_rd_byte_offset (dl_rd_byte_offset),                
        .dl_rd_valid       (dl_rd_valid),                      
        .rtc_rd_req        (rtc_rd_req),                       
        .rtc_rd_vl_index   (VL_INDEX_RTC),                     
        .rtc_rd_byte_offset(rtc_rd_byte_offset),               
        .rtc_rd_valid      (rtc_rd_valid),                     
        .buf_rd_en         (rx_buf_rd_en),                     
        .buf_rd_vl_index   (rx_buf_rd_vl_index),               
        .buf_rd_byte_offset(rx_buf_rd_byte_offset),            
        .buf_rd_data       (rx_buf_rd_data),                   
        .rd_data           (rx_rd_data)                        
    );                                                      
    tx_port_buf #(                                          
        .DATA_WIDTH        (DATA_WIDTH),                    
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH)              
    ) u_tx_port_buf (                                       
        .clk               (clk),                              
        .rst_b             (rst_b),                            
        .wr_en             (tx_buf_wr_en),                     
        .wr_vl_index       (tx_buf_wr_vl_index),               
        .wr_byte_offset    (tx_buf_wr_byte_offset),            
        .wr_data           (tx_buf_wr_data),                   
        .len_wr_en         (tx_buf_len_wr_en),                 
        .len_vl_index      (tx_buf_len_vl_index),              
        .len_byte_offset   (tx_buf_len_byte_offset),           
        .rd_en             (tx_rd_en),                         
        .rd_vl_index       (tx_rd_vl_index),                   
        .rd_byte_offset    (tx_rd_byte_offset),                
        .rd_data           (tx_rd_data),                       
        .rd_valid          (tx_rd_valid),                      
        .payload_len       (tx_payload_len),                   
        .vl_busy           (tx_buf_vl_busy),                    
        .abort_vl          (abort_vl)                           
    );                                                      
    tx_wr_arb #(                                            
        .VL_INDEX_WIDTH    (VL_IND_WIDTH),                  
        .SLOT_WIDTH        (VL_INDEX_WIDTH),                
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             
        .DATA_WIDTH        (DATA_WIDTH)                     
    ) u_tx_wr_arb (                                         
        .clk                  (clk),                           
        .rst_b                (rst_b),                         
        .app_wr_req           (app_wr_req),                    
        .app_wr_vl_index      (app_wr_vl_index),               
        .app_wr_byte_offset   (app_wr_byte_offset),            
        .app_wr_data          (app_wr_data),                   
        .app_frame_done       (app_frame_done),                
        .snmp_wr_req          (snmp_wr_req),                   
        .snmp_wr_vl_index     ({{(VL_IND_WIDTH-4){1'b0}}, VL_INDEX_SNMP}), 
        .snmp_wr_byte_offset  (snmp_wr_byte_offset),           
        .snmp_wr_data         (snmp_wr_data),                  
        .snmp_frame_done      (snmp_frame_done),               
        .dl_wr_req            (dl_wr_req),                     
        .dl_wr_vl_index       ({{(VL_IND_WIDTH-4){1'b0}}, VL_INDEX_615A}), 
        .dl_wr_byte_offset    (dl_wr_byte_offset),             
        .dl_wr_data           (dl_wr_data),                    
        .dl_frame_done        (dl_frame_done),                 
        .rtc_wr_req           (rtc_wr_req),                    
        .rtc_wr_vl_index      ({{(VL_IND_WIDTH-4){1'b0}}, VL_INDEX_RTC}),  
        .rtc_wr_byte_offset   (rtc_wr_byte_offset),            
        .rtc_wr_data          (rtc_wr_data),                   
        .rtc_frame_done       (rtc_frame_done),                
        .buf_wr_en            (tx_buf_wr_en),                  
        .buf_wr_vl_index      (tx_buf_wr_vl_index),            
        .buf_wr_byte_offset   (tx_buf_wr_byte_offset),         
        .buf_wr_data          (tx_buf_wr_data),                
        .buf_len_wr_en        (tx_buf_len_wr_en),              
        .buf_len_vl_index     (tx_buf_len_vl_index),           
        .buf_len_byte_offset  (tx_buf_len_byte_offset),        
        .app_wr_gnt           (app_wr_gnt),                    
        .snmp_wr_gnt          (snmp_wr_gnt),                   
        .dl_wr_gnt            (dl_wr_gnt),                     
        .rtc_wr_gnt           (rtc_wr_gnt),                    
        .vl_busy              (tx_buf_vl_busy)                 
    );

endmodule

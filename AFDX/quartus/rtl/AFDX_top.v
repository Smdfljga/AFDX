// AFDX_top : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module AFDX_top #(                                          
    parameter VLID_WIDTH        = 16,       
    parameter VL_ADDR_WIDTH     = 12,       
    parameter DATA_WIDTH        = 8,        
    parameter CNT_WIDTH         = 32,       
    parameter VL_INDEX_WIDTH    = 4,        
    parameter BYTE_OFFSET_WIDTH = 11,       
    parameter RTC_WIDTH         = 48,       
    parameter STATE_WIDTH       = 64,       
    parameter REDUNDANCY_EN     = 1'b1,     
    parameter VL_INDEX_SNMP     = 4'd1,     
    parameter VL_INDEX_615A     = 4'd2,     
    parameter VL_INDEX_RTC      = 4'd3,     
    parameter RTC_MASTER_MODE   = 1'b0,     
    parameter RTC_SYNC_PERIOD   = 16'd10,   
    parameter RTC_PROC_DELAY    = 32'd100   
)(                                                          
    
    input  wire                          clk_sys,                
    input  wire                          rst_b,                  

    
    input  wire [DATA_WIDTH-1:0]         ff_rx_data,             
    input  wire                          ff_rx_data_vld,         
    input  wire                          ff_rx_sop,              
    input  wire                          ff_rx_eop,              
    input  wire                          ff_rx_err,              
    output wire                          ff_rx_rdy,              
    input  wire                          rx_frame_net,           

    
    output wire [DATA_WIDTH-1:0]         ff_tx_data,             
    output wire                          ff_tx_wren,             
    output wire                          ff_tx_sop,              
    output wire                          ff_tx_eop,              
    output wire                          ff_tx_err,              
    input  wire                          ff_tx_rdy,              

    
    input  wire                          cfg_wr_en,              
    input  wire [VL_ADDR_WIDTH-1:0]      cfg_wr_addr,            
    input  wire [VLID_WIDTH-1:0]         cfg_wr_vlid,            
    input  wire [15:0]                   cfg_wr_udp_port,        
    input  wire [1:0]                    cfg_wr_port_type,       
    input  wire [15:0]                   cfg_wr_bag,             
    input  wire [15:0]                   cfg_wr_lmax,            
    input  wire                          cfg_wr_rm_en,           
    input  wire                          cfg_wr_ic_mode,         
    output wire                          cfg_done,               

    
    input  wire [VL_INDEX_WIDTH-1:0]     app_rd_vl_index,        
    input  wire [BYTE_OFFSET_WIDTH-1:0]  app_rd_byte_offset,     
    input  wire                          app_rd_en,              
    output wire [DATA_WIDTH-1:0]         app_rd_data,            
    output wire                          app_rd_valid,           
    output wire [15:0]                   app_rd_frame_len,       
    output wire [3:0]                    app_rd_frame_cnt,       
    input  wire                          app_wr_en,              
    input  wire [6:0]                    app_wr_vl_index,        
    input  wire [BYTE_OFFSET_WIDTH-1:0]  app_wr_byte_offset,     
    input  wire [DATA_WIDTH-1:0]         app_wr_data,            
    input  wire                          app_tx_req,             
    output wire                          app_wr_gnt,             

    
    output wire [RTC_WIDTH-1:0]          local_rtc,              
    output wire                          rtc_sync_valid,         

    
    output wire                          irq_rx_frame,           
    output wire                          irq_tx_done,            
    output wire                          irq_error               
);
wire [VL_ADDR_WIDTH-1:0]  rx_cfg_addr;                    
    wire                      rx_cfg_rd_en;                   
    wire [VLID_WIDTH-1:0]     rx_cfg_tag;                     
    wire                      rx_cfg_valid;                   
    wire [1:0]                rx_cfg_port_type;               
    wire [15:0]               rx_cfg_udp_port;                
    wire [15:0]               rx_cfg_bag;                     
    wire [15:0]               rx_cfg_lmax;                    
    wire                      rx_cfg_rm_en;                   
    wire                      rx_cfg_ic_mode;                 
    wire [VL_ADDR_WIDTH-1:0]  tx_cfg_addr;                    
    wire                      tx_cfg_rd_en;                   
    wire [VLID_WIDTH-1:0]     tx_cfg_tag;                     
    wire                      tx_cfg_valid;                   
    wire [1:0]                tx_cfg_port_type;               
    wire [15:0]               tx_cfg_udp_port;                
    wire [15:0]               tx_cfg_bag;                     
    wire [15:0]               tx_cfg_lmax;                    
    wire                      tx_cfg_rm_en;                   
    wire [VL_ADDR_WIDTH-1:0]  rx_st_addr;                     
    wire                      rx_st_rd_en;                    
    wire [STATE_WIDTH-1:0]    rx_st_rd_data;                  
    wire                      rx_st_wr_en;                    
    wire [STATE_WIDTH-1:0]    rx_st_wr_data;                  
    wire [VL_ADDR_WIDTH-1:0]  tx_st_addr;                     
    wire                      tx_st_rd_en;                    
    wire [STATE_WIDTH-1:0]    tx_st_rd_data;                  
    wire                      tx_st_wr_en;                    
    wire [STATE_WIDTH-1:0]    tx_st_wr_data;                  
    wire [VL_ADDR_WIDTH-1:0]  rx_mib_addr;                    
    wire                      mib_rx_frame_inc;               
    wire                      mib_rx_error_inc;               
    wire                      mib_sn_error_inc;               
    wire                      mib_rm_drop_inc;                
    wire                      mib_rx_byte_inc;                
    wire [VL_ADDR_WIDTH-1:0]  tx_mib_addr;                    
    wire                      mib_tx_frame_inc;               
    wire                      mib_tx_byte_inc;                
    wire                      mib_tx_error_inc;               
    wire                      mib_tx_frag_inc;                
    wire                      mib_tx_bag_inc;                 
    wire [(1<<VL_INDEX_WIDTH)*VLID_WIDTH-1:0] slot_vlid;       
    wire                      mib_sel;                        
    wire [VL_ADDR_WIDTH-1:0]  mib_rd_addr;                    
    wire                      mib_rd_en;                      
    wire [5*CNT_WIDTH-1:0]    mib_rd_data;                    
    wire                      rx_ready_app;                   
    wire                      rx_ready_snmp;                  
    wire                      rx_ready_615a;                  
    wire                      rx_ready_rtc;                   
    wire                      rx_port_wr_en;                  
    wire [VL_INDEX_WIDTH-1:0] rx_port_wr_vl_index;            
    wire [BYTE_OFFSET_WIDTH-1:0] rx_port_wr_byte_offset;      
    wire [DATA_WIDTH-1:0]     rx_port_wr_data;                
    wire                      rx_port_wr_frame_done;          
    wire [15:0]               rx_port_wr_frame_len;           
    wire                      rx_port_queue_mode;             
    wire                      rx_port_wr_full;                
    wire [DATA_WIDTH-1:0]     rx_rd_data_bus;                 
    wire                      snmp_rx_rd_req;                 
    wire [BYTE_OFFSET_WIDTH-1:0] snmp_rx_rd_byte_offset;      
    wire                      snmp_rx_rd_valid;               
    wire [15:0]               snmp_rx_frame_len;             
    wire [3:0]                snmp_rx_frame_cnt;             
    wire                      dl_rx_rd_req;                   
    wire [BYTE_OFFSET_WIDTH-1:0] dl_rx_rd_byte_offset;        
    wire                      dl_rx_rd_valid;                 
    wire [15:0]               dl_rx_frame_len;               
    wire [3:0]                dl_rx_frame_cnt;               
    wire                      rtc_rx_rd_req;                  
    wire [BYTE_OFFSET_WIDTH-1:0] rtc_rx_rd_byte_offset;       
    wire                      rtc_rx_rd_valid;                
    wire [15:0]               rtc_rx_frame_len;              
    wire [3:0]                rtc_rx_frame_cnt;              
    wire                      tx_port_rd_en;                  
    wire [VL_INDEX_WIDTH-1:0] tx_port_rd_vl_index;            
    wire [BYTE_OFFSET_WIDTH-1:0] tx_port_rd_byte_offset;      
    wire [DATA_WIDTH-1:0]     tx_port_rd_data;                
    wire                      tx_port_rd_valid;               
    wire [15:0]               tx_port_payload_len;            
    wire [15:0]               tx_abort_vl;                    
    wire                      snmp_tx_wr_en;                  
    wire [BYTE_OFFSET_WIDTH-1:0] snmp_tx_wr_byte_offset;      
    wire [DATA_WIDTH-1:0]     snmp_tx_wr_data;                
    wire                      snmp_tx_frame_done;             
    wire                      dl_tx_wr_en;                    
    wire [BYTE_OFFSET_WIDTH-1:0] dl_tx_wr_byte_offset;        
    wire [DATA_WIDTH-1:0]     dl_tx_wr_data;                  
    wire                      dl_tx_frame_done;               
    wire                      rtc_tx_wr_en;                   
    wire [BYTE_OFFSET_WIDTH-1:0] rtc_tx_wr_byte_offset;       
    wire [DATA_WIDTH-1:0]     rtc_tx_wr_data;                 
    wire                      rtc_tx_frame_done;              
    wire                      snmp_tx_wr_gnt;                 
    wire                      dl_tx_wr_gnt;                   
    wire                      rtc_tx_wr_gnt;                  
    wire                      load_busy;                      
    wire                      load_done;                      
    wire                      load_error;                     
    wire rx_frame_net_sel;
    afdx_rx #(                                              
        .DATA_WIDTH        (DATA_WIDTH),                    
        .VLID_WIDTH        (VLID_WIDTH),                    
        .VL_ADDR_WIDTH     (VL_ADDR_WIDTH),                 
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             
        .CNT_WIDTH         (CNT_WIDTH),                     
        .STATE_WIDTH       (STATE_WIDTH),                   
        .VL_INDEX_SNMP     (VL_INDEX_SNMP),                 
        .VL_INDEX_615A     (VL_INDEX_615A),                 
        .VL_INDEX_RTC      (VL_INDEX_RTC)                   
    ) u_afdx_rx (                                           
        .clk                  (clk_sys),                      
        .rst_b                (rst_b),                        
        .ff_rx_data           (ff_rx_data),                   
        .ff_rx_data_vld       (ff_rx_data_vld),               
        .ff_rx_sop            (ff_rx_sop),                    
        .ff_rx_eop            (ff_rx_eop),                    
        .ff_rx_err            (ff_rx_err),                    
        .ff_rx_rdy            (ff_rx_rdy),                    
        .frame_net            (rx_frame_net_sel),             
        .cfg_addr             (rx_cfg_addr),                  
        .cfg_rd_en            (rx_cfg_rd_en),                 
        .cfg_tag              (rx_cfg_tag),                   
        .cfg_valid            (rx_cfg_valid),                 
        .cfg_port_type        (rx_cfg_port_type),             
        .cfg_udp_port         (rx_cfg_udp_port),              
        .cfg_bag              (rx_cfg_bag),                   
        .cfg_lmax             (rx_cfg_lmax),                  
        .cfg_rm_en            (rx_cfg_rm_en),                 
        .cfg_ic_mode          (rx_cfg_ic_mode),               
        .st_addr              (rx_st_addr),                   
        .st_rd_en             (rx_st_rd_en),                  
        .st_rd_data           (rx_st_rd_data),                
        .st_wr_en             (rx_st_wr_en),                  
        .st_wr_data           (rx_st_wr_data),                
        .port_wr_en           (rx_port_wr_en),                
        .port_wr_vl_index     (rx_port_wr_vl_index),          
        .port_wr_byte_offset  (rx_port_wr_byte_offset),       
        .port_wr_data         (rx_port_wr_data),              
        .port_wr_frame_done   (rx_port_wr_frame_done),        
        .port_wr_frame_len    (rx_port_wr_frame_len),         
        .port_wr_queue_mode   (rx_port_queue_mode),           
        .port_wr_full         (rx_port_wr_full),              
        .port_type            (),                             
        .rx_ready_app         (rx_ready_app),                 
        .rx_ready_snmp        (rx_ready_snmp),                
        .rx_ready_615a        (rx_ready_615a),                
        .rx_ready_rtc         (rx_ready_rtc),                 
        .mib_addr             (rx_mib_addr),                  
        .mib_rx_frame_inc     (mib_rx_frame_inc),             
        .mib_rx_error_inc     (mib_rx_error_inc),             
        .mib_sn_error_inc     (mib_sn_error_inc),             
        .mib_rm_drop_inc      (mib_rm_drop_inc),              
        .mib_rx_byte_inc      (mib_rx_byte_inc),              
        .irq_rx_frame         (irq_rx_frame),                 
        .irq_error            (irq_error)                     
    );                                                      
    afdx_tx #(                                              
        .DATA_WIDTH        (DATA_WIDTH),                    
        .VLID_WIDTH        (VLID_WIDTH),                    
        .VL_ADDR_WIDTH     (VL_ADDR_WIDTH),                 
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             
        .CNT_WIDTH         (CNT_WIDTH),                     
        .STATE_WIDTH       (STATE_WIDTH),                   
        .VL_INDEX_SNMP     (VL_INDEX_SNMP),                 
        .VL_INDEX_615A     (VL_INDEX_615A),                 
        .VL_INDEX_RTC      (VL_INDEX_RTC)                   
    ) u_afdx_tx (                                           
        .clk                  (clk_sys),                      
        .rst_b                (rst_b),                        
        .sys_ts               (local_rtc[31:0]),              
        .ff_tx_data           (ff_tx_data),                   
        .ff_tx_wren           (ff_tx_wren),                   
        .ff_tx_sop            (ff_tx_sop),                    
        .ff_tx_eop            (ff_tx_eop),                    
        .ff_tx_err            (ff_tx_err),                    
        .ff_tx_rdy            (ff_tx_rdy),                    
        .slot_vlid            (slot_vlid),                    
        .cfg_addr             (tx_cfg_addr),                  
        .cfg_rd_en            (tx_cfg_rd_en),                 
        .cfg_tag              (tx_cfg_tag),                   
        .cfg_valid            (tx_cfg_valid),                 
        .cfg_port_type        (tx_cfg_port_type),             
        .cfg_udp_port         (tx_cfg_udp_port),              
        .cfg_bag              (tx_cfg_bag),                   
        .cfg_lmax             (tx_cfg_lmax),                  
        .cfg_rm_en            (tx_cfg_rm_en),                 
        .st_addr              (tx_st_addr),                   
        .st_rd_en             (tx_st_rd_en),                  
        .st_rd_data           (tx_st_rd_data),                
        .st_wr_en             (tx_st_wr_en),                  
        .st_wr_data           (tx_st_wr_data),                
        .port_rd_en           (tx_port_rd_en),                
        .port_rd_vl_index     (tx_port_rd_vl_index),          
        .port_rd_byte_offset  (tx_port_rd_byte_offset),       
        .port_rd_data         (tx_port_rd_data),              
        .port_rd_valid        (tx_port_rd_valid),             
        .port_payload_len     (tx_port_payload_len),          
        .abort_vl             (tx_abort_vl),                  
        .tx_valid_app         (app_tx_req),                   
        .tx_valid_snmp        (snmp_tx_frame_done),           
        .tx_valid_615a        (dl_tx_frame_done),             
        .tx_valid_rtc         (rtc_tx_frame_done),            
        .mib_addr             (tx_mib_addr),                  
        .mib_tx_frame_inc     (mib_tx_frame_inc),             
        .mib_tx_byte_inc      (mib_tx_byte_inc),              
        .mib_tx_error_inc     (mib_tx_error_inc),             
        .mib_tx_frag_inc      (mib_tx_frag_inc),              
        .mib_tx_bag_inc       (mib_tx_bag_inc),               
        .irq_tx_done          (irq_tx_done)                   
    );                                                      
    afdx_vl_cfg #(                                          
        .VLID_WIDTH    (VLID_WIDTH),                        
        .VL_ADDR_WIDTH (VL_ADDR_WIDTH),                     
        .VL_INDEX_WIDTH (VL_INDEX_WIDTH),                   
        .CNT_WIDTH     (CNT_WIDTH),                         
        .STATE_WIDTH   (STATE_WIDTH)                        
    ) u_afdx_vl_cfg (                                       
        .clk                  (clk_sys),                      
        .rst_b                (rst_b),                        
        .cfg_wr_en            (cfg_wr_en),                    
        .cfg_wr_addr          (cfg_wr_addr),                  
        .cfg_wr_vlid          (cfg_wr_vlid),                  
        .cfg_wr_udp_port      (cfg_wr_udp_port),              
        .cfg_wr_port_type     (cfg_wr_port_type),             
        .cfg_wr_bag           (cfg_wr_bag),                   
        .cfg_wr_lmax          (cfg_wr_lmax),                  
        .cfg_wr_rm_en         (cfg_wr_rm_en),                 
        .cfg_wr_ic_mode       (cfg_wr_ic_mode),               
        .cfg_done             (cfg_done),                     
        .rx_cfg_addr          (rx_cfg_addr),                  
        .rx_cfg_rd_en         (rx_cfg_rd_en),                 
        .rx_cfg_tag           (rx_cfg_tag),                   
        .rx_cfg_valid         (rx_cfg_valid),                 
        .rx_cfg_port_type     (rx_cfg_port_type),             
        .rx_cfg_udp_port      (rx_cfg_udp_port),              
        .rx_cfg_bag           (rx_cfg_bag),                   
        .rx_cfg_lmax          (rx_cfg_lmax),                  
        .rx_cfg_rm_en         (rx_cfg_rm_en),                 
        .rx_cfg_ic_mode       (rx_cfg_ic_mode),               
        .tx_cfg_addr          (tx_cfg_addr),                  
        .tx_cfg_rd_en         (tx_cfg_rd_en),                 
        .tx_cfg_tag           (tx_cfg_tag),                   
        .tx_cfg_valid         (tx_cfg_valid),                 
        .tx_cfg_port_type     (tx_cfg_port_type),             
        .tx_cfg_udp_port      (tx_cfg_udp_port),              
        .tx_cfg_bag           (tx_cfg_bag),                   
        .tx_cfg_lmax          (tx_cfg_lmax),                  
        .tx_cfg_rm_en         (tx_cfg_rm_en),                 
        .rx_st_addr           (rx_st_addr),                   
        .rx_st_rd_en          (rx_st_rd_en),                  
        .rx_st_rd_data        (rx_st_rd_data),                
        .rx_st_wr_en          (rx_st_wr_en),                  
        .rx_st_wr_data        (rx_st_wr_data),                
        .tx_st_addr           (tx_st_addr),                   
        .tx_st_rd_en          (tx_st_rd_en),                  
        .tx_st_rd_data        (tx_st_rd_data),                
        .tx_st_wr_en          (tx_st_wr_en),                  
        .tx_st_wr_data        (tx_st_wr_data),                
        .rx_mib_addr          (rx_mib_addr),                  
        .mib_rx_frame_inc     (mib_rx_frame_inc),             
        .mib_rx_error_inc     (mib_rx_error_inc),             
        .mib_sn_error_inc     (mib_sn_error_inc),             
        .mib_rm_drop_inc      (mib_rm_drop_inc),              
        .mib_rx_byte_inc      (mib_rx_byte_inc),              
        .tx_mib_addr          (tx_mib_addr),                  
        .mib_tx_frame_inc     (mib_tx_frame_inc),             
        .mib_tx_byte_inc      (mib_tx_byte_inc),              
        .mib_tx_error_inc     (mib_tx_error_inc),             
        .mib_tx_frag_inc      (mib_tx_frag_inc),              
        .mib_tx_bag_inc       (mib_tx_bag_inc),               
        .mib_sel              (mib_sel),                      
        .mib_rd_addr          (mib_rd_addr),                  
        .mib_rd_en            (mib_rd_en),                    
        .mib_rd_data          (mib_rd_data),                  
        .slot_vlid            (slot_vlid)                     
    );                                                      
    reg [127:0] app_data_written;                               
    integer     app_written_i;                                  
    wire        app_frame_done = app_tx_req &&                  
                                 (app_data_written[app_wr_vl_index] || app_wr_gnt); 
    afdx_port_buf #(                                        
        .DATA_WIDTH        (DATA_WIDTH),                    
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                
        .VL_IND_WIDTH      (7),                             
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             
        .VL_INDEX_SNMP     (VL_INDEX_SNMP),                 
        .VL_INDEX_615A     (VL_INDEX_615A),                 
        .VL_INDEX_RTC      (VL_INDEX_RTC)                   
    ) u_afdx_port_buf (                                     
        .clk                  (clk_sys),                      
        .rst_b                (rst_b),                        
        .rx_wr_en             (rx_port_wr_en),                
        .rx_wr_vl_index       (rx_port_wr_vl_index),          
        .rx_wr_byte_offset    (rx_port_wr_byte_offset),       
        .rx_wr_data           (rx_port_wr_data),              
        .rx_wr_frame_done     (rx_port_wr_frame_done),        
        .rx_wr_frame_len      (rx_port_wr_frame_len),         
        .rx_wr_queue_mode     (rx_port_queue_mode),           
        .rx_wr_full           (rx_port_wr_full),              
        .app_rd_req           (app_rd_en),                    
        .app_rd_vl_index      (app_rd_vl_index),              
        .app_rd_byte_offset   (app_rd_byte_offset),           
        .app_rd_valid         (app_rd_valid),                 
        .snmp_rd_req          (snmp_rx_rd_req),               
        .snmp_rd_byte_offset  (snmp_rx_rd_byte_offset),       
        .snmp_rd_valid        (snmp_rx_rd_valid),             
        .dl_rd_req            (dl_rx_rd_req),                 
        .dl_rd_byte_offset    (dl_rx_rd_byte_offset),         
        .dl_rd_valid          (dl_rx_rd_valid),               
        .rtc_rd_req           (rtc_rx_rd_req),                
        .rtc_rd_byte_offset   (rtc_rx_rd_byte_offset),        
        .rtc_rd_valid         (rtc_rx_rd_valid),              
        .rx_rd_data           (rx_rd_data_bus),               
        .app_rd_frame_len     (app_rd_frame_len),             
        .app_rd_frame_cnt     (app_rd_frame_cnt),             
        .snmp_rd_frame_len    (snmp_rx_frame_len),            
        .snmp_rd_frame_cnt    (snmp_rx_frame_cnt),            
        .dl_rd_frame_len      (dl_rx_frame_len),              
        .dl_rd_frame_cnt      (dl_rx_frame_cnt),              
        .rtc_rd_frame_len     (rtc_rx_frame_len),             
        .rtc_rd_frame_cnt     (rtc_rx_frame_cnt),             
        .app_wr_req           (app_wr_en),                    
        .app_wr_vl_index      (app_wr_vl_index),              
        .app_wr_byte_offset   (app_wr_byte_offset),           
        .app_wr_data          (app_wr_data),                  
        .app_frame_done       (app_frame_done),               
        .snmp_wr_req          (snmp_tx_wr_en),                
        .snmp_wr_byte_offset  (snmp_tx_wr_byte_offset),       
        .snmp_wr_data         (snmp_tx_wr_data),              
        .snmp_frame_done      (snmp_tx_frame_done),           
        .dl_wr_req            (dl_tx_wr_en),                  
        .dl_wr_byte_offset    (dl_tx_wr_byte_offset),         
        .dl_wr_data           (dl_tx_wr_data),                
        .dl_frame_done        (dl_tx_frame_done),             
        .rtc_wr_req           (rtc_tx_wr_en),                 
        .rtc_wr_byte_offset   (rtc_tx_wr_byte_offset),        
        .rtc_wr_data          (rtc_tx_wr_data),               
        .rtc_frame_done       (rtc_tx_frame_done),            
        .tx_rd_en             (tx_port_rd_en),                
        .tx_rd_vl_index       (tx_port_rd_vl_index),          
        .tx_rd_byte_offset    (tx_port_rd_byte_offset),       
        .tx_rd_data           (tx_port_rd_data),              
        .tx_rd_valid          (tx_port_rd_valid),             
        .tx_payload_len       (tx_port_payload_len),          
        .abort_vl             (tx_abort_vl),                  
        .app_wr_gnt           (app_wr_gnt),                   
        .snmp_wr_gnt          (snmp_tx_wr_gnt),               
        .dl_wr_gnt            (dl_tx_wr_gnt),                 
        .rtc_wr_gnt           (rtc_tx_wr_gnt)                 
    );                                                      
    snmp_agent #(                                           
        .DATA_WIDTH        (DATA_WIDTH),                    
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             
        .CNT_WIDTH         (CNT_WIDTH),                     
        .VL_ADDR_WIDTH     (VL_ADDR_WIDTH),                 
        .VL_INDEX_SELF     (VL_INDEX_SNMP)                  
    ) u_snmp_agent (                                        
        .clk                (clk_sys),                        
        .rst_b              (rst_b),                          
        .rx_ready_snmp      (rx_ready_snmp),                  
        .rx_rd_req          (snmp_rx_rd_req),                 
        .rx_rd_byte_offset  (snmp_rx_rd_byte_offset),         
        .rx_rd_data         (rx_rd_data_bus),                 
        .rx_rd_valid        (snmp_rx_rd_valid),               
        .rx_frame_len       (snmp_rx_frame_len),              
        .tx_wr_en           (snmp_tx_wr_en),                  
        .tx_wr_byte_offset  (snmp_tx_wr_byte_offset),         
        .tx_wr_data         (snmp_tx_wr_data),                
        .tx_frame_done      (snmp_tx_frame_done),             
        .tx_wr_gnt          (snmp_tx_wr_gnt),                 
        .mib_sel            (mib_sel),                        
        .mib_addr           (mib_rd_addr),                    
        .mib_rd_en          (mib_rd_en),                      
        .mib_rd_data        (mib_rd_data)                     
    );                                                      
    data_loader_615a #(                                     
        .DATA_WIDTH        (DATA_WIDTH),                    
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             
        .VL_INDEX_SELF     (VL_INDEX_615A)                  
    ) u_data_loader_615a (                                  
        .clk               (clk_sys),                         
        .rst_b             (rst_b),                           
        .rx_ready_615a     (rx_ready_615a),                   
        .rx_rd_req         (dl_rx_rd_req),                    
        .rx_rd_byte_offset (dl_rx_rd_byte_offset),            
        .rx_rd_data        (rx_rd_data_bus),                  
        .rx_rd_valid       (dl_rx_rd_valid),                  
        .rx_frame_len      (dl_rx_frame_len),                 
        .tx_wr_en          (dl_tx_wr_en),                     
        .tx_wr_byte_offset (dl_tx_wr_byte_offset),            
        .tx_wr_data        (dl_tx_wr_data),                   
        .tx_frame_done     (dl_tx_frame_done),                
        .tx_wr_gnt         (dl_tx_wr_gnt),                    
        .load_busy         (load_busy),                       
        .load_done         (load_done),                       
        .load_error        (load_error)                       
    );                                                      
    rtc_sync #(                                             
        .DATA_WIDTH        (DATA_WIDTH),                    
        .VL_INDEX_WIDTH    (VL_INDEX_WIDTH),                
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             
        .RTC_WIDTH         (RTC_WIDTH),                     
        .CNT_WIDTH         (CNT_WIDTH),                     
        .VL_INDEX_SELF     (VL_INDEX_RTC)                   
    ) u_rtc_sync (                                          
        .clk               (clk_sys),                         
        .rst_b             (rst_b),                           
        .rx_ready_rtc      (rx_ready_rtc),                    
        .rx_rd_req         (rtc_rx_rd_req),                   
        .rx_rd_byte_offset (rtc_rx_rd_byte_offset),           
        .rx_rd_data        (rx_rd_data_bus),                  
        .rx_rd_valid       (rtc_rx_rd_valid),                 
        .rx_frame_len      (rtc_rx_frame_len),                
        .tx_wr_en          (rtc_tx_wr_en),                    
        .tx_wr_byte_offset (rtc_tx_wr_byte_offset),           
        .tx_wr_data        (rtc_tx_wr_data),                  
        .tx_frame_done     (rtc_tx_frame_done),               
        .tx_wr_gnt         (rtc_tx_wr_gnt),                   
        .local_rtc         (local_rtc),                       
        .rtc_sync_valid    (rtc_sync_valid),                  
        .master_mode       (RTC_MASTER_MODE),                 
        .sync_period_ms    (RTC_SYNC_PERIOD),                 
        .rx_process_delay  (RTC_PROC_DELAY)                   
    );

endmodule

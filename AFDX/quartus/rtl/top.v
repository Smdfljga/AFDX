// top : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module top (                                                
    
    input  wire                          clk_50m,               
    input  wire                          rst_b,                  

    
    inout  wire                          mdio_a,                 
    output wire                          mdc_a,                  
    output wire                          phy_rstb_a,             
    output wire                          p0_gtxc_a,              
    output wire [7:0]                    p0_txd_a,               
    output wire                          p0_txen_a,              
    output wire                          p0_txer_a,              
    input  wire                          p0_txc_a,               
    input  wire                          p0_rxc_a,               
    input  wire [7:0]                    p0_rxd_a,               
    input  wire                          p0_rxdv_a,              
    input  wire                          p0_rxer_a,              
    input  wire                          p0_col_a,               
    input  wire                          p0_crs_a,               

    
    inout  wire                          mdio_b,                 
    output wire                          mdc_b,                  
    output wire                          phy_rstb_b,             
    output wire                          p0_gtxc_b,              
    output wire [7:0]                    p0_txd_b,               
    output wire                          p0_txen_b,              
    output wire                          p0_txer_b,              
    input  wire                          p0_txc_b,               
    input  wire                          p0_rxc_b,               
    input  wire [7:0]                    p0_rxd_b,               
    input  wire                          p0_rxdv_b,              
    input  wire                          p0_rxer_b,              
    input  wire                          p0_col_b,               
    input  wire                          p0_crs_b,               

    
    input  wire                          cfg_wr_en,              
    input  wire [11:0]                   cfg_wr_addr,            
    input  wire [15:0]                   cfg_wr_vlid,            
    input  wire [15:0]                   cfg_wr_udp_port,        
    input  wire [1:0]                    cfg_wr_port_type,       
    input  wire [15:0]                   cfg_wr_bag,             
    input  wire [15:0]                   cfg_wr_lmax,            
    input  wire                          cfg_wr_rm_en,           
    input  wire                          cfg_wr_ic_mode,         
    output wire                          cfg_done,               

    
    input  wire [3:0]                    app_rd_vl_index,        
    input  wire [10:0]                   app_rd_byte_offset,     
    input  wire                          app_rd_en,              
    output wire [7:0]                    app_rd_data,            
    output wire                          app_rd_valid,           
    output wire [15:0]                   app_rd_frame_len,       
    output wire [3:0]                    app_rd_frame_cnt,       
    input  wire                          app_wr_en,              
    input  wire [3:0]                    app_wr_vl_index,        
    input  wire [10:0]                   app_wr_byte_offset,     
    input  wire [7:0]                    app_wr_data,            
    input  wire                          app_tx_req,             
    output wire                          app_wr_gnt,             

    
    output wire [47:0]                   local_rtc,              
    output wire                          rtc_sync_valid,         

    
    output wire                          irq_rx_frame,           
    output wire                          irq_tx_done,            
    output wire                          irq_error               
);
wire                                 clk_125m;               
	wire                                 clk_25m;               
    wire                                 pll_locked;             
    wire                                 rst_n;                  
    pll u_pll (                                             
        .inclk0 (clk_50m),                                  
        .c0     (clk_125m),                                 
		.c1		(clk_25m),                                  
        .locked (pll_locked)                                
    );                                                      
    wire [7:0]                           core_rx_data;           
    wire                                 core_rx_data_vld;       
    wire                                 core_rx_sop;            
    wire                                 core_rx_eop;            
    wire                                 core_rx_err;            
    wire                                 core_rx_rdy;            
    wire                                 core_frame_net;         
    wire [7:0]                           core_tx_data;           
    wire                                 core_tx_wren;           
    wire                                 core_tx_sop;            
    wire                                 core_tx_eop;            
    wire                                 core_tx_err;            
    wire                                 core_tx_rdy;            
    wire                                 mac_a_tx_rdy;           
    wire                                 mac_b_tx_rdy;           
    wire [7:0]                           mac_tx_data;            
    wire                                 mac_tx_wren;            
    wire                                 mac_tx_sop;             
    wire                                 mac_tx_eop;             
    wire                                 mac_tx_err;             
    wire                                 mac_tx_rdy;             
    wire [7:0]                           mac_a_rx_data;          
    wire                                 mac_a_rx_data_vld;      
    wire                                 mac_a_rx_sop;           
    wire                                 mac_a_rx_eop;           
    wire                                 mac_a_rx_err;           
    wire                                 mac_a_rx_rdy;           
    wire [7:0]                           mac_b_rx_data;          
    wire                                 mac_b_rx_data_vld;      
    wire                                 mac_b_rx_sop;           
    wire                                 mac_b_rx_eop;           
    wire                                 mac_b_rx_err;           
    wire                                 mac_b_rx_rdy;           
    eth_1 u_eth_1 (                                         
        .mdc            (mdc_a),                            
        .phy_rstb0      (phy_rstb_a),                       
        .p0_gtxc        (p0_gtxc_a),                        
        .p0_txd         (p0_txd_a),                         
        .p0_txen        (p0_txen_a),                        
        .p0_txer        (p0_txer_a),                        
        .ff_tx_rdy      (mac_a_tx_rdy),                     
        .ff_tx_al_full  (),                                 
        .ff_rx_data_vld (mac_a_rx_data_vld),                
        .ff_rx_data     (mac_a_rx_data),                    
        .ff_rx_sop      (mac_a_rx_sop),                     
        .ff_rx_eop      (mac_a_rx_eop),                     
        .ff_rx_err      (mac_a_rx_err),                     
        .reg_data_out   (),                                 
        .reg_acc_bsy    (),                                 
        .mdio           (mdio_a),                           
        .clk_sys        (clk_125m),                         
        .rst_b          (rst_n),                            
        .p0_txc         (p0_txc_a),                         
        .p0_rxc         (p0_rxc_a),                         
        .p0_rxd         (p0_rxd_a),                         
        .p0_rxdv        (p0_rxdv_a),                        
        .p0_rxer        (p0_rxer_a),                        
        .p0_col         (p0_col_a),                         
        .p0_crs         (p0_crs_a),                         
        .ff_tx_clk      (clk_25m),                          
        .ff_tx_data     (mac_tx_data),                      
        .ff_tx_sop      (mac_tx_sop),                       
        .ff_tx_eop      (mac_tx_eop),                       
        .ff_tx_err      (mac_tx_err),                       
        .ff_tx_wren     (mac_tx_wren),                      
        .ff_rx_clk      (clk_25m),                          
        .ff_rx_rdy      (mac_a_rx_rdy),                     
        .reg_wr         (1'b0),                             
        .reg_rd         (1'b0),                             
        .reg_addr       (4'd0),                             
        .reg_data_in    (32'd0)                             
    );                                                      
    eth_2 u_eth_2 (                                         
        .mdc            (mdc_b),                            
        .phy_rstb0      (phy_rstb_b),                       
        .p0_gtxc        (p0_gtxc_b),                        
        .p0_txd         (p0_txd_b),                         
        .p0_txen        (p0_txen_b),                        
        .p0_txer        (p0_txer_b),                        
        .ff_tx_rdy      (mac_b_tx_rdy),                     
        .ff_tx_al_full  (),                                 
        .ff_rx_data_vld (mac_b_rx_data_vld),                
        .ff_rx_data     (mac_b_rx_data),                    
        .ff_rx_sop      (mac_b_rx_sop),                     
        .ff_rx_eop      (mac_b_rx_eop),                     
        .ff_rx_err      (mac_b_rx_err),                     
        .reg_data_out   (),                                 
        .reg_acc_bsy    (),                                 
        .mdio           (mdio_b),                           
        .clk_sys        (clk_125m),                         
        .rst_b          (rst_n),                            
        .p0_txc         (p0_txc_b),                         
        .p0_rxc         (p0_rxc_b),                         
        .p0_rxd         (p0_rxd_b),                         
        .p0_rxdv        (p0_rxdv_b),                        
        .p0_rxer        (p0_rxer_b),                        
        .p0_col         (p0_col_b),                         
        .p0_crs         (p0_crs_b),                         
        .ff_tx_clk      (clk_25m),                          
        .ff_tx_data     (mac_tx_data),                      
        .ff_tx_sop      (mac_tx_sop),                       
        .ff_tx_eop      (mac_tx_eop),                       
        .ff_tx_err      (mac_tx_err),                       
        .ff_tx_wren     (mac_tx_wren),                      
        .ff_rx_clk      (clk_25m),                          
        .ff_rx_rdy      (mac_b_rx_rdy),                     
        .reg_wr         (1'b0),                             
        .reg_rd         (1'b0),                             
        .reg_addr       (4'd0),                             
        .reg_data_in    (32'd0)                             
    );                                                      
    afdx_tx_buf u_afdx_tx_buf (                             
        .wr_clk        (clk_25m),                           
        .rd_clk        (clk_25m),                           
        .rst_b         (rst_n),                             
        .core_tx_data  (core_tx_data),                      
        .core_tx_wren  (core_tx_wren),                      
        .core_tx_sop   (core_tx_sop),                       
        .core_tx_eop   (core_tx_eop),                       
        .core_tx_err   (core_tx_err),                       
        .core_tx_rdy   (core_tx_rdy),                       
        .mac_tx_data   (mac_tx_data),                       
        .mac_tx_wren   (mac_tx_wren),                       
        .mac_tx_sop    (mac_tx_sop),                        
        .mac_tx_eop    (mac_tx_eop),                        
        .mac_tx_err    (mac_tx_err),                        
        .mac_tx_rdy    (mac_tx_rdy)                         
    );                                                      
    afdx_net_rx u_afdx_net_rx (                             
        .wr_clk           (clk_25m),                        
        .rd_clk           (clk_25m),                        
        .rst_b            (rst_n),                          
        .a_rx_data        (mac_a_rx_data),                  
        .a_rx_data_vld    (mac_a_rx_data_vld),              
        .a_rx_sop         (mac_a_rx_sop),                   
        .a_rx_eop         (mac_a_rx_eop),                   
        .a_rx_err         (mac_a_rx_err),                   
        .a_rx_rdy         (mac_a_rx_rdy),                   
        .b_rx_data        (mac_b_rx_data),                  
        .b_rx_data_vld    (mac_b_rx_data_vld),              
        .b_rx_sop         (mac_b_rx_sop),                   
        .b_rx_eop         (mac_b_rx_eop),                   
        .b_rx_err         (mac_b_rx_err),                   
        .b_rx_rdy         (mac_b_rx_rdy),                   
        .ff_rx_data       (core_rx_data),                   
        .ff_rx_data_vld   (core_rx_data_vld),               
        .ff_rx_sop        (core_rx_sop),                    
        .ff_rx_eop        (core_rx_eop),                    
        .ff_rx_err        (core_rx_err),                    
        .ff_rx_rdy        (core_rx_rdy),                    
        .frame_net        (core_frame_net)                  
    );                                                      
    AFDX_top #(                                             
        .DATA_WIDTH        (8),                             
        .VLID_WIDTH        (16),                            
        .VL_ADDR_WIDTH     (12),                            
        .CNT_WIDTH         (32),                            
        .VL_INDEX_WIDTH    (4),                             
        .BYTE_OFFSET_WIDTH (11),                            
        .RTC_WIDTH         (48),                            
        .STATE_WIDTH       (64),                            
        .REDUNDANCY_EN     (1'b1),                          
        .VL_INDEX_SNMP     (4'd1),                          
        .VL_INDEX_615A     (4'd2),                          
        .VL_INDEX_RTC      (4'd3),                          
        .RTC_MASTER_MODE   (1'b0),                          
        .RTC_SYNC_PERIOD   (16'd10),                        
        .RTC_PROC_DELAY    (32'd100)                        
    ) u_afdx (                                              
        .clk_sys             (clk_25m),                     
        .rst_b               (rst_n),                       
        .ff_rx_data          (core_rx_data),                
        .ff_rx_data_vld      (core_rx_data_vld),            
        .ff_rx_sop           (core_rx_sop),                 
        .ff_rx_eop           (core_rx_eop),                 
        .ff_rx_err           (core_rx_err),                 
        .ff_rx_rdy           (core_rx_rdy),                 
        .rx_frame_net        (core_frame_net),              
        .ff_tx_data          (core_tx_data),                
        .ff_tx_wren          (core_tx_wren),                
        .ff_tx_sop           (core_tx_sop),                 
        .ff_tx_eop           (core_tx_eop),                 
        .ff_tx_err           (core_tx_err),                 
        .ff_tx_rdy           (core_tx_rdy),                 
        .cfg_wr_en           (cfg_wr_en),                   
        .cfg_wr_addr         (cfg_wr_addr),                 
        .cfg_wr_vlid         (cfg_wr_vlid),                 
        .cfg_wr_udp_port     (cfg_wr_udp_port),             
        .cfg_wr_port_type    (cfg_wr_port_type),            
        .cfg_wr_bag          (cfg_wr_bag),                  
        .cfg_wr_lmax         (cfg_wr_lmax),                 
        .cfg_wr_rm_en        (cfg_wr_rm_en),                
        .cfg_wr_ic_mode      (cfg_wr_ic_mode),              
        .cfg_done            (cfg_done),                    
        .app_rd_vl_index     (app_rd_vl_index),             
        .app_rd_byte_offset  (app_rd_byte_offset),          
        .app_rd_en           (app_rd_en),                   
        .app_rd_data         (app_rd_data),                 
        .app_rd_valid        (app_rd_valid),                
        .app_rd_frame_len    (app_rd_frame_len),            
        .app_rd_frame_cnt    (app_rd_frame_cnt),            
        .app_wr_en           (app_wr_en),                   
        .app_wr_vl_index     (app_wr_vl_index),             
        .app_wr_byte_offset  (app_wr_byte_offset),          
        .app_wr_data         (app_wr_data),                 
        .app_tx_req          (app_tx_req),                  
        .app_wr_gnt          (app_wr_gnt),                  
        .local_rtc           (local_rtc),                   
        .rtc_sync_valid      (rtc_sync_valid),              
        .irq_rx_frame        (irq_rx_frame),                
        .irq_tx_done         (irq_tx_done),                 
        .irq_error           (irq_error)                    
    );

endmodule

// afdx_vl_cfg : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module afdx_vl_cfg #(                                       
    parameter VLID_WIDTH    = 16,           
    parameter VL_ADDR_WIDTH = 12,           
    parameter VL_INDEX_WIDTH = 4,           
    parameter CNT_WIDTH     = 32,           
    parameter STATE_WIDTH   = 64            
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
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

    
    input  wire [VL_ADDR_WIDTH-1:0]      rx_cfg_addr,            
    input  wire                          rx_cfg_rd_en,           
    output wire [VLID_WIDTH-1:0]         rx_cfg_tag,             
    output wire                          rx_cfg_valid,           
    output wire [1:0]                    rx_cfg_port_type,       
    output wire [15:0]                   rx_cfg_udp_port,        
    output wire [15:0]                   rx_cfg_bag,             
    output wire [15:0]                   rx_cfg_lmax,            
    output wire                          rx_cfg_rm_en,           
    output wire                          rx_cfg_ic_mode,         

    
    input  wire [VL_ADDR_WIDTH-1:0]      tx_cfg_addr,            
    input  wire                          tx_cfg_rd_en,           
    output wire [VLID_WIDTH-1:0]         tx_cfg_tag,             
    output wire                          tx_cfg_valid,           
    output wire [1:0]                    tx_cfg_port_type,       
    output wire [15:0]                   tx_cfg_udp_port,        
    output wire [15:0]                   tx_cfg_bag,             
    output wire [15:0]                   tx_cfg_lmax,            
    output wire                          tx_cfg_rm_en,           

    
    input  wire [VL_ADDR_WIDTH-1:0]      rx_st_addr,             
    input  wire                          rx_st_rd_en,            
    output wire [STATE_WIDTH-1:0]        rx_st_rd_data,          
    input  wire                          rx_st_wr_en,            
    input  wire [STATE_WIDTH-1:0]        rx_st_wr_data,          

    
    input  wire [VL_ADDR_WIDTH-1:0]      tx_st_addr,             
    input  wire                          tx_st_rd_en,            
    output wire [STATE_WIDTH-1:0]        tx_st_rd_data,          
    input  wire                          tx_st_wr_en,            
    input  wire [STATE_WIDTH-1:0]        tx_st_wr_data,          

    
    input  wire [VL_ADDR_WIDTH-1:0]      rx_mib_addr,            
    input  wire                          mib_rx_frame_inc,       
    input  wire                          mib_rx_error_inc,       
    input  wire                          mib_sn_error_inc,       
    input  wire                          mib_rm_drop_inc,        
    input  wire                          mib_rx_byte_inc,        

    
    input  wire [VL_ADDR_WIDTH-1:0]      tx_mib_addr,            
    input  wire                          mib_tx_frame_inc,       
    input  wire                          mib_tx_byte_inc,        
    input  wire                          mib_tx_error_inc,       
    input  wire                          mib_tx_frag_inc,        
    input  wire                          mib_tx_bag_inc,         

    
    input  wire                          mib_sel,                
    input  wire [VL_ADDR_WIDTH-1:0]      mib_rd_addr,            
    input  wire                          mib_rd_en,              
    output wire [5*CNT_WIDTH-1:0]        mib_rd_data,            

    
    
    output wire [(1<<VL_INDEX_WIDTH)*VLID_WIDTH-1:0] slot_vlid   
);
wire                      bram_wr_en;                       
    wire [VL_ADDR_WIDTH-1:0]  bram_wr_addr;                     
    wire [5*CNT_WIDTH-1:0]    mib_rx_rd_data;                   
    wire [5*CNT_WIDTH-1:0]    mib_tx_rd_data;                   
    reg [(1<<VL_INDEX_WIDTH)*VLID_WIDTH-1:0] slot_vlid_r;        
    integer slot_i;                                             
    config_wr #(                                            
        .VLID_WIDTH    (VLID_WIDTH),                        
        .VL_ADDR_WIDTH (VL_ADDR_WIDTH)                      
    ) u_config_wr (                                         
        .clk             (clk),                                
        .rst_b           (rst_b),                              
        .cfg_wr_en       (cfg_wr_en),                          
        .cfg_wr_addr     (cfg_wr_addr),                        
        .cfg_wr_vlid     (cfg_wr_vlid),                        
        .cfg_wr_udp_port (cfg_wr_udp_port),                    
        .cfg_wr_port_type(cfg_wr_port_type),                   
        .cfg_wr_bag      (cfg_wr_bag),                         
        .cfg_wr_lmax     (cfg_wr_lmax),                        
        .cfg_wr_rm_en    (cfg_wr_rm_en),                       
        .cfg_wr_ic_mode  (cfg_wr_ic_mode),                     
        .bram_wr_en      (bram_wr_en),                         
        .bram_wr_addr    (bram_wr_addr),                       
        .cfg_done        (cfg_done)                            
    );                                                      
    vl_config_ram #(                                        
        .VLID_WIDTH    (VLID_WIDTH),                        
        .VL_ADDR_WIDTH (VL_ADDR_WIDTH)                      
    ) u_vl_config_ram (                                     
        .clk_a           (clk),                                
        .rst_a           (~rst_b),                             
        .addr_a          (rx_cfg_addr),                        
        .rd_en_a         (rx_cfg_rd_en),                       
        .tag_a           (rx_cfg_tag),                         
        .valid_a         (rx_cfg_valid),                       
        .port_type_a     (rx_cfg_port_type),                   
        .udp_port_a      (rx_cfg_udp_port),                    
        .bag_a           (rx_cfg_bag),                         
        .lmax_a          (rx_cfg_lmax),                        
        .rm_en_a         (rx_cfg_rm_en),                       
        .ic_mode_a       (rx_cfg_ic_mode),                     
        .clk_b           (clk),                                
        .rst_b           (~rst_b),                             
        .addr_b          (tx_cfg_addr),                        
        .rd_en_b         (tx_cfg_rd_en),                       
        .tag_b           (tx_cfg_tag),                         
        .valid_b         (tx_cfg_valid),                       
        .port_type_b     (tx_cfg_port_type),                   
        .udp_port_b      (tx_cfg_udp_port),                    
        .bag_b           (tx_cfg_bag),                         
        .lmax_b          (tx_cfg_lmax),                        
        .rm_en_b         (tx_cfg_rm_en),                       
        .ic_mode_b       (),                                   
        .cfg_wr_en       (bram_wr_en),                         
        .cfg_wr_addr     (bram_wr_addr),                       
        .cfg_wr_vlid     (cfg_wr_vlid),                        
        .cfg_wr_udp_port (cfg_wr_udp_port),                    
        .cfg_wr_port_type(cfg_wr_port_type),                   
        .cfg_wr_bag      (cfg_wr_bag),                         
        .cfg_wr_lmax     (cfg_wr_lmax),                        
        .cfg_wr_rm_en    (cfg_wr_rm_en),                       
        .cfg_wr_ic_mode  (cfg_wr_ic_mode)                      
    );                                                      
    vl_state_ram #(                                         
        .VL_ADDR_WIDTH (VL_ADDR_WIDTH),                     
        .STATE_WIDTH   (STATE_WIDTH)                        
    ) u_vl_state_ram (                                      
        .clk_a      (clk),                                     
        .rst_a      (~rst_b),                                  
        .addr_a     (rx_st_addr),                              
        .rd_en_a    (rx_st_rd_en),                             
        .rd_data_a  (rx_st_rd_data),                           
        .wr_en_a    (rx_st_wr_en),                             
        .wr_data_a  (rx_st_wr_data),                           
        .clk_b      (clk),                                     
        .rst_b      (~rst_b),                                  
        .addr_b     (tx_st_addr),                              
        .rd_en_b    (tx_st_rd_en),                             
        .rd_data_b  (tx_st_rd_data),                           
        .wr_en_b    (tx_st_wr_en),                             
        .wr_data_b  (tx_st_wr_data)                            
    );                                                      
    mib_ram #(                                              
        .CNT_WIDTH  (CNT_WIDTH),                            
        .ADDR_WIDTH (VL_ADDR_WIDTH),                        
        .IS_RX      (1'b1)                                  
    ) u_mib_rx (                                            
        .clk        (clk),                                     
        .rst_b      (rst_b),                                   
        .inc_addr   (rx_mib_addr),                             
        .cnt0_inc   (mib_rx_frame_inc),                        
        .cnt1_inc   (mib_rx_error_inc),                        
        .cnt2_inc   (mib_sn_error_inc),                        
        .cnt3_inc   (mib_rm_drop_inc),                         
        .cnt4_inc   (mib_rx_byte_inc),                         
        .rd_addr    (mib_rd_addr),                             
        .rd_en      (mib_rd_en),                               
        .rd_data    (mib_rx_rd_data)                           
    );                                                      
    mib_ram #(                                              
        .CNT_WIDTH  (CNT_WIDTH),                            
        .ADDR_WIDTH (VL_ADDR_WIDTH),                        
        .IS_RX      (1'b0)                                  
    ) u_mib_tx (                                            
        .clk        (clk),                                     
        .rst_b      (rst_b),                                   
        .inc_addr   (tx_mib_addr),                             
        .cnt0_inc   (mib_tx_frame_inc),                        
        .cnt1_inc   (mib_tx_byte_inc),                         
        .cnt2_inc   (mib_tx_error_inc),                        
        .cnt3_inc   (mib_tx_frag_inc),                         
        .cnt4_inc   (mib_tx_bag_inc),                          
        .rd_addr    (mib_rd_addr),                             
        .rd_en      (mib_rd_en),                               
        .rd_data    (mib_tx_rd_data)                           
    );

endmodule

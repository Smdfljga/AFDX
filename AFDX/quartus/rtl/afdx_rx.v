// afdx_rx : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module afdx_rx #(                                           
    parameter DATA_WIDTH        = 8,        
    parameter VLID_WIDTH        = 16,       
    parameter VL_ADDR_WIDTH     = 12,       
    parameter VL_INDEX_WIDTH    = 4,        
    parameter BYTE_OFFSET_WIDTH = 11,       
    parameter CNT_WIDTH         = 32,       
    parameter STATE_WIDTH       = 64,       
    parameter VL_INDEX_SNMP     = 4'd1,     
    parameter VL_INDEX_615A     = 4'd2,     
    parameter VL_INDEX_RTC      = 4'd3      
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire [DATA_WIDTH-1:0]         ff_rx_data,             
    input  wire                          ff_rx_data_vld,         
    input  wire                          ff_rx_sop,              
    input  wire                          ff_rx_eop,              
    input  wire                          ff_rx_err,              
    output wire                          ff_rx_rdy,              

    
    input  wire                          frame_net,              

    
    output wire [VL_ADDR_WIDTH-1:0]      cfg_addr,               
    output wire                          cfg_rd_en,              
    input  wire [VLID_WIDTH-1:0]         cfg_tag,                
    input  wire                          cfg_valid,              
    input  wire [1:0]                    cfg_port_type,          
    input  wire [15:0]                   cfg_udp_port,           
    input  wire [15:0]                   cfg_bag,                
    input  wire [15:0]                   cfg_lmax,               
    input  wire                          cfg_rm_en,              
    input  wire                          cfg_ic_mode,            

    
    output wire [VL_ADDR_WIDTH-1:0]      st_addr,                
    output wire                          st_rd_en,               
    input  wire [STATE_WIDTH-1:0]        st_rd_data,             
    output wire                          st_wr_en,               
    output wire [STATE_WIDTH-1:0]        st_wr_data,             

    
    output wire                          port_wr_en,             
    output wire [VL_INDEX_WIDTH-1:0]     port_wr_vl_index,       
    output wire [BYTE_OFFSET_WIDTH-1:0]  port_wr_byte_offset,    
    output wire [DATA_WIDTH-1:0]         port_wr_data,           
    output wire [1:0]                    port_type,              

    
    output wire                          rx_ready_app,           
    output wire                          rx_ready_snmp,          
    output wire                          rx_ready_615a,          
    output wire                          rx_ready_rtc,           

    
    output wire                          port_wr_frame_done,     
    output wire [15:0]                   port_wr_frame_len,      
    output wire                          port_wr_queue_mode,     
    input  wire                          port_wr_full,           

    
    output wire [VL_ADDR_WIDTH-1:0]      mib_addr,               
    output wire                          mib_rx_frame_inc,       
    output wire                          mib_rx_error_inc,       
    output wire                          mib_sn_error_inc,       
    output wire                          mib_rm_drop_inc,        
    output wire                          mib_rx_byte_inc,        

    
    output wire                          irq_rx_frame,           
    output wire                          irq_error               
);
localparam S_IDLE        = 5'd0;                             
    localparam S_MAC_DA      = 5'd1;                             
    localparam S_MAC_SA      = 5'd2;                             
    localparam S_MAC_TYPE    = 5'd3;                             
    localparam S_VL_LOOKUP   = 5'd4;                             
    localparam S_IP_PARSE    = 5'd5;                             
    localparam S_FRAG_CHECK  = 5'd6;                             
    localparam S_UDP_PARSE   = 5'd7;                             
    localparam S_PORT_CHECK  = 5'd8;                             
    localparam S_PAYLOAD     = 5'd9;                             
    localparam S_SN_RECV     = 5'd10;                            
    localparam S_IC_CHECK    = 5'd11;                            
    localparam S_RM_SINGLE   = 5'd12;                            
    localparam S_DISPATCH    = 5'd13;                            
    localparam S_MIB_BYTES   = 5'd14;                            
    localparam S_DROP        = 5'd15;                            
    localparam S_DONE        = 5'd16;                            
    reg [4:0] state;                                            
    reg [47:0] da_acc;                                          
    reg [2:0]  da_cnt;                                          
    reg [2:0]  sa_cnt;                                          
    reg [1:0]  type_cnt;                                        
    reg [15:0] type_acc;                                        
    reg [VLID_WIDTH-1:0] vlid_r;                                
    reg        prefix_ok;                                       
    reg        frame_net_r;                                     
    reg [1:0]  cfg_port_type_r;                                 
    reg [15:0] cfg_udp_port_r;                                  
    reg [15:0] cfg_lmax_r;                                      
    reg        cfg_rm_en_r;                                     
    reg        cfg_ic_mode_r;                                   
    reg [4:0]  ip_cnt;                                          
    reg [7:0]  ip_prev;                                         
    reg [16:0] ip_cksum;                                        
    reg        ip_cksum_ok;                                     
    reg        ip_header_ok;                                    
    reg [15:0] ip_total_len_r;                                  
    reg [4:0]  ip_flags_lo;                                     
    reg        ip_mf;                                           
    reg [12:0] ip_frag_off;                                     
    reg [3:0]  udp_cnt;                                         
    reg [15:0] udp_dst_r;                                       
    reg [15:0] udp_len_r;                                       
    reg [15:0] pay_cnt;                                         
    reg [7:0]  sn_r;                                            
    reg        psn_write_en;                                    
    reg [7:0]  psn_write_val;                                   
    reg        drop_sn_err;                                     
    reg        drop_rm_drop;                                    
    reg        ic_cross_dup;                                    
    reg        err_counted;                                     
    reg        drop_entry;                                      
    reg [15:0] byte_left;                                       
    reg        eop_seen_r;                                      
    reg last_net_valid [(1<<VL_INDEX_WIDTH)-1:0];               
    reg last_net       [(1<<VL_INDEX_WIDTH)-1:0];               
    integer rx_i;                                               
    wire [15:0] data_len_w;
    wire [15:0] frame_core;
    wire config_hit;
    wire udp_len_ok;
    wire data_len_ok = ip_header_ok && ip_cksum_ok && udp_len_ok &&  
                       (ip_total_len_r >= 16'd29) &&        
                       (ip_total_len_r <= 16'd1504) &&      
                       (data_len_w >= 16'd17) &&            
                       (data_len_w <= 16'd1471) &&          
                       (data_len_w <= cfg_lmax_r);              
    wire port_ok;
    wire [VL_ADDR_WIDTH-1:0] vl_addr;
    wire [7:0] psn;
    wire       psn_valid;
    wire [8:0] expected9;
    wire       sn_expect;
    wire [VL_INDEX_WIDTH-1:0] vl_slot;
    wire       same_net_last = last_net_valid[vl_slot] ?    
                               (frame_net_r == last_net[vl_slot]) : 1'b1; 
    wire       same_dup;
    wire       cross_dup;
    wire       sn_zero_bad = psn_valid && (sn_r == 8'd0) &&  
                            !same_dup && !cross_dup;            
    wire       sn_jump = psn_valid && (sn_r != 8'd0) && !sn_expect &&  
                        !same_dup && !cross_dup;                
    wire [16:0] cksum_add;
    wire [16:0] cksum_sum;
    wire [16:0] cksum_fold;
    wire        cksum_now_ok;
    wire [47:0] da_new;
    wire dispatch_ok;
    wire is_snmp_slot;
    wire is_615a_slot;
    wire is_rtc_slot;
    reg [4:0] nxt_state;                                        
    reg       drop_req;                                         
    reg       drop_sn_err_req;                                  
    reg       drop_rm_drop_req;                                 
    wire drop_accept;

endmodule

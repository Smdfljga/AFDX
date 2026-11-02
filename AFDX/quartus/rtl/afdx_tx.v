// afdx_tx : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module afdx_tx #(                                           
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

    
    input  wire [31:0]                   sys_ts,                 

    
    output wire [DATA_WIDTH-1:0]         ff_tx_data,             
    output wire                          ff_tx_wren,             
    output wire                          ff_tx_sop,              
    output wire                          ff_tx_eop,              
    output wire                          ff_tx_err,              
    input  wire                          ff_tx_rdy,              

    
    input  wire [(1<<VL_INDEX_WIDTH)*VLID_WIDTH-1:0] slot_vlid,  

    
    output wire [VL_ADDR_WIDTH-1:0]      cfg_addr,               
    output wire                          cfg_rd_en,              
    input  wire [VLID_WIDTH-1:0]         cfg_tag,                
    input  wire                          cfg_valid,              
    input  wire [1:0]                    cfg_port_type,          
    input  wire [15:0]                   cfg_udp_port,           
    input  wire [15:0]                   cfg_bag,                
    input  wire [15:0]                   cfg_lmax,               
    input  wire                          cfg_rm_en,              

    
    output wire [VL_ADDR_WIDTH-1:0]      st_addr,                
    output wire                          st_rd_en,               
    input  wire [STATE_WIDTH-1:0]        st_rd_data,             
    output wire                          st_wr_en,               
    output wire [STATE_WIDTH-1:0]        st_wr_data,             

    
    output wire                          port_rd_en,             
    output wire [VL_INDEX_WIDTH-1:0]     port_rd_vl_index,       
    output wire [BYTE_OFFSET_WIDTH-1:0]  port_rd_byte_offset,    
    input  wire [DATA_WIDTH-1:0]         port_rd_data,           
    input  wire                          port_rd_valid,          
    input  wire [15:0]                   port_payload_len,       
    output wire [15:0]                   abort_vl,               

    
    input  wire                          tx_valid_app,           
    input  wire                          tx_valid_snmp,          
    input  wire                          tx_valid_615a,          
    input  wire                          tx_valid_rtc,           

    
    output wire [VL_ADDR_WIDTH-1:0]      mib_addr,               
    output wire                          mib_tx_frame_inc,       
    output wire                          mib_tx_byte_inc,        
    output wire                          mib_tx_error_inc,       
    output wire                          mib_tx_frag_inc,        
    output wire                          mib_tx_bag_inc,         

    
    output wire                          irq_tx_done             
);
localparam S_IDLE        = 4'd0;                             
    localparam S_SCAN        = 4'd1;                             
    localparam S_CFG_READ    = 4'd2;                             
    localparam S_STATE_READ  = 4'd3;                             
    localparam S_DECIDE      = 4'd4;                             
    localparam S_WAIT        = 4'd5;                             
    localparam S_PAYLOAD_RD  = 4'd6;                             
    localparam S_BUILD       = 4'd7;                             
    localparam S_FINISH      = 4'd8;                             
    localparam [31:0] SRC_IP        = 32'h04000001;             
    reg [15:0] pending;                                         
    reg        app_scan;                                        
    reg [VL_INDEX_WIDTH-1:0] scan_idx;                          
    reg [VL_INDEX_WIDTH-1:0] sched_idx;                         
    reg [VLID_WIDTH-1:0]    vlid_r;                             
    reg [15:0] cfg_udp_r;                                       
    reg [15:0] cfg_bag_r;                                       
    reg [15:0] payload_len_r;                                   
    reg [15:0] data_len_r;                                      
    reg [15:0] ip_total_r;                                      
    reg [15:0] udp_len_r;                                       
    reg [15:0] frame_total_r;                                   
    reg [15:0] ip_cksum_r;                                      
    reg [31:0] dst_ip_r;                                        
    reg [31:0] start_ts_r;                                      
    reg [7:0]  sn_r;                                            
    reg [7:0]  next_sn_r;                                       
    reg [15:0] ip_id_cnt;                                       
    reg [3:0]  state;                                           
    reg [15:0] tx_byte_pos;                                     
    reg [7:0]  pay_buf [0:3];                               
    reg [2:0]  pay_wr;                                      
    reg [2:0]  pay_rd;                                      
    reg [15:0] pay_req_ix;                                  
    reg        pay_iss_d1;                                  
    reg        pay_iss_d2;                                  
    reg [23:0] wait_cnt;                                        
    reg        bag_pulse;                                       
    reg [1:0]  finish_kind;                                     
    reg        frag_error;                                      
    reg [VL_INDEX_WIDTH-1:0] pending_idx;                       
    reg [15:0]               bag_skip;                          
    wire [15:0]              pending_ready;
    reg [VL_INDEX_WIDTH-1:0] pending_idx_ready;                 
    wire [15:0] bag_cfg_now;
    wire [31:0] bag_us;
    wire [31:0] elapsed;
    wire bag_due;
    wire [15:0] payload_pos;
    wire [7:0] payload_data;
    wire build_active;
    wire pay_arr;
    wire [2:0] pay_used;
    wire pay_room;
    wire pay_issue = (state == S_BUILD) &&                       
                     pay_room && (pay_req_ix < payload_len_r);   
    wire pay_pop   = build_active && (tx_byte_pos >= 16'd42) &&  
                     (payload_pos < payload_len_r);              
    wire pay_clr;
    reg [3:0] nxt_state;                                        
    reg [7:0] tx_byte;                                          
    wire finish_success;
    wire finish_error;

endmodule

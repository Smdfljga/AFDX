// afdx_net_rx : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module afdx_net_rx #(                                        
    parameter DATA_WIDTH = 8,                               
    parameter ADDR_WIDTH = 12,                              
    parameter MAX_FRAME  = 1536,                            
    parameter SLOT_BITS  = 11                               
)(                                                          
    
    input  wire                          wr_clk,                 
    input  wire                          rd_clk,                 
    input  wire                          rst_b,                  

    
    input  wire [DATA_WIDTH-1:0]         a_rx_data,              
    input  wire                          a_rx_data_vld,          
    input  wire                          a_rx_sop,               
    input  wire                          a_rx_eop,               
    input  wire                          a_rx_err,               
    output wire                          a_rx_rdy,               

    
    input  wire [DATA_WIDTH-1:0]         b_rx_data,              
    input  wire                          b_rx_data_vld,          
    input  wire                          b_rx_sop,               
    input  wire                          b_rx_eop,               
    input  wire                          b_rx_err,               
    output wire                          b_rx_rdy,               

    
    output wire [DATA_WIDTH-1:0]         ff_rx_data,             
    output wire                          ff_rx_data_vld,         
    output wire                          ff_rx_sop,              
    output wire                          ff_rx_eop,              
    output wire                          ff_rx_err,              
    input  wire                          ff_rx_rdy,              
    output wire                          frame_net               
);
wire [ADDR_WIDTH-1:0] a_wr_addr;                            
    wire [DATA_WIDTH-1:0] a_wr_data;                            
    wire                  a_wr_en;                              
    wire [1:0]            a_wr_tog;                             
    wire [ADDR_WIDTH-1:0] a_len0, a_len1;                       
    wire [1:0]            a_err;                                
    wire [1:0]            a_ack_tog;                            
    wire [ADDR_WIDTH-1:0] b_wr_addr;                            
    wire [DATA_WIDTH-1:0] b_wr_data;                            
    wire                  b_wr_en;                              
    wire [1:0]            b_wr_tog;                             
    wire [ADDR_WIDTH-1:0] b_len0, b_len1;                       
    wire [1:0]            b_err;                                
    wire [1:0]            b_ack_tog;                            
    reg  [1:0] a_wr_tog_d0, a_wr_tog_d1;                        
    reg  [1:0] b_wr_tog_d0, b_wr_tog_d1;                        
    reg  [1:0] a_ack_d0, a_ack_d1;                              
    reg  [1:0] b_ack_d0, b_ack_d1;                              
    reg  [1:0] a_rd_tog;                                        
    reg  [1:0] b_rd_tog;                                        
    wire [1:0] a_avail_slot;
    wire [1:0] b_avail_slot;
    wire       a_avail;
    wire       b_avail;
    localparam S_IDLE = 1'd0;                               
    localparam S_READ = 1'd1;                               
    reg                   state;                            
    reg                   net_sel;                          
    reg                   slot_sel;                         
    reg  [ADDR_WIDTH-1:0] issue_ix;                         
    reg  [ADDR_WIDTH-1:0] emit_ix;                          
    reg  [ADDR_WIDTH-1:0] cur_len;                          
    reg                   cur_err;                          
    reg                   last_net;                         
    reg                   ren;                              
    reg                   ren_d1;                           
    reg                   ren_d;                            
    reg  [ADDR_WIDTH-1:0] rd_addr;                          
    wire                  start;
    wire                  pick_b;
    wire [1:0]            pick_avail;
    wire                  pick_slot;
    wire [ADDR_WIDTH-1:0] pick_len;
    wire                  pick_err;
    wire                  last_byte;
    wire [1:0]            a_tog_next;
    wire [1:0]            b_tog_next;
    wire [ADDR_WIDTH-1:0] rd_addr_cur;
    wire [DATA_WIDTH-1:0] a_ram_q;                          
    wire [DATA_WIDTH-1:0] b_ram_q;                          
    rx_frame_buf u_rx_frame_buf_a (                         
        .wrclock   (wr_clk),                                
        .rdclock   (rd_clk),                                
        .data      (a_wr_data),                             
        .rdaddress (rd_addr_cur),                           
        .wraddress (a_wr_addr),                             
        .wren      (a_wr_en),                               
        .rden      (ren && !net_sel),                       
        .q         (a_ram_q)                                
    );                                                      
    rx_frame_buf u_rx_frame_buf_b (                         
        .wrclock   (wr_clk),                                
        .rdclock   (rd_clk),                                
        .data      (b_wr_data),                             
        .rdaddress (rd_addr_cur),                           
        .wraddress (b_wr_addr),                             
        .wren      (b_wr_en),                               
        .rden      (ren && net_sel),                        
        .q         (b_ram_q)                                
    );                                                      
    afdx_net_rx_wr #(                                       
        .DATA_WIDTH (DATA_WIDTH),                           
        .ADDR_WIDTH (ADDR_WIDTH),                           
        .MAX_FRAME  (MAX_FRAME),                            
        .SLOT_BITS  (SLOT_BITS)                             
    ) u_a_wr (                                              
        .clk        (wr_clk),                               
        .rst_b      (rst_b),                                
        .rx_data    (a_rx_data),                            
        .rx_data_vld(a_rx_data_vld),                        
        .rx_sop     (a_rx_sop),                             
        .rx_eop     (a_rx_eop),                             
        .rx_err     (a_rx_err),                             
        .rx_rdy     (a_rx_rdy),                             
        .ram_wr_addr(a_wr_addr),                            
        .ram_wr_data(a_wr_data),                            
        .ram_wr_en  (a_wr_en),                              
        .ack_toggle (a_ack_tog),                            
        .wr_toggle  (a_wr_tog),                             
        .slot_len0  (a_len0),                               
        .slot_len1  (a_len1),                               
        .slot_err   (a_err)                                 
    );                                                      
    afdx_net_rx_wr #(                                       
        .DATA_WIDTH (DATA_WIDTH),                           
        .ADDR_WIDTH (ADDR_WIDTH),                           
        .MAX_FRAME  (MAX_FRAME),                            
        .SLOT_BITS  (SLOT_BITS)                             
    ) u_b_wr (                                              
        .clk        (wr_clk),                               
        .rst_b      (rst_b),                                
        .rx_data    (b_rx_data),                            
        .rx_data_vld(b_rx_data_vld),                        
        .rx_sop     (b_rx_sop),                             
        .rx_eop     (b_rx_eop),                             
        .rx_err     (b_rx_err),                             
        .rx_rdy     (b_rx_rdy),                             
        .ram_wr_addr(b_wr_addr),                            
        .ram_wr_data(b_wr_data),                            
        .ram_wr_en  (b_wr_en),                              
        .ack_toggle (b_ack_tog),                            
        .wr_toggle  (b_wr_tog),                             
        .slot_len0  (b_len0),                               
        .slot_len1  (b_len1),                               
        .slot_err   (b_err)                                 
    );

endmodule

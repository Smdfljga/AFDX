// afdx_net_rx_wr : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module afdx_net_rx_wr #(                                    
    parameter DATA_WIDTH = 8,                               
    parameter ADDR_WIDTH = 12,                              
    parameter MAX_FRAME  = 1536,                            
    parameter SLOT_BITS  = 11                               
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire [DATA_WIDTH-1:0]         rx_data,                
    input  wire                          rx_data_vld,            
    input  wire                          rx_sop,                 
    input  wire                          rx_eop,                 
    input  wire                          rx_err,                 
    output wire                          rx_rdy,                 

    
    output wire [ADDR_WIDTH-1:0]         ram_wr_addr,            
    output wire [DATA_WIDTH-1:0]         ram_wr_data,            
    output wire                          ram_wr_en,              

    
    input  wire [1:0]                    ack_toggle,             
    output wire [1:0]                    wr_toggle,              

    
    output wire [ADDR_WIDTH-1:0]         slot_len0,              
    output wire [ADDR_WIDTH-1:0]         slot_len1,              
    output wire [1:0]                    slot_err                 
);
localparam SLOT_BYTES = (1 << SLOT_BITS);                   
    reg  [DATA_WIDTH-1:0] q_data;                              
    reg                   q_vld;                               
    reg                   q_sop;                               
    reg                   q_eop;                               
    reg                   q_err;                               
    reg                   busy;                                 
    reg                   drop;                                 
    reg  [0:0]            cur_slot;                             
    reg  [SLOT_BITS-1:0]  wr_off;                               
    reg  [1:0]            tog_r;                                
    reg  [ADDR_WIDTH-1:0] len_rx [0:1];                         
    reg  [1:0]            err_r;                                
    reg                   err_acc;                              
    wire slot_free0;
    wire slot_free1;
    wire any_free;
    wire        wr_en;
    wire        wr_first;
    wire [0:0]  wr_slot;
    wire [SLOT_BITS-1:0] wr_off_sel;
    wire [SLOT_BITS-1:0] wr_off_nxt;
    wire        over_len = (wr_off_nxt > MAX_FRAME) ||          
                           (wr_off_nxt > SLOT_BYTES);

endmodule

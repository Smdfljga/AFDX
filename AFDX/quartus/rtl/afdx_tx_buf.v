// afdx_tx_buf : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module afdx_tx_buf #(                                       
    parameter DATA_WIDTH  = 8,                              
    parameter ADDR_WIDTH  = 12,                             
    parameter SLOT_BITS   = 11                              
)(                                                          
    
    input  wire                          wr_clk,                 
    input  wire                          rd_clk,                 
    input  wire                          rst_b,                  

    
    input  wire [DATA_WIDTH-1:0]         core_tx_data,           
    input  wire                          core_tx_wren,           
    input  wire                          core_tx_sop,            
    input  wire                          core_tx_eop,            
    input  wire                          core_tx_err,            
    output wire                          core_tx_rdy,            

    
    output wire [DATA_WIDTH-1:0]         mac_tx_data,            
    output wire                          mac_tx_wren,            
    output wire                          mac_tx_sop,             
    output wire                          mac_tx_eop,             
    output wire                          mac_tx_err,             
    input  wire                          mac_tx_rdy              
);
localparam SLOT_BYTES   = (1 << SLOT_BITS);                 
    localparam S_IDLE_STATE = 1'b0;                             
    localparam S_READ_STATE = 1'b1;                             
    reg                   busy;                                 
    reg                   drop;                                 
    reg  [0:0]            cur_slot;                             
    reg  [SLOT_BITS-1:0]  wr_off;                               
    reg  [1:0]            wr_tog;                               
    reg  [1:0]            err_r;                                
    reg  [1:0]            free_ack;                             
    reg  [ADDR_WIDTH-1:0] len_rx [0:1];                         
    reg                   err_acc;                              
    reg                   finish_pend;                          
    reg  [1:0]            wr_tog_d0, wr_tog_d1;                 
    reg  [1:0]            ack_tog;                              
    reg                   state;                                
    reg  [0:0]            slot_r;                               
    reg  [ADDR_WIDTH-1:0] len_r;                                
    reg                   err_r_sel;                            
    reg  [ADDR_WIDTH-1:0] issue_ix;                             
    reg  [ADDR_WIDTH-1:0] emit_ix;                              
    reg                   fetch_d1;                             
    reg                   fetch_d2;                             
    reg  [DATA_WIDTH-1:0] f0, f1;                               
    reg  [1:0]            fcnt;                                 
    wire free0;
    wire free1;
    wire any_free;
    wire [SLOT_BITS-1:0] wr_off_nxt;
    wire over_len;
    wire        wr_first;
    wire [0:0]  wr_slot;
    wire [SLOT_BITS-1:0] wr_off_sel;
    wire [ADDR_WIDTH-1:0] ram_wr_addr;
    wire                  ram_wr_en   = core_tx_wren &&         
                                        (busy ? !drop : core_tx_sop) && (busy || any_free); 
    wire [DATA_WIDTH-1:0] ram_q;                                
    wire [1:0] avail_slot;
    wire       any_avail;
    wire       pick_slot;
    wire       arr;
    wire       room;
    wire       fetch;
    wire       pop;
    wire       frame_last;
    wire [ADDR_WIDTH-1:0] ram_rd_addr;
    reg [1:0] ack_d0, ack_d1;                               
    rx_frame_buf u_tx_frame_buf (                           
        .wrclock   (wr_clk),                                
        .rdclock   (rd_clk),                                
        .data      (core_tx_data),                          
        .rdaddress (ram_rd_addr),                           
        .wraddress (ram_wr_addr),                           
        .wren      (ram_wr_en),                             
        .rden      (fetch),                                 
        .q         (ram_q)                                  
    );

endmodule

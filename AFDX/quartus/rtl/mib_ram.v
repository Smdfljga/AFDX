// mib_ram : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module mib_ram #(                                           
    parameter CNT_WIDTH  = 32,              
    parameter ADDR_WIDTH = 12,              
    parameter IS_RX      = 1'b1             
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire [ADDR_WIDTH-1:0]         inc_addr,               
    input  wire                          cnt0_inc,               
    input  wire                          cnt1_inc,               
    input  wire                          cnt2_inc,               
    input  wire                          cnt3_inc,               
    input  wire                          cnt4_inc,               

    
    input  wire [ADDR_WIDTH-1:0]         rd_addr,                
    input  wire                          rd_en,                  
    output wire [5*CNT_WIDTH-1:0]        rd_data                 
);
localparam DELTA_WIDTH = 16;                                
    localparam EV_WIDTH    = 5 * DELTA_WIDTH;                   
    localparam BIN_DEPTH   = 8;                                 
    wire [5*CNT_WIDTH-1:0] cnt_word;                            
    wire [5*CNT_WIDTH-1:0] cnt_next;                            
    wire                   cnt_wr;                              
    wire [EV_WIDTH-1:0] event_vec = {                       
        {DELTA_WIDTH-1{1'b0}}, cnt4_inc,                    
        {DELTA_WIDTH-1{1'b0}}, cnt3_inc,                    
        {DELTA_WIDTH-1{1'b0}}, cnt2_inc,                    
        {DELTA_WIDTH-1{1'b0}}, cnt1_inc,                    
        {DELTA_WIDTH-1{1'b0}}, cnt0_inc                     
    };                                                          
    wire inc_any;
    reg [BIN_DEPTH-1:0]         bin_valid;                     
    reg [ADDR_WIDTH-1:0]        bin_addr [0:BIN_DEPTH-1];      
    reg [EV_WIDTH-1:0]          bin_delta [0:BIN_DEPTH-1];     
    wire [BIN_DEPTH-1:0] match_bit;                            
    wire [BIN_DEPTH-1:0] empty_bit;                            
    genvar match_i;                                         
    generate                                                
        for (match_i = 0; match_i < BIN_DEPTH; match_i = match_i + 1) begin : g_match  
            assign match_bit[match_i] = bin_valid[match_i] && (bin_addr[match_i] == inc_addr);  
            assign empty_bit[match_i] = !bin_valid[match_i];  
        end                                                 
    endgenerate                                             
    wire match_hit;
    wire empty_hit;
    reg [2:0] match_idx;                                        
    reg [2:0] empty_idx;                                        
    reg [2:0] sel_idx;                                          
    wire sel_any;
    localparam S_IDLE  = 2'd0;                                  
    localparam S_READ  = 2'd1;                                  
    localparam S_READ2 = 2'd3;                                  
    localparam S_WRITE = 2'd2;                                  
    reg [1:0]          state;                                   
    reg [2:0]          op_bin;                                  
    reg [ADDR_WIDTH-1:0] op_addr;                               
    reg [EV_WIDTH-1:0] op_delta;                                
    wire event_matches_op = (state != S_IDLE) &&            
                            bin_valid[op_bin] &&            
                            (bin_addr[op_bin] == inc_addr);     
    reg [1:0] nxt_state;                                        
    wire [CNT_WIDTH-1:0] cnt0_next = cnt_word[1*CNT_WIDTH-1:0*CNT_WIDTH] +  
                                     {16'd0, op_delta[1*DELTA_WIDTH-1:0*DELTA_WIDTH]};  
    wire [CNT_WIDTH-1:0] cnt1_next = cnt_word[2*CNT_WIDTH-1:1*CNT_WIDTH] +  
                                     {16'd0, op_delta[2*DELTA_WIDTH-1:1*DELTA_WIDTH]};  
    wire [CNT_WIDTH-1:0] cnt2_next = cnt_word[3*CNT_WIDTH-1:2*CNT_WIDTH] +  
                                     {16'd0, op_delta[3*DELTA_WIDTH-1:2*DELTA_WIDTH]};  
    wire [CNT_WIDTH-1:0] cnt3_next = cnt_word[4*CNT_WIDTH-1:3*CNT_WIDTH] +  
                                     {16'd0, op_delta[4*DELTA_WIDTH-1:3*DELTA_WIDTH]};  
    wire [CNT_WIDTH-1:0] cnt4_next = cnt_word[5*CNT_WIDTH-1:4*CNT_WIDTH] +  
                                     {16'd0, op_delta[5*DELTA_WIDTH-1:4*DELTA_WIDTH]};  
    localparam IP_WIDTH = 256;                                  
    localparam RSRV     = IP_WIDTH - 5*CNT_WIDTH;                
    wire [IP_WIDTH-1:0] cnt_word_ip;                            
    wire [IP_WIDTH-1:0] cnt_next_ip;                            
    wire [IP_WIDTH-1:0] rd_data_ip;                             
    generate                                                
        if (IS_RX) begin : g_mib_rx                         
            mib_rx_ip u_mib_ip (                            
                .clock_a    (clk),                              
                .aclr_a     (~rst_b),                           
                .address_a  (op_addr),                          
                .data_a     (cnt_next_ip),                      
                .wren_a     (cnt_wr),                           
                .q_a        (cnt_word_ip),                      
                .clock_b    (clk),                              
                .aclr_b     (~rst_b),                           
                .address_b  (rd_addr),                          
                .data_b     ({IP_WIDTH{1'b0}}),                 
                .wren_b     (1'b0),                             
                .q_b        (rd_data_ip)                        
            );                                              
        end else begin : g_mib_tx                           
            mib_tx_ip u_mib_ip (                            
                .clock_a    (clk),                              
                .aclr_a     (~rst_b),                           
                .address_a  (op_addr),                          
                .data_a     (cnt_next_ip),                      
                .wren_a     (cnt_wr),                           
                .q_a        (cnt_word_ip),                      
                .clock_b    (clk),                              
                .aclr_b     (~rst_b),                           
                .address_b  (rd_addr),                          
                .data_b     ({IP_WIDTH{1'b0}}),                 
                .wren_b     (1'b0),                             
                .q_b        (rd_data_ip)                        
            );                                              
        end                                                 
    endgenerate

endmodule

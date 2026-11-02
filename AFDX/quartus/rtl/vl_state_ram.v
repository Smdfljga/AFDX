// vl_state_ram : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module vl_state_ram #(                                      
    parameter VL_ADDR_WIDTH = 12,           
    parameter STATE_WIDTH   = 64            
)(                                                          
    
    input  wire                          clk_a,                  
    input  wire                          rst_a,                  
    input  wire [VL_ADDR_WIDTH-1:0]      addr_a,                 
    input  wire                          rd_en_a,                
    output wire [STATE_WIDTH-1:0]        rd_data_a,              
    input  wire                          wr_en_a,                
    input  wire [STATE_WIDTH-1:0]        wr_data_a,              

    
    input  wire                          clk_b,                  
    input  wire                          rst_b,                  
    input  wire [VL_ADDR_WIDTH-1:0]      addr_b,                 
    input  wire                          rd_en_b,                
    output wire [STATE_WIDTH-1:0]        rd_data_b,              
    input  wire                          wr_en_b,                
    input  wire [STATE_WIDTH-1:0]        wr_data_b               
);
wire [63:0] rx_word_a;                                  
    wire [63:0] rx_word_b;                                  
    wire [63:0] tx_word_a;                                  
    wire [63:0] tx_word_b;                                  
    vl_state_ip u_vl_state_ip_rx (                          
        .clock_a    (clk_a),                                    
        .aclr_a     (rst_a),                                    
        .address_a  (addr_a),                                   
        .data_a     ({48'd0, wr_data_a[15:0]}),             
        .wren_a     (wr_en_a),                                  
        .q_a        (rx_word_a),                            
        .clock_b    (clk_b),                                    
        .aclr_b     (rst_b),                                    
        .address_b  (addr_b),                                   
        .data_b     (64'd0),                                
        .wren_b     (1'b0),                                 
        .q_b        (rx_word_b)                             
    );                                                      
    vl_state_ip u_vl_state_ip_tx (                          
        .clock_a    (clk_a),                                    
        .aclr_a     (rst_a),                                    
        .address_a  (addr_a),                                   
        .data_a     (64'd0),                                
        .wren_a     (1'b0),                                 
        .q_a        (tx_word_a),                            
        .clock_b    (clk_b),                                    
        .aclr_b     (rst_b),                                    
        .address_b  (addr_b),                                   
        .data_b     ({wr_data_b[63:16], 16'd0}),            
        .wren_b     (wr_en_b),                                  
        .q_b        (tx_word_b)                             
    );                                                      
    reg [(1<<VL_ADDR_WIDTH)-1:0] rx_initialized;            
    reg [(1<<VL_ADDR_WIDTH)-1:0] tx_initialized;            
    reg rx_valid_a;                                         
    reg tx_valid_a;                                         
    reg rx_valid_b;                                         
    reg tx_valid_b;

endmodule

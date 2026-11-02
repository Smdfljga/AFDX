// vl_config_ram : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module vl_config_ram #(                                     
    parameter VLID_WIDTH    = 16,           
    parameter VL_ADDR_WIDTH = 12            
)(                                                          
    
    input  wire                          clk_a,                  
    input  wire                          rst_a,                  
    input  wire [VL_ADDR_WIDTH-1:0]      addr_a,                 
    input  wire                          rd_en_a,                
    output wire [VLID_WIDTH-1:0]         tag_a,                  
    output wire                          valid_a,                
    output wire [1:0]                    port_type_a,            
    output wire [15:0]                   udp_port_a,             
    output wire [15:0]                   bag_a,                  
    output wire [15:0]                   lmax_a,                 
    output wire                          rm_en_a,                
    output wire                          ic_mode_a,              

    
    input  wire                          clk_b,                  
    input  wire                          rst_b,                  
    input  wire [VL_ADDR_WIDTH-1:0]      addr_b,                 
    input  wire                          rd_en_b,                
    output wire [VLID_WIDTH-1:0]         tag_b,                  
    output wire                          valid_b,                
    output wire [1:0]                    port_type_b,            
    output wire [15:0]                   udp_port_b,             
    output wire [15:0]                   bag_b,                  
    output wire [15:0]                   lmax_b,                 
    output wire                          rm_en_b,                
    output wire                          ic_mode_b,              

    
    input  wire                          cfg_wr_en,              
    input  wire [VL_ADDR_WIDTH-1:0]      cfg_wr_addr,            
    input  wire [VLID_WIDTH-1:0]         cfg_wr_vlid,            
    input  wire [15:0]                   cfg_wr_udp_port,        
    input  wire [1:0]                    cfg_wr_port_type,       
    input  wire [15:0]                   cfg_wr_bag,             
    input  wire [15:0]                   cfg_wr_lmax,            
    input  wire                          cfg_wr_rm_en,           
    input  wire                          cfg_wr_ic_mode          
);
wire [127:0] q_a;                                           
    wire [127:0] q_b;                                           
    vl_config_ip u_vl_config_ip (                           
        .clock_a    (clk_a),                                    
        .aclr_a     (rst_a),                                    
        .address_a  (cfg_wr_en ? cfg_wr_addr : addr_a),         
        
        .data_a     ({cfg_wr_vlid, 1'b1, cfg_wr_port_type, cfg_wr_udp_port,  
                      cfg_wr_bag, cfg_wr_lmax, cfg_wr_rm_en, cfg_wr_ic_mode,  
                      59'd0}),                                  
        .wren_a     (cfg_wr_en),                                
        .q_a        (q_a),                                      
        .clock_b    (clk_b),                                    
        .aclr_b     (rst_b),                                    
        .address_b  (addr_b),                                   
        .data_b     (128'd0),                                   
        .wren_b     (1'b0),                                     
        .q_b        (q_b)                                       
    );

endmodule

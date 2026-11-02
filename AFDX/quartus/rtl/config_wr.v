// config_wr : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module config_wr #(                                         
    parameter VLID_WIDTH    = 16,           
    parameter VL_ADDR_WIDTH = 12            
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

    
    output wire                          bram_wr_en,             
    output wire [VL_ADDR_WIDTH-1:0]      bram_wr_addr,           

    
    output wire                          cfg_done                
);
wire is_sentinel;
    reg done_r;                                                 
    wire [VL_ADDR_WIDTH-1:0] wr_addr;

endmodule

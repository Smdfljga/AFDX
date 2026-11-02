// flash_ctrl : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module flash_ctrl #(                                        
    parameter DATA_WIDTH = 8                
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          wr_req,                 
    input  wire [23:0]                   wr_addr,                
    input  wire [DATA_WIDTH-1:0]         wr_data,                
    output wire                          wr_done,                

    
    output wire                          flash_wr_en,            
    output wire [23:0]                   flash_wr_addr,          
    output wire [DATA_WIDTH-1:0]         flash_wr_data,          
    output wire                          flash_erase             
);
localparam S_IDLE  = 2'd0;                                  
    localparam S_ERASE = 2'd1;                                  
    localparam S_WRITE = 2'd2;                                  
    reg [1:0]          state;                                   
    reg [23:0]         addr_r;                                  
    reg [DATA_WIDTH-1:0] data_r;                                
    reg [11:0]         erased_sector;                           
    reg                erased_valid;                            
    reg [1:0] nxt_state;

endmodule

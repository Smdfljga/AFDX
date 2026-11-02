// file_table : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module file_table #(                                        
    parameter FILE_NAME_WIDTH = 64,         
    parameter FILE_SIZE_WIDTH = 32          
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          wr_en,                  
    input  wire [3:0]                    wr_index,               
    input  wire [FILE_NAME_WIDTH-1:0]    wr_name,                
    input  wire [FILE_SIZE_WIDTH-1:0]    wr_size,                
    input  wire [31:0]                   wr_crc,                 

    
    input  wire                          rd_en,                  
    input  wire [3:0]                    rd_index,               
    output wire [FILE_NAME_WIDTH-1:0]    rd_name,                
    output wire [FILE_SIZE_WIDTH-1:0]    rd_size,                
    output wire [31:0]                   rd_crc                  
);
wire [127:0] q_0;                                           
    file_table_ip u_file_table_ip (                         
        .inclock    (clk),                                      
        .in_aclr    (~rst_b),                                   
        .wraddress  (wr_index),                                 
        .data       ({wr_crc, wr_size, wr_name}),               
        .wren       (wr_en),                                    
        .outclock   (clk),                                      
        .out_aclr   (~rst_b),                                   
        .rdaddress  (rd_index),                                 
        .rden       (rd_en),                                    
        .q          (q_0)                                       
    );

endmodule

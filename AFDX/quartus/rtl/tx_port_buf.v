// tx_port_buf : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module tx_port_buf #(                                       
    parameter DATA_WIDTH        = 8,        
    parameter VL_INDEX_WIDTH    = 4,        
    parameter BYTE_OFFSET_WIDTH = 11        
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          wr_en,                  
    input  wire [VL_INDEX_WIDTH-1:0]     wr_vl_index,            
    input  wire [BYTE_OFFSET_WIDTH-1:0]  wr_byte_offset,         
    input  wire [DATA_WIDTH-1:0]         wr_data,                

    
    input  wire                          len_wr_en,              
    input  wire [VL_INDEX_WIDTH-1:0]     len_vl_index,           
    input  wire [BYTE_OFFSET_WIDTH-1:0]  len_byte_offset,        

    
    input  wire                          rd_en,                  
    input  wire [VL_INDEX_WIDTH-1:0]     rd_vl_index,            
    input  wire [BYTE_OFFSET_WIDTH-1:0]  rd_byte_offset,         
    output wire [DATA_WIDTH-1:0]         rd_data,                
    output wire                          rd_valid,               
    output wire [15:0]                   payload_len,            
    output wire [15:0]                   vl_busy,                
    input  wire [15:0]                   abort_vl                
);
wire [VL_INDEX_WIDTH+BYTE_OFFSET_WIDTH-1:0] wr_addr =   
        {wr_vl_index, wr_byte_offset};                          
    wire [VL_INDEX_WIDTH+BYTE_OFFSET_WIDTH-1:0] rd_addr =   
        {rd_vl_index, rd_byte_offset};                          
    tx_port_buf_ip u_tx_port_buf_ip (                       
        .inclock    (clk),                                      
        .in_aclr    (~rst_b),                                   
        .wraddress  (wr_addr),                                  
        .data       (wr_data),                                  
        .wren       (wr_en),                                    
        .outclock   (clk),                                      
        .out_aclr   (~rst_b),                                   
        .rdaddress  (rd_addr),                                  
        .rden       (rd_en),                                    
        .q          (rd_data)                                   
    );                                                      
    reg [15:0] payload_len_reg [0:(1<<VL_INDEX_WIDTH)-1];       
    integer init_len;                                           
    wire       read_last = rd_en && (payload_len != 16'd0) &&  
                           (rd_byte_offset == payload_len - 16'd1); 
    reg rd_en_d1;                                               
    reg rd_en_d;                                                
    reg [15:0] busy_r;                                          
    integer    init_busy;

endmodule

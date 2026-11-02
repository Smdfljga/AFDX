// data_loader_615a : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module data_loader_615a #(                                  
    parameter DATA_WIDTH        = 8,        
    parameter VL_INDEX_WIDTH    = 4,        
    parameter BYTE_OFFSET_WIDTH = 11,       
    parameter VL_INDEX_SELF     = 4'd2      
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          rx_ready_615a,          
    output wire                          rx_rd_req,              
    output wire [BYTE_OFFSET_WIDTH-1:0]  rx_rd_byte_offset,      
    input  wire [DATA_WIDTH-1:0]         rx_rd_data,             
    input  wire                          rx_rd_valid,            
    input  wire [15:0]                   rx_frame_len,           

    
    output wire                          tx_wr_en,               
    output wire [BYTE_OFFSET_WIDTH-1:0]  tx_wr_byte_offset,      
    output wire [DATA_WIDTH-1:0]         tx_wr_data,             
    output wire                          tx_frame_done,          
    input  wire                          tx_wr_gnt,              

    
    output wire                          load_busy,              
    output wire                          load_done,              
    output wire                          load_error              
);
wire         tftp_op_valid;                                 
    wire [1:0]   tftp_op_type;                                  
    wire [15:0]  tftp_block_num;                                
    wire [15:0]  tftp_data_len;                                 
    wire         buf_wr_en;                                     
    wire [DATA_WIDTH-1:0] buf_wr_data;                          
    wire         buf_rd_en;                                     
    wire [DATA_WIDTH-1:0] buf_rd_data;                          
    wire         fifo_rdempty;                                  
    wire         buf_rd_valid;                                  
    wire         flash_wr_req;                                  
    wire [23:0]  flash_wr_addr;                                 
    wire         flash_wr_done;                                 
    tftp #(                                                 
        .DATA_WIDTH        (DATA_WIDTH),                    
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH)              
    ) u_tftp (                                              
        .clk               (clk),                               
        .rst_b             (rst_b),                             
        .start             (rx_ready_615a),                     
        .rx_frame_len      (rx_frame_len),                      
        .rx_rd_req         (rx_rd_req),                         
        .rx_rd_byte_offset (rx_rd_byte_offset),                 
        .rx_rd_data        (rx_rd_data),                        
        .rx_rd_valid       (rx_rd_valid),                       
        .tftp_op_valid     (tftp_op_valid),                     
        .tftp_op_type      (tftp_op_type),                      
        .tftp_block_num    (tftp_block_num),                    
        .tftp_data_len     (tftp_data_len),                     
        .buf_wr_en         (buf_wr_en),                         
        .buf_wr_data       (buf_wr_data),                       
        .buf_rd_en         (buf_rd_en),                         
        .buf_rd_data       (buf_rd_data),                       
        .buf_rd_valid      (buf_rd_valid),                      
        .flash_wr_req      (flash_wr_req),                      
        .flash_wr_addr     (flash_wr_addr),                     
        .flash_wr_done     (flash_wr_done),                     
        .tx_wr_en          (tx_wr_en),                          
        .tx_wr_byte_offset (tx_wr_byte_offset),                 
        .tx_wr_data        (tx_wr_data),                        
        .tx_frame_done     (tx_frame_done),                     
        .tx_wr_gnt         (tx_wr_gnt),                         
        .load_busy         (load_busy),                         
        .load_done         (load_done),                         
        .load_error        (load_error)                         
    );                                                      
    file_buffer #(                                          
        .DATA_WIDTH (DATA_WIDTH),                           
        .FIFO_DEPTH (512)                                   
    ) u_file_buffer (                                       
        .clk       (clk),                                       
        .rst_b     (rst_b),                                     
        .wr_req    (buf_wr_en),                                 
        .data      (buf_wr_data),                               
        .rd_req    (buf_rd_en),                                 
        .q         (buf_rd_data),                               
        .rdempty   (fifo_rdempty),                              
        .rdfull    (),                                          
        .wrusedw   ()                                           
    );                                                      
    reg fifo_rd_valid_r;                                    
    flash_ctrl #(                                           
        .DATA_WIDTH (DATA_WIDTH)                            
    ) u_flash_ctrl (                                        
        .clk          (clk),                                    
        .rst_b        (rst_b),                                  
        .wr_req       (flash_wr_req),                           
        .wr_addr      (flash_wr_addr),                          
        .wr_data      (buf_rd_data),                            
        .wr_done      (flash_wr_done),                          
        .flash_wr_en  (),                                       
        .flash_wr_addr(),                                       
        .flash_wr_data(),                                       
        .flash_erase  ()                                        
    );                                                      
    file_table #(                                           
        .FILE_NAME_WIDTH (64),                              
        .FILE_SIZE_WIDTH (32)                               
    ) u_file_table (                                        
        .clk      (clk),                                        
        .rst_b    (rst_b),                                      
        .wr_en    (tftp_op_valid),                              
        .wr_index (tftp_block_num[3:0]),                         
        .wr_name ( {tftp_block_num, tftp_data_len, 32'd0} ),    
        .wr_size ( {16'd0, tftp_data_len} ),                    
        .wr_crc  ( 32'd0 ),                                     
        .rd_en   (1'b1),                                        
        .rd_index(tftp_block_num[3:0]),                          
        .rd_name (),                                            
        .rd_size (),                                            
        .rd_crc  ()                                             
    );

endmodule

// file_buffer : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module file_buffer #(                                       
    parameter DATA_WIDTH = 8,               
    parameter FIFO_DEPTH = 512              
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          wr_req,                 
    input  wire [DATA_WIDTH-1:0]         data,                   

    
    input  wire                          rd_req,                 
    output wire [DATA_WIDTH-1:0]         q,                      
    output wire                          rdempty,                
    output wire                          rdfull,                 
    output wire [8:0]                    wrusedw                 
);
file_buffer_ip u_file_buffer_ip (                       
        .clock       (clk),                                     
        .aclr        (~rst_b),                                  
        .sclr        (1'b0),                                    
        .data        (data),                                    
        .wrreq       (wr_req),                                  
        .rdreq       (rd_req),                                  
        .q           (q),                                       
        .full        (rdfull),                                  
        .empty       (rdempty),                                 
        .usedw       (wrusedw),                                 
        .almost_full (),                                        
        .almost_empty()                                         
    );

endmodule

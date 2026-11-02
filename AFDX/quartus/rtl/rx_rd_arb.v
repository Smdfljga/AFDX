// rx_rd_arb : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module rx_rd_arb #(                                         
    parameter DATA_WIDTH        = 8,        
    parameter VL_INDEX_WIDTH    = 4,        
    parameter BYTE_OFFSET_WIDTH = 11        
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          app_rd_req,             
    input  wire [VL_INDEX_WIDTH-1:0]     app_rd_vl_index,        
    input  wire [BYTE_OFFSET_WIDTH-1:0]  app_rd_byte_offset,     
    output wire                          app_rd_valid,           

    
    input  wire                          snmp_rd_req,            
    input  wire [VL_INDEX_WIDTH-1:0]     snmp_rd_vl_index,       
    input  wire [BYTE_OFFSET_WIDTH-1:0]  snmp_rd_byte_offset,    
    output wire                          snmp_rd_valid,          

    
    input  wire                          dl_rd_req,              
    input  wire [VL_INDEX_WIDTH-1:0]     dl_rd_vl_index,         
    input  wire [BYTE_OFFSET_WIDTH-1:0]  dl_rd_byte_offset,      
    output wire                          dl_rd_valid,            

    
    input  wire                          rtc_rd_req,             
    input  wire [VL_INDEX_WIDTH-1:0]     rtc_rd_vl_index,        
    input  wire [BYTE_OFFSET_WIDTH-1:0]  rtc_rd_byte_offset,     
    output wire                          rtc_rd_valid,           

    
    output wire                          buf_rd_en,              
    output wire [VL_INDEX_WIDTH-1:0]     buf_rd_vl_index,        
    output wire [BYTE_OFFSET_WIDTH-1:0]  buf_rd_byte_offset,     
    input  wire [DATA_WIDTH-1:0]         buf_rd_data,            

    
    output wire [DATA_WIDTH-1:0]         rd_data                 
);
reg app_v1;                                                 
    reg snmp_v1;                                                
    reg dl_v1;                                                  
    reg rtc_v1;                                                 
    reg app_v;                                                  
    reg snmp_v;                                                 
    reg dl_v;                                                   
    reg rtc_v;                                                  
    wire snmp_pend;
    wire dl_pend;
    wire rtc_pend;
    wire app_gnt;
    wire snmp_gnt;
    wire dl_gnt;
    wire rtc_gnt;

endmodule

// snmp_agent : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module snmp_agent #(                                        
    parameter DATA_WIDTH        = 8,        
    parameter VL_INDEX_WIDTH    = 4,        
    parameter BYTE_OFFSET_WIDTH = 11,       
    parameter CNT_WIDTH         = 32,       
    parameter VL_ADDR_WIDTH     = 12,       
    parameter OID_WIDTH         = 16,       
    parameter VL_INDEX_SELF     = 4'd1      
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          rx_ready_snmp,          
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

    
    output wire                          mib_sel,                
    output wire [VL_ADDR_WIDTH-1:0]      mib_addr,               
    output wire                          mib_rd_en,              
    input  wire [5*CNT_WIDTH-1:0]        mib_rd_data             
);
wire         pdu_valid;                                     
    wire [1:0]   pdu_type;                                      
    wire [OID_WIDTH-1:0] oid;                                   
    wire         decode_done;                                   
    wire         query_done;                                    
    wire [CNT_WIDTH-1:0] query_value;                           
    wire         enc_done;                                      
    snmp_decoder #(                                         
        .DATA_WIDTH        (DATA_WIDTH),                    
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             
        .OID_WIDTH         (OID_WIDTH)                      
    ) u_snmp_decoder (                                      
        .clk               (clk),                               
        .rst_b             (rst_b),                             
        .start             (rx_ready_snmp),                     
        .rx_frame_len      (rx_frame_len),                      
        .rx_rd_req         (rx_rd_req),                         
        .rx_rd_byte_offset (rx_rd_byte_offset),                 
        .rx_rd_valid       (rx_rd_valid),                       
        .rx_rd_data        (rx_rd_data),                        
        .pdu_valid         (pdu_valid),                         
        .pdu_type          (pdu_type),                          
        .oid               (oid),                               
        .decode_done       (decode_done)                        
    );                                                      
    mib_query #(                                            
        .CNT_WIDTH     (CNT_WIDTH),                         
        .VL_ADDR_WIDTH (VL_ADDR_WIDTH),                     
        .OID_WIDTH     (OID_WIDTH)                          
    ) u_mib_query (                                         
        .clk         (clk),                                     
        .rst_b       (rst_b),                                   
        .query_req   (pdu_valid),                               
        .oid         (oid),                                     
        .mib_sel     (mib_sel),                                 
        .mib_addr    (mib_addr),                                
        .mib_rd_en   (mib_rd_en),                               
        .mib_rd_data (mib_rd_data),                             
        .query_done  (query_done),                              
        .query_value (query_value)                              
    );                                                      
    snmp_encoder #(                                         
        .DATA_WIDTH        (DATA_WIDTH),                    
        .BYTE_OFFSET_WIDTH (BYTE_OFFSET_WIDTH),             
        .OID_WIDTH         (OID_WIDTH)                      
    ) u_snmp_encoder (                                      
        .clk               (clk),                               
        .rst_b             (rst_b),                             
        .enc_req           (query_done),                        
        .oid         (oid),                                     
        .value             (query_value),                       
        .tx_wr_gnt         (tx_wr_gnt),                         
        .tx_wr_en          (tx_wr_en),                          
        .tx_wr_byte_offset (tx_wr_byte_offset),                 
        .tx_wr_data        (tx_wr_data),                        
        .enc_done          (enc_done)                           
    );

endmodule

// mib_query : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module mib_query #(                                         
    parameter CNT_WIDTH     = 32,           
    parameter VL_ADDR_WIDTH = 12,           
    parameter OID_WIDTH     = 16            
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          query_req,              
    input  wire [OID_WIDTH-1:0]          oid,                    

    
    output wire                          mib_sel,                
    output wire [VL_ADDR_WIDTH-1:0]      mib_addr,               
    output wire                          mib_rd_en,              
    input  wire [5*CNT_WIDTH-1:0]        mib_rd_data,            

    
    output wire                          query_done,             
    output wire [CNT_WIDTH-1:0]          query_value             
);
wire [2:0]               cnt_sel;
    wire [VL_ADDR_WIDTH-1:0] vl_addr;
    wire                     tbl_sel;
    reg                  rq_d1, rq_d2, rq_d3;               
    reg [2:0]            cnt_d1, cnt_d2;                    
    reg                  tbl_d1, tbl_d2;                    
    reg [VL_ADDR_WIDTH-1:0] addr_r;                         
    reg [CNT_WIDTH-1:0]  value_r;

endmodule

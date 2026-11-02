// delay_comp : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module delay_comp #(                                        
    parameter RTC_WIDTH = 48                
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire [RTC_WIDTH-1:0]          master_ts,              
    input  wire [31:0]                   delay_val,              
    input  wire [31:0]                   rx_process_delay,       
    input  wire                          calc_req,               

    
    output wire [RTC_WIDTH-1:0]          corrected_ts,           
    output wire                          calc_done               
);
wire [RTC_WIDTH-1:0] proc_delay_us;
    wire [RTC_WIDTH:0]   sum =                              
        {1'b0, master_ts} + {1'b0, {16'd0, delay_val}} + {1'b0, proc_delay_us}; 
    reg [RTC_WIDTH-1:0] corrected_r;                            
    reg                 done_r;

endmodule

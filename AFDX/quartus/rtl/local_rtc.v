// local_rtc : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module local_rtc #(                                         
    parameter RTC_WIDTH = 48                
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          sync_en,                
    input  wire [RTC_WIDTH-1:0]          sync_value,             

    
    input  wire [15:0]                   sync_period_ms,         

    
    output wire [RTC_WIDTH-1:0]          rtc_value,              
    output wire                          rtc_tick                
);
localparam US_DIV = 25;                                     
    reg [6:0]  us_cnt;                                          
    reg [9:0]  us_in_ms;                                    
    reg [15:0] ms_cnt;                                          
    reg [RTC_WIDTH-1:0] rtc_r;

endmodule

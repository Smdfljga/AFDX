// rx_frame_buf : vendor IP stub for Quartus RTL Viewer
// Port list copied from the real IP wrapper; body intentionally empty.
module rx_frame_buf (
    rdclock,
    wrclock,
    data,
    rdaddress,
    wraddress,
    wren,
    rden,
    q);
input rdclock;
input wrclock;
input [7:0] data;
input [11:0] rdaddress;
input [11:0] wraddress;
input wren;
output [7:0] q;
input rden;

endmodule

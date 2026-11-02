// rx_port_buf_ip : vendor IP stub for Quartus RTL Viewer
// Port list copied from the real IP wrapper; body intentionally empty.
module rx_port_buf_ip (
    in_aclr,
    out_aclr,
    inclock,
    outclock,
    data,
    rdaddress,
    wraddress,
    wren,
    rden,
    q);
input in_aclr;
input out_aclr;
input inclock;
input outclock;
input [7:0] data;
input [14:0] rdaddress;
input [14:0] wraddress;
input wren;
output [7:0] q;
input rden;

endmodule

// file_table_ip : vendor IP stub for Quartus RTL Viewer
// Port list copied from the real IP wrapper; body intentionally empty.
module file_table_ip (
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
input [127:0] data;
input [3:0] rdaddress;
input [3:0] wraddress;
input wren;
output [127:0] q;
input rden;

endmodule

// vl_state_ip : vendor IP stub for Quartus RTL Viewer
// Port list copied from the real IP wrapper; body intentionally empty.
module vl_state_ip (
    aclr_a,
    aclr_b,
    clock_a,
    clock_b,
    data_a,
    data_b,
    address_a,
    address_b,
    wren_a,
    wren_b,
    q_a,
    q_b);
input clock_a;
input clock_b;
input aclr_a;
input aclr_b;
input [63:0] data_a;
input [63:0] data_b;
input [11:0] address_b;
input [11:0] address_a;
input wren_a;
input wren_b;
output [63:0] q_a;
output [63:0] q_b;

endmodule

// file_buffer_ip : vendor IP stub for Quartus RTL Viewer
// Port list copied from the real IP wrapper; body intentionally empty.
module file_buffer_ip (
	aclr,
	clock,
	data,
	rdreq,
	wrreq,
	sclr,
	almost_empty,
	almost_full,
	empty,
	full,
	usedw,
	q
	);
input aclr;
input clock;
input [7:0] data;
input rdreq;
input wrreq;
input sclr;
output almost_empty;
output almost_full;
output empty;
output full;
output [8:0] usedw;
output [7:0] q;

endmodule

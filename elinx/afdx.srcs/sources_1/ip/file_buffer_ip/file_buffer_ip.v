// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
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

	input    aclr;
	input    clock;
	input    [7:0]    data;
	input    rdreq;
	input    wrreq;
	input    sclr;
	output    almost_empty;
	output    almost_full;
	output    empty;
	output    full;
	output    [8:0]    usedw;
	output    [7:0]    q;

	scfifo    scfifo (
		.clock (clock),
		.sclr (sclr),
		.wrreq (wrreq),
		.aclr (aclr),
		.data (data),
		.rdreq (rdreq),
		.usedw (usedw),
		.empty (empty),
		.full (full),
		.q (q),
		.almost_empty (almost_empty),
		.almost_full (almost_full)
	);

	defparam
		scfifo.add_ram_output_register = "ON",
		scfifo.almost_full_value = 511,
		scfifo.almost_empty_value = 1,
		scfifo.intended_device_family = "Stratix",
		scfifo.lpm_hint = "RAM_BLOCK_TYPE=M4K",
		scfifo.lpm_numwords = 512,
		scfifo.lpm_showahead = "OFF",
		scfifo.lpm_type = "scfifo",
		scfifo.lpm_width = 8,
		scfifo.lpm_widthu = 9,
		scfifo.overflow_checking = "ON",
		scfifo.underflow_checking = "ON",
		scfifo.use_eab = "ON";
endmodule
//#M4K
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

    input	  clock_a;
    input	  clock_b;
    input	  aclr_a;
    input	  aclr_b;
    input	[63:0]  data_a;
    input	[63:0]  data_b;
    input	[11:0]  address_b;
    input	[11:0]  address_a;
    input	  wren_a;
    input	  wren_b;
    output	[63:0]  q_a;
    output	[63:0]  q_b;

    wire [63:0] sub_wire0;
    wire [63:0] sub_wire1;
    wire [63:0] q_a = sub_wire0[63:0];
    wire [63:0] q_b = sub_wire1[63:0];

    altsyncram	altsyncram_component (
                .wren_a (wren_a),
                .wren_b (wren_b),
                .clock0 (clock_a),
                .clock1 (clock_b),
                .address_a (address_a),
                .address_b (address_b),
                .data_a (data_a),
                .data_b (data_b),
                .q_a (sub_wire0),
                .q_b (sub_wire1),
                .aclr0 (aclr_a),
                .aclr1 (aclr_b),
                .addressstall_a (1'b0),
                .addressstall_b (1'b0),
                .byteena_a (1'b1),
                .byteena_b (1'b1),
                .clocken0 (1'b1),
                .clocken1 (1'b1),
                .clocken2 (1'b1),
                .clocken3 (1'b1),
                .eccstatus (),
                .rden_a (1'b1),
                .rden_b (1'b1)
);

    defparam
        altsyncram_component.address_aclr_a = "CLEAR0",
        altsyncram_component.address_aclr_b = "CLEAR1",
        altsyncram_component.address_reg_b = "CLOCK1",
        altsyncram_component.indata_aclr_a = "CLEAR0",
        altsyncram_component.indata_aclr_b = "CLEAR1",
        altsyncram_component.indata_reg_b = "CLOCK1",
        altsyncram_component.intended_device_family = "Stratix",
        altsyncram_component.lpm_type = "altsyncram",
        altsyncram_component.numwords_a = 4096,
        altsyncram_component.numwords_b = 4096,
        altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
        altsyncram_component.outdata_aclr_a = "NONE",
        altsyncram_component.outdata_aclr_b = "CLEAR1",
        altsyncram_component.outdata_reg_a = "CLOCK0",
        altsyncram_component.outdata_reg_b = "CLOCK1",
        altsyncram_component.power_up_uninitialized = "FALSE",
        altsyncram_component.ram_block_type = "M4K",
        altsyncram_component.init_file_layout = "PORT_B",
        altsyncram_component.widthad_a = 12,
        altsyncram_component.widthad_b = 12,
        altsyncram_component.width_a = 64,
        altsyncram_component.width_b = 64,
        altsyncram_component.width_byteena_a = 1,
        altsyncram_component.init_file = "UNUSED",
        altsyncram_component.wrcontrol_aclr_a = "CLEAR0",
        altsyncram_component.width_byteena_b = 1,
        altsyncram_component.wrcontrol_aclr_b = "CLEAR1",
        altsyncram_component.wrcontrol_wraddress_reg_b = "CLOCK1";


endmodule

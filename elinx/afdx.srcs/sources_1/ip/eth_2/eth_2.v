module eth_2 (
  // Outputs
  mdc, phy_rstb0, p0_gtxc, p0_txd, p0_txen, p0_txer, ff_tx_rdy, 
  ff_tx_al_full, ff_rx_data_vld, ff_rx_data, 
  ff_rx_sop, ff_rx_eop, ff_rx_err, reg_data_out, reg_acc_bsy, 
  // Inouts
  mdio, 
  // Inputs
  clk_sys, rst_b, p0_txc, p0_rxc, p0_rxd, p0_rxdv, p0_rxer, p0_col, 
  p0_crs, ff_tx_clk, ff_tx_data, ff_tx_sop, ff_tx_eop, ff_tx_err, 
  ff_tx_wren, ff_rx_clk, ff_rx_rdy, reg_wr, reg_rd, reg_addr, 
  reg_data_in
  );
// ------------------------------------------------------
//   IO declaration
// ------------------------------------------------------
inout       mdio      ;

output      mdc       ;
output      phy_rstb0 ;
output      p0_gtxc   ;//O    
output[7:0] p0_txd    ;//O   
output      p0_txen   ;//O   
output      p0_txer   ;//

input       clk_sys   ;
input       rst_b     ;//reset input

input       p0_txc    ;//I
input       p0_rxc    ;//I      
input [7:0] p0_rxd    ;//I    
input       p0_rxdv   ;//I  
input       p0_rxer   ;
input       p0_col    ;
input       p0_crs    ;

////////following is the user TX interface////////////// 

input      ff_tx_clk       ;
input[7:0] ff_tx_data      ;
input      ff_tx_sop       ;
input      ff_tx_eop       ;
input      ff_tx_err       ;//Indi the mac forwards the invalid frame to the GMII interface
input      ff_tx_wren      ;

output     ff_tx_rdy       ;//when this signla is 1'b1, indi the data can write into the fifo
output     ff_tx_al_full   ;

////////following is the user RX interface//////////////////// 

input      ff_rx_clk       ;
output     ff_rx_data_vld  ;//when asserted, the following RX data are valid
output[7:0]ff_rx_data      ;//8bit data
output     ff_rx_sop       ;
output     ff_rx_eop       ;
output     ff_rx_err       ;//indi the error found 
input      ff_rx_rdy       ;//indi the user is ready to receive data

////////following is the register access interface////////////// 

input        reg_wr        ; 
input        reg_rd        ;
input [3 :0] reg_addr      ;
input [31:0] reg_data_in   ;

output[31:0] reg_data_out  ;
output       reg_acc_bsy   ;//indi the register access busy 

////////////////////////////////////////////////////////////////

wire phy_rstb0 = 1'b1   ;
wire p0_gtxc   = p0_rxc ;//O    


//wire ff_tx_al_empty  ;

//following is the auto polling status indication 
wire       mdc   ; 
wire       mdio  ; 
wire [1:0] speed ; 
wire       link  ; 
wire [3:0] led   ; 


smi_config  inst_smi_config
                       (
                       .clk    (clk_sys     ),
                       .rst_n  (rst_b       ),
                       
                       .mdc    (mdc         ), //mdc interface
                       .mdio   (mdio        ), //mdio interface
                       .speed  (speed[1:0]  ), //ethernet speed 00:10M 01:100M 10:1000M
                       .link   (link        ), //ethernet link signal
                       .led    (led  [3:0]  )  //led 1110: 10M  1100: 100M 1000:1000M  1111: not link
                       /*AUTOINST*/);


//////////////////////////////////////////////////
/////following is the gmii like signal process////
//////////////////////////////////////////////////
wire [31:0] pack_total_len ;  
wire        e_rst_n        ;      

wire        rxdv_in        ;  
wire [7 :0] rxd_in         ;  

reg         txe_out        ;  
reg  [7 :0] txd_out        ;  

gmii_arbi inst_gmii_arbi
                       (
                       .clk             (p0_rxc                ),
                       .rst_n           (rst_b                 ),
                       .speed           (speed  [1 :0]         ),  
                       .link            (link                  ),                                            

                       .pack_total_len  (pack_total_len [31:0] ),//delay time
                       .e_rst_n         (e_rst_n               ),

                       .gmii_tx_en      (txe_out               ),
                       .gmii_txd        (txd_out  [7 :0]       ),                       
                       .e_rxd           (rxd_in   [7 :0]       ),
                       .e_rx_dv         (rxdv_in               ),

                       .gmii_rx_dv      (p0_rxdv               ),
                       .gmii_rxd        (p0_rxd  [7 :0]        ),
                       .e_tx_en         (p0_txen               ),
                       .e_txd           (p0_txd  [7 :0]        )      
                       /*AUTOINST*/);

//////////////////////////////////////////////////////////////////////
////////////////following is the MAC packet process///////////////////
//////////////////////////////////////////////////////////////////////

wire [47:0] mac_addr   ;
wire [31:0] arp_des_ip ;



register_acc  inst_register_acc (
                       .sys_clk       (clk_sys             ),
                       .sys_rst_b     (rst_b               ),     

                       .reg_wr        (reg_wr              ), 
                       .reg_rd        (reg_rd              ), 
                       .reg_addr      (reg_addr    [3 :0]  ), 
                       .reg_data_in   (reg_data_in [31:0]  ), 
                       .reg_data_out  (reg_data_out[31:0]  ), 
                       .reg_acc_bsy   (reg_acc_bsy         ), 
                       .mac_addr      (mac_addr[47:0]      ),
                       .arp_des_ip    (arp_des_ip[31:0]    ),
                       .tx_enable     (tx_enable           ),
                       .rx_enable     (rx_enable           ),
                       .pause_send    (pause_send          ),
                       .eth_speed     (eth_speed           ),
                       .da_filter_en  (da_filter_en        ),
                       .pause_fwd_en  (pause_fwd_en        ),
                       .pause_ignore  (pause_ignore        ),
                       .soft_reset    (soft_reset          ),
                       .loop_enable   (loop_enable         )
                       /*AUTOINST*/);


//////////////////////////////////////////////////////////////////////
////////////////following is the parsor_giga instance/////////////////
//////////////////////////////////////////////////////////////////////

wire [15:0] typelen       ;
wire        ipv4oph       ;
wire        ipv6oph       ;
wire        l2err         ;                    
wire        pause_tx      ; 
wire        pause_pkt     ;  
wire        rxc_goodpktps ;   
wire        rxc_badpktps  ;   
wire        crceq         ;                        

wire        octet_nonzero ;     
wire        octet_below64 ;     
wire        octet_maxlen  ;     
wire        realrxdv      ;     
wire        symbolerr     ;     


/*AUTOWIRE*/
// Beginning of automatic wires (for undeclared instantiated-module outputs)
wire [47:0]		da;			// From inst_parsor_giga of parsor_giga.v
wire [1:0]		datype;			// From inst_parsor_giga of parsor_giga.v
wire [13:0]		fifo_rbcq;		// From inst_rec of rec.v
wire [112:0]		hsb_payload;		// From inst_parsor_giga of parsor_giga.v
wire [1:0]		l2fmt;			// From inst_parsor_giga of parsor_giga.v
wire [3:0]		l34fmt;			// From inst_parsor_giga of parsor_giga.v
wire			pppoe;			// From inst_parsor_giga of parsor_giga.v
wire [13:0]		rbcq;			// From inst_rec of rec.v
wire			rcv;			// From inst_rec of rec.v
wire [13:0]		real_rbcq;		// From inst_rec of rec.v
wire			receive;		// From inst_rec of rec.v
wire			rxc_crcendps;		// From inst_rec of rec.v
wire			rxc_pktbegps_int;	// From inst_rec of rec.v
wire			rxc_recbegps;		// From inst_rec of rec.v
wire			rxc_recendps;		// From inst_rec of rec.v
wire [47:0]		sa;			// From inst_parsor_giga of parsor_giga.v
wire			short_ipg_indi_pls;	// From inst_rec of rec.v
// End of automatics


parsor_giga  inst_parsor_giga (
			       // Outputs
			       .hsb_payload             (hsb_payload[112:0]           ),
			       .da	                (da[47:0]                     ),
			       .sa	                (sa[47:0]                     ),
			       .datype	                (datype[1:0]                  ),
			       .l2fmt	                (l2fmt[1:0]                   ),
			       .l34fmt	                (l34fmt[3:0]                  ),
			       .typelen	                (typelen[15:0]                ),
			       .ipv4oph	                (ipv4oph                      ),
			       .ipv6oph	                (ipv6oph                      ),
			       .l2err	                (l2err                        ),//CRC Related
			       .pause_tx                (pause_tx                     ),
			       .pause_pkt               (pause_pkt                    ),
			       .rxc_goodpktps           (rxc_goodpktps                ),
			       .rxc_badpktps            (rxc_badpktps                 ),
			       .crceq	                (crceq                        ),

			       .pppoe	                (                             ),
			       .otagexist               (                             ),
			       .opri	                (                             ),
			       .dei	                (                             ),
			       .ovid	                (                             ),
			       .itagexist               (                             ),
			       .ipri	                (                             ),
			       .cfi	                (                             ),
			       .ivid	                (                             ),
			       .ptp_class               (                             ),
			       .rtkpp	                (                             ),
			       .b_lat6	                (                             ),
			       .b_lat12	                (                             ),
			       .b_lat20	                (                             ),
			       .b_lat28	                (                             ),
			       .b_lat30	                (                             ),
			       .unknopcode_pkt          (                             ),
			       .unknethertp_pkt         (                             ),
			       .unknda_pkt              (                             ),
			       .timestamp_sec           (                             ),
			       .timestamp_512ns         (                             ),
			       .timestamp_valid         (                             ),
			       .del_itag                (                             ),
			       .del_otag                (                             ),
			       // Inputs
			       .mac_rxpause             (1'b1                         ),
			       .mac_duplx               (1'b1                         ),
			       .spid	                (16'b0                        ),
			       .tpid	                (16'b0                        ),
			       .otagen	                (1'b0                         ),
			       .itagen	                (1'b0                         ),
			       .snapflag                (1'b0                         ),
			       .rldp_enable_pmsk        (1'b0                         ),
			       .enrx_fc	                (1'b1                         ),
			       .l2crcerrdrop            (1'b0                         ),
			       .time_sync_en            (1'b0                         ),
			       .ingress_timestamp_sec   (32'b0                        ),
			       .ingress_timestamp_512ns (23'b0                        ),

			       .rxc	                (p0_rxc                       ),
			       .rxc_rstb                (rst_b                        ),
			       .rxd	                (rxd_in   [7 :0]              ),
			       .rxdv	                (rxdv_in                      ),
			       .rxc_crcendps            (rxc_crcendps                 ),
			       .rbcq	                (rbcq[13:0]                   ),
			       .rcv	                (rcv                          ),
			       .receive	                (receive                      ),
			       .rxc_recbegps            (rxc_recbegps                 ),
			       .rxc_recendps            (rxc_recendps                 ),
			       .sw_mac	                (mac_addr[47:0]               ),
			       .swip	                (arp_des_ip [31:0]            ) //ARP DIP
                               /*AUTOINST*/);


rec           inst_rec         (
	                       // Outputs
	                       .rxc_pktbegps_int	(rxc_pktbegps_int      ),
	                       .short_ipg_indi_pls	(short_ipg_indi_pls    ),
	                       .rxc_recbegps		(rxc_recbegps          ),
	                       .rxc_recendps		(rxc_recendps          ),
	                       .rxc_crcendps		(rxc_crcendps          ),
	                       .receive			(receive               ),
	                       .rcv			(rcv                   ),
	                       .rbcq			(rbcq[13:0]            ),
	                       .real_rbcq		(real_rbcq[13:0]       ),
	                       .fifo_rbcq		(fifo_rbcq[13:0]       ),

	                       .octet_nonzero		(octet_nonzero         ),
	                       .octet_below64		(octet_below64         ),
	                       .octet_maxlen		(octet_maxlen          ),
	                       .realrxdv		(realrxdv              ),
	                       .symbolerr		(symbolerr             ),
	                       .rbcq_new		(                      ),
	                       .rxc_recendps_new	(                      ),

	                       .length_mismatch		(                      ),
	                       .octet_over12pg		(                      ),
	                       .octet_over1522		(                      ),
	                       .disrx			(                      ),
	                       .eee_rx_sts		(                      ),
	                       .rx_dbg_rec		(                      ),
	                       .dscerr			(                      ),
	                       .receive_new		(                      ),
	                       .receive_for_rxcongest	(                      ),
	                       .octet_jabber		(                      ),
	                       // Inputs
	                       .rxc			(p0_rxc                ),
	                       .rxc_rstb		(rst_b                 ),
	                       .rxd			(rxd_in   [7 :0]       ),
	                       .rxdv			(rxdv_in               ),
	                       .link			(link                  ),
	                       .typelen			(typelen[15:0]         ),

	                       .maxlen_inc_tag		(1'b1                  ),
	                       .cputag			(1'b0                  ),
	                       .itagexist		(1'b0                  ),
	                       .otagexist		(1'b0                  ),
	                       .ck			(1'b0                  ),
	                       .ck_rstb			(1'b0                  ),
	                       .rxer			(1'b0                  ),
	                       .initok			(1'b1                  ),
	                       .dis_eee			(1'b1                  ),
	                       .enrx_eee		(1'b0                  ),
	                       .mac_rxeee		(1'b0                  ),
	                       .dscrunout		(1'b0                  ),
	                       .del_itag		(1'b1                  ),
	                       .del_otag		(1'b1                  ),
	                       .enrx			(1'b1                  ),
	                       .enrxer			(1'b1                  ),
	                       .maxlen			(14'd1518              ),
	                       .ipg_protect_sel		(4'd9                  ),
	                       .itfsp			(1'b0                  ),
	                       .lpi_sel			(1'b0                  ),
	                       .mac_lpi_rx		(1'b0                  )
                               /*AUTOINST*/);


////////////////////////////////////////////////////////////////////////////////////////////////
//////following is the RX fifo instance module, which is used to store the received data////////
////////////////////////////////////////////////////////////////////////////////////////////////


/////////////////////////////////////////////////////////////////////
////following is used to deal with the MAC RX fifo write process/////
/////////////////////////////////////////////////////////////////////
reg       wr_receive_dat_en;
wire      wr_receive_full  ;
wire      receive_neg      ; 

reg [1:0] cnt_for_wr_dat;
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        cnt_for_wr_dat <= 2'b0;
    else if(rcv)
        cnt_for_wr_dat <= cnt_for_wr_dat + 1'b1;
    else if(receive_neg)
        cnt_for_wr_dat <= 2'b0;
    
reg [1:0] cnt_for_wr_dat_d1;
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        cnt_for_wr_dat_d1 <= 2'b0;
    else 
        cnt_for_wr_dat_d1 <= cnt_for_wr_dat;

reg receive_d0;
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        receive_d0 <= 1'b0;
    else 
        receive_d0 <= rcv;

wire   receive_pos = ~receive_d0 &  rcv;   
assign receive_neg =  receive_d0 & ~rcv;  

always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        wr_receive_dat_en <= 1'b0;
    else if(wr_receive_full)
        wr_receive_dat_en <= 1'b0;
    else if(receive_neg & ~wr_receive_dat_en)
        wr_receive_dat_en <= 1'b1;
    else if(rcv & (&cnt_for_wr_dat))
        wr_receive_dat_en <= 1'b1;
    else 
        wr_receive_dat_en <= 1'b0;

reg[31:0] pre_receive_data;
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        pre_receive_data <= 32'b0;
    else if(rcv)
        pre_receive_data <= {pre_receive_data[23:0],rxd_in[7:0]} ;

reg wr_sop_indi;
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        wr_sop_indi <= 1'b0;
    else if(wr_receive_dat_en)
        wr_sop_indi <= 1'b0;
    else if(receive_pos)
        wr_sop_indi <= 1'b1;

reg wr_eop_indi;
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        wr_eop_indi <= 1'b0;
    else if(wr_receive_dat_en)
        wr_eop_indi <= 1'b0;
    else if(receive_neg)
        wr_eop_indi <= 1'b1;
 
reg err_found;
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        err_found <= 1'b0;
    else if(receive_pos)
        err_found <= 1'b0;
    else if(p0_rxer | rxc_badpktps)
        err_found <= 1'b1;

wire neg_write_delay = (receive_neg & ~wr_receive_dat_en);

reg  neg_write_delay_d0; 
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        neg_write_delay_d0 <= 1'b0;
    else 
        neg_write_delay_d0 <= neg_write_delay;


wire[1:0] sop_eop_indi =
                         wr_sop_indi ? 2'b01 : //SOP Indication
     wr_receive_dat_en & receive_neg ? 2'b10 : //EOP Indication
     wr_receive_dat_en & wr_eop_indi ? 2'b10 : //EOP Indication
                         err_found   ? 2'b11 : //Err Indication
                                       2'b00 ;

wire  wr_eop_final_indi = (sop_eop_indi == 2'b10);  

wire[1:0] byte_indi = {(2){wr_eop_final_indi}} & ( neg_write_delay_d0 ?  cnt_for_wr_dat_d1[1:0] : cnt_for_wr_dat[1:0]); 


wire [35:0] wr_receive_data = { 
                              sop_eop_indi     [1:0] , //SOP Indi                           
                              byte_indi        [1:0] , //Byte Indi
                              pre_receive_data                      
                              }; 

////////////////////////////////////////////////////////////////////
////following is used to deal with the MAC RX fifo read process/////
////////////////////////////////////////////////////////////////////

wire        rdempty ;     

/////////////following is used to sync the reset domain////////////
reg rst_b_syn0;
reg rst_b_syn1;
always @(posedge ff_rx_clk or negedge rst_b)
    if(~rst_b)
        begin
            rst_b_syn0 <= 1'b0;
            rst_b_syn1 <= 1'b0;
        end
    else
        begin
            rst_b_syn0 <= 1'b1;
            rst_b_syn1 <= rst_b_syn0;
        end

wire rst_b_rx_clk = rst_b_syn1;

/////////////following is used to gen the fifo read////////////
reg[2:0] cnt_for_data_out;
reg      pre_rd_req      ;
reg[2:0] rd_req_dly      ;
wire     rd_req          ;

always @(posedge ff_rx_clk or negedge rst_b_rx_clk)
    if(!rst_b_rx_clk)
        pre_rd_req <= 1'b0;
    else if(|rd_req_dly[1:0] | rd_req)
        pre_rd_req <= 1'b0;
    else if(~rdempty & ff_rx_rdy /*& ((cnt_for_data_out[2:0] == 3'h2) | (cnt_for_data_out[2:0] == 3'h1) | (cnt_for_data_out[2:0] == 3'h0))*/)  
        pre_rd_req <= 1'b1;
    else 
        pre_rd_req <= 1'b0;

assign  rd_req = pre_rd_req & ff_rx_rdy;


wire [6:0]  rdusedw_rx; 
wire [35:0] rd_data   ; 

always @(posedge ff_rx_clk or negedge rst_b_rx_clk)
    if(!rst_b_rx_clk)
        rd_req_dly <= 3'b0;
    else if(ff_rx_rdy)
        rd_req_dly <= {rd_req_dly[1:0] , rd_req};

reg[35:0] fifo_data_out;
always @(posedge ff_rx_clk or negedge rst_b_rx_clk)
    if(!rst_b_rx_clk)
        fifo_data_out <= 36'b0;
    else if(rd_req_dly[0])
        fifo_data_out <= rd_data[35:0];

always @(posedge ff_rx_clk or negedge rst_b_rx_clk)
    if(!rst_b_rx_clk)
        cnt_for_data_out <= 3'b0;
    else if(~ff_rx_rdy)
        cnt_for_data_out <= cnt_for_data_out;
    else if(rd_req)  
        cnt_for_data_out <= 3'h4;
    else if(~|cnt_for_data_out | ff_rx_eop)
        cnt_for_data_out <= 3'h0;
    else if(|cnt_for_data_out)
        cnt_for_data_out <= cnt_for_data_out - 1'b1;

wire ff_rx_data_vld = |cnt_for_data_out[2:0] & ff_rx_rdy; //when asserted, the following RX data are valid

//reg ff_rx_data_vld; 
//always @(posedge ff_rx_clk or negedge rst_b_rx_clk)
//    if(!rst_b_rx_clk)
//        ff_rx_data_vld <= 1'b0;
//    else 
//        ff_rx_data_vld <= |cnt_for_data_out[2:0];


wire ff_rx_sop      = cnt_for_data_out[2] & (rd_data[35:34] == 2'b01);

wire ff_rx_eop      = (rd_data[35:34] == 2'b10) & (                               //EOP Indi
                      (rd_data[33:32] == 2'b11) ? (cnt_for_data_out[2:0] == 3'h2) :  
                      (rd_data[33:32] == 2'b10) ? (cnt_for_data_out[2:0] == 3'h3) :  
                      (rd_data[33:32] == 2'b01) ? (cnt_for_data_out[2:0] == 3'h4) :  
                                                  (cnt_for_data_out[2:0] == 3'h1)
                      );

wire ff_rx_err      = (rd_data[35:34] == 2'b11);


wire [31:0] rev_rd_data = 
                      (rd_data[33:32] == 2'b11) ? {rd_data[23:0],rd_data[31:24]} :  
                      (rd_data[33:32] == 2'b10) ? {rd_data[15:0],rd_data[31:16]} :  
                      (rd_data[33:32] == 2'b01) ? {rd_data[7 :0],rd_data[31: 8]} :  
                                                   rd_data[31:0]                 ;


wire[31:0] final_rd_data = (rd_data[35:34] == 2'b10) ? rev_rd_data : rd_data[31:0];


wire[7:0]ff_rx_data = 
                      (cnt_for_data_out == 3'h4) ? final_rd_data[31:24] :  
                      (cnt_for_data_out == 3'h3) ? final_rd_data[23:16] :  
                      (cnt_for_data_out == 3'h2) ? final_rd_data[15: 8] :  
                      (cnt_for_data_out == 3'h1) ? final_rd_data[7 : 0] :  
                                                         8'b0           ;


fifo_test  inst_fifo_test_rx(
           //following is the write domain
	   .aclr    (~rst_b            ),
	   .wrclk   (p0_rxc            ),

	   .wrreq   (wr_receive_dat_en ),
	   .data    (wr_receive_data   ),
	   .wrfull  (wr_receive_full   ),

           //following is the read domain
	   .rdclk   (ff_rx_clk         ),
	   .rdreq   (rd_req            ),

	   .q       (rd_data[35:0]     ),
           .rdusedw (rdusedw_rx[6:0]   ),
	   .rdempty (rdempty           )
	   );


////////////////////////////////////////////////////////////////////////////////////////////////
////////////following is the TX fifo instance module, which is used to send the data////////////
////////////////////////////////////////////////////////////////////////////////////////////////

/////////////following is used to sync the reset domain////////////
reg rst_b_tx_syn0;
reg rst_b_tx_syn1;
always @(posedge ff_tx_clk or negedge rst_b)
    if(~rst_b)
        begin
            rst_b_tx_syn0 <= 1'b0;
            rst_b_tx_syn1 <= 1'b0;
        end
    else
        begin
            rst_b_tx_syn0 <= 1'b1;
            rst_b_tx_syn1 <= rst_b_tx_syn0;
        end

wire rst_b_tx_clk = rst_b_tx_syn1;

////////////////////////////////////////////////////////////////////
wire      ff_tx_wr_full            ;        
reg [1:0] ff_tx_wr_cnt             ;
reg       lat_ff_wr_done           ;
wire      final_lat_ff_wr_done_indi;

wire  ff_tx_al_full = ff_tx_wr_full ;

wire ff_tx_rdy = ~ff_tx_wr_full & (~final_lat_ff_wr_done_indi);//when this signla is 1'b1, indi the data can write into the fifo

reg      ff_tx_wr_en    ;        
reg[2:0] ff_tx_wr_en_dly; 
wire     ff_wr_done     ; 

always @(posedge ff_tx_clk or negedge rst_b_tx_clk)
    if(~rst_b_tx_clk)
        ff_tx_wr_en_dly <= 3'b0;
    else 
        ff_tx_wr_en_dly <= {ff_tx_wr_en_dly[1:0],ff_tx_wr_en};

wire  pre_ff_wr_done = ff_tx_eop & ff_tx_wren;

always @(posedge ff_tx_clk or negedge rst_b_tx_clk)
    if(~rst_b_tx_clk)
        lat_ff_wr_done <= 1'b0;
    else if(ff_wr_done)
        lat_ff_wr_done <= 1'b0;
    else if((|ff_tx_wr_en_dly[2:0] | ff_tx_wren) & pre_ff_wr_done & ~(&ff_tx_wr_cnt[1:0]))
        lat_ff_wr_done <= 1'b1;

reg lat_ff_wr_done_d0; 
reg lat_ff_wr_done_d1; 
always @(posedge ff_tx_clk or negedge rst_b_tx_clk)
    if(~rst_b_tx_clk)
        begin
            lat_ff_wr_done_d0 <= 1'b0;
            lat_ff_wr_done_d1 <= 1'b0;
        end
    else
        begin
            lat_ff_wr_done_d0 <= lat_ff_wr_done   ;
            lat_ff_wr_done_d1 <= lat_ff_wr_done_d0;
        end

assign final_lat_ff_wr_done_indi = lat_ff_wr_done | lat_ff_wr_done_d0 | lat_ff_wr_done_d1; 


assign ff_wr_done =
                   ((lat_ff_wr_done | pre_ff_wr_done) & (~|ff_tx_wr_en_dly[2:0]) & (~ff_tx_wr_en) |
                    pre_ff_wr_done & (&ff_tx_wr_cnt[1:0])) &  ~ff_tx_wr_full ;


reg ff_wr_done_d1; 
always @(posedge ff_tx_clk or negedge rst_b_tx_clk)
    if(~rst_b_tx_clk)
        ff_wr_done_d1 <= 1'b0;
    else 
        ff_wr_done_d1 <= ff_wr_done;

wire ff_wr_done_neg = ff_wr_done_d1 & ~ff_wr_done;   

always @(posedge ff_tx_clk or negedge rst_b_tx_clk)
    if(~rst_b_tx_clk)
        ff_tx_wr_cnt <= 2'b0;
    else if(ff_wr_done)
        ff_tx_wr_cnt <= 2'b0;
    else if(ff_tx_wren)
        ff_tx_wr_cnt <= ff_tx_wr_cnt + 1'b1;

reg[31:0] ff_tx_wr_dat;
always @(posedge ff_tx_clk or negedge rst_b_tx_clk)
    if(~rst_b_tx_clk)
        ff_tx_wr_dat <= 32'b0;
    else if(ff_tx_wren)
        ff_tx_wr_dat <= {ff_tx_wr_dat[23:0],ff_tx_data[7:0]};

reg[1:0] ff_tx_sop_eop_err_indi;
reg[1:0] ff_tx_wr_byte_indi    ;

always @(posedge ff_tx_clk or negedge rst_b_tx_clk)
    if(~rst_b_tx_clk)
        ff_tx_sop_eop_err_indi <= 2'h0;
    else if(ff_wr_done_neg)
        ff_tx_sop_eop_err_indi <= 2'h0;
    else if(ff_tx_err & ff_tx_wren)
        ff_tx_sop_eop_err_indi <= 2'h3;
    else if(ff_tx_sop & ff_tx_wren)
        ff_tx_sop_eop_err_indi <= 2'h1;
    else if(ff_wr_done)
        ff_tx_sop_eop_err_indi <= 2'h2;
    else if(ff_tx_wr_en) 
        ff_tx_sop_eop_err_indi <= 2'h0;

always @(posedge ff_tx_clk or negedge rst_b_tx_clk)
    if(~rst_b_tx_clk)
        ff_tx_wr_byte_indi <= 2'h0;
    else if(ff_wr_done_neg)
        ff_tx_wr_byte_indi <= 2'h0;

    else if(ff_wr_done & lat_ff_wr_done & (ff_tx_wr_cnt == 2'b00))
        ff_tx_wr_byte_indi <= 2'h0;
    else if(ff_wr_done & lat_ff_wr_done & (ff_tx_wr_cnt == 2'b01))
        ff_tx_wr_byte_indi <= 2'h1;
    else if(ff_wr_done & lat_ff_wr_done & (ff_tx_wr_cnt == 2'b10))
        ff_tx_wr_byte_indi <= 2'h2;
    else if(ff_wr_done & lat_ff_wr_done & (ff_tx_wr_cnt == 2'b11))
        ff_tx_wr_byte_indi <= 2'h3;

    else if(ff_wr_done & (ff_tx_wr_cnt == 2'b00))
        ff_tx_wr_byte_indi <= 2'h1;
    else if(ff_wr_done & (ff_tx_wr_cnt == 2'b01))
        ff_tx_wr_byte_indi <= 2'h2;
    else if(ff_wr_done & (ff_tx_wr_cnt == 2'b10))
        ff_tx_wr_byte_indi <= 2'h3;
    else if(ff_wr_done & (ff_tx_wr_cnt == 2'b11))
        ff_tx_wr_byte_indi <= 2'h0;

always @(posedge ff_tx_clk or negedge rst_b_tx_clk)
    if(~rst_b_tx_clk)
        ff_tx_wr_en <= 1'b0;
    else if(ff_wr_done)
        ff_tx_wr_en <= 1'b1;
    else if((ff_tx_wr_cnt == 2'h3) & ff_tx_wren)
        ff_tx_wr_en <= 1'b1;
    else 
        ff_tx_wr_en <= 1'b0;


wire [35:0]  ff_tx_wr_data = {
                             ff_tx_sop_eop_err_indi [1 :0] , 
                             ff_tx_wr_byte_indi     [1 :0] ,
                             ff_tx_wr_dat           [31:0]     
                             };     
  
////////////////////////////////////////////////////////////////////
////following is used to deal with the MAC TX fifo read process/////
////////////////////////////////////////////////////////////////////
wire[6 :0]  rdusedw_tx     ;

wire[35:0]  ff_tx_rd_data  ;
wire        ff_tx_rd_empty ;

wire        ff_tx_eop_rd   ;      


reg      ff_tx_rd_en       ;
reg[2:0] ff_tx_rd_en_dly   ;
reg      first_rd_tx_ff    ;
reg[1:0] rd_ff_tx_cnt      ;
reg[3:0] cnt_for_sfd_indi  ;


wire indi_cnt_for_sfd_val = |cnt_for_sfd_indi[3:0];

reg[1:0] indi_cnt_for_sfd_val_dly; 
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        indi_cnt_for_sfd_val_dly <= 2'b0;
    else 
        indi_cnt_for_sfd_val_dly <= {indi_cnt_for_sfd_val_dly[0],indi_cnt_for_sfd_val};


always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        first_rd_tx_ff <= 1'b0;
    else if(ff_tx_rd_en)
        first_rd_tx_ff <= 1'b1;
    else if(ff_tx_eop_rd)
        first_rd_tx_ff <= 1'b0;

always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        ff_tx_rd_en_dly[2:0] <= 3'b0;
    else   
        ff_tx_rd_en_dly[2:0] <= {ff_tx_rd_en_dly[1:0] ,ff_tx_rd_en};


reg[11:0] ff_tx_eop_find_dly    ;
reg[11:0] err_find_during_rd_dly;  

always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        ff_tx_rd_en <= 1'b0;
    else if(|cnt_for_sfd_indi[3:0] | (|indi_cnt_for_sfd_val_dly[1:0]) | (|ff_tx_eop_find_dly[11:0]))
        ff_tx_rd_en <= 1'b0;
    else if(~ff_tx_rd_empty & ~first_rd_tx_ff & (rdusedw_tx  >= 7'd12) & (~|ff_tx_rd_en_dly[1:0]) & ~ff_tx_rd_en)
        ff_tx_rd_en <= 1'b1;
    else if(~ff_tx_rd_empty & first_rd_tx_ff & (~|ff_tx_rd_en_dly[1:0]) & ~ff_tx_rd_en) 
        ff_tx_rd_en <= 1'b1;
    else 
        ff_tx_rd_en <= 1'b0;

reg  ff_tx_rd_en_d0 ;
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        ff_tx_rd_en_d0 <= 1'b0;
    else  
        ff_tx_rd_en_d0 <= ff_tx_rd_en;

always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        rd_ff_tx_cnt <= 2'b0;
    else if(ff_tx_rd_en)
        rd_ff_tx_cnt <= 2'h3;
    else if(|cnt_for_sfd_indi[3:0])
        rd_ff_tx_cnt <= 2'h3;
    else if(|rd_ff_tx_cnt[1:0])
        rd_ff_tx_cnt <= rd_ff_tx_cnt - 1'b1;

reg[35:0] ff_tx_rd_dat;
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        ff_tx_rd_dat <= 36'b0;
    else if(ff_tx_rd_en_d0)
        ff_tx_rd_dat <= ff_tx_rd_data ;

wire ff_tx_sop_rd      = (ff_tx_rd_data[35:34] == 2'b01);  

reg ff_tx_sop_rd_d0;
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        ff_tx_sop_rd_d0 <= 1'b0;
    else
        ff_tx_sop_rd_d0 <= ff_tx_sop_rd;

wire ff_tx_sop_rd_pos = ff_tx_sop_rd & ~ff_tx_sop_rd_d0;

wire err_find_during_rd = ff_tx_sop_rd_pos & txe_out;

reg ff_tx_sop_rd_pos_d0; 
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        ff_tx_sop_rd_pos_d0 <= 1'b0;
    else 
        ff_tx_sop_rd_pos_d0 <= ff_tx_sop_rd_pos;


always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        cnt_for_sfd_indi <= 4'b0;
    else if(ff_tx_sop_rd_pos | err_find_during_rd | (|err_find_during_rd_dly[11:0]))
        cnt_for_sfd_indi <= 4'h8;
    else if(~|cnt_for_sfd_indi[3:0])
        cnt_for_sfd_indi <= 4'b0;
    else if(|cnt_for_sfd_indi[3:0])
        cnt_for_sfd_indi <= cnt_for_sfd_indi - 1'b1;


always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        err_find_during_rd_dly <= 12'b0;
    else 
        err_find_during_rd_dly <= {err_find_during_rd_dly[10:0],err_find_during_rd} ;



wire eop_final_indi = 
                       (ff_tx_rd_data[33:32] == 2'b01) ? (rd_ff_tx_cnt == 2'h3) : 
                       (ff_tx_rd_data[33:32] == 2'b10) ? (rd_ff_tx_cnt == 2'h2) : 
                       (ff_tx_rd_data[33:32] == 2'b11) ? (rd_ff_tx_cnt == 2'h1) : 
                                                         (rd_ff_tx_cnt == 2'h0) ;
                 


wire   ff_tx_eop_find    = (ff_tx_rd_data[35:34] == 2'b10);

reg ff_tx_eop_find_d0;    
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        ff_tx_eop_find_d0 <= 1'b0;
    else 
        ff_tx_eop_find_d0 <= ff_tx_eop_find;

wire ff_tx_eop_find_pos = ~ff_tx_eop_find_d0 & ff_tx_eop_find;   

always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        ff_tx_eop_find_dly <= 12'b0;
    else 
        ff_tx_eop_find_dly <= {ff_tx_eop_find_dly[10:0],ff_tx_eop_find_pos};


assign ff_tx_eop_rd      = (ff_tx_rd_data[35:34] == 2'b10) & eop_final_indi;    

reg ff_tx_eop_rd_d0;
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        ff_tx_eop_rd_d0 <= 1'b0;
    else 
        ff_tx_eop_rd_d0 <= ff_tx_eop_rd;

wire   ff_tx_err_find    = (ff_tx_rd_data[35:34] == 2'b11);

reg[3:0] ff_tx_err_find_dly;    
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        ff_tx_err_find_dly <= 4'b0;
    else 
        ff_tx_err_find_dly <= {ff_tx_err_find_dly[2:0] , ff_tx_err_find};

wire ff_tx_err_find_pos = ff_tx_err_find & ~ff_tx_err_find_dly[0];         

always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        txe_out <= 1'b0;
    else if(ff_tx_eop_rd_d0)
        txe_out <= 1'b0;
    else if(ff_tx_sop_rd_pos & txe_out)
        txe_out <= 1'b0;
//  else if(ff_tx_err_find_dly[3])
    else if(ff_tx_err_find_pos)
        txe_out <= 1'b0;
    else if(ff_tx_sop_rd_pos_d0 & ~err_find_during_rd_dly[0] | err_find_during_rd_dly[11])        
        txe_out <= 1'b1;


wire spd_10m_100m = (speed == 2'b01) | (speed == 2'b00); 
wire spd_1000m    = (speed == 2'b10); 

reg p0_txen_d0;
always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        p0_txen_d0 <= 1'b0;
    else 
        p0_txen_d0 <= p0_txen;

wire p0_txen_pos = ~p0_txen_d0 &  p0_txen;   
wire p0_txen_neg =  p0_txen_d0 & ~p0_txen;   

reg  p0_txer               ;
reg  p0_txer_d0            ;
reg  lat_ff_tx_err_find    ; 

wire p0_txer_pos = p0_txer & ~p0_txer_d0;

always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        lat_ff_tx_err_find <= 1'b0;
    else if(p0_txer_pos)
        lat_ff_tx_err_find <= 1'b0;
    else if(ff_tx_err_find_pos) 
        lat_ff_tx_err_find <= 1'b1;

always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        p0_txer <= 1'b0;
    else if(ff_tx_sop_rd | p0_txen_neg)
        p0_txer <= 1'b0;
    else if(spd_1000m & ff_tx_err_find & p0_txen)
        p0_txer <= 1'b1;
    else if(spd_10m_100m & p0_txen_pos & lat_ff_tx_err_find)
        p0_txer <= 1'b1;

always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        p0_txer_d0 <= 1'b0;
    else 
        p0_txer_d0 <= p0_txer;


//reg txe_out_d0; 
//always @(posedge p0_rxc or negedge rst_b)
//    if(!rst_b)
//        txe_out_d0 <= 1'b0;
//    else 
//        txe_out_d0 <= txe_out;
//
//wire txe_out_neg = ~txe_out & txe_out_d0;

wire[31:0] revert_ff_tx_rd_data = 
                       (ff_tx_rd_data[33:32] == 2'b01) ? {ff_tx_rd_data[7 :0],ff_tx_rd_data[31: 8]} : 
                       (ff_tx_rd_data[33:32] == 2'b10) ? {ff_tx_rd_data[15:0],ff_tx_rd_data[31:16]} : 
                       (ff_tx_rd_data[33:32] == 2'b11) ? {ff_tx_rd_data[23:0],ff_tx_rd_data[31:24]} : 
                                                          ff_tx_rd_data[31:0]                       ;


wire[31:0] final_ff_tx_rd_data = (ff_tx_rd_data[35:34] == 2'b10) ? revert_ff_tx_rd_data[31:0] : ff_tx_rd_data[31:0] ;

always @(posedge p0_rxc or negedge rst_b)
    if(!rst_b)
        txd_out <= 8'b0;
//  else if(txe_out_neg)
//      txd_out <= 8'b0;

    else if(ff_tx_sop_rd_pos)
        txd_out <= 8'b0;
    else if(|cnt_for_sfd_indi[3:1])
        txd_out <= 8'h55;
    else if(cnt_for_sfd_indi[0])
        txd_out <= 8'hd5;
    else if(rd_ff_tx_cnt == 2'd3)    
        txd_out <= final_ff_tx_rd_data[31:24];
    else if(rd_ff_tx_cnt == 2'd2)    
        txd_out <= final_ff_tx_rd_data[23:16];
    else if(rd_ff_tx_cnt == 2'd1)    
        txd_out <= final_ff_tx_rd_data[15: 8];
    else 
        txd_out <= final_ff_tx_rd_data[7 : 0];



fifo_test  inst_fifo_test_tx(
           //following is the write domain
	   .aclr    (~rst_b_tx_clk        ),
	   .wrclk   ( ff_tx_clk           ),

	   .wrreq   (ff_tx_wr_en          ),
	   .data    (ff_tx_wr_data[35:0]  ),
	   .wrfull  (ff_tx_wr_full        ),

           //following is the read domain
	   .rdclk   (p0_rxc               ),
	   .rdreq   (ff_tx_rd_en          ),

	   .q       (ff_tx_rd_data[35:0]  ),
           .rdusedw (rdusedw_tx[6:0]      ),
	   .rdempty (ff_tx_rd_empty       )
	   );



endmodule
// Local Variables:
// verilog-library-directories:( "./" )
// End:

// eth_1 : vendor IP stub for Quartus RTL Viewer
// Port list copied from the real IP wrapper; body intentionally empty.
module eth_1 (
  
  mdc, phy_rstb0, p0_gtxc, p0_txd, p0_txen, p0_txer, ff_tx_rdy, 
  ff_tx_al_full, ff_rx_data_vld, ff_rx_data, 
  ff_rx_sop, ff_rx_eop, ff_rx_err, reg_data_out, reg_acc_bsy, 
  
  mdio, 
  
  clk_sys, rst_b, p0_txc, p0_rxc, p0_rxd, p0_rxdv, p0_rxer, p0_col, 
  p0_crs, ff_tx_clk, ff_tx_data, ff_tx_sop, ff_tx_eop, ff_tx_err, 
  ff_tx_wren, ff_rx_clk, ff_rx_rdy, reg_wr, reg_rd, reg_addr, 
  reg_data_in
  );
inout mdio ;
output mdc ;
output phy_rstb0 ;
output p0_gtxc ;
output[7:0] p0_txd ;
output p0_txen ;
output p0_txer ;
input clk_sys ;
input rst_b ;
input p0_txc ;
input p0_rxc ;
input [7:0] p0_rxd ;
input p0_rxdv ;
input p0_rxer ;
input p0_col ;
input p0_crs ;
input ff_tx_clk ;
input[7:0] ff_tx_data ;
input ff_tx_sop ;
input ff_tx_eop ;
input ff_tx_err ;
input ff_tx_wren ;
output ff_tx_rdy ;
output ff_tx_al_full ;
input ff_rx_clk ;
output ff_rx_data_vld ;
output[7:0]ff_rx_data ;
output ff_rx_sop ;
output ff_rx_eop ;
output ff_rx_err ;
input ff_rx_rdy ;
input reg_wr ;
input reg_rd ;
input [3 :0] reg_addr ;
input [31:0] reg_data_in ;
output[31:0] reg_data_out ;
output reg_acc_bsy ;

endmodule

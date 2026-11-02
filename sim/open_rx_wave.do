# GUI-only waveform viewer for tb_afdx_rx.
# Run this from the ModelSim transcript after the library has been compiled:
#   cd C:/Users/wei/AppData/Local/Temp/afdxproj/sim
#   do open_rx_wave.do
vsim -novopt work.tb_afdx_rx
view wave
run 0ns

add wave -radix hex /tb_afdx_rx/clk
add wave -radix hex /tb_afdx_rx/rst_b
add wave -radix hex /tb_afdx_rx/dut/state
add wave -radix hex /tb_afdx_rx/dut/ff_rx_data
add wave -radix binary /tb_afdx_rx/dut/ff_rx_data_vld
add wave -radix binary /tb_afdx_rx/dut/ff_rx_sop
add wave -radix binary /tb_afdx_rx/dut/ff_rx_eop
add wave -radix binary /tb_afdx_rx/dut/ff_rx_err
add wave -radix binary /tb_afdx_rx/dut/ff_rx_rdy
add wave -radix hex /tb_afdx_rx/dut/pay_cnt
add wave -radix binary /tb_afdx_rx/dut/port_wr_frame_done

run 1us
wave zoom full
echo RX_WAVE_READY

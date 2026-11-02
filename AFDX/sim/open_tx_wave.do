# GUI-only waveform viewer for tb_afdx_tx.
# Run this from the ModelSim transcript after the library has been compiled:
#   cd C:/Users/wei/AppData/Local/Temp/afdxproj/sim
#   do open_tx_wave.do
vsim -novopt work.tb_afdx_tx
view wave
run 0ns

add wave -radix hex /tb_afdx_tx/clk
add wave -radix hex /tb_afdx_tx/rst_b
add wave -radix hex /tb_afdx_tx/dut/state
add wave -radix hex /tb_afdx_tx/dut/ff_tx_data
add wave -radix binary /tb_afdx_tx/dut/ff_tx_wren
add wave -radix binary /tb_afdx_tx/dut/ff_tx_sop
add wave -radix binary /tb_afdx_tx/dut/ff_tx_eop
add wave -radix binary /tb_afdx_tx/dut/ff_tx_err
add wave -radix hex /tb_afdx_tx/dut/tx_byte_pos
add wave -radix binary /tb_afdx_tx/dut/port_rd_en
add wave -radix hex /tb_afdx_tx/dut/port_rd_vl_index
add wave -radix hex /tb_afdx_tx/dut/port_rd_byte_offset
add wave -radix hex /tb_afdx_tx/dut/payload_data
add wave -radix binary /tb_afdx_tx/dut/tx_valid_app
add wave -radix binary /tb_afdx_tx/dut/irq_tx_done

run 10us
wave zoom full
echo TX_WAVE_READY

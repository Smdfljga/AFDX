if {[file exists work]} { vdel -all -lib work }
vlib work
vmap work work

# 只编译 RX 状态机和这个 TB（TB 自带配置表/状态表的简单 RAM 模型，不依赖 IP 仿真模型）
vlog -quiet ../elinx/rtl/afdx_rx.v
vlog -quiet tb_afdx_rx.v

# 打开 GUI 并加载测试平台；-novopt 避免 vopt 在本机上的内部错误，同时保留 dut 内部信号可见性
vsim -novopt work.tb_afdx_rx

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

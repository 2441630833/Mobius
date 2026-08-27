# -----------------------------------------------------------------------------
# Arty A7-35T constraints for sampler_uart_top
#
# Pins taken from Digilent's Arty-A7-35-Master.xdc. Only the signals the sampler
# actually uses are constrained; nextpnr-xilinx errors on a constraint for a port
# that does not exist, so do not paste the full master file in here.
#
# Naming trap worth remembering: Digilent names the USB-UART pins from the
# FTDI's point of view, so `uart_rxd_out` is the FPGA's *output*. The mapping
# below is deliberately crossed over.
# -----------------------------------------------------------------------------

## 100 MHz system clock (Sch=gclk[100])
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { clk_100mhz }]
## The crystal runs at 100 MHz, but sampler_uart_top divides it by 2 on chip
## (BUFG-buffered clk_sys) and runs ALL logic on the resulting 50 MHz clock;
## clk_100mhz itself drives only the single divide-by-2 flop (Q -> ~Q -> D,
## the shortest path in the fabric, which closes at 100 MHz with huge slack).
## nextpnr-xilinx does not infer the /2 generated-clock relationship, so the
## analysed period is set to the 50 MHz system domain the design actually runs
## at. This is conservative for the divider flop (20 ns vs its true 10 ns) and
## gives clk_sys its correct 20 ns budget.
create_clock -add -name sys_clk_pin -period 20.000 -waveform {0 10} [get_ports { clk_100mhz }]

## CK_RST, active low (Sch=ck_rst). Held high by an on-board pull-up.
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports { resetn }]

## USB-UART bridge.
##   D10 = Sch uart_rxd_out : FPGA drives      -> our uart_txd
##   A9  = Sch uart_txd_in  : FTDI drives      -> our uart_rxd
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports { uart_txd }]
set_property -dict { PACKAGE_PIN A9  IOSTANDARD LVCMOS33 } [get_ports { uart_rxd }]

## LEDs 4..7 (the single-colour row).
##   led[0] heartbeat   led[1] sampling
##   led[2] entropy_fail  led[3] uart frame error
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]

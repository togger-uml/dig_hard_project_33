# top.sdc -- Synopsys Design Constraints for Project 3
#
# Two truly asynchronous primary clocks enter the design:
#
#   * MAX10_CLK1_50  -- 50 MHz reference, drives the consumer domain
#                       and is the input to the PLL.
#   * The producer-side clock is derived from the PLL output (10 MHz)
#     and then internally divided by 10 inside the MAX10 ADC block,
#     producing the 1 MHz ADC clock dft (clk_dft) used as the FIFO
#     write clock.
#
# Because the producer and consumer clocks are unrelated, false_path
# constraints are applied between them; the asynchronous FIFO and the
# two-flop synchronizers handle the safe transfer of data.

# ---------------------------------------------------------------- #
# Primary input clocks                                             #
# ---------------------------------------------------------------- #

# main 50 MHz board clock (period in ns)
create_clock -period 20.000 -name clk_50 [get_ports MAX10_CLK1_50]

# virtual clocks for I/O analysis
create_clock -period 20.000 -name main_clock_virt
create_clock -period 100.000 -name adc_clock_virt

# ---------------------------------------------------------------- #
# PLL-derived clocks                                               #
# ---------------------------------------------------------------- #

derive_pll_clocks -create_base_clocks
derive_clock_uncertainty

# 10 MHz PLL output feeding the ADC.  The exact node name produced
# by Quartus depends on the altpll instance hierarchy; if your fitter
# reports a different name update the get_pins target accordingly.
create_generated_clock -name clk_10 \
    -source [get_pins {pll_inst|altpll_component|auto_generated|pll1|inclk[0]}] \
    -divide_by 5 -multiply_by 1 \
    [get_pins {pll_inst|altpll_component|auto_generated|pll1|clk[0]}]

# 1 MHz producer clock generated inside the MAX10 ADC block by the
# divide-by-10 prescaler (clkdiv = 2).  The ADC primitive output
# clk_dft is registered by the MAX10 fabric.
create_generated_clock -name clk_prod \
    -source [get_pins {adc_inst|primitive_instance|clkin_from_pll_c0}] \
    -divide_by 10 -multiply_by 1 \
    [get_pins {adc_inst|primitive_instance|clk_dft}]

# ---------------------------------------------------------------- #
# Clock-domain-crossing exceptions                                 #
# ---------------------------------------------------------------- #

# The two-flop pointer synchronizers and the dual-clock FIFO memory
# implement a metastability-tolerant CDC, so static timing analysis
# does not need to verify the path between the producer and consumer
# clock domains.  Cut all paths in both directions.
set_clock_groups -asynchronous \
    -group {clk_50 main_clock_virt} \
    -group {clk_prod adc_clock_virt clk_10}

# ---------------------------------------------------------------- #
# I/O timing (loose constraints; outputs only drive on-board LEDs) #
# ---------------------------------------------------------------- #

# Reset/key inputs are asynchronous to all clocks.
set_false_path -from [get_ports {KEY[*]}] -to [all_clocks]

# Seven-segment outputs are visually observed; relax timing.
set_false_path -from [all_clocks] -to [get_ports {HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]

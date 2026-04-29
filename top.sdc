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

# ---------------------------------------------------------------- #
# PLL-derived clocks                                               #
# ---------------------------------------------------------------- #

# derive_pll_clocks already creates the auto-named generated clock
# for the PLL output (10 MHz feeding the ADC).  Do NOT pass
# -create_base_clocks: we already created clk_50 manually above,
# and passing -create_base_clocks would place a second clock on the
# same MAX10_CLK1_50 node, giving TimeQuest two overlapping clocks
# and producing spurious slack violations.
derive_pll_clocks
derive_clock_uncertainty

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
#
# Group 1: consumer clock (clk_50 / 50 MHz).
# Group 2: producer clocks -- the PLL 10 MHz output created by
#   derive_pll_clocks (TimeQuest names it using the stripped hierarchy
#   path: pll_inst|altpll_component|auto_generated|pll1|clk[0]) and
#   the 1 MHz ADC clock clk_prod derived from it.
#   Note: get_clocks -filter is NOT available in Quartus TimeQuest;
#   the clocks are enumerated explicitly here.
set_clock_groups -asynchronous \
    -group [get_clocks {clk_50}] \
    -group [get_clocks {clk_prod pll_inst|altpll_component|auto_generated|pll1|clk[0]}]

# ---------------------------------------------------------------- #
# I/O timing (loose constraints; outputs only drive on-board LEDs) #
# ---------------------------------------------------------------- #

# Reset/key inputs are asynchronous to all clocks; they enter only
# through synchronisers so no setup/hold or recovery/removal path
# needs to be analysed.  The previous constraint used
#   -to [all_clocks]
# which targets *clock-network nodes*, not the register D/reset pins
# downstream of the KEY ports, making it a near-no-op.  Dropping the
# -to clause cuts every path that originates at KEY ports, which is
# the correct way to suppress the recovery-time violations that were
# causing "Critical Warning 332148: Timing requirements not met".
set_false_path -from [get_ports {KEY[*]}]

# Seven-segment outputs are visually observed; relax timing.
set_false_path -from [all_clocks] -to [get_ports {HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]

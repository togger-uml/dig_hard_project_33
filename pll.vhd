library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PLL wrapper for the DE10-Lite MAX10 FPGA.
-- Converts the 10 MHz ADC reference clock (ADC_CLK_10) into a 10 MHz
-- output that is properly routed through the FPGA's PLL network.
-- (The fiftyfivenm_adcblock primitive requires its clock input to
-- originate from a PLL, not directly from a clock pin.)
--
-- The internal clkdiv => 2 setting inside max10_adc already divides the
-- PLL output by 10, producing the 1 MHz ADC operating clock on clk_dft.
--
-- NOTE: This file uses the Altera altpll megafunction.  It must be
--       compiled together with the altera_mf simulation library.
--       In Quartus you may alternatively regenerate the PLL using the
--       IP Catalog (MegaWizard) with the same parameters.

library altera_mf;
use altera_mf.altera_mf_components.all;

entity pll is
	port (
		inclk0	: in	std_logic;  -- 10 MHz input clock
		c0		: out	std_logic   -- 10 MHz output to max10_adc pll_clk
	);
end entity pll;

architecture rtl of pll is

	signal clk_vec   : std_logic_vector(4 downto 0);
	signal inclk_vec : std_logic_vector(1 downto 0);

begin

	inclk_vec <= '0' & inclk0;
	c0        <= clk_vec(0);

	altpll_inst: altpll
		generic map (
			bandwidth_type          => "AUTO",
			clk0_divide_by          => 1,
			clk0_duty_cycle         => 50,
			clk0_multiply_by        => 1,
			clk0_phase_shift        => "0",
			compensate_clock        => "CLK0",
			inclk0_input_frequency  => 100000,   -- 100 000 ps = 10 MHz
			intended_device_family  => "MAX 10",
			lpm_type                => "altpll",
			operation_mode          => "NORMAL",
			pll_type                => "AUTO",
			port_activeclock        => "PORT_UNUSED",
			port_areset             => "PORT_UNUSED",
			port_clkbad0            => "PORT_UNUSED",
			port_clkbad1            => "PORT_UNUSED",
			port_clkloss            => "PORT_UNUSED",
			port_clkswitch          => "PORT_UNUSED",
			port_configupdate       => "PORT_UNUSED",
			port_fbin               => "PORT_UNUSED",
			port_inclk0             => "PORT_USED",
			port_inclk1             => "PORT_UNUSED",
			port_locked             => "PORT_UNUSED",
			port_pfdena             => "PORT_UNUSED",
			port_phasecounterselect => "PORT_UNUSED",
			port_phasedone          => "PORT_UNUSED",
			port_phasestep          => "PORT_UNUSED",
			port_phaseupdown        => "PORT_UNUSED",
			port_pllena             => "PORT_UNUSED",
			port_scanaclr           => "PORT_UNUSED",
			port_scanclk            => "PORT_UNUSED",
			port_scanclkena         => "PORT_UNUSED",
			port_scandata           => "PORT_UNUSED",
			port_scandataout        => "PORT_UNUSED",
			port_scandone           => "PORT_UNUSED",
			port_scanread           => "PORT_UNUSED",
			port_scanwrite          => "PORT_UNUSED",
			port_clk0               => "PORT_USED",
			port_clk1               => "PORT_UNUSED",
			port_clk2               => "PORT_UNUSED",
			port_clk3               => "PORT_UNUSED",
			port_clk4               => "PORT_UNUSED",
			port_clk5               => "PORT_UNUSED",
			port_clkena0            => "PORT_UNUSED",
			port_clkena1            => "PORT_UNUSED",
			port_clkena2            => "PORT_UNUSED",
			port_clkena3            => "PORT_UNUSED",
			port_clkena4            => "PORT_UNUSED",
			port_clkena5            => "PORT_UNUSED",
			port_extclk0            => "PORT_UNUSED",
			port_extclk1            => "PORT_UNUSED",
			port_extclk2            => "PORT_UNUSED",
			port_extclk3            => "PORT_UNUSED",
			self_reset_on_loss_lock => "OFF",
			width_clock             => 5
		)
		port map (
			inclk  => inclk_vec,
			clk    => clk_vec
		);

end architecture rtl;

-- pll: wrapper around the Altera/Intel altpll megafunction that takes
-- the 50 MHz reference clock on the DE10-Lite and produces a 10 MHz
-- clock for the MAX10 ADC.
--
-- The altpll instance is configured with INCLK frequency 20000 ps
-- (50 MHz) and a single output (c0) divided to 10 MHz via a 1/5
-- multiply/divide ratio.  Quartus will infer this into a real PLL on
-- the FPGA at fitting time.

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity pll is
	port (
		refclk:		in	std_logic;	-- 50 MHz reference
		rst:		in	std_logic;	-- active-high reset
		outclk:		out	std_logic;	-- 10 MHz to ADC
		locked:		out	std_logic
	);
end entity pll;

architecture wrapper of pll is
	signal sub_wire0:	std_logic_vector(4 downto 0);
	signal sub_wire1:	std_logic;
	signal sub_wire2:	std_logic_vector(0 downto 0);
	signal inclk_wire:	std_logic_vector(1 downto 0);
begin

	inclk_wire <= '0' & refclk;

	altpll_component: altpll
		generic map (
			bandwidth_type			=> "AUTO",
			clk0_divide_by			=> 5,
			clk0_duty_cycle			=> 50,
			clk0_multiply_by		=> 1,
			clk0_phase_shift		=> "0",
			compensate_clock		=> "CLK0",
			inclk0_input_frequency	=> 20000,	-- 50 MHz period in ps
			intended_device_family	=> "MAX 10",
			lpm_hint				=> "CBX_MODULE_PREFIX=pll_altpll",
			lpm_type				=> "altpll",
			operation_mode			=> "NORMAL",
			pll_type				=> "AUTO",
			port_activeclock		=> "PORT_UNUSED",
			port_areset				=> "PORT_USED",
			port_clkbad0			=> "PORT_UNUSED",
			port_clkbad1			=> "PORT_UNUSED",
			port_clkloss			=> "PORT_UNUSED",
			port_clkswitch			=> "PORT_UNUSED",
			port_configupdate		=> "PORT_UNUSED",
			port_fbin				=> "PORT_UNUSED",
			port_inclk0				=> "PORT_USED",
			port_inclk1				=> "PORT_UNUSED",
			port_locked				=> "PORT_USED",
			port_pfdena				=> "PORT_UNUSED",
			port_phasecounterselect	=> "PORT_UNUSED",
			port_phasedone			=> "PORT_UNUSED",
			port_phasestep			=> "PORT_UNUSED",
			port_phaseupdown		=> "PORT_UNUSED",
			port_pllena				=> "PORT_UNUSED",
			port_scanaclr			=> "PORT_UNUSED",
			port_scanclk			=> "PORT_UNUSED",
			port_scanclkena			=> "PORT_UNUSED",
			port_scandata			=> "PORT_UNUSED",
			port_scandataout		=> "PORT_UNUSED",
			port_scandone			=> "PORT_UNUSED",
			port_scanread			=> "PORT_UNUSED",
			port_scanwrite			=> "PORT_UNUSED",
			port_clk0				=> "PORT_USED",
			port_clk1				=> "PORT_UNUSED",
			port_clk2				=> "PORT_UNUSED",
			port_clk3				=> "PORT_UNUSED",
			port_clk4				=> "PORT_UNUSED",
			port_clk5				=> "PORT_UNUSED",
			port_clkena0			=> "PORT_UNUSED",
			port_clkena1			=> "PORT_UNUSED",
			port_clkena2			=> "PORT_UNUSED",
			port_clkena3			=> "PORT_UNUSED",
			port_clkena4			=> "PORT_UNUSED",
			port_clkena5			=> "PORT_UNUSED",
			port_extclk0			=> "PORT_UNUSED",
			port_extclk1			=> "PORT_UNUSED",
			port_extclk2			=> "PORT_UNUSED",
			port_extclk3			=> "PORT_UNUSED",
			self_reset_on_loss_lock	=> "OFF",
			width_clock				=> 5
		)
		port map (
			areset	 => rst,
			inclk	 => inclk_wire,
			clk		 => sub_wire0,
			locked	 => sub_wire1
		);

	sub_wire2 <= sub_wire0(0 downto 0);
	outclk <= sub_wire2(0);
	locked <= sub_wire1;

end architecture wrapper;

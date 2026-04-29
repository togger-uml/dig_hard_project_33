-- top: top-level entity for Project 3.
--
-- Wires together the two clock domains:
--
--   producer (slow)            consumer (fast, 50 MHz)
--   --------------------       ------------------------
--   PLL  -> 10 MHz -> ADC      display_unit -> 7-seg
--   ADC  -> clk_dft (~1 MHz)
--   adc_fsm   <-> async_fifo write port      ->   read port -> display_unit
--
-- KEY0 on the DE10-Lite is used as an active-low reset.  The reset
-- signal is locally synchronized into each clock domain (via sync_2ff)
-- so that resets are deasserted in sync with each clock — this avoids
-- the recovery/removal race that would otherwise affect the FIFO
-- pointers.  The PLL "locked" signal is ANDed in to keep the system
-- held in reset until the PLL output clock is stable.

library ieee;
use ieee.std_logic_1164.all;

entity top is
	port (
		-- DE10-Lite on-board clock
		MAX10_CLK1_50:	in	std_logic;

		-- KEY0 is active-low; serves as global reset
		KEY:		in	std_logic_vector(1 downto 0);

		-- Seven segment displays (active-low, common-anode)
		HEX0:		out	std_logic_vector(6 downto 0);
		HEX1:		out	std_logic_vector(6 downto 0);
		HEX2:		out	std_logic_vector(6 downto 0);
		HEX3:		out	std_logic_vector(6 downto 0);
		HEX4:		out	std_logic_vector(6 downto 0);
		HEX5:		out	std_logic_vector(6 downto 0)
	);
end entity top;

architecture rtl of top is

	component pll is
		port (
			areset:	in	std_logic := '0';
			inclk0:	in	std_logic := '0';
			c0:		out	std_logic;
			locked:	out	std_logic
		);
	end component pll;

	component max10_adc is
		port (
			pll_clk:	in	std_logic;
			chsel:		in	natural range 0 to 2**5 - 1;
			soc:		in	std_logic;
			tsen:		in	std_logic;
			dout:		out	natural range 0 to 2**12 - 1;
			eoc:		out	std_logic;
			clk_dft:	out	std_logic
		);
	end component max10_adc;

	component adc_fsm is
		generic (data_width: positive := 12);
		port (
			clk:		in	std_logic;
			rst_n:		in	std_logic;
			eoc:		in	std_logic;
			dout:		in	natural range 0 to 2**12 - 1;
			soc:		out	std_logic;
			chsel:		out	natural range 0 to 2**5 - 1;
			tsen:		out	std_logic;
			fifo_full:	in	std_logic;
			fifo_winc:	out	std_logic;
			fifo_wdata:	out	std_logic_vector(data_width - 1 downto 0)
		);
	end component adc_fsm;

	component async_fifo is
		generic (
			data_width:	positive := 12;
			addr_width:	positive := 4
		);
		port (
			wclk:	in	std_logic;
			wrst_n:	in	std_logic;
			winc:	in	std_logic;
			wdata:	in	std_logic_vector(data_width - 1 downto 0);
			wfull:	out	std_logic;
			rclk:	in	std_logic;
			rrst_n:	in	std_logic;
			rinc:	in	std_logic;
			rdata:	out	std_logic_vector(data_width - 1 downto 0);
			rempty:	out	std_logic
		);
	end component async_fifo;

	component display_unit is
		generic (data_width: positive := 12);
		port (
			clk:		in	std_logic;
			rst_n:		in	std_logic;
			fifo_empty:	in	std_logic;
			fifo_rdata:	in	std_logic_vector(data_width - 1 downto 0);
			fifo_rinc:	out	std_logic;
			hex0:	out	std_logic_vector(6 downto 0);
			hex1:	out	std_logic_vector(6 downto 0);
			hex2:	out	std_logic_vector(6 downto 0);
			hex3:	out	std_logic_vector(6 downto 0);
			hex4:	out	std_logic_vector(6 downto 0);
			hex5:	out	std_logic_vector(6 downto 0)
		);
	end component display_unit;

	component sync_2ff is
		generic (width: positive := 1);
		port (
			clk:	in	std_logic;
			rst_n:	in	std_logic;
			d:		in	std_logic_vector(width - 1 downto 0);
			q:		out	std_logic_vector(width - 1 downto 0)
		);
	end component sync_2ff;

	-- clocks
	signal clk_50:		std_logic;
	signal clk_10:		std_logic;
	signal clk_prod:	std_logic;	-- ADC clk_dft, ~1 MHz
	signal pll_locked:	std_logic;

	-- raw and synchronized resets
	signal rst_n_async:	std_logic;
	signal rst_n_50_d:	std_logic_vector(0 downto 0);
	signal rst_n_50_q:	std_logic_vector(0 downto 0);
	signal rst_n_pr_d:	std_logic_vector(0 downto 0);
	signal rst_n_pr_q:	std_logic_vector(0 downto 0);
	signal rst_n_50:	std_logic;
	signal rst_n_prod:	std_logic;

	-- ADC interface
	signal adc_soc:		std_logic;
	signal adc_eoc:		std_logic;
	signal adc_tsen:	std_logic;
	signal adc_chsel:	natural range 0 to 2**5 - 1;
	signal adc_dout:	natural range 0 to 2**12 - 1;

	-- FIFO interface
	signal fifo_winc, fifo_full:	std_logic;
	signal fifo_rinc, fifo_empty:	std_logic;
	signal fifo_wdata, fifo_rdata:	std_logic_vector(11 downto 0);

begin

	clk_50 <= MAX10_CLK1_50;

	-- KEY0 low = reset asserted; gate by PLL lock so that we do not
	-- come out of reset until the producer-side clock is valid
	rst_n_async <= KEY(0) and pll_locked;

	pll_inst: pll
		port map (
			inclk0 => clk_50,
			areset => not KEY(0),
			c0     => clk_10,
			locked => pll_locked
		);

	adc_inst: max10_adc
		port map (
			pll_clk => clk_10,
			chsel   => adc_chsel,
			soc     => adc_soc,
			tsen    => adc_tsen,
			dout    => adc_dout,
			eoc     => adc_eoc,
			clk_dft => clk_prod
		);

	-- synchronize reset deassertion to the consumer clock
	rst_n_50_d(0) <= rst_n_async;
	rst_sync_50: sync_2ff
		generic map (width => 1)
		port map (
			clk   => clk_50,
			rst_n => rst_n_async,
			d     => rst_n_50_d,
			q     => rst_n_50_q
		);
	rst_n_50 <= rst_n_50_q(0);

	-- synchronize reset deassertion to the producer clock
	rst_n_pr_d(0) <= rst_n_async;
	rst_sync_pr: sync_2ff
		generic map (width => 1)
		port map (
			clk   => clk_prod,
			rst_n => rst_n_async,
			d     => rst_n_pr_d,
			q     => rst_n_pr_q
		);
	rst_n_prod <= rst_n_pr_q(0);

	fsm_inst: adc_fsm
		generic map (data_width => 12)
		port map (
			clk        => clk_prod,
			rst_n      => rst_n_prod,
			eoc        => adc_eoc,
			dout       => adc_dout,
			soc        => adc_soc,
			chsel      => adc_chsel,
			tsen       => adc_tsen,
			fifo_full  => fifo_full,
			fifo_winc  => fifo_winc,
			fifo_wdata => fifo_wdata
		);

	fifo_inst: async_fifo
		generic map (data_width => 12, addr_width => 4)
		port map (
			wclk   => clk_prod,
			wrst_n => rst_n_prod,
			winc   => fifo_winc,
			wdata  => fifo_wdata,
			wfull  => fifo_full,
			rclk   => clk_50,
			rrst_n => rst_n_50,
			rinc   => fifo_rinc,
			rdata  => fifo_rdata,
			rempty => fifo_empty
		);

	disp_inst: display_unit
		generic map (data_width => 12)
		port map (
			clk        => clk_50,
			rst_n      => rst_n_50,
			fifo_empty => fifo_empty,
			fifo_rdata => fifo_rdata,
			fifo_rinc  => fifo_rinc,
			hex0 => HEX0, hex1 => HEX1, hex2 => HEX2,
			hex3 => HEX3, hex4 => HEX4, hex5 => HEX5
		);

end architecture rtl;

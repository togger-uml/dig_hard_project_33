library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Top-level design for the DE10-Lite temperature measurement project.
--
-- Clock domains
-- ─────────────
-- Consumer domain  – CLOCK_50 (50 MHz, from the board oscillator)
--   Drives: FIFO read side, temperature_display
--
-- Producer domain  – adc_clk (clk_dft output of max10_adc, ≈1 MHz)
--   CLOCK_50 is fed into the PLL (50 MHz → ÷5 → 10 MHz output) which
--   satisfies the fiftyfivenm_adcblock requirement for a PLL-sourced
--   clock.  The max10_adc wrapper internally divides the PLL output by
--   10 (clkdiv => 2), yielding ~1 MHz on clk_dft.  All ADC-side logic
--   is clocked by this derived clock.
--   Drives: adc_fsm, FIFO write side
--
-- Clock-domain crossing
-- ─────────────────────
-- A 16-deep asynchronous FIFO (fifo_sync) with Gray-coded pointer
-- synchronisers bridges the two clock domains.
--
-- Reset
-- ─────
-- KEY(0) is the active-low asynchronous reset.  The PLL areset is
-- driven from the inverted KEY(0).
--
-- The producer-domain (adc_clk) reset synchroniser is additionally
-- held in reset until the PLL has locked, because adc_clk is sourced
-- from the PLL output and must not clock logic until it is stable.
--
-- The consumer-domain (CLOCK_50) reset synchroniser is NOT gated by
-- pll_locked: CLOCK_50 is the always-running board oscillator and
-- the consumer logic (FIFO read side, display register) is safe to
-- run regardless of PLL state.  Gating it on pll_locked previously
-- caused the consumer to be held in reset whenever pll_locked was
-- low, making KEY(0) appear inert and leaving display_reg stuck at
-- its reset value.
--
-- HEX5 pipeline-status indicator
-- ──────────────────────────────
-- HEX5 (driven by temperature_display) shows a one-character status
-- letter so that an "all dashes" reading on HEX0..HEX3 is no longer
-- ambiguous:
--   'P' – PLL not locked (producer domain has no clock)
--   'F' – PLL locked but no FIFO sample has ever been latched
--   'C' – at least one valid sample seen; normal Celsius indicator
-- The CLOCK_50-domain status signals driving this are pll_locked_50
-- (a 2-flop synchroniser of pll_locked) and sample_seen (a sticky
-- flag set the first time a FIFO word is latched into display_reg).

entity top is
	port (
		-- 50 MHz board oscillator (consumer clock domain + PLL input)
		CLOCK_50	: in	std_logic;

		-- Active-low push-buttons; KEY(0) = system reset
		KEY			: in	std_logic_vector(1 downto 0);

		-- Six 7-segment displays (active-low segments, DE10-Lite)
		HEX0		: out	std_logic_vector(6 downto 0);
		HEX1		: out	std_logic_vector(6 downto 0);
		HEX2		: out	std_logic_vector(6 downto 0);
		HEX3		: out	std_logic_vector(6 downto 0);
		HEX4		: out	std_logic_vector(6 downto 0);
		HEX5		: out	std_logic_vector(6 downto 0)
	);
end entity top;

architecture rtl of top is

	-- ----------------------------------------------------------------
	-- Component declarations
	-- ----------------------------------------------------------------

	component pll is
		port (
			areset	: in	std_logic;
			inclk0	: in	std_logic;
			c0		: out	std_logic;
			locked	: out	std_logic
		);
	end component pll;

	component max10_adc is
		port (
			pll_clk	: in	std_logic;
			chsel	: in	natural range 0 to 2**5 - 1;
			soc		: in	std_logic;
			tsen	: in	std_logic;
			dout	: out	natural range 0 to 2**12 - 1;
			eoc		: out	std_logic;
			clk_dft	: out	std_logic
		);
	end component max10_adc;

	component adc_fsm is
		port (
			clk			: in	std_logic;
			rst_n		: in	std_logic;
			soc			: out	std_logic;
			eoc			: in	std_logic;
			dout		: in	natural range 0 to 2**12 - 1;
			tsen		: out	std_logic;
			fifo_data	: out	std_logic_vector(11 downto 0);
			fifo_wen	: out	std_logic;
			fifo_full	: in	std_logic
		);
	end component adc_fsm;

	component fifo_sync is
		generic (
			data_width	: positive := 12;
			addr_width	: positive := 4
		);
		port (
			wclk	: in	std_logic;
			wrst_n	: in	std_logic;
			wen		: in	std_logic;
			wdata	: in	std_logic_vector(data_width - 1 downto 0);
			wfull	: out	std_logic;
			rclk	: in	std_logic;
			rrst_n	: in	std_logic;
			ren		: in	std_logic;
			rdata	: out	std_logic_vector(data_width - 1 downto 0);
			rempty	: out	std_logic
		);
	end component fifo_sync;

	component temperature_display is
		port (
			value					: in	std_logic_vector(11 downto 0);
			status_pll_locked		: in	std_logic;
			status_sample_seen		: in	std_logic;
			HEX0	: out	std_logic_vector(6 downto 0);
			HEX1	: out	std_logic_vector(6 downto 0);
			HEX2	: out	std_logic_vector(6 downto 0);
			HEX3	: out	std_logic_vector(6 downto 0);
			HEX4	: out	std_logic_vector(6 downto 0);
			HEX5	: out	std_logic_vector(6 downto 0)
		);
	end component temperature_display;

	-- ----------------------------------------------------------------
	-- Internal signals
	-- ----------------------------------------------------------------

	-- Clocks
	signal pll_clk	: std_logic;   -- PLL output (10 MHz) → max10_adc
	signal adc_clk	: std_logic;   -- max10_adc clk_dft (~1 MHz, producer)

	-- PLL control
	signal pll_areset	: std_logic;   -- active-high PLL reset (from KEY(0))
	signal pll_locked	: std_logic;   -- PLL lock indicator

	-- Reset (active-low)
	-- rst_async_n     – consumer (CLOCK_50) async reset: KEY(0) only
	-- rst_adc_async_n – producer (adc_clk)  async reset: KEY(0) AND pll_locked
	signal rst_async_n		: std_logic;
	signal rst_adc_async_n	: std_logic;

	-- Producer-domain reset synchroniser
	signal rst_adc_s1, rst_adc_n	: std_logic := '0';

	-- Consumer-domain reset synchroniser
	signal rst_50_s1, rst_50_n	: std_logic := '0';

	-- ADC signals
	signal adc_soc, adc_eoc, adc_tsen	: std_logic;
	signal adc_dout	: natural range 0 to 2**12 - 1;

	-- FIFO signals (write = producer, read = consumer)
	signal fifo_wdata, fifo_rdata	: std_logic_vector(11 downto 0);
	signal fifo_wen, fifo_wfull	: std_logic;
	signal fifo_ren, fifo_rempty	: std_logic;

	-- Consumer-side display register
	signal display_reg	: std_logic_vector(11 downto 0) := (others => '0');

	-- Pipeline status indicators in the CLOCK_50 domain, used to drive
	-- HEX5 with a single-character diagnostic ('P' / 'F' / 'C').
	-- pll_locked_s1/pll_locked_50 form a 2-flop CDC synchroniser
	-- bringing the PLL lock signal into CLOCK_50; it shares the same
	-- async reset as the consumer reset synchroniser (KEY(0)) so all
	-- consumer-domain status flops come out of reset together.
	-- sample_seen is a sticky flag set the first time a FIFO word is
	-- latched into display_reg; it is cleared by rst_50_n in the
	-- consumer process.
	signal pll_locked_s1, pll_locked_50	: std_logic := '0';
	signal sample_seen	: std_logic := '0';

begin

	-- KEY(0) is active-low; convert to active-high for PLL areset.
	-- Consumer reset uses KEY(0) directly (CLOCK_50 always runs).
	-- Producer reset is additionally gated by pll_locked because
	-- adc_clk is derived from the PLL output.
	pll_areset      <= not KEY(0);
	rst_async_n     <= KEY(0);
	rst_adc_async_n <= KEY(0) and pll_locked;

	-- ----------------------------------------------------------------
	-- Reset synchroniser – producer clock domain (adc_clk)
	-- ----------------------------------------------------------------
	sync_rst_adc: process(adc_clk, rst_adc_async_n)
	begin
		if rst_adc_async_n = '0' then
			rst_adc_s1 <= '0';
			rst_adc_n  <= '0';
		elsif rising_edge(adc_clk) then
			rst_adc_s1 <= '1';
			rst_adc_n  <= rst_adc_s1;
		end if;
	end process sync_rst_adc;

	-- ----------------------------------------------------------------
	-- Reset synchroniser – consumer clock domain (CLOCK_50)
	-- ----------------------------------------------------------------
	sync_rst_50: process(CLOCK_50, rst_async_n)
	begin
		if rst_async_n = '0' then
			rst_50_s1 <= '0';
			rst_50_n  <= '0';
		elsif rising_edge(CLOCK_50) then
			rst_50_s1 <= '1';
			rst_50_n  <= rst_50_s1;
		end if;
	end process sync_rst_50;

	-- ----------------------------------------------------------------
	-- PLL: derives 10 MHz from the 50 MHz board oscillator
	-- (CLOCK_50 ÷ 5 = 10 MHz) for the fiftyfivenm_adcblock primitive.
	-- ----------------------------------------------------------------
	pll_inst: pll
		port map (
			areset => pll_areset,
			inclk0 => CLOCK_50,
			c0     => pll_clk,
			locked => pll_locked
		);

	-- ----------------------------------------------------------------
	-- MAX10 ADC (produces clk_dft for the producer clock domain)
	-- ----------------------------------------------------------------
	adc_inst: max10_adc
		port map (
			pll_clk => pll_clk,
			chsel   => 0,          -- channel 0 (temperature sensor)
			soc     => adc_soc,
			tsen    => adc_tsen,
			dout    => adc_dout,
			eoc     => adc_eoc,
			clk_dft => adc_clk
		);

	-- ----------------------------------------------------------------
	-- ADC control FSM (producer clock domain)
	-- ----------------------------------------------------------------
	fsm_inst: adc_fsm
		port map (
			clk       => adc_clk,
			rst_n     => rst_adc_n,
			soc       => adc_soc,
			eoc       => adc_eoc,
			dout      => adc_dout,
			tsen      => adc_tsen,
			fifo_data => fifo_wdata,
			fifo_wen  => fifo_wen,
			fifo_full => fifo_wfull
		);

	-- ----------------------------------------------------------------
	-- Asynchronous FIFO – clock-domain crossing
	-- ----------------------------------------------------------------
	fifo_inst: fifo_sync
		generic map (
			data_width => 12,
			addr_width => 4    -- 16 entries
		)
		port map (
			wclk   => adc_clk,
			wrst_n => rst_adc_n,
			wen    => fifo_wen,
			wdata  => fifo_wdata,
			wfull  => fifo_wfull,
			rclk   => CLOCK_50,
			rrst_n => rst_50_n,
			ren    => fifo_ren,
			rdata  => fifo_rdata,
			rempty => fifo_rempty
		);

	-- ----------------------------------------------------------------
	-- Consumer logic (CLOCK_50 domain):
	-- Drain the FIFO and keep the most-recent sample in display_reg.
	--
	-- FIFO read timing (FWFT / look-ahead model):
	--   rdata is driven combinatorially from the current rptr.  When
	--   ren='1' is registered on the rising edge, rptr increments one
	--   cycle LATER.  Therefore fifo_rdata at the sampling moment still
	--   reflects mem[rptr_current], i.e. the entry we intend to read.
	--   Asserting ren and latching rdata in the same cycle is correct
	--   and is the standard technique for first-word-fall-through FIFOs.
	-- ----------------------------------------------------------------
	consumer_proc: process(CLOCK_50, rst_50_n)
	begin
		if rst_50_n = '0' then
			display_reg <= (others => '0');
			fifo_ren    <= '0';
			sample_seen <= '0';
		elsif rising_edge(CLOCK_50) then
			fifo_ren <= '0';           -- default: no read
			if fifo_rempty = '0' then
				-- Latch the current head-of-FIFO word.  rptr advances
				-- on the NEXT rising edge, so fifo_rdata here is the
				-- word at the current (pre-advance) read pointer.
				fifo_ren    <= '1';
				display_reg <= fifo_rdata;
				sample_seen <= '1';    -- sticky: first valid sample arrived
			end if;
		end if;
	end process consumer_proc;

	-- ----------------------------------------------------------------
	-- pll_locked → CLOCK_50 CDC synchroniser (2-flop)
	-- pll_locked is generated inside the PLL (asynchronous to CLOCK_50)
	-- so it must be synchronised before being used as a status bit by
	-- the consumer-domain display logic.
	--
	-- This synchroniser uses rst_async_n (= KEY(0)) as its async reset
	-- so it comes out of reset in lock-step with sync_rst_50.  A side
	-- effect is that while KEY(0) is held low, pll_locked_50 is forced
	-- to '0' even if the PLL itself remains locked, briefly showing
	-- 'P' on HEX5; this is harmless because the consumer is in reset
	-- and the display is being re-initialised anyway.
	-- ----------------------------------------------------------------
	sync_pll_locked: process(CLOCK_50, rst_async_n)
	begin
		if rst_async_n = '0' then
			pll_locked_s1 <= '0';
			pll_locked_50 <= '0';
		elsif rising_edge(CLOCK_50) then
			pll_locked_s1 <= pll_locked;
			pll_locked_50 <= pll_locked_s1;
		end if;
	end process sync_pll_locked;

	-- ----------------------------------------------------------------
	-- Temperature display (consumer clock domain, combinatorial)
	-- ----------------------------------------------------------------
	disp_inst: temperature_display
		port map (
			value              => display_reg,
			status_pll_locked  => pll_locked_50,
			status_sample_seen => sample_seen,
			HEX0  => HEX0,
			HEX1  => HEX1,
			HEX2  => HEX2,
			HEX3  => HEX3,
			HEX4  => HEX4,
			HEX5  => HEX5
		);

end architecture rtl;
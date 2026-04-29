-- adc_fsm: producer-side finite state machine.
--
-- This FSM lives in the producer clock domain (driven by clk_dft from
-- the MAX10 ADC, ~1 MHz with the divide-by-10 prescaler in
-- max10_adc.vhd).  It repeatedly:
--
--   1. issues a start-of-conversion pulse to the ADC,
--   2. waits for the end-of-conversion strobe,
--   3. captures the 12-bit result,
--   4. pushes that result into the asynchronous FIFO so it can cross
--      into the consumer (50 MHz) clock domain that drives the
--      seven-segment displays.
--
-- The chsel/tsen ports are exposed so the top-level can wire the FSM
-- to ADC channel 0 in temperature-sensing mode (tsen = '1').
--
-- States:
--   IDLE      -- wait one cycle, then request a new conversion
--   START     -- assert soc for one clock to launch the conversion
--   WAIT_EOC  -- hold soc low and wait for eoc to assert
--   PUSH      -- if FIFO has room, write the captured sample; if not,
--                drop the sample (overflow) and return to IDLE so the
--                producer never stalls

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adc_fsm is
	generic (
		data_width:	positive := 12
	);
	port (
		clk:		in	std_logic;
		rst_n:		in	std_logic;

		-- ADC interface
		eoc:		in	std_logic;
		dout:		in	natural range 0 to 2**12 - 1;
		soc:		out	std_logic;
		chsel:		out	natural range 0 to 2**5 - 1;
		tsen:		out	std_logic;

		-- FIFO write interface
		fifo_full:	in	std_logic;
		fifo_winc:	out	std_logic;
		fifo_wdata:	out	std_logic_vector(data_width - 1 downto 0)
	);
end entity adc_fsm;

architecture rtl of adc_fsm is
	type state_t is (S_IDLE, S_START, S_WAIT_EOC, S_PUSH);
	signal state, next_state: state_t;

	signal sample_reg: std_logic_vector(data_width - 1 downto 0);
	signal capture:    std_logic;

	-- DEBUG: diagnostic counter used to bisect the producer-side path.
	-- Step 1 (free-running counter, eoc bypassed) showed the consumer
	-- chain (FIFO -> bin_to_bcd -> 7-seg) is healthy.
	-- Step 2 (this build): keep debug mode but use the real eoc and
	-- increment dbg_count only on real captures. The display now shows
	-- the number of eoc pulses observed:
	--   * ticking  -> eoc is live, bug is in dout
	--   * frozen   -> FSM stuck in WAIT_EOC, eoc never asserts
	-- Set this constant back to false to restore normal ADC operation.
	constant debug_counter_mode: boolean := true;
	signal dbg_count: unsigned(data_width - 1 downto 0);
begin

	-- channel 0, temperature sensing mode are static for this design
	chsel <= 0;
	tsen  <= '1';

	-- next-state and output decoding
	process (state, eoc, fifo_full) is
		variable eoc_eff: std_logic;
	begin
		next_state <= state;
		soc        <= '0';
		fifo_winc  <= '0';
		capture    <= '0';

		-- use the real eoc; debug mode now only changes what data
		-- gets written into the FIFO and how dbg_count is updated
		eoc_eff := eoc;

		case state is
			when S_IDLE =>
				next_state <= S_START;

			when S_START =>
				-- one-cycle pulse on soc
				soc        <= '1';
				next_state <= S_WAIT_EOC;

			when S_WAIT_EOC =>
				if eoc_eff = '1' then
					-- latch the conversion result on this edge
					capture    <= '1';
					next_state <= S_PUSH;
				end if;

			when S_PUSH =>
				if fifo_full = '0' then
					fifo_winc <= '1';
				end if;
				-- whether or not the FIFO accepted the sample, return
				-- to IDLE: the consumer is faster than us so under
				-- normal operation the FIFO will not be full.
				next_state <= S_IDLE;
		end case;
	end process;

	-- state register and sample capture register
	process (clk, rst_n) is
	begin
		if rst_n = '0' then
			state      <= S_IDLE;
			sample_reg <= (others => '0');
			dbg_count  <= (others => '0');
		elsif rising_edge(clk) then
			state <= next_state;
			if capture = '1' then
				sample_reg <= std_logic_vector(
					to_unsigned(dout, data_width));
				-- bump the diagnostic counter once per real eoc
				-- event so the display becomes a visible tally of
				-- conversions completed
				dbg_count <= dbg_count + 1;
			end if;
		end if;
	end process;

	fifo_wdata <= std_logic_vector(dbg_count) when debug_counter_mode
	              else sample_reg;

end architecture rtl;

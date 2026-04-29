-- adc_fsm: producer-side finite state machine.
--
-- This FSM lives in the producer clock domain (driven by clk_dft from
-- the MAX10 ADC, ~1 MHz with the divide-by-10 prescaler in
-- max10_adc.vhd).  It repeatedly:
--
--   1. asserts start-of-conversion to the ADC,
--   2. holds soc high until the end-of-conversion strobe rises,
--   3. captures the 12-bit result on the eoc edge,
--   4. pushes that result into the asynchronous FIFO so it can cross
--      into the consumer (50 MHz) clock domain that drives the
--      seven-segment displays.
--
-- The chsel/tsen ports are exposed so the top-level can wire the FSM
-- to ADC channel 0 in temperature-sensing mode (tsen = '1').
--
-- States:
--   IDLE      -- wait one cycle, then request a new conversion
--   CONVERT   -- assert soc and hold it high until eoc rises.  The
--                MAX 10 ADC requires soc to be held high for the
--                duration of the conversion -- a one-cycle pulse
--                causes the conversion to abort and eoc never fires.
--                On the eoc edge, increment the diagnostic counter
--                so dbg_count tallies one tick per real conversion.
--   PUSH      -- one cycle after eoc detection.  Capture dout into
--                sample_reg here (giving dout one extra clk_dft
--                cycle to settle past the eoc-clearing edge), and
--                if the FIFO has room, write the sample.  Whether
--                or not the write happens, return to IDLE.

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
	type state_t is (S_IDLE, S_CONVERT, S_PUSH);
	signal state, next_state: state_t;

	signal sample_reg: std_logic_vector(data_width - 1 downto 0);
	signal eoc_seen:   std_logic;        -- '1' for the cycle eoc was first detected (S_CONVERT->S_PUSH transition)
	signal capture:    std_logic;        -- '1' in S_PUSH, one cycle after eoc -> dout is settled, latch it

	-- DEBUG: diagnostic counter used to bisect the producer-side path.
	-- Step 1 (free-running counter, eoc bypassed) showed the consumer
	-- chain (FIFO -> bin_to_bcd -> 7-seg) is healthy.
	-- Step 2 (real eoc, single-cycle soc pulse) showed the display
	-- frozen at 0000 -> conversions never completed.  Root cause:
	-- the MAX 10 ADC needs soc held high until eoc rises.  Fix:
	-- hold soc across S_CONVERT.  Counter then ticked correctly
	-- (HEX3 cycles 0..3 as the 12-bit dbg_count wraps).
	-- Step 3: with debug_counter_mode=false the display read 0000.
	-- The 3-state FSM captured dout on the same edge the ADC
	-- updates dout, so sample_reg got the previous (initially zero)
	-- value.  Fix: keep the same 3-state FSM (so dbg_count still
	-- ticks once per eoc), but defer the dout capture by one clk_dft
	-- cycle by latching dout in S_PUSH instead of S_CONVERT.  This
	-- mirrors the working ReninJose/ADS Project4 reference, which
	-- registers the result two state edges after eoc detection.
	-- Step 4: with the display_unit pop-timing bug fixed (it was
	-- latching mem[rbin+1] instead of mem[rbin]), normal ADC
	-- operation works again, so debug_counter_mode is set back to
	-- false.  Flip to true to re-enable the diagnostic counter.
	constant debug_counter_mode: boolean := false;
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
		eoc_seen   <= '0';
		capture    <= '0';

		-- use the real eoc; debug mode now only changes what data
		-- gets written into the FIFO and how dbg_count is updated
		eoc_eff := eoc;

		case state is
			when S_IDLE =>
				next_state <= S_CONVERT;

			when S_CONVERT =>
				-- hold soc high for the full duration of the
				-- conversion; the MAX 10 ADC samples soc on each
				-- internal clock and aborts the conversion if soc
				-- is deasserted before eoc rises
				soc <= '1';
				if eoc_eff = '1' then
					-- mark the conversion as complete this cycle
					-- (used to tick dbg_count once per real eoc).
					-- Do NOT capture dout here: dout is being
					-- updated by the ADC on this same rising edge,
					-- so it has not yet settled.  Capture in
					-- S_PUSH (next cycle) instead.
					eoc_seen   <= '1';
					next_state <= S_PUSH;
				end if;

			when S_PUSH =>
				-- one cycle after eoc -> dout is now stable.
				-- Latch it into sample_reg.
				capture <= '1';
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
			end if;
			if eoc_seen = '1' then
				-- bump the diagnostic counter once per real eoc
				-- event so the display becomes a visible tally of
				-- conversions completed
				dbg_count <= dbg_count + 1;
			end if;
		end if;
	end process;

	-- In normal mode write dout directly: dout is stable in S_PUSH (one
	-- clk_dft cycle after eoc, giving the ADC time to settle the output
	-- bus).  Using sample_reg instead produced a one-sample lag where the
	-- very first FIFO entry was always 0x000 (sample_reg reset value),
	-- causing the display to read "0000" on the first pop.
	fifo_wdata <= std_logic_vector(dbg_count) when debug_counter_mode
	              else std_logic_vector(to_unsigned(dout, data_width));

end architecture rtl;

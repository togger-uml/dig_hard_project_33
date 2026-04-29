-- adc_fsm: producer-side finite state machine.
--
-- This FSM lives in the producer clock domain (driven by clk_dft from
-- the MAX10 ADC, ~1 MHz with the divide-by-10 prescaler in
-- max10_adc.vhd).  It repeatedly:
--
--   1. asserts start-of-conversion to the ADC,
--   2. holds soc high until the end-of-conversion strobe rises,
--   3. captures the 12-bit result one cycle after the eoc edge,
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
--                On the eoc edge, transition to SAMPLE.
--   SAMPLE    -- one cycle after eoc.  dout has now settled past the
--                eoc-clearing edge.  Capture dout into sample_reg.
--                The diagnostic counter increments here so dbg_count
--                tallies one tick per real conversion.  Transition to
--                PUSH.
--   PUSH      -- one cycle after SAMPLE.  sample_reg holds a stable
--                copy of dout.  If the FIFO has room, write it.
--                Whether or not the write happens, return to IDLE.

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
	type state_t is (S_IDLE, S_CONVERT, S_SAMPLE, S_PUSH);
	signal state, next_state: state_t;

	signal sample_reg: std_logic_vector(data_width - 1 downto 0);
	signal eoc_seen:   std_logic;        -- '1' for the cycle eoc was first detected (S_CONVERT->S_SAMPLE transition)
	signal capture:    std_logic;        -- '1' in S_SAMPLE: latch dout (now settled) into sample_reg

	-- DEBUG: diagnostic counter used to bisect the producer-side path.
	-- Step 1 (free-running counter, eoc bypassed) showed the consumer
	-- chain (FIFO -> bin_to_bcd -> 7-seg) is healthy.
	-- Step 2 (real eoc, single-cycle soc pulse) showed the display
	-- frozen at 0000 -> conversions never completed.  Root cause:
	-- the MAX 10 ADC needs soc held high until eoc rises.  Fix:
	-- hold soc across S_CONVERT.  Counter then ticked correctly
	-- (HEX3 cycles 0..3 as the 12-bit dbg_count wraps).
	-- Step 3: with debug_counter_mode=false the display read 0000.
	-- Root cause: dout is updated by the ADC on the same rising edge
	-- that eoc asserts, so capturing it then gives the previous
	-- (initially zero) value.  Fix: add a dedicated S_SAMPLE state
	-- so dout is registered into sample_reg one clk_dft cycle after
	-- eoc, giving the ADC bus time to settle.  S_PUSH then writes
	-- the stable sample_reg to the FIFO.  This eliminates the
	-- one-sample lag of the earlier two-state approach and ensures
	-- sample_reg is always valid when the FIFO write occurs.
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
	begin
		next_state <= state;
		soc        <= '0';
		fifo_winc  <= '0';
		eoc_seen   <= '0';
		capture    <= '0';

		case state is
			when S_IDLE =>
				next_state <= S_CONVERT;

			when S_CONVERT =>
				-- hold soc high for the full duration of the
				-- conversion; the MAX 10 ADC samples soc on each
				-- internal clock and aborts the conversion if soc
				-- is deasserted before eoc rises
				soc <= '1';
				if eoc = '1' then
					-- mark the conversion complete (used to tick
					-- dbg_count once per real eoc).  Do NOT capture
					-- dout here: the ADC is updating dout on this
					-- same rising edge.  Wait until S_SAMPLE instead.
					eoc_seen   <= '1';
					next_state <= S_SAMPLE;
				end if;

			when S_SAMPLE =>
				-- one cycle after eoc -> dout is now stable.
				-- Latch it into sample_reg so S_PUSH can forward
				-- a registered (glitch-free) value to the FIFO.
				capture    <= '1';
				next_state <= S_PUSH;

			when S_PUSH =>
				-- sample_reg now holds the settled conversion result.
				-- Write it to the FIFO if there is room, then return
				-- to IDLE and start the next conversion.
				if fifo_full = '0' then
					fifo_winc <= '1';
				end if;
				next_state <= S_IDLE;
		end case;
	end process;

	-- state register, sample capture register, and diagnostic counter
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

	-- In normal mode, write sample_reg: it was captured in S_SAMPLE
	-- (one clk_dft cycle after eoc), so the ADC output bus is fully
	-- settled.  The FIFO write in S_PUSH therefore always carries a
	-- valid, registered sample -- including the very first conversion.
	fifo_wdata <= std_logic_vector(dbg_count) when debug_counter_mode
	              else sample_reg;

end architecture rtl;

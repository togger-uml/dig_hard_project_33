-- display_unit: consumer-side logic.
--
-- Lives in the consumer (50 MHz) clock domain.  Its job is to pop
-- samples out of the asynchronous FIFO and present them on the
-- DE10-Lite seven-segment displays as a four-digit decimal value.
--
-- A simple two-state FSM is used: when the FIFO is not empty, the
-- consumer asserts rinc for one cycle (the FIFO output is stable on
-- the next clock edge) and then registers the popped sample into a
-- holding register that drives the binary-to-BCD converter and the
-- seven-segment decoders.  HEX0..HEX3 show the decimal value,
-- HEX4..HEX5 are blanked.

library ieee;
use ieee.std_logic_1164.all;

entity display_unit is
	generic (
		data_width:	positive := 12
	);
	port (
		clk:		in	std_logic;
		rst_n:		in	std_logic;

		-- FIFO read interface
		fifo_empty:	in	std_logic;
		fifo_rdata:	in	std_logic_vector(data_width - 1 downto 0);
		fifo_rinc:	out	std_logic;

		-- seven segment displays (each is active-low, 7 bits per digit)
		hex0:	out	std_logic_vector(6 downto 0);
		hex1:	out	std_logic_vector(6 downto 0);
		hex2:	out	std_logic_vector(6 downto 0);
		hex3:	out	std_logic_vector(6 downto 0);
		hex4:	out	std_logic_vector(6 downto 0);
		hex5:	out	std_logic_vector(6 downto 0)
	);
end entity display_unit;

architecture rtl of display_unit is

	component bin_to_bcd is
		generic (
			input_width:	positive := 12;
			digits:			positive := 4
		);
		port (
			bin_in:		in	std_logic_vector(input_width - 1 downto 0);
			bcd_out:	out	std_logic_vector(4 * digits - 1 downto 0)
		);
	end component bin_to_bcd;

	component seven_seg_decoder is
		port (
			digit:	in	std_logic_vector(3 downto 0);
			blank:	in	std_logic;
			seg:	out	std_logic_vector(6 downto 0)
		);
	end component seven_seg_decoder;

	type state_t is (S_WAIT, S_POP);
	signal state, next_state: state_t;

	signal sample: std_logic_vector(data_width - 1 downto 0);
	signal bcd:    std_logic_vector(15 downto 0);
	signal load:   std_logic;
begin

	-- next-state / output decoding
	process (state, fifo_empty) is
	begin
		next_state <= state;
		fifo_rinc  <= '0';
		load       <= '0';

		case state is
			when S_WAIT =>
				if fifo_empty = '0' then
					fifo_rinc  <= '1';
					next_state <= S_POP;
				end if;
			when S_POP =>
				-- fifo_rdata is now stable; latch it and go back to wait
				load       <= '1';
				next_state <= S_WAIT;
		end case;
	end process;

	-- registers
	process (clk, rst_n) is
	begin
		if rst_n = '0' then
			state  <= S_WAIT;
			sample <= (others => '0');
		elsif rising_edge(clk) then
			state <= next_state;
			if load = '1' then
				sample <= fifo_rdata;
			end if;
		end if;
	end process;

	-- decimalisation: 12-bit sample produces 4 BCD digits
	bcd_inst: bin_to_bcd
		generic map (input_width => data_width, digits => 4)
		port map (bin_in => sample, bcd_out => bcd);

	-- four active digits (HEX0 = ones, HEX3 = thousands)
	hex0_inst: seven_seg_decoder
		port map (digit => bcd( 3 downto  0), blank => '0', seg => hex0);
	hex1_inst: seven_seg_decoder
		port map (digit => bcd( 7 downto  4), blank => '0', seg => hex1);
	hex2_inst: seven_seg_decoder
		port map (digit => bcd(11 downto  8), blank => '0', seg => hex2);
	hex3_inst: seven_seg_decoder
		port map (digit => bcd(15 downto 12), blank => '0', seg => hex3);

	-- two unused digits, blanked
	hex4_inst: seven_seg_decoder
		port map (digit => "0000", blank => '1', seg => hex4);
	hex5_inst: seven_seg_decoder
		port map (digit => "0000", blank => '1', seg => hex5);

end architecture rtl;

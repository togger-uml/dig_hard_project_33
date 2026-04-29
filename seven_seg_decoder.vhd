-- seven_seg_decoder: hex digit (0-F) to seven-segment encoding.
--
-- The DE10-Lite drives its seven-segment displays in a common-anode
-- configuration: the FPGA pulls the cathode of each segment low to
-- light it.  Hence the encoding here is active-low.  Bit ordering on
-- the HEXn ports follows the DE10-Lite pin assignment: HEXn(0) drives
-- segment 'a', HEXn(1) drives 'b', ..., HEXn(6) drives 'g'.
--
-- Internally the patterns below are written with the more readable
-- "(a,b,c,d,e,f,g)" left-to-right ordering (so seg_active_high(6)
-- corresponds to segment 'a'); the final output assignment reverses
-- the bit order to match the physical pin map.
--
-- Although the project description mentions "logic high turns on the
-- LED", the DE10-Lite hardware is wired such that the segment pin is
-- driven low to illuminate the LED, so this decoder uses active-low
-- outputs to match the physical board.  If the board you are targeting
-- truly uses active-high segments, simply invert the output.

library ieee;
use ieee.std_logic_1164.all;

entity seven_seg_decoder is
	port (
		digit:	in	std_logic_vector(3 downto 0);
		blank:	in	std_logic;	-- when '1' the digit is blanked
		seg:	out	std_logic_vector(6 downto 0)
	);
end entity seven_seg_decoder;

architecture rtl of seven_seg_decoder is
	signal seg_active_high: std_logic_vector(6 downto 0);
begin

	-- segments numbered (a b c d e f g) where seg_active_high(6) = a
	with digit select seg_active_high <=
		"1111110" when "0000",	-- 0
		"0110000" when "0001",	-- 1
		"1101101" when "0010",	-- 2
		"1111001" when "0011",	-- 3
		"0110011" when "0100",	-- 4
		"1011011" when "0101",	-- 5
		"1011111" when "0110",	-- 6
		"1110000" when "0111",	-- 7
		"1111111" when "1000",	-- 8
		"1111011" when "1001",	-- 9
		"1110111" when "1010",	-- A
		"0011111" when "1011",	-- b
		"1001110" when "1100",	-- C
		"0111101" when "1101",	-- d
		"1001111" when "1110",	-- E
		"1000111" when "1111",	-- F
		"0000000" when others;

	-- invert for the active-low common-anode displays; force all
	-- segments off (= '1') when blanked.  Reverse the bit order so
	-- seg(0) drives segment 'a' (matching the DE10-Lite HEXn pinout)
	-- while the patterns above remain readable as (a,b,c,d,e,f,g).
	gen_seg: for i in 0 to 6 generate
		seg(i) <= '1' when blank = '1' else not seg_active_high(6 - i);
	end generate;

end architecture rtl;

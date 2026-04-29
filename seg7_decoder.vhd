library ieee;
use ieee.std_logic_1164.all;

-- Decodes a single 4-bit hexadecimal (or BCD) digit into the 7-segment
-- display pattern required by the DE10-Lite board.
--
-- The DE10-Lite drives each segment active-low: logic '0' turns the
-- corresponding LED on, logic '1' turns it off.
--
-- Output bit assignment (matches the DE10-Lite HEXn port convention):
--   seg(0) = segment a  (top horizontal)
--   seg(1) = segment b  (top-right vertical)
--   seg(2) = segment c  (bottom-right vertical)
--   seg(3) = segment d  (bottom horizontal)
--   seg(4) = segment e  (bottom-left vertical)
--   seg(5) = segment f  (top-left vertical)
--   seg(6) = segment g  (middle horizontal)

entity seg7_decoder is
	port (
		digit	: in	std_logic_vector(3 downto 0);
		seg		: out	std_logic_vector(6 downto 0)
	);
end entity seg7_decoder;

architecture rtl of seg7_decoder is
begin

	with digit select
		--              gfedcba
		seg <=	"1000000" when "0000",	-- 0
				"1111001" when "0001",	-- 1
				"0100100" when "0010",	-- 2
				"0110000" when "0011",	-- 3
				"0011001" when "0100",	-- 4
				"0010010" when "0101",	-- 5
				"0000010" when "0110",	-- 6
				"1111000" when "0111",	-- 7
				"0000000" when "1000",	-- 8
				"0010000" when "1001",	-- 9
				"0001000" when "1010",	-- A
				"0000011" when "1011",	-- b
				"1000110" when "1100",	-- C
				"0100001" when "1101",	-- d
				"0000110" when "1110",	-- E
				"0001110" when others;	-- F

end architecture rtl;

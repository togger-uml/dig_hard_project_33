library ieee;
use ieee.std_logic_1164.all;

entity bin_to_gray is
	generic (
		input_width:	positive :=	16
	);
	port (
		bin_in:			in	std_logic_vector(input_width - 1 downto 0);
		gray_out:		out	std_logic_vector(input_width - 1 downto 0)
	);
end entity bin_to_gray;

architecture rtl of bin_to_gray is
	signal shifted: std_logic_vector(bin_in'range);
begin
	shifted(input_width - 2 downto 0) <= bin_in(input_width - 1 downto 1);
	shifted(bin_in'high) <= '0';
	gray_out <= bin_in xor shifted; 
end architecture rtl;

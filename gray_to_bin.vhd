library ieee;
use ieee.std_logic_1164.all;

entity gray_to_bin is
	generic (
		input_width:	positive := 16
	);
	port (
		gray_in:		in	std_logic_vector(input_width - 1 downto 0);
		bin_out:		out	std_logic_vector(input_width - 1 downto 0)
	);
end entity gray_to_bin;

architecture rtl of gray_to_bin is
	function unary_xor (
			vector: in	std_logic_vector
		) return std_logic
	is
		variable ret: std_logic := '0';
	begin
		for i in vector'range loop
			ret := ret xor vector(i);
		end loop;
		return ret;
	end function unary_xor;
begin

	xor_tree: for i in bin_out'range generate
		-- if using VHDL-2008 then we just use the regular unary xor
		-- bin_out(i) <= xor gray_in(gray_in'high downto 0);
		-- since we do not have VHDL-2008 support we need an auxiliary function
		-- to do the unary XOR operation
		bin_out(i) <= unary_xor(gray_in(gray_in'high downto i));
	end generate xor_tree;

end architecture rtl;

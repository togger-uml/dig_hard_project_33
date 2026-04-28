-- bin_to_bcd: binary to packed BCD using the shift-and-add-3
-- (double-dabble) algorithm.
--
-- This is purely combinational.  For a 12-bit input the worst-case
-- value is 4095, which fits in four BCD digits (16 bits of output).
-- The algorithm shifts the binary value left into the BCD field,
-- adding 3 to any nibble that exceeds 4 before each shift so that
-- after the final shift each nibble holds a valid decimal digit.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bin_to_bcd is
	generic (
		input_width:	positive := 12;
		digits:			positive := 4		-- number of BCD digits
	);
	port (
		bin_in:		in	std_logic_vector(input_width - 1 downto 0);
		bcd_out:	out	std_logic_vector(4 * digits - 1 downto 0)
	);
end entity bin_to_bcd;

architecture rtl of bin_to_bcd is
begin

	process (bin_in) is
		variable scratch:	unsigned(4 * digits + input_width - 1 downto 0);
		variable nibble:	unsigned(3 downto 0);
	begin
		scratch := (others => '0');
		scratch(input_width - 1 downto 0) := unsigned(bin_in);

		-- input_width shifts; before each shift, every BCD nibble
		-- whose value is 5 or more gets 3 added to it.
		for i in 0 to input_width - 1 loop
			for d in 0 to digits - 1 loop
				nibble := scratch(input_width + 4 * d + 3
				                  downto input_width + 4 * d);
				if nibble >= 5 then
					scratch(input_width + 4 * d + 3
					        downto input_width + 4 * d) := nibble + 3;
				end if;
			end loop;
			scratch := shift_left(scratch, 1);
		end loop;

		bcd_out <= std_logic_vector(
			scratch(4 * digits + input_width - 1 downto input_width));
	end process;

end architecture rtl;

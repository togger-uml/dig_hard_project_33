-- sync_2ff: two-flip-flop synchronizer
--
-- This entity is the canonical metastability filter.  An asynchronous
-- input is sampled by two flip-flops driven by the destination clock.
-- The output of the second flip-flop is considered safe to use in the
-- destination clock domain.  The data being crossed must change at most
-- one bit at a time across the boundary; this is why the FIFO
-- synchronizer transfers Gray-coded pointers rather than raw binary.

library ieee;
use ieee.std_logic_1164.all;

entity sync_2ff is
	generic (
		width:	positive := 1
	);
	port (
		clk:	in	std_logic;
		rst_n:	in	std_logic;
		d:		in	std_logic_vector(width - 1 downto 0);
		q:		out	std_logic_vector(width - 1 downto 0)
	);
end entity sync_2ff;

architecture rtl of sync_2ff is
	signal stage1, stage2: std_logic_vector(width - 1 downto 0);
begin

	process (clk, rst_n) is
	begin
		if rst_n = '0' then
			stage1 <= (others => '0');
			stage2 <= (others => '0');
		elsif rising_edge(clk) then
			stage1 <= d;
			stage2 <= stage1;
		end if;
	end process;

	q <= stage2;

end architecture rtl;

-- rptr_empty: read-side pointer logic and empty-flag generator.
--
-- Lives entirely in the read (consumer) clock domain.  Holds the
-- binary read pointer plus an extra MSB used as a wrap bit, exposes a
-- Gray version for crossing into the write domain, and asserts empty
-- when the next-state read Gray pointer equals the synchronized write
-- Gray pointer.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rptr_empty is
	generic (
		addr_width:	positive := 4
	);
	port (
		rclk:		in	std_logic;
		rrst_n:		in	std_logic;
		rinc:		in	std_logic;
		rq2_wptr:	in	std_logic_vector(addr_width downto 0);
		raddr:		out	std_logic_vector(addr_width - 1 downto 0);
		rptr:		out	std_logic_vector(addr_width downto 0);
		rempty:		out	std_logic
	);
end entity rptr_empty;

architecture rtl of rptr_empty is
	signal rbin, rbin_next:		unsigned(addr_width downto 0);
	signal rgray, rgray_next:	std_logic_vector(addr_width downto 0);
	signal rempty_val:			std_logic;
	signal rempty_reg:			std_logic;
begin

	-- next-state binary read pointer.  Gate the increment on the
	-- *registered* empty flag, not the combinational rempty_val: gating
	-- on rempty_val creates a combinational loop
	-- (rbin_next -> rgray_next -> rempty_val -> rbin_next) that Quartus
	-- flagged with warning 332125 and which synthesises to unreliable
	-- hardware.  Using the registered signal matches the Cummings
	-- async-FIFO reference and is functionally correct because
	-- rempty_reg already reflects the post-flop empty status the
	-- consumer must observe before issuing a read.
	rbin_next <= rbin + 1 when (rinc = '1') and (rempty_reg = '0') else rbin;

	-- binary-to-Gray on the next-state pointer
	rgray_next(addr_width) <= rbin_next(addr_width);
	gray_gen: for i in addr_width - 1 downto 0 generate
		rgray_next(i) <= rbin_next(i + 1) xor rbin_next(i);
	end generate gray_gen;

	-- registered pointers
	process (rclk, rrst_n) is
	begin
		if rrst_n = '0' then
			rbin  <= (others => '0');
			rgray <= (others => '0');
		elsif rising_edge(rclk) then
			rbin  <= rbin_next;
			rgray <= rgray_next;
		end if;
	end process;

	-- empty when the next-state Gray read pointer equals the
	-- synchronized Gray write pointer
	rempty_val <= '1' when rgray_next = rq2_wptr else '0';

	-- registered empty flag
	process (rclk, rrst_n) is
	begin
		if rrst_n = '0' then
			rempty_reg <= '1';
		elsif rising_edge(rclk) then
			rempty_reg <= rempty_val;
		end if;
	end process;

	raddr  <= std_logic_vector(rbin(addr_width - 1 downto 0));
	rptr   <= rgray;
	rempty <= rempty_reg;

end architecture rtl;

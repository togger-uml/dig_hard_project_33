-- wptr_full: write-side pointer logic and full-flag generator.
--
-- Lives entirely in the write (producer) clock domain.  It holds the
-- binary write pointer (one extra bit so we can tell empty apart from
-- full) and exposes a Gray-coded version of that pointer for crossing
-- into the read domain.  Full is detected by comparing the next-state
-- write Gray pointer against the synchronized read Gray pointer using
-- the standard Cummings condition: the two MSBs differ and the rest
-- match.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity wptr_full is
	generic (
		addr_width:	positive := 4
	);
	port (
		wclk:		in	std_logic;
		wrst_n:		in	std_logic;
		winc:		in	std_logic;
		wq2_rptr:	in	std_logic_vector(addr_width downto 0);
		waddr:		out	std_logic_vector(addr_width - 1 downto 0);
		wptr:		out	std_logic_vector(addr_width downto 0);
		wfull:		out	std_logic
	);
end entity wptr_full;

architecture rtl of wptr_full is
	signal wbin, wbin_next:		unsigned(addr_width downto 0);
	signal wgray, wgray_next:	std_logic_vector(addr_width downto 0);
	signal wfull_val:			std_logic;
	signal wfull_reg:			std_logic;
begin

	-- next-state binary write pointer.  Gate the increment on the
	-- *registered* full flag, not the combinational wfull_val: gating
	-- on wfull_val creates a combinational loop
	-- (wbin_next -> wgray_next -> wfull_val -> wbin_next) that Quartus
	-- flagged with warning 332125 and which synthesises to unreliable
	-- hardware.  Using the registered signal matches the Cummings
	-- async-FIFO reference (assign wbinnext = wbin + (winc & ~wfull))
	-- and is functionally correct because wfull_reg already reflects
	-- the post-flop full status the producer must observe.
	wbin_next <= wbin + 1 when (winc = '1') and (wfull_reg = '0') else wbin;

	-- binary-to-Gray on the next-state pointer
	wgray_next(addr_width) <= wbin_next(addr_width);
	gray_gen: for i in addr_width - 1 downto 0 generate
		wgray_next(i) <= wbin_next(i + 1) xor wbin_next(i);
	end generate gray_gen;

	-- registered pointers
	process (wclk, wrst_n) is
	begin
		if wrst_n = '0' then
			wbin  <= (others => '0');
			wgray <= (others => '0');
		elsif rising_edge(wclk) then
			wbin  <= wbin_next;
			wgray <= wgray_next;
		end if;
	end process;

	-- full when next-state Gray write pointer equals synchronized Gray
	-- read pointer with the top two bits inverted.  This is the
	-- Cummings full-detection comparison.
	wfull_val <= '1' when wgray_next = (
			(not wq2_rptr(addr_width)) &
			(not wq2_rptr(addr_width - 1)) &
			wq2_rptr(addr_width - 2 downto 0)
		) else '0';

	-- registered full output to break the comparator combinational path
	process (wclk, wrst_n) is
	begin
		if wrst_n = '0' then
			wfull_reg <= '0';
		elsif rising_edge(wclk) then
			wfull_reg <= wfull_val;
		end if;
	end process;

	waddr <= std_logic_vector(wbin(addr_width - 1 downto 0));
	wptr  <= wgray;
	wfull <= wfull_reg;

end architecture rtl;

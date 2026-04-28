-- async_fifo: top-level asynchronous FIFO synchronizer.
--
-- This is the structural composition of the four pieces described in
-- Cummings' "Clock Domain Crossing (CDC) Design & Verification
-- Techniques Using SystemVerilog":
--
--   * fifo_mem    -- dual-clock RAM
--   * wptr_full   -- write-side pointer + full flag (in wclk domain)
--   * rptr_empty  -- read-side pointer + empty flag (in rclk domain)
--   * sync_2ff    -- two-flop synchronizers carrying the Gray-coded
--                    pointers across the clock boundary
--
-- The pointer width is one bit wider than the address width so that
-- the wrap-around is encoded; full and empty are then distinguishable
-- because in the full case the MSBs differ while in the empty case
-- the entire pointer matches.

library ieee;
use ieee.std_logic_1164.all;

entity async_fifo is
	generic (
		data_width:	positive := 12;
		addr_width:	positive := 4		-- depth = 2**addr_width
	);
	port (
		-- write (producer) side
		wclk:		in	std_logic;
		wrst_n:		in	std_logic;
		winc:		in	std_logic;
		wdata:		in	std_logic_vector(data_width - 1 downto 0);
		wfull:		out	std_logic;

		-- read (consumer) side
		rclk:		in	std_logic;
		rrst_n:		in	std_logic;
		rinc:		in	std_logic;
		rdata:		out	std_logic_vector(data_width - 1 downto 0);
		rempty:		out	std_logic
	);
end entity async_fifo;

architecture rtl of async_fifo is

	component sync_2ff is
		generic (width: positive := 1);
		port (
			clk:	in	std_logic;
			rst_n:	in	std_logic;
			d:		in	std_logic_vector(width - 1 downto 0);
			q:		out	std_logic_vector(width - 1 downto 0)
		);
	end component sync_2ff;

	component fifo_mem is
		generic (
			data_width:	positive := 12;
			addr_width:	positive := 4
		);
		port (
			wclk:	in	std_logic;
			winc:	in	std_logic;
			wfull:	in	std_logic;
			waddr:	in	std_logic_vector(addr_width - 1 downto 0);
			raddr:	in	std_logic_vector(addr_width - 1 downto 0);
			wdata:	in	std_logic_vector(data_width - 1 downto 0);
			rdata:	out	std_logic_vector(data_width - 1 downto 0)
		);
	end component fifo_mem;

	component wptr_full is
		generic (addr_width: positive := 4);
		port (
			wclk:		in	std_logic;
			wrst_n:		in	std_logic;
			winc:		in	std_logic;
			wq2_rptr:	in	std_logic_vector(addr_width downto 0);
			waddr:		out	std_logic_vector(addr_width - 1 downto 0);
			wptr:		out	std_logic_vector(addr_width downto 0);
			wfull:		out	std_logic
		);
	end component wptr_full;

	component rptr_empty is
		generic (addr_width: positive := 4);
		port (
			rclk:		in	std_logic;
			rrst_n:		in	std_logic;
			rinc:		in	std_logic;
			rq2_wptr:	in	std_logic_vector(addr_width downto 0);
			raddr:		out	std_logic_vector(addr_width - 1 downto 0);
			rptr:		out	std_logic_vector(addr_width downto 0);
			rempty:		out	std_logic
		);
	end component rptr_empty;

	signal waddr, raddr:		std_logic_vector(addr_width - 1 downto 0);
	signal wptr_g, rptr_g:		std_logic_vector(addr_width downto 0);
	signal wq2_rptr, rq2_wptr:	std_logic_vector(addr_width downto 0);
	signal wfull_int, rempty_int: std_logic;

begin

	-- synchronize the read-side Gray pointer into the write clock domain
	r2w_sync: sync_2ff
		generic map (width => addr_width + 1)
		port map (
			clk   => wclk,
			rst_n => wrst_n,
			d     => rptr_g,
			q     => wq2_rptr
		);

	-- synchronize the write-side Gray pointer into the read clock domain
	w2r_sync: sync_2ff
		generic map (width => addr_width + 1)
		port map (
			clk   => rclk,
			rst_n => rrst_n,
			d     => wptr_g,
			q     => rq2_wptr
		);

	wptr_full_inst: wptr_full
		generic map (addr_width => addr_width)
		port map (
			wclk     => wclk,
			wrst_n   => wrst_n,
			winc     => winc,
			wq2_rptr => wq2_rptr,
			waddr    => waddr,
			wptr     => wptr_g,
			wfull    => wfull_int
		);

	rptr_empty_inst: rptr_empty
		generic map (addr_width => addr_width)
		port map (
			rclk     => rclk,
			rrst_n   => rrst_n,
			rinc     => rinc,
			rq2_wptr => rq2_wptr,
			raddr    => raddr,
			rptr     => rptr_g,
			rempty   => rempty_int
		);

	mem_inst: fifo_mem
		generic map (
			data_width => data_width,
			addr_width => addr_width
		)
		port map (
			wclk  => wclk,
			winc  => winc,
			wfull => wfull_int,
			waddr => waddr,
			raddr => raddr,
			wdata => wdata,
			rdata => rdata
		);

	wfull  <= wfull_int;
	rempty <= rempty_int;

end architecture rtl;

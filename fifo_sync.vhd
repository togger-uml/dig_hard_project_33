library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Asynchronous FIFO for clock-domain crossing.
--
-- The write clock (wclk) and read clock (rclk) may be completely
-- unrelated in frequency and phase.  Pointer synchronisation is
-- performed using Gray-coded counters passed through a two-flop
-- synchroniser in the opposite clock domain, following the
-- methodology described in Clifford E. Cummings, "Clock Domain
-- Crossing (CDC) Design & Verification Techniques Using
-- SystemVerilog", SNUG 2008.
--
-- Generic parameters:
--   data_width – width of each data word (default 12 for ADC)
--   addr_width – log2 of FIFO depth (depth = 2^addr_width)
--
-- Full  flag is generated in the write clock domain.
-- Empty flag is generated in the read  clock domain.

entity fifo_sync is
	generic (
		data_width	: positive := 12;
		addr_width	: positive := 4
	);
	port (
		-- Write clock domain
		wclk	: in	std_logic;
		wrst_n	: in	std_logic;
		wen		: in	std_logic;
		wdata	: in	std_logic_vector(data_width - 1 downto 0);
		wfull	: out	std_logic;

		-- Read clock domain
		rclk	: in	std_logic;
		rrst_n	: in	std_logic;
		ren		: in	std_logic;
		rdata	: out	std_logic_vector(data_width - 1 downto 0);
		rempty	: out	std_logic
	);
end entity fifo_sync;

architecture rtl of fifo_sync is

	constant DEPTH : positive := 2 ** addr_width;

	-- Dual-port FIFO memory
	type mem_t is array (0 to DEPTH - 1) of std_logic_vector(data_width - 1 downto 0);
	signal mem : mem_t := (others => (others => '0'));

	-- Write-domain pointer (addr_width+1 bits; MSB is the wrap bit)
	signal wptr		: unsigned(addr_width downto 0) := (others => '0');
	signal wptr_gray	: std_logic_vector(addr_width downto 0) := (others => '0');

	-- Read pointer Gray code synchronised into write clock domain (2-stage)
	signal rptr_gray_s1, rptr_gray_s2 : std_logic_vector(addr_width downto 0) := (others => '0');

	-- Read-domain pointer
	signal rptr		: unsigned(addr_width downto 0) := (others => '0');
	signal rptr_gray	: std_logic_vector(addr_width downto 0) := (others => '0');

	-- Write pointer Gray code synchronised into read clock domain (2-stage)
	signal wptr_gray_s1, wptr_gray_s2 : std_logic_vector(addr_width downto 0) := (others => '0');

	signal wfull_i	: std_logic;
	signal rempty_i	: std_logic;

	-- Binary-to-Gray conversion
	function to_gray(bin : unsigned) return std_logic_vector is
		variable b : std_logic_vector(bin'length - 1 downto 0);
	begin
		b := std_logic_vector(bin);
		return b xor ('0' & b(b'high downto 1));
	end function to_gray;

begin

	-- Convert write and read binary pointers to Gray code
	wptr_gray <= to_gray(wptr);
	rptr_gray <= to_gray(rptr);

	-- 2-flop synchroniser: write pointer Gray → read clock domain
	sync_wptr: process(rclk, rrst_n)
	begin
		if rrst_n = '0' then
			wptr_gray_s1 <= (others => '0');
			wptr_gray_s2 <= (others => '0');
		elsif rising_edge(rclk) then
			wptr_gray_s1 <= wptr_gray;
			wptr_gray_s2 <= wptr_gray_s1;
		end if;
	end process sync_wptr;

	-- 2-flop synchroniser: read pointer Gray → write clock domain
	sync_rptr: process(wclk, wrst_n)
	begin
		if wrst_n = '0' then
			rptr_gray_s1 <= (others => '0');
			rptr_gray_s2 <= (others => '0');
		elsif rising_edge(wclk) then
			rptr_gray_s1 <= rptr_gray;
			rptr_gray_s2 <= rptr_gray_s1;
		end if;
	end process sync_rptr;

	-- FIFO write logic (write clock domain)
	write_proc: process(wclk, wrst_n)
	begin
		if wrst_n = '0' then
			wptr <= (others => '0');
		elsif rising_edge(wclk) then
			if wen = '1' and wfull_i = '0' then
				mem(to_integer(wptr(addr_width - 1 downto 0))) <= wdata;
				wptr <= wptr + 1;
			end if;
		end if;
	end process write_proc;

	-- Full flag (write clock domain):
	-- The FIFO is full when the write pointer has wrapped one extra time
	-- relative to the read pointer.  In Gray code this manifests as the
	-- top two bits of wptr_gray being the bitwise inverse of the
	-- corresponding bits of the synchronised rptr_gray, while the
	-- remaining lower bits are identical.
	wfull_i <= '1' when (
		wptr_gray(addr_width)     /= rptr_gray_s2(addr_width)     and
		wptr_gray(addr_width - 1) /= rptr_gray_s2(addr_width - 1) and
		wptr_gray(addr_width - 2 downto 0) = rptr_gray_s2(addr_width - 2 downto 0)
	) else '0';
	wfull <= wfull_i;

	-- FIFO read logic (read clock domain)
	read_proc: process(rclk, rrst_n)
	begin
		if rrst_n = '0' then
			rptr <= (others => '0');
		elsif rising_edge(rclk) then
			if ren = '1' and rempty_i = '0' then
				rptr <= rptr + 1;
			end if;
		end if;
	end process read_proc;

	-- Asynchronous read data: the output word is available
	-- combinatorially from the current read pointer address.
	rdata <= mem(to_integer(rptr(addr_width - 1 downto 0)));

	-- Empty flag (read clock domain):
	-- The FIFO is empty when both pointers (in Gray code) are equal.
	rempty_i <= '1' when rptr_gray = wptr_gray_s2 else '0';
	rempty   <= rempty_i;

end architecture rtl;

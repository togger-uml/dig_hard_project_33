-- fifo_mem: dual-clock RAM used as the storage backing of the async FIFO.
--
-- Writes happen on wclk when winc is asserted and the FIFO is not full.
-- Reads are combinational on the read pointer.  This is the classic
-- "asynchronous FIFO" memory described in Cummings: a small register
-- file inferred as distributed memory.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo_mem is
	generic (
		data_width:		positive := 12;
		addr_width:		positive := 4		-- depth = 2**addr_width
	);
	port (
		wclk:		in	std_logic;
		winc:		in	std_logic;
		wfull:		in	std_logic;
		waddr:		in	std_logic_vector(addr_width - 1 downto 0);
		raddr:		in	std_logic_vector(addr_width - 1 downto 0);
		wdata:		in	std_logic_vector(data_width - 1 downto 0);
		rdata:		out	std_logic_vector(data_width - 1 downto 0)
	);
end entity fifo_mem;

architecture rtl of fifo_mem is
	type mem_t is array (0 to 2**addr_width - 1)
		of std_logic_vector(data_width - 1 downto 0);
	-- No explicit initializer: an init value would cause Quartus to emit
	-- memory-initialization data, which on MAX 10 requires the project's
	-- internal configuration mode to be one of the "with Memory
	-- Initialization" variants (else Assembler error 14703).  The FIFO
	-- never reads a location before it has been written -- wptr_full /
	-- rptr_empty enforce that -- so leaving mem uninitialized is safe.
	signal mem: mem_t;
begin

	-- write port: synchronous on wclk
	process (wclk) is
	begin
		if rising_edge(wclk) then
			if (winc = '1') and (wfull = '0') then
				mem(to_integer(unsigned(waddr))) <= wdata;
			end if;
		end if;
	end process;

	-- read port: combinational read of the addressed location.  The
	-- consumer registers this externally on rclk via the FIFO output.
	rdata <= mem(to_integer(unsigned(raddr)));

end architecture rtl;

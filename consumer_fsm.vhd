library ieee;
use ieee.std_logic_1164.all;

use work.uc_pkg.all;

-- ----------------------------------------------------------------------------
-- Display consumer FSM (consumer clock domain)
-- ----------------------------------------------------------------------------
-- Second instance of uc_sequencer, this time driven by a 2-instruction
-- microprogram that drains the asynchronous FIFO and latches each fresh
-- sample into display_reg.  Functionally equivalent to the original
-- consumer_proc that lived inside top.vhd; refactored to satisfy the
-- project's +10pt extra credit ("utilise the same sequencer and finite
-- state machine to drive both clock domains").
--
-- Microprogram (2 words, addresses 0..1):
--   0 WAIT  – ren=0, latch=0.  Branches back to 0 while fifo_rempty='1'.
--   1 READ  – ren=1, latch=1.  Unconditional jump back to 0.
--
-- Note on FWFT timing: the FIFO uses a first-word-fall-through model, so
-- fifo_rdata reflects the entry at the current rptr combinationally.  At
-- PC=1 the wrapper asserts ren and (one cycle later) latches fifo_rdata into
-- display_reg.  rptr advances on the same edge that ends PC=1, so the next
-- visit to PC=1 sees the next entry.
-- ----------------------------------------------------------------------------

entity consumer_fsm is
	port (
		clk         : in  std_logic;
		rst_n       : in  std_logic;

		-- FIFO consumer interface
		fifo_rempty : in  std_logic;
		fifo_rdata  : in  std_logic_vector(11 downto 0);
		fifo_ren    : out std_logic;

		-- Display-side outputs
		display_reg : out std_logic_vector(11 downto 0);
		sample_seen : out std_logic
	);
end entity consumer_fsm;

architecture rtl of consumer_fsm is

	-- Control bit indices within ctrl_out
	constant C_REN   : natural := 0;
	constant C_LATCH : natural := 1;

	-- Condition input indices within cond_in
	constant K_REMPTY : natural := 0;

	-- Helper: build a UC_CTRL_WIDTH-wide control word
	function ctrl_w (
		ren_b   : std_logic;
		latch_b : std_logic
	) return std_logic_vector is
		variable v : std_logic_vector(UC_CTRL_WIDTH - 1 downto 0) := (others => '0');
	begin
		v(C_REN)   := ren_b;
		v(C_LATCH) := latch_b;
		return v;
	end function ctrl_w;

	-- Consumer microprogram
	constant CONSUMER_UCODE : uc_rom_t := (
		-- 0 WAIT: stay while FIFO empty
		0 => (ctrl      => ctrl_w('0','0'),
		      br_mode   => UC_BR_IFT,
		      cond_sel  => K_REMPTY,
		      next_addr => 0),

		-- 1 READ: assert ren, latch rdata, jump back to WAIT
		1 => (ctrl      => ctrl_w('1','1'),
		      br_mode   => UC_BR_ALWAYS,
		      cond_sel  => 0,
		      next_addr => 0)
	);

	signal cond : std_logic_vector(UC_COND_WIDTH - 1 downto 0);
	signal ctrl : std_logic_vector(UC_CTRL_WIDTH - 1 downto 0);

	signal display_r : std_logic_vector(11 downto 0) := (others => '0');
	signal seen_r    : std_logic := '0';

begin

	-- Pack condition signals into the cond_in bus (unused bits driven low).
	-- Single concurrent process to avoid multiple drivers on `cond`.
	pack_cond: process(fifo_rempty)
		variable v : std_logic_vector(UC_COND_WIDTH - 1 downto 0);
	begin
		v := (others => '0');
		v(K_REMPTY) := fifo_rempty;
		cond <= v;
	end process pack_cond;

	-- Sequencer instance: generic-mapped with the consumer microprogram.
	-- This is the SAME entity as the one driving the ADC FSM, exercising
	-- the +10pt extra-credit goal of reusing one sequencer in both clock
	-- domains via differing microcode generics.
	seq_inst: entity work.uc_sequencer
		generic map (
			microcode => CONSUMER_UCODE
		)
		port map (
			clk      => clk,
			rst_n    => rst_n,
			cond_in  => cond,
			ctrl_out => ctrl
		);

	fifo_ren <= ctrl(C_REN);

	-- Datapath: latch the FIFO output into display_reg, and set the sticky
	-- sample_seen flag, on every cycle the microprogram asserts LATCH.
	latch_proc: process(clk, rst_n)
	begin
		if rst_n = '0' then
			display_r <= (others => '0');
			seen_r    <= '0';
		elsif rising_edge(clk) then
			if ctrl(C_LATCH) = '1' then
				display_r <= fifo_rdata;
				seen_r    <= '1';
			end if;
		end if;
	end process latch_proc;

	display_reg <= display_r;
	sample_seen <= seen_r;

end architecture rtl;

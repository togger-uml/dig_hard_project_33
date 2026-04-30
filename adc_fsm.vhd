library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.uc_pkg.all;

-- ----------------------------------------------------------------------------
-- ADC control FSM (producer clock domain)
-- ----------------------------------------------------------------------------
-- Implemented as a microcoded controller: a generic uc_sequencer running a
-- 5-instruction microprogram, plus a small datapath wrapper that latches the
-- ADC result into the FIFO write-data register.  The original hand-coded 4-
-- state FSM (IDLE / SOC_HIGH / WAIT_EOC / STORE) is preserved functionally,
-- with STORE split into two micro-cycles (LATCH then WRITE) so that the FIFO
-- captures stable, freshly-latched data on the cycle wen is asserted.
--
-- This is the project's +15pt extra credit (microcoded ADC driver).  The
-- entity port map is unchanged from the original, so top.vhd needs no edit.
--
-- Microprogram (5 words, addresses 0..4):
--   0 IDLE   – wait for FIFO room.  Branches back to 0 while fifo_full='1'.
--   1 SOC    – assert SOC for one cycle.
--   2 WAIT   – wait for end-of-conversion.  Branches back to 2 while eoc='0'.
--   3 LATCH  – capture dout into the fifo_data register.
--   4 WRITE  – assert FIFO wen with the latched value, then jump to 0.
-- ----------------------------------------------------------------------------

entity adc_fsm is
	port (
		clk			: in	std_logic;
		rst_n		: in	std_logic;

		-- MAX10 ADC interface
		soc			: out	std_logic;
		eoc			: in	std_logic;
		dout		: in	natural range 0 to 2**12 - 1;
		tsen		: out	std_logic;

		-- FIFO producer interface
		fifo_data	: out	std_logic_vector(11 downto 0);
		fifo_wen	: out	std_logic;
		fifo_full	: in	std_logic
	);
end entity adc_fsm;

architecture rtl of adc_fsm is

	-- Control bit indices within ctrl_out (matches uc_pkg.UC_CTRL_WIDTH).
	constant C_SOC        : natural := 0;
	constant C_WEN        : natural := 1;
	constant C_LATCH_DOUT : natural := 2;

	-- Condition input indices within cond_in (matches uc_pkg.UC_COND_WIDTH).
	constant K_FULL : natural := 0;   -- fifo_full
	constant K_EOC  : natural := 1;   -- eoc

	-- Helper: build a UC_CTRL_WIDTH-wide control word from named bits.
	-- Keeps the microprogram literal below readable.
	function ctrl_w (
		soc_b   : std_logic;
		wen_b   : std_logic;
		latch_b : std_logic
	) return std_logic_vector is
		variable v : std_logic_vector(UC_CTRL_WIDTH - 1 downto 0) := (others => '0');
	begin
		v(C_SOC)        := soc_b;
		v(C_WEN)        := wen_b;
		v(C_LATCH_DOUT) := latch_b;
		return v;
	end function ctrl_w;

	-- ADC microprogram
	constant ADC_UCODE : uc_rom_t := (
		-- 0 IDLE: stay while FIFO full
		0 => (ctrl      => ctrl_w('0','0','0'),
		      br_mode   => UC_BR_IFT,
		      cond_sel  => K_FULL,
		      next_addr => 0),

		-- 1 SOC: assert start-of-conversion for one cycle
		1 => (ctrl      => ctrl_w('1','0','0'),
		      br_mode   => UC_BR_NEVER,
		      cond_sel  => 0,
		      next_addr => 0),

		-- 2 WAIT: wait for eoc (stay while eoc='0')
		2 => (ctrl      => ctrl_w('0','0','0'),
		      br_mode   => UC_BR_IFF,
		      cond_sel  => K_EOC,
		      next_addr => 2),

		-- 3 LATCH: capture dout into fifo_data register
		3 => (ctrl      => ctrl_w('0','0','1'),
		      br_mode   => UC_BR_NEVER,
		      cond_sel  => 0,
		      next_addr => 0),

		-- 4 WRITE: assert wen with the latched data, jump back to IDLE
		4 => (ctrl      => ctrl_w('0','1','0'),
		      br_mode   => UC_BR_ALWAYS,
		      cond_sel  => 0,
		      next_addr => 0)
	);

	signal cond : std_logic_vector(UC_COND_WIDTH - 1 downto 0);
	signal ctrl : std_logic_vector(UC_CTRL_WIDTH - 1 downto 0);

	signal fifo_data_reg : std_logic_vector(11 downto 0) := (others => '0');

begin

	-- Temperature-sensing mode is permanently enabled
	tsen <= '1';

	-- Pack condition signals into the cond_in bus (unused bits driven low).
	-- Single concurrent process to avoid multiple drivers on `cond`.
	pack_cond: process(fifo_full, eoc)
		variable v : std_logic_vector(UC_COND_WIDTH - 1 downto 0);
	begin
		v := (others => '0');
		v(K_FULL) := fifo_full;
		v(K_EOC)  := eoc;
		cond <= v;
	end process pack_cond;

	-- Sequencer instance: generic-mapped with the ADC microprogram
	seq_inst: entity work.uc_sequencer
		generic map (
			microcode => ADC_UCODE
		)
		port map (
			clk      => clk,
			rst_n    => rst_n,
			cond_in  => cond,
			ctrl_out => ctrl
		);

	-- Decode control bus into FSM outputs.  ctrl is a combinational function
	-- of the sequencer's PC register, so soc / fifo_wen are effectively
	-- registered (matching the timing of the original hand-coded FSM).
	soc      <= ctrl(C_SOC);
	fifo_wen <= ctrl(C_WEN);

	-- Datapath: latch the current ADC result into fifo_data_reg whenever the
	-- microprogram asserts the LATCH_DOUT control bit (i.e. at PC=3).  The
	-- next micro-cycle (PC=4) asserts wen with this stable value present on
	-- fifo_data, ensuring the FIFO captures correct write data.
	dout_latch: process(clk, rst_n)
	begin
		if rst_n = '0' then
			fifo_data_reg <= (others => '0');
		elsif rising_edge(clk) then
			if ctrl(C_LATCH_DOUT) = '1' then
				fifo_data_reg <= std_logic_vector(to_unsigned(dout, 12));
			end if;
		end if;
	end process dout_latch;

	fifo_data <= fifo_data_reg;

end architecture rtl;

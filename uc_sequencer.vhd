library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.uc_pkg.all;

-- ----------------------------------------------------------------------------
-- Generic microcoded sequencer
-- ----------------------------------------------------------------------------
-- A tiny Moore-style controller driven by a microprogram passed in as a
-- generic.  Each clock the sequencer:
--   1. drives ctrl_out from the current microinstruction's ctrl field
--   2. evaluates the branch condition against cond_in
--   3. updates PC to either next_addr (branch taken) or PC+1 (sequential)
--
-- The same entity is instantiated in both the ADC producer domain
-- (adc_fsm.vhd) and the display consumer domain (consumer_fsm.vhd); each
-- instance receives its own microcode via the `microcode` generic.  This is
-- the reusable driver required by the project's +10pt extra credit.
-- ----------------------------------------------------------------------------

entity uc_sequencer is
	generic (
		microcode : uc_rom_t
	);
	port (
		clk      : in  std_logic;
		rst_n    : in  std_logic;
		cond_in  : in  std_logic_vector(UC_COND_WIDTH - 1 downto 0);
		ctrl_out : out std_logic_vector(UC_CTRL_WIDTH - 1 downto 0)
	);
end entity uc_sequencer;

architecture rtl of uc_sequencer is

	signal pc : natural range microcode'low to microcode'high := microcode'low;

begin

	-- Moore output: ctrl bus reflects the word at the current PC
	ctrl_out <= microcode(pc).ctrl;

	-- Sequencer next-PC logic
	seq: process(clk, rst_n)
		variable cur   : uc_word_t;
		variable cond  : std_logic;
		variable taken : boolean;
	begin
		if rst_n = '0' then
			pc <= microcode'low;
		elsif rising_edge(clk) then
			cur  := microcode(pc);
			cond := cond_in(cur.cond_sel);

			case cur.br_mode is
				when UC_BR_NEVER  => taken := false;
				when UC_BR_IFT    => taken := (cond = '1');
				when UC_BR_IFF    => taken := (cond = '0');
				when UC_BR_ALWAYS => taken := true;
				when others       => taken := false;
			end case;

			if taken then
				pc <= cur.next_addr;
			elsif pc < microcode'high then
				pc <= pc + 1;
			else
				-- Falling off the end without a branch is a microprogram
				-- bug; wrap to the start so the design stays well-defined.
				pc <= microcode'low;
			end if;
		end if;
	end process seq;

end architecture rtl;

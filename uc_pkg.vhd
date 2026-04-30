library ieee;
use ieee.std_logic_1164.all;

-- ----------------------------------------------------------------------------
-- Microcode package
-- ----------------------------------------------------------------------------
-- Defines the microinstruction format and ROM array type used by the generic
-- uc_sequencer.  Each microinstruction is a Moore-style record:
--   ctrl      – control output bits asserted while PC = this address
--   br_mode   – branch mode (none / on cond=1 / on cond=0 / unconditional)
--   cond_sel  – which bit of cond_in to test when branching conditionally
--   next_addr – branch target (used when br_mode triggers a jump)
--
-- The sequencer always advances PC <= PC+1 unless the branch fires, in which
-- case PC <= next_addr.  Maximum widths are fixed (one superset format) so
-- the same sequencer entity can be reused across instances; an instance ties
-- unused condition bits low and ignores unused control bits.
-- ----------------------------------------------------------------------------

package uc_pkg is

	-- Bus widths shared by every sequencer instance.  These are sized to
	-- comfortably fit the two FSMs in this project (ADC producer + display
	-- consumer); enlarge if a future microprogram needs more.
	constant UC_ADDR_WIDTH : positive := 4;     -- up to 16 microinstructions
	constant UC_COND_WIDTH : positive := 4;     -- up to 4 condition inputs
	constant UC_CTRL_WIDTH : positive := 8;     -- up to 8 control outputs

	-- Branch mode encoding
	subtype uc_brmode_t is std_logic_vector(1 downto 0);
	constant UC_BR_NEVER  : uc_brmode_t := "00"; -- always sequential (PC+1)
	constant UC_BR_IFT    : uc_brmode_t := "01"; -- branch if cond_in(sel) = '1'
	constant UC_BR_IFF    : uc_brmode_t := "10"; -- branch if cond_in(sel) = '0'
	constant UC_BR_ALWAYS : uc_brmode_t := "11"; -- unconditional jump

	type uc_word_t is record
		ctrl      : std_logic_vector(UC_CTRL_WIDTH - 1 downto 0);
		br_mode   : uc_brmode_t;
		cond_sel  : natural range 0 to UC_COND_WIDTH - 1;
		next_addr : natural range 0 to 2**UC_ADDR_WIDTH - 1;
	end record uc_word_t;

	type uc_rom_t is array (natural range <>) of uc_word_t;

end package uc_pkg;

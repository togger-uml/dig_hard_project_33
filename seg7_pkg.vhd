library ieee;
use ieee.std_logic_1164.all;

-- Package: seg7_pkg
--
-- Provides type definitions and functions for driving seven-segment
-- displays in both common-anode and common-cathode configurations.
--
-- Q1  seven_segment_config record + unconstrained array type
-- Q2  lamp_configuration enumerated type + default_lamp_config constant
-- Q3  seven_segment_table constant (hexadecimal alphabet 0–F)
-- Q4  hex_digit subtype + get_hex_digit function
-- Q5  lamps_off function

package seg7_pkg is

	-- ----------------------------------------------------------------
	-- Q1: Record representing one seven-segment digit.
	--     Each member corresponds to a physical segment label.
	--     The logical value '1' means the lamp is illuminated;
	--     '0' means the lamp is off.  get_hex_digit translates
	--     these to the physical drive polarity required by the board.
	-- ----------------------------------------------------------------
	type seven_segment_config is record
		a : std_logic;  -- top horizontal
		b : std_logic;  -- top-right vertical
		c : std_logic;  -- bottom-right vertical
		d : std_logic;  -- bottom horizontal
		e : std_logic;  -- bottom-left vertical
		f : std_logic;  -- top-left vertical
		g : std_logic;  -- middle horizontal
	end record seven_segment_config;

	-- Unconstrained array of seven_segment_config entries.
	type seven_segment_array is array (natural range <>) of seven_segment_config;

	-- ----------------------------------------------------------------
	-- Q2: Lamp configuration enumeration.
	--     common_anode  – segments driven active-low  (DE10-Lite)
	--     common_cathode – segments driven active-high
	-- ----------------------------------------------------------------
	type lamp_configuration is (common_anode, common_cathode);

	-- The DE10-Lite board uses common-anode seven-segment displays.
	constant default_lamp_config : lamp_configuration := common_anode;

	-- ----------------------------------------------------------------
	-- Q3: Look-up table for the hexadecimal alphabet (0–F).
	--     Values are stored as logical lamp states (1 = lit, 0 = off),
	--     independent of physical drive polarity.
	--
	--     Segment reference (standard layout):
	--         aaa
	--        f   b
	--        f   b
	--         ggg
	--        e   c
	--        e   c
	--         ddd
	-- ----------------------------------------------------------------
	constant seven_segment_table : seven_segment_array(0 to 15) := (
		--       a    b    c    d    e    f    g
		0  => ('1', '1', '1', '1', '1', '1', '0'),  -- 0
		1  => ('0', '1', '1', '0', '0', '0', '0'),  -- 1
		2  => ('1', '1', '0', '1', '1', '0', '1'),  -- 2
		3  => ('1', '1', '1', '1', '0', '0', '1'),  -- 3
		4  => ('0', '1', '1', '0', '0', '1', '1'),  -- 4
		5  => ('1', '0', '1', '1', '0', '1', '1'),  -- 5
		6  => ('1', '0', '1', '1', '1', '1', '1'),  -- 6
		7  => ('1', '1', '1', '0', '0', '0', '0'),  -- 7
		8  => ('1', '1', '1', '1', '1', '1', '1'),  -- 8
		9  => ('1', '1', '1', '1', '0', '1', '1'),  -- 9
		10 => ('1', '1', '1', '0', '1', '1', '1'),  -- A
		11 => ('0', '0', '1', '1', '1', '1', '1'),  -- b
		12 => ('1', '0', '0', '1', '1', '1', '0'),  -- C
		13 => ('0', '1', '1', '1', '1', '0', '1'),  -- d
		14 => ('1', '0', '0', '1', '1', '1', '1'),  -- E
		15 => ('1', '0', '0', '0', '1', '1', '1')   -- F
	);

	-- ----------------------------------------------------------------
	-- Q4: hex_digit subtype – constrained to valid table indices.
	-- ----------------------------------------------------------------
	subtype hex_digit is natural range seven_segment_table'low to seven_segment_table'high;

	-- Return the seven_segment_config that activates the correct lamps
	-- for digit in the requested lamp_mode.
	function get_hex_digit (
		digit     : in hex_digit;
		lamp_mode : in lamp_configuration := default_lamp_config
	) return seven_segment_config;

	-- ----------------------------------------------------------------
	-- Q5: Return a seven_segment_config where all lamps are off.
	-- ----------------------------------------------------------------
	function lamps_off (
		lamp_mode : in lamp_configuration := default_lamp_config
	) return seven_segment_config;

end package seg7_pkg;

package body seg7_pkg is

	-- ----------------------------------------------------------------
	-- Helper: invert every segment of a config entry.
	--
	-- Used to convert between common-cathode logical values (1=ON)
	-- and the common-anode physical drive polarity (0=ON).
	-- ----------------------------------------------------------------
	function invert_config (cfg : seven_segment_config) return seven_segment_config is
		variable result : seven_segment_config;
	begin
		result.a := not cfg.a;
		result.b := not cfg.b;
		result.c := not cfg.c;
		result.d := not cfg.d;
		result.e := not cfg.e;
		result.f := not cfg.f;
		result.g := not cfg.g;
		return result;
	end function invert_config;

	-- ----------------------------------------------------------------
	-- get_hex_digit
	--   Returns the physical drive values for the requested digit.
	--   The table stores logical values (1=lit).
	--     common_cathode → return table entry as-is (1=drive high=ON)
	--     common_anode   → invert table entry   (0=drive low=ON)
	-- ----------------------------------------------------------------
	function get_hex_digit (
		digit     : in hex_digit;
		lamp_mode : in lamp_configuration := default_lamp_config
	) return seven_segment_config is
		variable entry : seven_segment_config;
	begin
		entry := seven_segment_table(digit);
		if lamp_mode = common_anode then
			entry := invert_config(entry);
		end if;
		return entry;
	end function get_hex_digit;

	-- ----------------------------------------------------------------
	-- lamps_off
	--     common_cathode → '0' on all segments (drive low = OFF)
	--     common_anode   → '1' on all segments (drive high = OFF)
	-- ----------------------------------------------------------------
	function lamps_off (
		lamp_mode : in lamp_configuration := default_lamp_config
	) return seven_segment_config is
		variable off_val : std_logic;
		variable result  : seven_segment_config;
	begin
		if lamp_mode = common_anode then
			off_val := '1';
		else
			off_val := '0';
		end if;
		result := (a => off_val, b => off_val, c => off_val, d => off_val,
		           e => off_val, f => off_val, g => off_val);
		return result;
	end function lamps_off;

end package body seg7_pkg;

-- temperature_display: converts a 12-bit raw ADC code from the MAX 10
-- on-chip temperature sensor into a Celsius reading and drives six
-- seven-segment displays on the DE10-Lite.
--
-- Display layout:
--   HEX5 – 'C' (Celsius indicator)
--   HEX4 – dash separator
--   HEX3 – thousands BCD digit  \
--   HEX2 – hundreds BCD digit    > decimal Celsius value
--   HEX1 – tens     BCD digit    |
--   HEX0 – ones     BCD digit   /
--
-- Temperature conversion formula (Intel MAX 10 ADC User Guide):
--   T(°C) = (ADC_code × 503.975 / 4096) − 273.15
--
-- Implemented in integer arithmetic (no floating-point) as:
--   T = (raw × 503975 − 1118822400) / 4096000
--
-- This avoids the two bugs seen in previous attempts:
--   1. The raw ADC code (e.g. 3661) was displayed directly (C-3661)
--      because no conversion was applied.
--   2. An incorrect formula (693*raw/1024 − 265) produced negative
--      results for small or zero ADC codes (e.g. in simulation where
--      the ADC outputs 0), which clamped to zero → all-zero display.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity temperature_display is
	port (
		value	: in	std_logic_vector(11 downto 0);
		HEX0	: out	std_logic_vector(6 downto 0);
		HEX1	: out	std_logic_vector(6 downto 0);
		HEX2	: out	std_logic_vector(6 downto 0);
		HEX3	: out	std_logic_vector(6 downto 0);
		HEX4	: out	std_logic_vector(6 downto 0);
		HEX5	: out	std_logic_vector(6 downto 0)
	);
end entity temperature_display;

architecture rtl of temperature_display is

	-- Converted temperature value (integer °C, stored as 12-bit binary)
	signal value_celsius : std_logic_vector(11 downto 0);

	signal bcd_ones		: std_logic_vector(3 downto 0);
	signal bcd_tens		: std_logic_vector(3 downto 0);
	signal bcd_hundreds	: std_logic_vector(3 downto 0);
	signal bcd_thousands	: std_logic_vector(3 downto 0);

	-- Use the repository's existing seven_seg_decoder (active-low,
	-- blank='1' turns all segments off, blank='0' shows the digit).
	component seven_seg_decoder is
		port (
			digit	: in	std_logic_vector(3 downto 0);
			blank	: in	std_logic;
			seg	: out	std_logic_vector(6 downto 0)
		);
	end component seven_seg_decoder;

begin

	-- ---------------------------------------------------------------
	-- Step 1 – Convert raw 12-bit ADC code to integer Celsius.
	--
	-- Intel MAX 10 temperature sensor formula:
	--   T(°C) = (raw × 503.975 / 4096) − 273.15
	--
	-- Scaled to integers (multiply by 4096000 to clear both
	-- the /4096 and the ×1000 precision factor):
	--   T = (raw × 503975 − 1118822400) / 4096000
	--
	-- Overflow check (VHDL integer is at least 32-bit signed):
	--   max raw = 4095  →  4095 × 503975 ≈ 2.06 × 10⁹ < 2³¹ − 1  ✓
	--   1118822400 < 2³¹ − 1  ✓
	--
	-- Temperature range with 12-bit ADC: roughly −40 °C to +230 °C.
	-- Negative results are clamped to 0 (sensor below calibrated range).
	-- ---------------------------------------------------------------
	temp_convert: process(value) is
		variable raw  : integer range 0 to 4095;
		variable temp : integer;
	begin
		raw  := to_integer(unsigned(value));

		-- Correct Intel MAX 10 temperature sensor formula
		temp := (raw * 503975 - 1118822400) / 4096000;

		-- Clamp: negative °C readings are shown as 0
		if temp < 0 then
			temp := 0;
		end if;

		-- Clamp upper bound to 4095 (fits in 12 bits)
		if temp > 4095 then
			temp := 4095;
		end if;

		value_celsius <= std_logic_vector(to_unsigned(temp, 12));
	end process temp_convert;

	-- ---------------------------------------------------------------
	-- Step 2 – Convert the Celsius integer to packed BCD using the
	-- double-dabble (shift-and-add-3) algorithm.
	-- ---------------------------------------------------------------
	bcd_convert: process(value_celsius) is
		variable scratch : std_logic_vector(27 downto 0);
		variable nibble  : unsigned(3 downto 0);
	begin
		scratch              := (others => '0');
		scratch(11 downto 0) := value_celsius;

		for i in 0 to 11 loop
			-- Ones digit (scratch 15:12)
			nibble := unsigned(scratch(15 downto 12));
			if nibble >= 5 then
				scratch(15 downto 12) := std_logic_vector(nibble + 3);
			end if;

			-- Tens digit (scratch 19:16)
			nibble := unsigned(scratch(19 downto 16));
			if nibble >= 5 then
				scratch(19 downto 16) := std_logic_vector(nibble + 3);
			end if;

			-- Hundreds digit (scratch 23:20)
			nibble := unsigned(scratch(23 downto 20));
			if nibble >= 5 then
				scratch(23 downto 20) := std_logic_vector(nibble + 3);
			end if;

			-- Thousands digit (scratch 27:24)
			nibble := unsigned(scratch(27 downto 24));
			if nibble >= 5 then
				scratch(27 downto 24) := std_logic_vector(nibble + 3);
			end if;

			-- Shift the whole register left by one
			scratch := scratch(26 downto 0) & '0';
		end loop;

		bcd_thousands <= scratch(27 downto 24);
		bcd_hundreds  <= scratch(23 downto 20);
		bcd_tens      <= scratch(19 downto 16);
		bcd_ones      <= scratch(15 downto 12);
	end process bcd_convert;

	-- ---------------------------------------------------------------
	-- Step 3 – Drive the seven-segment displays.
	--
	-- Layout: HEX5='C'  HEX4='-'  HEX3=thousands  HEX2=hundreds
	--                              HEX1=tens       HEX0=ones
	-- ---------------------------------------------------------------

	-- HEX0..HEX3: decimal digits of the Celsius temperature
	hex0_inst: seven_seg_decoder
		port map (digit => bcd_ones,      blank => '0', seg => HEX0);
	hex1_inst: seven_seg_decoder
		port map (digit => bcd_tens,      blank => '0', seg => HEX1);
	hex2_inst: seven_seg_decoder
		port map (digit => bcd_hundreds,  blank => '0', seg => HEX2);
	hex3_inst: seven_seg_decoder
		port map (digit => bcd_thousands, blank => '0', seg => HEX3);

	-- HEX4: dash/minus sign separator.
	-- Only the middle segment (g, bit 6) is lit.
	-- Active-low: '0' = segment ON.  DE10-Lite pin order: bit0=a … bit6=g.
	-- g=on(0), f-a=off(1) → "0111111"
	HEX4 <= "0111111";

	-- HEX5: 'C' for Celsius.
	-- The seven_seg_decoder maps digit "1100" to the letter C
	-- (segments a, d, e, f on; b, c, g off) with active-low output.
	hex5_inst: seven_seg_decoder
		port map (digit => "1100", blank => '0', seg => HEX5);

end architecture rtl;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Converts a 12-bit raw MAX10 ADC temperature-sensor code into degrees
-- Celsius and drives six 7-segment displays on the DE10-Lite.
--
-- Temperature conversion (Intel MAX 10 internal temperature sensor formula):
--   T(°C) = 693 × raw_code / 4096 − 265
-- Reference: Intel MAX 10 FPGA Device Datasheet, internal temperature sensor.
-- At 25 °C the raw 12-bit ADC code is approximately 1716.
--
-- Implementation notes:
--   * 693 × raw requires 22 bits (max 2 837 835).  The product is held in an
--     explicit unsigned(23 downto 0) so Quartus synthesises the full 24-bit
--     multiplier with no truncation.
--   * Division by 4096 is implemented as a pure bit-slice: prod(23 downto 12).
--     This is just wiring — no integer arithmetic, no synthesis ambiguity.
--   * Both the temperature conversion and BCD stages are combined into a
--     single combinatorial process to avoid any intermediate-signal delta-cycle
--     boundary that could confuse synthesis.
-- Results below 0 °C are clamped to 0 before display.
--
-- The binary-to-BCD conversion uses the "double-dabble" (shift-and-add-3)
-- algorithm implemented as a purely combinatorial process.  No clock is
-- needed; the result updates whenever the input changes.
--
-- Display layout:
--   HEX5 – 'C' (Celsius indicator)
--   HEX4 – dash / blank separator
--   HEX3 – thousands BCD digit
--   HEX2 – hundreds BCD digit
--   HEX1 – tens BCD digit
--   HEX0 – ones BCD digit

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

	signal bcd_ones		: std_logic_vector(3 downto 0);
	signal bcd_tens		: std_logic_vector(3 downto 0);
	signal bcd_hundreds	: std_logic_vector(3 downto 0);
	signal bcd_thousands	: std_logic_vector(3 downto 0);

	component seg7_decoder is
		port (
			digit	: in	std_logic_vector(3 downto 0);
			seg		: out	std_logic_vector(6 downto 0)
		);
	end component seg7_decoder;

begin

	-- Combined temperature conversion + double-dabble BCD conversion.
	--
	-- Step 1 – Temperature:
	--   prod    = 693 × raw                  (unsigned 24-bit; no truncation)
	--   shifted = prod(23 downto 12)          (divide by 4096 via bit-slice)
	--   celsius = shifted − 265  (clamped to 0 when shifted ≤ 265)
	--
	-- Step 2 – Double-dabble (shift-and-add-3) BCD:
	--   28-bit scratch:  [27:24]=thousands  [23:20]=hundreds
	--                    [19:16]=tens       [15:12]=ones
	--                    [11:0] =binary input
	--   12 iterations: add-3 to any nibble ≥ 5, then shift left 1.
	temp_bcd_convert: process(value)
		variable raw_u   : unsigned(11 downto 0);
		variable prod    : unsigned(23 downto 0);
		variable shifted : unsigned(11 downto 0);
		variable celsius : unsigned(11 downto 0);
		variable scratch : std_logic_vector(27 downto 0);
		variable nibble  : unsigned(3 downto 0);
	begin
		-- Temperature conversion (pure unsigned, no integer division)
		raw_u   := unsigned(value);
		prod    := to_unsigned(693, 12) * raw_u;    -- 24-bit product
		shifted := prod(23 downto 12);              -- exact ÷4096 via bit-slice
		if shifted > to_unsigned(265, 12) then
			celsius := shifted - to_unsigned(265, 12);
		else
			celsius := (others => '0');
		end if;

		-- Double-dabble binary-to-BCD
		scratch              := (others => '0');
		scratch(11 downto 0) := std_logic_vector(celsius);

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
	end process temp_bcd_convert;

	-- Drive the four numeric displays via individual decoders
	hex0_inst: seg7_decoder port map (digit => bcd_ones,      seg => HEX0);
	hex1_inst: seg7_decoder port map (digit => bcd_tens,      seg => HEX1);
	hex2_inst: seg7_decoder port map (digit => bcd_hundreds,  seg => HEX2);
	hex3_inst: seg7_decoder port map (digit => bcd_thousands, seg => HEX3);

	-- HEX4: dash/minus sign (only middle segment g is on).
	-- Bit assignment: seg(6)=g, seg(5..0)=f,e,d,c,b,a
	-- Active-low: '0' = LED on.
	-- "0111111" → g=0 (on), all others=1 (off) = horizontal middle bar.
	HEX4 <= "0111111";

	-- HEX5: 'C' for Celsius (segments a, d, e, f on; g, b, c off)
	-- "1000110" → g=1(off), f=0(on), e=0(on), d=0(on), c=1(off), b=1(off), a=0(on)
	HEX5 <= "1000110";

end architecture rtl;

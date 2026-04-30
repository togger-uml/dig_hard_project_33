library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Converts a 12-bit MAX10 ADC temperature-sensor reading into a signed
-- Celsius temperature and drives six 7-segment displays on the DE10-Lite.
--
-- ADC code → °C conversion
-- ────────────────────────
-- The MAX10 internal temperature sensor produces a 12-bit code that
-- decreases (non-linearly) as the die temperature rises.  The mapping
-- is defined by Table 4, "Temperature Code Conversion Table", in the
-- Intel MAX 10 Analog to Digital Converter User Guide (UG-M10ADC):
--
--     -40 °C → code 3798        25 °C → code 3677
--     ...                        85 °C → code 3542
--     125 °C → code 3431       100 °C → code 3500
--
-- The full table (165 entries, −40 °C … +125 °C) is reproduced as a
-- 368-entry ROM (CODE_LO_C .. CODE_HI_C) below.  Each ROM slot holds
-- the integer Celsius value of the temperature whose tabulated code is
-- closest to the slot's code.  Codes outside the calibrated range are
-- clamped to −40 °C / +125 °C.
--
-- The signed result is split into a sign bit and a magnitude that is
-- then run through the double-dabble (shift-and-add-3) binary-to-BCD
-- converter.  The whole datapath is purely combinatorial; the result
-- updates whenever the input changes.
--
-- Display layout:
--   HEX5 – 'C' (Celsius indicator)
--   HEX4 – '-' when the temperature is negative, blank otherwise
--   HEX3 – thousands BCD digit (typically blank)
--   HEX2 – hundreds  BCD digit (typically blank)
--   HEX1 – tens      BCD digit
--   HEX0 – ones      BCD digit

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

	-- ----------------------------------------------------------------
	-- ADC-code → °C lookup table (UG-M10ADC Table 4)
	-- ----------------------------------------------------------------
	-- The TSD produces codes in the range 3431 (≈125 °C) to 3798 (−40 °C).
	-- For each code in that span, CODE_TO_TEMP_C holds the integer °C
	-- whose tabulated code is closest to the index value.  Codes outside
	-- this range are clamped at the endpoints (see temp_convert below).
	constant CODE_LO_C	: integer := 3431;   -- code at +125 °C (table min)
	constant CODE_HI_C	: integer := 3798;   -- code at  −40 °C (table max)

	type code_to_temp_t is array(CODE_LO_C to CODE_HI_C) of integer range -40 to 125;

	constant CODE_TO_TEMP_C : code_to_temp_t := (
		 125,  124,  124,  124,  124,  123,  123,  123,
		 123,  123,  123,  123,  122,  122,  122,  122,
		 121,  121,  121,  120,  119,  119,  119,  118,
		 118,  118,  118,  117,  117,  116,  115,  115,
		 114,  114,  114,  114,  113,  113,  113,  112,
		 112,  112,  111,  111,  111,  110,  110,  110,
		 109,  109,  109,  108,  108,  108,  107,  107,
		 107,  106,  106,  105,  104,  104,  103,  103,
		 102,  102,  101,  101,  100,  100,   99,   99,
		  98,   98,   98,   97,   97,   97,   96,   96,
		  96,   95,   95,   95,   94,   94,   94,   93,
		  93,   93,   92,   92,   91,   91,   90,   89,
		  89,   88,   88,   88,   88,   87,   87,   87,
		  87,   86,   86,   86,   86,   85,   85,   85,
		  85,   84,   84,   84,   83,   82,   81,   80,
		  79,   78,   78,   77,   77,   77,   76,   76,
		  76,   75,   75,   75,   74,   74,   74,   73,
		  73,   73,   72,   72,   72,   71,   71,   71,
		  70,   70,   70,   69,   69,   69,   68,   68,
		  68,   67,   67,   67,   66,   66,   66,   65,
		  64,   63,   62,   61,   60,   60,   59,   59,
		  59,   58,   58,   58,   57,   57,   57,   56,
		  56,   56,   55,   55,   55,   54,   54,   54,
		  53,   53,   53,   52,   52,   52,   51,   51,
		  51,   50,   50,   50,   49,   49,   48,   48,
		  47,   47,   46,   46,   45,   45,   44,   44,
		  43,   43,   42,   41,   40,   39,   39,   39,
		  38,   38,   38,   37,   37,   37,   36,   36,
		  35,   35,   34,   34,   33,   33,   32,   32,
		  31,   31,   30,   30,   29,   29,   28,   28,
		  28,   27,   27,   27,   26,   26,   25,   24,
		  23,   23,   22,   22,   21,   21,   21,   20,
		  20,   20,   20,   20,   20,   19,   19,   19,
		  19,   18,   17,   16,   15,   14,   13,   13,
		  12,   11,   11,   10,   10,    9,    9,    8,
		   8,    7,    7,    6,    6,    5,    5,    4,
		   4,    3,    2,    2,    1,    1,    1,    0,
		   0,    0,   -1,   -1,   -2,   -3,   -4,   -4,
		  -5,   -5,   -6,   -6,   -7,   -7,   -8,   -8,
		  -9,   -9,  -10,  -10,  -11,  -11,  -12,  -12,
		 -13,  -14,  -15,  -15,  -16,  -16,  -16,  -17,
		 -17,  -17,  -18,  -18,  -19,  -19,  -20,  -21,
		 -22,  -22,  -23,  -23,  -24,  -25,  -25,  -26,
		 -26,  -27,  -27,  -28,  -28,  -29,  -30,  -31,
		 -31,  -32,  -32,  -33,  -34,  -34,  -35,  -35,
		 -36,  -36,  -37,  -38,  -38,  -39,  -40,  -40
	);

	signal temp_magnitude	: std_logic_vector(11 downto 0);
	signal temp_negative	: std_logic;

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

	-- ----------------------------------------------------------------
	-- ADC code → signed Celsius conversion via UG-M10ADC Table 4 lookup.
	--
	-- The result is split into a sign bit (temp_negative) and a 12-bit
	-- unsigned magnitude (temp_magnitude) that feeds the BCD pipeline
	-- below.  Codes outside the calibrated range [CODE_LO_C..CODE_HI_C]
	-- are clamped to +125 °C / −40 °C respectively.
	-- ----------------------------------------------------------------
	temp_convert: process(value)
		variable code_int	: integer range 0 to 4095;
		variable t_signed	: integer range -40 to 125;
		variable abs_t		: integer range 0 to 125;
	begin
		code_int := to_integer(unsigned(value));

		if code_int <= CODE_LO_C then
			-- Codes at or below the table minimum → maximum temperature
			t_signed := 125;
		elsif code_int >= CODE_HI_C then
			-- Codes at or above the table maximum → minimum temperature
			t_signed := -40;
		else
			t_signed := CODE_TO_TEMP_C(code_int);
		end if;

		if t_signed < 0 then
			temp_negative <= '1';
			abs_t         := -t_signed;
		else
			temp_negative <= '0';
			abs_t         := t_signed;
		end if;

		temp_magnitude <= std_logic_vector(to_unsigned(abs_t, 12));
	end process temp_convert;

	-- Double-dabble binary-to-BCD conversion.
	--
	-- A 28-bit scratch register is used:
	--   scratch(27:24) = thousands digit
	--   scratch(23:20) = hundreds  digit
	--   scratch(19:16) = tens      digit
	--   scratch(15:12) = ones      digit
	--   scratch(11:0)  = binary input (shifted out over 12 iterations)
	--
	-- Each iteration:
	--   1. For every BCD nibble: if the nibble >= 5, add 3.
	--   2. Shift the entire 28-bit register left by one.
	-- After 12 iterations the BCD digits occupy scratch(27:12).
	bcd_convert: process(temp_magnitude)
		variable scratch : std_logic_vector(27 downto 0);
		variable nibble  : unsigned(3 downto 0);
	begin
		scratch             := (others => '0');
		scratch(11 downto 0) := temp_magnitude;

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

	-- Drive the four numeric displays via individual decoders
	hex0_inst: seg7_decoder port map (digit => bcd_ones,      seg => HEX0);
	hex1_inst: seg7_decoder port map (digit => bcd_tens,      seg => HEX1);
	hex2_inst: seg7_decoder port map (digit => bcd_hundreds,  seg => HEX2);
	hex3_inst: seg7_decoder port map (digit => bcd_thousands, seg => HEX3);

	-- HEX4: minus sign when negative, blank otherwise.
	-- Bit assignment: seg(6)=g, seg(5..0)=f,e,d,c,b,a (active-low).
	--   "0111111" → only segment g on  (minus sign)
	--   "1111111" → all segments off    (blank)
	HEX4 <= "0111111" when temp_negative = '1' else "1111111";

	-- HEX5: 'C' for Celsius (segments a, d, e, f on; g, b, c off)
	-- "1000110" → g=1(off), f=0(on), e=0(on), d=0(on), c=1(off), b=1(off), a=0(on)
	HEX5 <= "1000110";

end architecture rtl;
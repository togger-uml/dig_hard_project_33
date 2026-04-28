library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wysiwyg;
use wysiwyg.fiftyfivenm_components.all;
----
-- port map:
--
-- pll_clk:	clock input (10 MHz)
-- chsel:	channel select
-- soc:		start of conversion
-- tsen:	0 - normal mode
--			1 - temperature sensing mode
-- dout:	data output
-- eoc:		end of conversion
-- clk_dft:	clock output from clock divider

entity max10_adc is
	port (
		pll_clk:	in	std_logic;
		chsel:		in	natural range 0 to 2**5 - 1;
		soc:		in	std_logic;
		tsen:		in	std_logic;
		dout:		out	natural range 0 to 2**12 - 1;
		eoc:		out	std_logic;
		clk_dft:	out	std_logic
	);
end entity max10_adc;

architecture wrapper of max10_adc is
	signal adc_dout: std_logic_vector(11 downto 0);
	signal adc_chsel: std_logic_vector(4 downto 0);
begin

	dout <= to_integer(unsigned(adc_dout));
	adc_chsel <= std_logic_vector(to_unsigned(chsel, adc_chsel'length));

	---- from what i can tell, the following generic parameters apply
	--
	-- clkdiv:
	--	first stage clock divider:
	--	* 0:	divide by 1
	--	* 1:	divide by 2
	--	* 2:	divide by 10
	--	* 3:	divide by 20
	--	* 4:	divide by 40
	--	* 5:	divide by 80
	--	* 6:	invalid configuration
	--	* 7:	invalid configuration
	--
	-- tsclkdiv:
	-- tsclksel:
	-- pwd:
	-- prescalar:
	-- refsel:
	-- device_partname_fivechar_prefix
	-- is_this_first_or_second_adc
	-- analog_input_pin_mask
	-- enable_usr_sim
	-- reference_voltage_sim


	primitive_instance: fiftyfivenm_adcblock
		generic map (
			clkdiv		=> 2,	-- first stage clock divider
			tsclkdiv	=> 1,
			tsclksel	=> 1,
			pwd			=> 0,
			prescalar	=> 0,
			refsel		=> 0,
			device_partname_fivechar_prefix	=> "10M50",
			is_this_first_or_second_adc		=> 1,
			analog_input_pin_mask			=> 0,
			enable_usr_sim	=> 0,
			reference_voltage_sim	=> 0--,
--			simfilename_ch0		=> "",
--			simfilename_ch1		=> "",
--			simfilename_ch2		=> "",
--			simfilename_ch3		=> "",
--			simfilename_ch4		=> "",
--			simfilename_ch5		=> "",
--			simfilename_ch6		=> "",
--			simfilename_ch7		=> "",
--			simfilename_ch8		=> "",
--			simfilename_ch9		=> "",
--			simfilename_ch10	=> "",
--			simfilename_ch11	=> "",
--			simfilename_ch12	=> "",
--			simfilename_ch13	=> "",
--			simfilename_ch14	=> "",
--			simfilename_ch15	=> "",
--			simfilename_ch16	=> ""
		)
		port map (
			chsel		=> adc_chsel,	-- input: channel select
			soc			=> soc,			-- input: start conversion
			eoc			=> eoc,			-- output: end of conversion
			usr_pwd		=> '0',			-- input: user power off if 1
			tsen		=> tsen,		-- input: temperature sensing mode if 1
			clk_dft		=> clk_dft,		-- output: scaled clock
			dout		=> adc_dout,	-- output: result of conversion
			clkin_from_pll_c0	=> pll_clk	-- input: 10 MHz clock
		);

end architecture wrapper;

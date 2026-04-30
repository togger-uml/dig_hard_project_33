library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Finite state machine that drives the MAX10 ADC in temperature-sensing
-- mode and transfers each converted sample into the producer-side of the
-- async FIFO synchroniser.
--
-- Port map:
--   clk        – ADC operating clock (clk_dft from max10_adc)
--   rst_n      – asynchronous active-low reset
--   soc        – start-of-conversion pulse sent to max10_adc
--   eoc        – end-of-conversion flag received from max10_adc
--   dout       – 12-bit raw ADC result from max10_adc
--   tsen       – temperature-sensing enable (held high)
--   fifo_data  – data word written into the FIFO
--   fifo_wen   – write-enable pulse for the FIFO
--   fifo_full  – full flag from the FIFO (prevents writes when asserted)
--
-- State encoding:
--   IDLE       – wait until the FIFO has room, then assert SOC
--   SOC_HIGH   – hold SOC high for one clock cycle
--   WAIT_EOC   – deassert SOC, wait for ADC to assert EOC
--   STORE      – capture DOUT and push it into the FIFO

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

	type state_t is (IDLE, SOC_HIGH, WAIT_EOC, STORE);
	signal state : state_t := IDLE;

begin

	-- Temperature-sensing mode is permanently enabled
	tsen <= '1';

	fsm: process(clk, rst_n)
	begin
		if rst_n = '0' then
			state     <= IDLE;
			soc       <= '0';
			fifo_wen  <= '0';
			fifo_data <= (others => '0');

		elsif rising_edge(clk) then
			-- Default output values (deasserted unless overridden below)
			soc      <= '0';
			fifo_wen <= '0';

			case state is

				-- Wait for a free FIFO slot, then kick off a conversion
				when IDLE =>
					if fifo_full = '0' then
						soc   <= '1';
						state <= SOC_HIGH;
					end if;

				-- SOC has been asserted for one cycle; release it and
				-- wait for the ADC to complete its conversion
				when SOC_HIGH =>
					soc   <= '0';
					state <= WAIT_EOC;

				-- Poll the end-of-conversion flag
				when WAIT_EOC =>
					if eoc = '1' then
						state <= STORE;
					end if;

				-- Latch the ADC result and write it into the FIFO
				when STORE =>
					fifo_data <= std_logic_vector(to_unsigned(dout, 12));
					fifo_wen  <= '1';
					state     <= IDLE;

			end case;
		end if;
	end process fsm;

end architecture rtl;
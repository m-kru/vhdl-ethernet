library ieee;
  use ieee.std_logic_1164.all;

library amba5_axi_stream;
  use amba5_axi_stream.axi_stream;

-- The xgmii_tx allows sending Ethernet frames via XGMII interface.
-- The entity works with 32-bit wide XGMII interface described in the IEEE Std 802.3-2022.
--
-- The entity does not calculate the FCS.
-- It is up to user to calculate the FCS before feeding the data into xgmii_tx.
-- No padding or frame length check is performed.
--
-- One word is accepted on each rising edge of tx_clk_i. DDR conversion,
-- when needed, belongs outside this entity. There is no backpressure:
-- valid must remain high from the first transfer through last, and at least
-- six cycles with valid low must separate frames.
-- All non-last transfers must have keep = "1111". On the last transfer,
-- keep must be "0000", "0001", "0011", "0111", or "1111".
-- Bytes are sent from lane 0 upwards; strb, user, id, dest, and wakeup are ignored.
-- An underrun or unsupported keep mask aborts transmission with /E/ then /T/.
--
-- /S/, six preamble bytes, SFD, /T/, and at least twelve idle bytes between
-- frames are inserted. A full last word is followed by /T/ in the next word.
entity xgmii_tx is
  port (
    arst_i : in std_logic;

    -- XGMII Tx interface
    tx_clk_i : in  std_logic;
    txd_i    : out std_logic_vector(31 downto 0);
    txc_i    : out std_logic_vector( 3 downto 0);

    -- Input 32-bits AXI Stream interface
    frame_stream_i : in axi_stream.stream32_t
  );
end entity;


architecture rtl of xgmii_tx is

  type state_t is (idle, preamble, frame, terminate, interpacket_gap);
  signal state : state_t := idle;

  -- Hold the first two transfers while the preamble is transmitted.
  type stream_pipeline_t is array (0 to 1) of axi_stream.stream32_t;
  signal pipeline : stream_pipeline_t := (others => axi_stream.init);

  signal gap_count : natural range 0 to 3 := 0;

begin

  transmit : process (tx_clk_i, arst_i)
    variable data : std_logic_vector(31 downto 0);
    variable control : std_logic_vector(3 downto 0);
    variable stream : axi_stream.stream32_t;
  begin
    if arst_i = '1' then
      state <= idle;
      pipeline <= (others => axi_stream.init);
      gap_count <= 0;
      txd_i <= x"07070707";
      txc_i <= "1111";
    elsif rising_edge(tx_clk_i) then
      pipeline(0) <= frame_stream_i;
      pipeline(1) <= pipeline(0);
      stream := pipeline(1);

      data := x"07070707";
      control := "1111";

      case state is
        when idle =>
          if frame_stream_i.valid = '1' then
            data := x"555555FB";
            control := "0001";
            state <= preamble;
          end if;

        when preamble =>
          data := x"D5555555";
          control := "0000";
          state <= frame;

        when frame =>
          if stream.valid /= '1' or
            (stream.last /= '1' and stream.keep /= "1111") or
            (stream.keep /= "0000" and stream.keep /= "0001" and
             stream.keep /= "0011" and stream.keep /= "0111" and
             stream.keep /= "1111")
          then
            data := x"070707FE";
            state <= terminate;
          else
            for lane in 0 to 3 loop
              if stream.keep(lane) = '1' then
                data(8 * lane + 7 downto 8 * lane) :=
                  stream.data(8 * lane + 7 downto 8 * lane);
                control(lane) := '0';
              else
                data(8 * lane + 7 downto 8 * lane) := x"FD";
                gap_count <= 3;
                state <= interpacket_gap;
                exit;
              end if;
            end loop;

            if stream.last = '1' and stream.keep = "1111" then
              state <= terminate;
            end if;
          end if;

        when terminate =>
          data := x"070707FD";
          gap_count <= 3;
          state <= interpacket_gap;

        when interpacket_gap =>
          if gap_count = 1 then
            gap_count <= 0;
            state <= idle;
          else
            gap_count <= gap_count - 1;
          end if;
      end case;

      txd_i <= data;
      txc_i <= control;
    end if;
  end process;

end architecture;

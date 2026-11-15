library ieee;
  use ieee.std_logic_1164.all;

library amba5_axi_stream;
  use amba5_axi_stream.axi_stream;

-- The xgmii_rx_frame_extractor is a simple entity allowing receiving Ethernet frames via XGMII interface.
-- The entity works with 32-bit wide XGMII interface described in the IEEE Std 802.3-2022.
--
-- The entity does not calculate the FCS (Frame Check Sequence).
-- It simply treats FCS as part of the frame.
--
-- The Start character, six 0x55 preamble bytes, SFD (0xD5), and Terminate (/T/) character are removed.
-- AXI-Stream keep and strb mark the frame bytes in each transfer.
-- The last transfer might carry 0 bytes if /T/ character is placed in lane 0 (bits 7 downto 0).
--
-- Malformed preambles are discarded, the entire frame is ignored.
--
-- An unexpected control character within a frame terminates the stream packet
-- with user(i) asserted on its last transfer. For example, if unexpected control
-- character was placed on position 2 (23 downto 16), then user(2) = '1'.
--
-- No frame length or FCS checks are performed.
-- Other user bits, id, and dest are zero; wakeup is always high.
-- The receiver must accept every valid transfer.
entity xgmii_rx_frame_extractor is
  port (
    arst_i : in std_logic;

    -- XGMII Rx interface
    rx_clk_i : in std_logic;
    rxd_i    : in std_logic_vector(31 downto 0);
    rxc_i    : in std_logic_vector( 3 downto 0);

    -- Output 32-bits AXI Stream interface
    frame_stream_o : out axi_stream.stream32_t
  );
end entity;


architecture rtl of xgmii_rx_frame_extractor is

  type state_t is (idle, preamble, frame);
  signal state : state_t := idle;

begin

  -- One 32-bit word is sampled on each rising edge. The DDR-to-SDR
  -- conversion, when needed, belongs outside this entity.
  receive : process (rx_clk_i, arst_i)
    variable stream : axi_stream.stream32_t;
  begin
    if arst_i = '1' then
      state <= idle;
      frame_stream_o <= (
        data => (others => '0'), keep => (others => '0'),
        strb => (others => '0'), user => (others => '0'),
        id => (others => '0'), dest => (others => '0'),
        valid => '0', last => '0', wakeup => '1'
      );
    elsif rising_edge(rx_clk_i) then
      stream := (
        data => (others => '0'), keep => (others => '0'),
        strb => (others => '0'), user => (others => '0'),
        id => (others => '0'), dest => (others => '0'),
        valid => '0', last => '0', wakeup => '1'
      );

      case state is
        when idle =>
          -- /S/ is only legal in lane 0 on the 32-bit interface.
          if rxc_i = "0001" and rxd_i = x"555555FB" then
            state <= preamble;
          end if;

        when preamble =>
          if rxc_i = "0000" and rxd_i = x"D5555555" then
            state <= frame;
          else
            state <= idle;
          end if;

        when frame =>
          stream.valid := '1';
          for lane in 0 to 3 loop
            if rxc_i(lane) = '1' then
              -- Only bytes preceding the first control character belong
              -- to this packet. Ignore all later lanes in this word.
              stream.last := '1';
              if rxd_i(8 * lane + 7 downto 8 * lane) /= x"FD" then
                stream.user(lane) := '1';
              end if;
              state <= idle;
              exit;
            else
              stream.data(8 * lane + 7 downto 8 * lane) :=
                rxd_i(8 * lane + 7 downto 8 * lane);
              stream.keep(lane) := '1';
              stream.strb(lane) := '1';
            end if;
          end loop;
      end case;
      frame_stream_o <= stream;
    end if;
  end process;

end architecture;

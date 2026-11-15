library ieee;
  use ieee.std_logic_1164.all;

library amba5;
  use amba5.data.all;

library amba5_axi_stream;
  use amba5_axi_stream.axi_stream.all;
  use amba5_axi_stream.bfm;
  use amba5_axi_stream.buffer_receiver.all;
  use amba5_axi_stream.checker;

library lethernet;
  use lethernet.ethernet.all;

entity tb_xgmii_loopback is
end entity;

architecture test of tb_xgmii_loopback is

  constant CLK_PERIOD : time := 3.2 ns;
  signal clk : std_logic := '0';
  signal arst : std_logic := '0';

  signal xgmiid : std_logic_vector(31 downto 0);
  signal xgmiic : std_logic_vector(3 downto 0);

  signal tx_strm : stream32_t := init;
  signal rx_strm : stream32_t := init;

  signal tx_strm_ck : checker.checker_t := checker.init(REPORT_PREFIX => "tx stream checker");
  signal rx_strm_ck : checker.checker_t := checker.init(REPORT_PREFIX => "rx stream checker");

  signal ready : std_logic := '1';

  constant FRAME_SIZE : natural := 40;
  constant FRAME : data8_array_t(0 to FRAME_SIZE - 1) := (
    x"40", x"89", x"FE", x"BB", x"1A", x"97", x"12", x"43", x"BC", x"1F",
    x"41", x"19", x"F5", x"89", x"1F", x"97", x"14", x"43", x"BC", x"2F",
    x"42", x"09", x"F6", x"DD", x"1B", x"67", x"72", x"43", x"BC", x"3F",
    x"43", x"39", x"F8", x"aC", x"1D", x"97", x"88", x"43", x"BC", x"4F"
  );

  signal buf_rcv : buffer_receiver_t(buf(0 to MIN_FRAME_SIZE-1)) := init(buf_len => MIN_FRAME_SIZE);

begin

  clk <= not clk after CLK_PERIOD / 2;


  dut_rx : entity work.xgmii_rx
  port map (
    arst_i   => arst,
    rx_clk_i => clk,
    rxd_i    => xgmiid,
    rxc_i    => xgmiic,
    frame_stream_o => rx_strm
  );


  dut_tx : entity work.xgmii_tx
  port map (
    arst_i   => arst,
    tx_clk_i => clk,
    txd_i    => xgmiid,
    txc_i    => xgmiic,
    frame_stream_i => tx_strm
  );


  stream_checkers : process (clk)
  begin
    if rising_edge(clk) then
      tx_strm_ck <= checker.clock(tx_strm_ck, tx_strm);
      rx_strm_ck <= checker.clock(rx_strm_ck, rx_strm);
    end if;
  end process;


  buffer_receiver : process (clk)
  begin
    if rising_edge(clk) then
      buf_rcv <= clock(buf_rcv, to_stream1024(rx_strm));
    end if;
  end process;


  axi_stream_user_checker : process (clk)
  begin
    if rising_edge(clk) then
      assert (or rx_strm.user) /= '1'
        report "asserted rx stream user bits:" & LF & to_debug(rx_strm)
        severity failure;
      assert (or tx_strm.user) /= '1'
        report "asserted tx stream user bits:" & LF & to_debug(tx_strm)
        severity failure;
    end if;
  end process;


  main : process
  begin
    wait for 2 * CLK_PERIOD;

    bfm.transmit(MIN_SIZE_FRAME_TB, tx_strm, ready, clk);

    assert buf_rcv.buf = MIN_SIZE_FRAME_TB
      report "got: " & LF & to_string(buf_rcv.buf) & LF & "want:" & LF & to_string(MIN_SIZE_FRAME_TB)
      severity failure;

    assert buf_rcv.transfers = MIN_FRAME_SIZE / 4 + 1
      report "transfers = " & to_string(buf_rcv.transfers)
      severity failure;

    wait for 2 * CLK_PERIOD;
    std.env.finish;
  end process;

end architecture;

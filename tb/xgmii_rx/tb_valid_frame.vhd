library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library amba5;
  use amba5.data.all;

library amba5_axi_stream;
  use amba5_axi_stream.axi_stream.all;
  use amba5_axi_stream.axi_stream."=";
  use amba5_axi_stream.buffer_receiver.all;
  use amba5_axi_stream.checker.all;

entity tb_valid_frame is
end entity;

architecture test of tb_valid_frame is

  constant CLK_PERIOD : time := 3.2 ns;
  signal clk : std_logic := '0';

  signal arst : std_logic := '0';
  signal rxd : std_logic_vector(31 downto 0) := x"07070707";
  signal rxc : std_logic_vector(3 downto 0) := "1111";
  signal frame_strm : stream32_t;
  signal frame_strm_ck : checker_t := init;

  constant FRAME_SIZE : natural := 40;
  constant FRAME : data8_array_t(0 to FRAME_SIZE - 1) := (
    x"40", x"89", x"FE", x"BB", x"1A", x"97", x"12", x"43", x"BC", x"1F",
    x"41", x"19", x"F5", x"89", x"1F", x"97", x"14", x"43", x"BC", x"2F",
    x"42", x"09", x"F6", x"DD", x"1B", x"67", x"72", x"43", x"BC", x"3F",
    x"43", x"39", x"F8", x"aC", x"1D", x"97", x"88", x"43", x"BC", x"4F"
  );

  signal buf_rcv : buffer_receiver_t(buf(0 to FRAME_SIZE-1)) := init(buf_len => FRAME_SIZE);

  signal strm_last_cnt : natural := 0;
  signal last_keep : std_logic_vector(3 downto 0);

begin

  clk <= not clk after CLK_PERIOD / 2;


  dut  : entity work.xgmii_rx
  port map (
    arst_i   => arst,
    rx_clk_i => clk,
    rxd_i    => rxd,
    rxc_i    => rxc,
    frame_stream_o => frame_strm
  );


  frame_strm_checker : process (clk, arst)
    variable next_checker : checker_t;
  begin
    if arst = '1' then
      frame_strm_ck <= reset(frame_strm_ck);
    elsif rising_edge(clk) then
      frame_strm_ck <= clock(frame_strm_ck, frame_strm);
    end if;
  end process;


  buffer_receiver : process (clk)
  begin
    if rising_edge(clk) then
      buf_rcv <= clock(buf_rcv, to_stream1024(frame_strm));
    end if;
  end process;


  keep_strb_checker : process (clk)
  begin
    if rising_edge(clk) then
      assert frame_strm.keep = frame_strm.strb
        report "keep/strb mismatch: keep=0x" & to_hstring(frame_strm.keep) &
          ", strb=0x" & to_hstring(frame_strm.strb)
        severity failure;
    end if;
  end process;


  user_checker : process (clk)
  begin
    if rising_edge(clk) then
      assert (or frame_strm.user) /= '1'
        report "unexpected user bits: 0x" & to_hstring(frame_strm.user)
        severity failure;
    end if;
  end process;


  stream_last_counter : process (clk)
  begin
    if rising_edge(clk) then
      if frame_strm.last = '1' then
        strm_last_cnt <= strm_last_cnt + 1;
        last_keep <= frame_strm.keep;
      end if;
    end if;
  end process;


  watchdog : process
  begin
    wait for 1 ms;
    assert false report "testbench timed out" severity failure;
  end process;


  main : process

    procedure send_frame (
      signal clk : in std_logic;
      constant frame : in data8_array_t
    ) is
      variable word : std_logic_vector(31 downto 0) := x"07070707";
      variable control : std_logic_vector(3 downto 0) := "1111";
      variable lane : natural range 0 to 3 := 0;
    begin
      wait until falling_edge(clk);
      rxd <= x"555555FB";
      rxc <= "0001";
      wait until falling_edge(clk);
      rxd <= x"D5555555";
      rxc <= "0000";
      wait until falling_edge(clk);

      for i in frame'range loop
        word(8 * lane + 7 downto 8 * lane) := frame(i);
        control(lane) := '0';
        if lane = 3 then
          rxd <= word;
          rxc <= control;
          wait until falling_edge(clk);
          word := x"07070707";
          control := "1111";
          lane := 0;
        else
          lane := lane + 1;
        end if;
      end loop;

      word(8 * lane + 7 downto 8 * lane) := x"FD";
      rxd <= word;
      rxc <= control;
      wait until falling_edge(clk);
      rxd <= x"07070707";
      rxc <= "1111";
    end procedure;

  begin
    wait for 2 * CLK_PERIOD;

    send_frame(clk, FRAME);
    wait for CLK_PERIOD;

    --
    -- Check frame with empty last transfer
    --

    assert buf_rcv.buf = FRAME
      report "got: " & LF & to_string(buf_rcv.buf) & LF & "want:" & LF & to_string(FRAME)
      severity failure;

    assert buf_rcv.transfers = 11
      report "transfers = " & to_string(buf_rcv.transfers)
      severity failure;

    assert strm_last_cnt = 1
      report "strm_last_cnt = " & to_string(strm_last_cnt)
      severity failure;

    assert last_keep = "0000"
      report "expected an empty last transfer, keep=0x" & to_hstring(last_keep)
      severity failure;

    --
    -- Check frame with non-empty last transfer
    -- Send 39 bytes so that the last transfer contains three frame bytes.
    -- Start from offset so there is no need to clear the rceiver buffer.
    --

    send_frame(clk, FRAME(1 to FRAME_SIZE - 1));
    wait for CLK_PERIOD;

    assert buf_rcv.buf(0 to FRAME_SIZE - 2) = FRAME(1 to FRAME_SIZE - 1)
      report "got: " & LF & to_string(buf_rcv.buf(0 to FRAME_SIZE - 2)) & LF &
        "want:" & LF & to_string(FRAME(1 to FRAME_SIZE - 1))
      severity failure;

    assert buf_rcv.transfers = 10
      report "transfers = " & to_string(buf_rcv.transfers)
      severity failure;

    assert strm_last_cnt = 2
      report "strm_last_cnt = " & to_string(strm_last_cnt)
      severity failure;

    assert last_keep = "0111"
      report "expected three bytes in the last transfer, keep=0x" & to_hstring(last_keep)
      severity failure;

    wait for 2 * CLK_PERIOD;
    std.env.finish;
  end process;

end architecture;

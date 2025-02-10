library ieee;
  use ieee.std_logic_1164.all;

library ethernet;
  use ethernet.gmii_tx_tester.all;


entity tb_gmii_tx_tester is
end entity;


architecture test of tb_gmii_tx_tester is

  constant CLK_PERIOD : time := 8 ns; -- 125 MHz
  signal clk : std_logic := '0';

  signal gtt : gmii_tx_tester_t := init(cnt => 10);

  constant DST_MAC : std_logic_vector(47 downto 0) := x"AA0102030405";
  constant SRC_MAC : std_logic_vector(47 downto 0) := x"B028AC1893BA";

  constant WANT_PAYLOAD : std_logic_vector(87 downto 0) := x"48656C6C6F20474D494921";

  constant WANT_CRC : std_logic_vector(31 downto 0) := x"EEBB34F1";

begin

  clk <= not clk after CLK_PERIOD / 2;


  DUT : process (clk) is
  begin
    if rising_edge(clk) then
      gtt <= clock(gtt, DST_MAC, SRC_MAC);
    end if;
  end process;


  main : process is
    variable byte : std_logic_vector(7 downto 0);
    variable payload : std_logic_vector(87 downto 0);
    variable crc : std_logic_vector(31 downto 0);
  begin
    wait until rising_edge(gtt.tx_en);

    -- Check preamle
    for i in 0 to 6 loop
      wait for CLK_PERIOD;
      assert gtt.txd = x"AA"
        report "invalid preamble data, got: x""" & to_hstring(gtt.txd) & """, want: x""AA"""
        severity failure;
    end loop;

    -- Check SFD
    wait for CLK_PERIOD;
    assert gtt.txd = x"D5"
      report "invalid SFD, got x""" & to_hstring(gtt.txd) & """, want x""D5"""
      severity failure;

    -- Check destination MAC address
    for i in 5 downto 0 loop
      wait for CLK_PERIOD;
      byte := DST_MAC(7 + i * 8 downto i * 8);
      assert gtt.txd = byte
        report i'image & ": invalid byte, got x""" & to_hstring(gtt.txd) & """, want x""" & to_hstring(byte) & """"
        severity failure;
    end loop;

    -- Check source MAC address
    for i in 5 downto 0 loop
      wait for CLK_PERIOD;
      byte := SRC_MAC(7 + i * 8 downto i * 8);
      assert gtt.txd = byte
        report i'image & ": invalid byte, got x""" & to_hstring(gtt.txd) & """, want x""" & to_hstring(byte) & """"
        severity failure;
    end loop;

    -- Check ether type
    wait for CLK_PERIOD;
    assert gtt.txd = x"88"
      report "invalid ether type, got x""" & to_hstring(gtt.txd) & """, want x""88"""
      severity failure;
    wait for CLK_PERIOD;
    assert gtt.txd = x"B5"
      report "invalid ether type, got x""" & to_hstring(gtt.txd) & """, want x""B5"""
      severity failure;

    -- Check payload
    for i in 10 downto 0 loop
      wait for CLK_PERIOD;
      payload(7 + i * 8 downto i * 8) := gtt.txd;
    end loop;
    assert payload = WANT_PAYLOAD
      report "invalid playload, got: x""" & to_hstring(payload) & """, want: x""" & to_hstring(WANT_PAYLOAD) & """"
      severity failure;

    -- Check padding
    for i in 0 to 34 loop
      wait for CLK_PERIOD;
      assert gtt.txd = x"00"
        report "invalid padding, got: x""" & to_hstring(gtt.txd) & """, want: x""00"""
        severity failure;
    end loop;

    -- Check CRC
    for i in 0 to 3 loop
      wait for CLK_PERIOD;
      crc(7 + i * 8 downto i * 8) := gtt.txd;
    end loop;
    assert crc = WANT_CRC
      report "invalid crc, got: x""" & to_hstring(crc) & """, want x""" & to_hstring(WANT_CRC) & """"
      severity failure;

    wait for 5 * CLK_PERIOD;
    std.env.finish;
  end process;

end architecture;
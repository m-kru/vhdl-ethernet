library ieee;
  use ieee.std_logic_1164.all;

library mdio;
  use mdio.mdio;


entity tb_read is
end entity;


architecture test of tb_read is

  constant CLK_PERIOD : time := 10 ns;
  signal clk : std_logic := '0';

  constant PREAMBLE_LEN : positive := 32;
  signal mgr : mdio.manager_t := mdio.init(preamble_length => PREAMBLE_LEN);

  signal di, start : std_logic := '0';
  signal op_code   : std_logic_vector(1 downto 0) := mdio.READ_INC;
  constant port_addr   : std_logic_vector(4 downto 0) := b"10101";
  constant device_addr : std_logic_vector(4 downto 0) := b"00100";
  constant wdata       : std_logic_vector(15 downto 0) := (others => '-');

  constant RDATA : std_logic_vector(15 downto 0) := b"1111000010101010";

begin

  clk <= not clk after CLK_PERIOD / 2;


  DUT : process (clk) is
  begin
    if rising_edge(clk) then
      mgr <= mdio.clock(mgr, start, di, op_code, port_addr, device_addr, wdata);
    end if;
  end process;


  -- MDC must not be asserted for more than 1 clock cycle.
  MDC_Checker : process is
    variable prev_mgr_clk : std_logic;
  begin
    wait until rising_edge(clk);

    assert prev_mgr_clk /= '1' or mgr.clk /= '1'
      report "MDC asserted for more than 1 clock cycle"
      severity failure;

    prev_mgr_clk := mgr.clk;

  end process;


  main : process is
  begin
    wait for 5 * CLK_PERIOD;

    -- Start transaction
    start <= '1';
    wait for CLK_PERIOD;
    start <= '0';

    -- Check signal values during the preamble
    for i in 1 to 2 * PREAMBLE_LEN - 1 loop
      assert mgr.do = '1'
        report "do must equal '1' during the preamble, current value '" & to_string(mgr.do) & "'"
        severity failure;

      assert mgr.serial_dir = '0'
        report "serial_dir must equal '0' during the preamble, current value '" & to_string(mgr.serial_dir) & "'"
        severity failure;

      wait for CLK_PERIOD;
    end loop;

    -- Check start of frame pattern
    assert mgr.do = '0'
      report "first bit of start of frame must equal '0', current value '" & to_string(mgr.do) & "'"
      severity failure;
    wait for 2 * CLK_PERIOD;
    assert mgr.do = '1'
      report "second bit of start of frame must equal '1', current value '" & to_string(mgr.do) & "'"
      severity failure;
    wait for 2 * CLK_PERIOD;

    -- Check port address
    for i in 4 downto 0 loop
      assert mgr.do = PORT_ADDR(i)
        report "invalid port address bit " & to_string(i) &
          ": got '" & to_string(mgr.do) &
          "', want '" & to_string(PORT_ADDR(i)) & "'"
        severity failure;
      wait for 2 * CLK_PERIOD;
    end loop;

    wait for 5 * CLK_PERIOD;
    std.env.finish;
  end process;

end architecture;
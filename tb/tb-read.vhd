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

  signal di, start   : std_logic := '0';
  signal op_code     : std_logic_vector(1 downto 0) := mdio.READ_INC;
  signal port_addr   : std_logic_vector(4 downto 0) := b"10101";
  signal device_addr : std_logic_vector(4 downto 0) := b"00100";
  signal wdata       : std_logic_vector(15 downto 0) := (others => '-');

begin

  clk <= not clk after CLK_PERIOD / 2;


  DUT : process (clk) is
  begin
    if rising_edge(clk) then
      mgr <= mdio.clock(mgr, start, di, op_code, port_addr, device_addr, wdata);
    end if;
  end process;


  main : process is
  begin
    wait for 5 * CLK_PERIOD;

    -- Start transaction
    start <= '1';
    wait for CLK_PERIOD;
    start <= '0';

    -- Check signals values during the preamble
    for i in 1 to 2 * PREAMBLE_LEN loop
      wait for CLK_PERIOD;
      assert mgr.do = '1'
        report "do must equal '1' during the preamble, current value '" & to_string(mgr.do) & "'"
        severity failure;
    end loop;

    -- Check start of frame pattern
    wait for CLK_PERIOD;
    assert mgr.do = '0'
      report "first bit of start of frame must equal '0', current value '" & to_string(mgr.do) & "'"
      severity failure;
    wait for CLK_PERIOD;
    assert mgr.do = '1'
      report "second bit of start of frame must equal '1', current value '" & to_string(mgr.do) & "'"
      severity failure;

    wait for 5 * CLK_PERIOD;
    std.env.finish;
  end process;

end architecture;
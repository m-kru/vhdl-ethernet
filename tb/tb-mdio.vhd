library ieee;
  use ieee.std_logic_1164.all;

library ethernet;
  use ethernet.mdio;


entity tb_mdio is
end entity;


architecture test of tb_mdio is

  constant CLK_PERIOD : time := 10 ns;
  signal clk : std_logic := '0';

  signal mgr : mdio.manager_t := mdio.init(preamble_length => mdio.PREAMBLE_LENGTH);

  signal mdi, start : std_logic := '0';
  constant PORT_ADDR   : std_logic_vector(4 downto 0) := b"10101";
  constant DEVICE_ADDR : std_logic_vector(4 downto 0) := b"00100";

  constant RDATA : std_logic_vector(15 downto 0) := b"1110001010111000";
  constant WDATA : std_logic_vector(15 downto 0) := b"1111000001010101";

begin

  clk <= not clk after CLK_PERIOD / 2;


  DUT : process (clk) is
  begin
    if rising_edge(clk) then
      mgr <= mdio.clock(mgr, mdi, start, mdio.READ_INC, port_addr, device_addr, WDATA);
    end if;
  end process;


  -- MDC must not be asserted for more than 1 clock cycle.
  MDC_Checker : process is
    variable prev_mgr_mdc : std_logic;
  begin
    wait until rising_edge(clk);

    assert prev_mgr_mdc /= '1' or mgr.mdc /= '1'
      report "MDC asserted for more than 1 clock cycle"
      severity failure;

    prev_mgr_mdc := mgr.mdc;

  end process;


  MMD_Mock : process is
  begin
    wait until rising_edge(mgr.serial_dir);

    wait for 4 * CLK_PERIOD;

    for i in 15 downto 0 loop
      mdi <= RDATA(i);
      wait for 2 * CLK_PERIOD;
    end loop;

  end process;


  Rdata_Checker : process is
  begin
    wait until rising_edge(mgr.rdata_valid);
    assert mgr.rdata = RDATA
      report "invalid rdata, got " & mgr.rdata'image & ", want " & RDATA'image
      severity failure;
  end process;


  main : process is
  begin
    wait for 5 * CLK_PERIOD;

    -- Start transaction
    start <= '1';
    wait for CLK_PERIOD;
    start <= '0';

    -- Check signal values during the preamble
    for i in 1 to 2 * mdio.PREAMBLE_LENGTH - 1 loop
      assert mgr.mdo = '1'
        report "mdo must equal '1' during the preamble, current value " & mgr.mdo'image
        severity failure;

      assert mgr.serial_dir = '0'
        report "serial_dir must equal '0' during the preamble, current value " & mgr.serial_dir'image
        severity failure;

      wait for CLK_PERIOD;
    end loop;

    -- Check start of frame pattern
    assert mgr.mdo = '0'
      report "first bit of start of frame must equal '0', current value " & mgr.mdo'image
      severity failure;
    wait for 2 * CLK_PERIOD;
    assert mgr.mdo = '1'
      report "second bit of start of frame must equal '1', current value " & mgr.mdo'image
      severity failure;
    wait for 2 * CLK_PERIOD;

    -- Check operation code
    assert mgr.mdo = MDIO.READ_INC(1)
      report "first bit of op code must equal '1', current value " & mgr.mdo'image
      severity failure;
    wait for 2 * CLK_PERIOD;
    assert mgr.mdo = MDIO.READ_INC(0)
      report "second bit of op code must equal '0', current value " & mgr.mdo'image
      severity failure;
    wait for 2 * CLK_PERIOD;

    -- Check port address
    for i in 4 downto 0 loop
      assert mgr.mdo = PORT_ADDR(i)
        report "invalid port address bit " & i'image &
          ": got " & mgr.mdo'image &
          ", want " & PORT_ADDR(i)'image
        severity failure;
      wait for 2 * CLK_PERIOD;
    end loop;

    -- Check device address
    for i in 4 downto 0 loop
      assert mgr.mdo = DEVICE_ADDR(i)
        report "invalid device address bit " & i'image &
          ": got " & mgr.mdo'image &
          ", want " & DEVICE_ADDR(i)'image
        severity failure;
      wait for 2 * CLK_PERIOD;
    end loop;

    -- Check turnaround
    assert mgr.mdo = '1'
      report "first bit of turnaround must equal '1', current value " & mgr.mdo'image
      severity failure;
    wait for 2 * CLK_PERIOD;
    assert mgr.mdo = '0'
      report "second bit of turnaround must equal '0', current value " & mgr.mdo'image
      severity failure;
    wait for 2 * CLK_PERIOD;

    -- Check write data
    for i in 15 downto 0 loop
      assert mgr.mdo = WDATA(i)
        report "invalid wdata bit " & i'image &
          ": got " & mgr.mdo'image &
          ", want " & WDATA(i)'image
        severity failure;
      wait for 2 * CLK_PERIOD;
    end loop;

    wait for 5 * CLK_PERIOD;
    std.env.finish;
  end process;

end architecture;
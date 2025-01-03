-- SPDX-License-Identifier: MIT
-- https://github.com/m-kru/vhdl-mdio
-- Copyright (c) 2025 Michał Kruszewski

library ieee;
  use ieee.std_logic_1164.all;

-- The mdio package contains types and subprograms useful for working with
-- the MDIO (Management Data Input/Output) interface defined in the IEEE 802.3-2022 specification.
--
-- The package implements extended MDIO according to the Clause 45.
-- The Clause 45 is an extension to the basic MDIO interface (Clause 22).
-- However, the Clause 45 is logically backward compatible with the standard MDIO interface.
-- The main difference is that Clause 45 supports two new OP codes, allowing to access more registers.
-- There are also some differences in the management frame structure interpretation.
--
-- If you want to use this package with a standard MDIO interface, then remember that:
--   1. Port address is a PHY address.
--   2. Device address is a register address.
--   3. Don't use op code "00", it was introduced in the Clause 45.
--   4. Don't use op code "11", it was introduced in the Clause 45.
--      In standard MDIO op code "10", is a read. In the Caluse 45,
--      op code "10" is a read with post address increment, and
--      op code "11" is a read without an address increment.
package mdio is

  -- Operation code constants
  constant ADDR     : std_logic_vector(1 downto 0) := b"00";
  constant WRITE    : std_logic_vector(1 downto 0) := b"01";
  constant READ_INC : std_logic_vector(1 downto 0) := b"10";
  constant READ     : std_logic_vector(1 downto 0) := b"11";

  -- Type state_t represents manager internal state.
  --
  -- The state_t is not intended to be used by the user of the package.
  --   IDLE  - idle condition
  --   PRE   - preamble
  --   ST    - start of frame
  --   OP    - operation code
  --   PRTAD - port address
  --   DEVAD - device address
  --   TA    - turnaround
  --   DATA  - address / data
  type state_t is (IDLE, PRE, ST, OP, PRTAD, DEVAD, TA, DATA);

  -- The manager_t represents Station Management Entity (STA), the term used in IEEE 802.3.
  -- In PHY datasheets, the STA is often called simply Station Manager.
  --
  -- The IEEE 802.3 defines a maxium clock frequency for MDIO interface.
  -- However, some PHYs support higher frequencies.
  -- The manager doesn't impose any limits on the maximum frequency.
  -- It is user's responsiblity to clock the manager within a frequency range permitted by a given PHY.
  -- The MDC frequency is always two times lower than the frequency used to clock the manager.
  --
  -- It is also user's responsibility to meet MDIO setup and hold times.
  -- However, for low frequencies setup and hold times are usually met by default.
  -- This is because MDC rising edge always delays MDIO change by one clock cycle.
  --
  -- The serial_dir signal shall be used to properly multiplex the MDIO signal direction.
  type manager_t is record
    -- Configuration elements
    prefix : string; -- Optional prefix used in report messages
    preamble_length : positive range 1 to 32;
    -- Output elements
    ready       : std_logic; -- Asserted when manager is ready to carry out a transaction
    clk         : std_logic; -- MDIO clock
    do          : std_logic; -- MDIO serial data output to PHY
    serial_dir  : std_logic; -- Direction of serial data, '0': Manager -> PHY, '1': Manager <- PHY
    rdata       : std_logic_vector(15 downto 0); -- MDIO read data
    rdata_valid : std_logic; -- Asserted for one cycle when read data becomes valid
    -- Internal elements
    state  : state_t;
    cnt    : natural range 0 to 32; -- General purpose counter
    subcnt : natural range 0 to 1; -- General purpose subcounter
    read   : boolean; -- True if current operation is one of read operations
  end record;

  function init (
    prefix : string := "mdio: manager: ";
    preamble_length : positive := 32
  ) return manager_t;

  -- Function clock is used to clock the manager state.
  --
  -- The manager doesn't latch inputs at the transaction start.
  -- It is user's responsibility to ensure input data has valid value throughout the transaction.
  function clock (
    manager     : manager_t;
    start       : std_logic; -- Start MDIO transaction
    di          : std_logic; -- MDIO serial data input from PHY
    op_code     : std_logic_vector(1 downto 0);
    port_addr   : std_logic_vector(4 downto 0); -- Port address
    device_addr : std_logic_vector(4 downto 0); -- Device address
    wdata       : std_logic_vector(15 downto 0) -- MDIO write data, for op code "00", the data is a register address
  ) return manager_t;

end package;

package body mdio is

  function init (
    prefix : string := "mdio: manager: ";
    preamble_length : positive := 32
  ) return manager_t is
    constant mgr : manager_t := (
      prefix => prefix,
      preamble_length => preamble_length,
      ready       => '1',
      clk         => '0',
      do          => '1',
      serial_dir  => '0',
      rdata       => b"0000000000000000",
      rdata_valid => '0',
      state       => IDLE,
      cnt         => 32,
      subcnt      => 1,
      read        => false
    );
  begin
    return mgr;
  end function;


  function clock_idle (
    manager     : manager_t;
    start       : std_logic;
    di          : std_logic;
    op_code     : std_logic_vector(1 downto 0);
    port_addr   : std_logic_vector(4 downto 0);
    device_addr : std_logic_vector(4 downto 0);
    wdata       : std_logic_vector(15 downto 0)
  ) return manager_t is
    variable mgr : manager_t := manager;
  begin
    mgr.do := '1';
    mgr.cnt := mgr.preamble_length - 1;
    mgr.subcnt := 0;

    if start = '1' then
      mgr.ready := '0';
      mgr.clk := '1';
      mgr.state := PRE;
      report mgr.prefix & "starting transaction, " &
        "op_code => b"""  & to_string(op_code) & """, " &
        "port_addr => b""" & to_string(port_addr) & """, " &
        "device_addr => b""" & to_string(device_addr) & """, " &
        "wdata => b""" & to_string(wdata) & """"
        severity note;
    end if;

    return mgr;
  end function;


  function clock_pre (
    manager     : manager_t;
    start       : std_logic;
    di          : std_logic;
    op_code     : std_logic_vector(1 downto 0);
    port_addr   : std_logic_vector(4 downto 0);
    device_addr : std_logic_vector(4 downto 0);
    wdata       : std_logic_vector(15 downto 0)
  ) return manager_t is
    variable mgr : manager_t := manager;
  begin
    if mgr.subcnt = 1 then
        mgr.clk := '1';
        mgr.subcnt := 0;
    elsif mgr.subcnt = 0 then
        mgr.clk := '0';
        mgr.subcnt := 1;
        if mgr.cnt > 0 then
          mgr.cnt := mgr.cnt - 1;
        else
          mgr.cnt := 3;
          mgr.do := '0';
          mgr.state := ST;
        end if;
    end if;

    return mgr;
  end function;


  function clock_st (
    manager     : manager_t;
    start       : std_logic;
    di          : std_logic;
    op_code     : std_logic_vector(1 downto 0);
    port_addr   : std_logic_vector(4 downto 0);
    device_addr : std_logic_vector(4 downto 0);
    wdata       : std_logic_vector(15 downto 0)
  ) return manager_t is
    variable mgr : manager_t := manager;
  begin
    if mgr.cnt = 3 then
      mgr.clk := '1';
      mgr.cnt := mgr.cnt - 1;
    elsif mgr.cnt = 2 then
      mgr.do := '1';
      mgr.clk := '0';
      mgr.cnt := mgr.cnt - 1;
    elsif mgr.cnt = 1 then
      mgr.clk := '1';
      mgr.cnt := mgr.cnt - 1;
    elsif mgr.cnt = 0 then
      mgr.do := op_code(1);
      mgr.cnt := 3;
      mgr.clk := '0';
      mgr.state := OP;
    end if;

    return mgr;
  end function;


  function clock_op (
    manager     : manager_t;
    start       : std_logic;
    di          : std_logic;
    op_code     : std_logic_vector(1 downto 0);
    port_addr   : std_logic_vector(4 downto 0);
    device_addr : std_logic_vector(4 downto 0);
    wdata       : std_logic_vector(15 downto 0)
  ) return manager_t is
    variable mgr : manager_t := manager;
  begin
    if mgr.cnt = 3 then
      mgr.clk := '1';
      mgr.cnt := mgr.cnt - 1;
    elsif mgr.cnt = 2 then
      mgr.do := op_code(0);
      mgr.clk := '0';
      mgr.cnt := mgr.cnt - 1;
    elsif mgr.cnt = 1 then
      mgr.clk := '1';
      mgr.cnt := mgr.cnt - 1;
    elsif mgr.cnt = 0 then
      mgr.do := port_addr(4);
      mgr.cnt := 4;
      mgr.subcnt := 1;
      mgr.clk := '0';
      mgr.state := PRTAD;
    end if;
    return mgr;
  end function;


  function clock_prtad (
    manager     : manager_t;
    start       : std_logic;
    di          : std_logic;
    op_code     : std_logic_vector(1 downto 0);
    port_addr   : std_logic_vector(4 downto 0);
    device_addr : std_logic_vector(4 downto 0);
    wdata       : std_logic_vector(15 downto 0)
  ) return manager_t is
    variable mgr : manager_t := manager;
  begin
    if mgr.subcnt = 1 then
      mgr.clk := '1';
      mgr.subcnt := 0;
    elsif mgr.subcnt = 0 then
        mgr.clk := '0';
        mgr.subcnt := 1;
        if mgr.cnt > 0 then
          mgr.cnt := mgr.cnt - 1;
          mgr.do := port_addr(mgr.cnt);
        else
          mgr.cnt := 3;
          mgr.do := device_addr(4);
          mgr.state := DEVAD;
        end if;
    end if;

    return mgr;
  end function;


  function clock (
    manager     : manager_t;
    start       : std_logic;
    di          : std_logic;
    op_code     : std_logic_vector(1 downto 0);
    port_addr   : std_logic_vector(4 downto 0);
    device_addr : std_logic_vector(4 downto 0);
    wdata       : std_logic_vector(15 downto 0)
  ) return manager_t is
    variable mgr : manager_t := manager;
  begin
    case mgr.state is
      when IDLE  => mgr := clock_idle  (mgr, start, di, op_code, port_addr, device_addr, wdata);
      when PRE   => mgr := clock_pre   (mgr, start, di, op_code, port_addr, device_addr, wdata);
      when ST    => mgr := clock_st    (mgr, start, di, op_code, port_addr, device_addr, wdata);
      when OP    => mgr := clock_op    (mgr, start, di, op_code, port_addr, device_addr, wdata);
      when PRTAD => mgr := clock_prtad (mgr, start, di, op_code, port_addr, device_addr, wdata);
      when others => report "unimplemented state " & state_t'image(mgr.state) severity failure;
    end case;

    return mgr;
  end function;

end package body;
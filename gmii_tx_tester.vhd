-- SPDX-License-Identifier: MIT
-- https://github.com/m-kru/vhdl-mdio
-- Copyright (c) 2025 Michał Kruszewski

library ieee;
  use ieee.std_logic_1164.all;

library work;
  use work.crc.crc32;


package gmii_tx_tester is

  type state_t is (IDLE, PREAMBLE, SFD, DMAC, SMAC, ETHER_TYPE, PAYLOAD, PADDING, FCS);

  -- Module for testing GMII Tx path without MAC layer.
  -- 
  -- The module transmits a frame every about one second.
  -- The destination and source MAC addresses are configurable.
  -- However, the frame data content is fixed to "Hello GMII!" string. 
  --
  -- The ether type is fixed to the 0x88B5 (IEEE 802.1 Local Experimental Ethertype 1).
  type gmii_tx_tester_t is record
    -- Configuration elements
    REPORT_PREFIX : string;
    -- Output elements
    tx_en : std_logic;
    tx_er : std_logic;
    txd   : std_logic_vector(7 downto 0);
    -- Internal elements
    state : state_t;
    cnt : natural range 0 to 125_000_000; -- General purpose counter
    crc : std_logic_vector(31 downto 0);
  end record;

  -- Initializes gmii tx tester.
  function init (
    REPORT_PREFIX : string := "ethernet: gmii tx tester: ";
    tx_en : std_logic := '0';
    tx_er : std_logic := '0';
    txd   : std_logic_vector(7 downto 0) := (others => '-');
    state : state_t := IDLE;
    cnt   : natural range 0 to 125_000_000 := 125_000_000;
    crc   : std_logic_vector(31 downto 0) := (others => '1')
  ) return gmii_tx_tester_t;

  -- Clocks the gmii tx tester.
  --
  -- The tester must be clocked with the 125 MHz GMII GTX clock.
  function clock (
    gmii_tx_tester : gmii_tx_tester_t;
    dst_mac : std_logic_vector(47 downto 0); -- Destionation MAC address
    src_mac : std_logic_vector(47 downto 0)  -- Source MAC address
  ) return gmii_tx_tester_t;

end package;


package body gmii_tx_tester is

  function init (
    REPORT_PREFIX : string := "ethernet: gmii tx tester: ";
    tx_en : std_logic := '0';
    tx_er : std_logic := '0';
    txd   : std_logic_vector(7 downto 0) := (others => '-');
    state : state_t := IDLE;
    cnt   : natural range 0 to 125_000_000 := 125_000_000;
    crc   : std_logic_vector(31 downto 0) := (others => '1')
  ) return gmii_tx_tester_t is
    constant gtt : gmii_tx_tester_t := (
      REPORT_PREFIX => REPORT_PREFIX,
      tx_en => tx_en,
      tx_er => tx_er,
      txd   => txd,
      state => state,
      cnt   => cnt,
      crc   => crc
    );
  begin
    return gtt;
  end function;


  function clock_idle (
    gmii_tx_tester : gmii_tx_tester_t
  ) return gmii_tx_tester_t is
    variable gtt : gmii_tx_tester_t := gmii_tx_tester; 
  begin
    gtt.tx_en := '0';
    gtt.tx_er := '0';
    gtt.txd := x"00";

    gtt.crc := x"FFFFFFFF"; 

    if gtt.cnt = 0 then
      gtt.tx_en := '1';
      gtt.tx_er := '0';
      gtt.txd := x"55";

      gtt.cnt := 5;
      gtt.state := PREAMBLE;
    else
      gtt.cnt := gtt.cnt - 1;
    end if;

    return gtt;
  end function;

  
  function clock_preamble (
    gmii_tx_tester : gmii_tx_tester_t
  ) return gmii_tx_tester_t is
    variable gtt : gmii_tx_tester_t := gmii_tx_tester; 
  begin
    if gtt.cnt = 0 then
      gtt.state := SFD;
    else
      gtt.cnt := gtt.cnt - 1;
    end if;

    return gtt;
  end function;


  function clock_sfd (
    gmii_tx_tester : gmii_tx_tester_t
  ) return gmii_tx_tester_t is
    variable gtt : gmii_tx_tester_t := gmii_tx_tester; 
  begin
    gtt.txd := x"D5";
    gtt.state := DMAC;
    gtt.cnt := 5;
    return gtt;
  end function;


  function clock_dmac (
    gmii_tx_tester : gmii_tx_tester_t;
    dst_mac : std_logic_vector(47 downto 0)
  ) return gmii_tx_tester_t is
    variable gtt : gmii_tx_tester_t := gmii_tx_tester; 
  begin
    if gtt.cnt = 0 then
      gtt.txd := dst_mac(7 downto 0);
      gtt.cnt := 5;
      gtt.state := SMAC;
    else
      gtt.txd := dst_mac(7 + gtt.cnt * 8 downto gtt.cnt * 8);
      gtt.cnt := gtt.cnt - 1;
    end if;

    gtt.crc := crc32(gtt.txd, gtt.crc);

    return gtt;
  end function;


  function clock_smac (
    gmii_tx_tester : gmii_tx_tester_t;
    src_mac : std_logic_vector(47 downto 0)
  ) return gmii_tx_tester_t is
    variable gtt : gmii_tx_tester_t := gmii_tx_tester; 
  begin
    if gtt.cnt = 0 then
      gtt.txd := src_mac(7 downto 0);
      gtt.cnt := 1;
      gtt.state := ETHER_TYPE;
    else
      gtt.txd := src_mac(7 + gtt.cnt * 8 downto gtt.cnt * 8);
      gtt.cnt := gtt.cnt - 1;
    end if;

    gtt.crc := crc32(gtt.txd, gtt.crc);

    return gtt;
  end function;


  function clock_ether_type (
    gmii_tx_tester : gmii_tx_tester_t
  ) return gmii_tx_tester_t is
    variable gtt : gmii_tx_tester_t := gmii_tx_tester; 
  begin
    if gtt.cnt = 1 then
      gtt.txd := x"88";
      gtt.cnt := 0;
    else
      gtt.txd := x"B5";
      gtt.cnt := 10;
      gtt.state := PAYLOAD;
    end if;

    gtt.crc := crc32(gtt.txd, gtt.crc);

    return gtt;
  end function;


  function clock_payload (
    gmii_tx_tester : gmii_tx_tester_t
  ) return gmii_tx_tester_t is
    constant PAYLOAD : std_logic_vector(87 downto 0) := x"48656C6C6F20474D494921"; -- "Hello GMII!"
    variable gtt : gmii_tx_tester_t := gmii_tx_tester; 
  begin
    if gtt.cnt = 0 then
      gtt.txd := PAYLOAD(7 downto 0);
      gtt.cnt := 34;
      gtt.state := PADDING;
    else
      gtt.txd := PAYLOAD(7 + gtt.cnt * 8 downto gtt.cnt * 8);
      gtt.cnt := gtt.cnt - 1;
    end if;

    gtt.crc := crc32(gtt.txd, gtt.crc);

    return gtt;
  end function;


  function clock_padding (
    gmii_tx_tester : gmii_tx_tester_t
  ) return gmii_tx_tester_t is
    variable gtt : gmii_tx_tester_t := gmii_tx_tester; 
  begin
    gtt.txd := x"00";

    if gtt.cnt = 0 then
      gtt.cnt := 3;
      gtt.state := FCS;
    else
      gtt.cnt := gtt.cnt - 1;
    end if;

    gtt.crc := crc32(gtt.txd, gtt.crc);

    return gtt;
  end function;


  function clock_fcs (
    gmii_tx_tester : gmii_tx_tester_t
  ) return gmii_tx_tester_t is
    variable gtt : gmii_tx_tester_t := gmii_tx_tester;

    -- Reverses order of bits in a byte.
    function rev(d : in std_logic_vector(7 downto 0)) return std_logic_vector is
      variable r : std_logic_vector(7 downto 0);
    begin
      for i in 0 to 7 loop r(i) := d(7-i); end loop;
      return r;
    end;

  begin
    gtt.txd := not rev(gtt.crc(7 + gtt.cnt * 8 downto gtt.cnt * 8));

    if gtt.cnt = 0 then
      gtt.cnt := 125_000_000;
      gtt.state := IDLE;
    else
      gtt.cnt := gtt.cnt - 1;
    end if;

    return gtt;
  end function;


  function clock (
    gmii_tx_tester : gmii_tx_tester_t;
    dst_mac : std_logic_vector(47 downto 0);
    src_mac : std_logic_vector(47 downto 0)
  ) return gmii_tx_tester_t is
    variable gtt : gmii_tx_tester_t := gmii_tx_tester; 
  begin
    case gtt.state is
      when IDLE       => gtt := clock_idle       (gtt);
      when PREAMBLE   => gtt := clock_preamble   (gtt);
      when SFD        => gtt := clock_sfd        (gtt);
      when DMAC       => gtt := clock_dmac       (gtt, dst_mac);
      when SMAC       => gtt := clock_smac       (gtt, src_mac);
      when ETHER_TYPE => gtt := clock_ether_type (gtt);
      when PAYLOAD    => gtt := clock_payload    (gtt);
      when PADDING    => gtt := clock_padding    (gtt);
      when FCS        => gtt := clock_fcs        (gtt);
    end case;

    return gtt;
  end function;

end package body;

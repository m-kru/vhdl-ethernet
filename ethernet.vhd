library ieee;
  use ieee.std_logic_1164.all;

library amba5;
  use amba5.data.all;

package ethernet is

  -- Minimum ethernet frame size
  constant MIN_FRAME_SIZE : positive := 64;

  -- Random minimum size ethernet frame used in testbenches.
  -- The included FCS is valid.
  constant MIN_SIZE_FRAME_TB : data8_array_t(0 to MIN_FRAME_SIZE - 1) := (
    x"01", x"80", x"c2", x"00", x"00", x"00", x"f4", x"1e", x"57", x"ff", x"f0", x"4c", x"00", x"27", x"42",
    x"42", x"03", x"00", x"00", x"02", x"02", x"3c", x"80", x"00", x"04", x"f4", x"1c", x"80", x"6f", x"78",
    x"00", x"00", x"00", x"02", x"80", x"00", x"f4", x"1e", x"57", x"ff", x"f0", x"44", x"80", x"09", x"01",
    x"00", x"14", x"00", x"02", x"00", x"0f", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
    x"d1", x"be", x"a7", x"bc" -- FCS in transmission byte order
  );

end package;

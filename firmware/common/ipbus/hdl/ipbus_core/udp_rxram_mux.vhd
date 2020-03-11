-- Multiplex into transport dual-port RAM/interface
--
-- Dave Sankey, July 2012

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity udp_rxram_mux is
  port (
    mac_clk: in std_logic;
    rx_reset: in std_logic;
--
    rarp_mode: in std_logic;
    rarp_addr: in std_logic_vector(12 downto 0);
    rarp_data: in std_logic_vector(7 downto 0);
    rarp_end_addr: in std_logic_vector(12 downto 0);
    rarp_send: in std_logic;
    rarp_we: in std_logic;
--
    pkt_drop_arp: in std_logic;
    arp_data: in std_logic_vector(7 downto 0);
    arp_addr: in std_logic_vector(12 downto 0);
    arp_we: in std_logic;
    arp_end_addr: in std_logic_vector(12 downto 0);
    arp_send: in std_logic;
--
    pkt_drop_ping: in std_logic;
    ping_data: in std_logic_vector(7 downto 0);
    ping_addr: in std_logic_vector(12 downto 0);
    ping_we: in std_logic;
    ping_end_addr: in std_logic_vector(12 downto 0);
    ping_send: in std_logic;
--
    pkt_drop_status: in std_logic;
    status_data: in std_logic_vector(7 downto 0);
    status_addr: in std_logic_vector(12 downto 0);
    status_we: in std_logic;
    status_end_addr: in std_logic_vector(12 downto 0);
    status_send: in std_logic;
--
    my_rx_valid: in std_logic;
    my_rx_last: in std_logic;
    rxram_busy: in std_logic;
    pkt_runt: in std_logic;
--
    dia: out std_logic_vector(7 downto 0);
    addra: out std_logic_vector(12 downto 0);
    wea: out std_logic;
    rxram_end_addr: out std_logic_vector(12 downto 0);
    rxram_send: out std_logic;
    rxram_dropped: out std_logic
  );
end udp_rxram_mux;

architecture rtl of udp_rxram_mux is

  signal ram_ready, rxram_send_sig: std_logic;

begin

  rxram_send <= rxram_send_sig and ram_ready;

do_ram_ready:  process(mac_clk)
  variable ram_ready_int, rxram_dropped_int: std_logic;
  begin
    if rising_edge(mac_clk) then
      if rx_reset = '1' or rarp_mode = '1' then
        ram_ready_int := '1';
      elsif my_rx_valid = '1' and rxram_busy = '1' then 
        ram_ready_int := '0';
      end if;
      if rxram_send_sig = '1' and ram_ready_int = '0' then
        rxram_dropped_int := '1';
      else
        rxram_dropped_int := '0';
      end if;
      ram_ready <= ram_ready_int;
      rxram_dropped <= rxram_dropped_int;
    end if;
  end process;

send_packet:  process(mac_clk)
  variable rxram_end_addr_int: std_logic_vector(12 downto 0);
  variable rxram_send_int: std_logic;
  begin
    if rising_edge(mac_clk) then
      if rarp_send = '1' then
        rxram_end_addr_int := rarp_end_addr;
	rxram_send_int := '1';
      elsif arp_send = '1' then
        rxram_end_addr_int := arp_end_addr;
	rxram_send_int := '1';
      elsif ping_send = '1' then
        rxram_end_addr_int := ping_end_addr;
	rxram_send_int := '1';
      elsif status_send = '1' then
        rxram_end_addr_int := status_end_addr;
	rxram_send_int := '1';
      else
        rxram_end_addr_int := (Others => '0');
        rxram_send_int := '0';
      end if;
      rxram_end_addr <= rxram_end_addr_int;
      rxram_send_sig <= rxram_send_int and (rarp_mode or not pkt_runt);
    end if;
  end process;

build_packet:  process(mac_clk)
  variable dia_int: std_logic_vector(7 downto 0);
  variable addra_int: std_logic_vector(12 downto 0);
  variable wea_int, incoming: std_logic;
  variable pkt_type: integer range 0 to 4;
  begin
    if rising_edge(mac_clk) then
-- Remember packet type after rx_last...
      if rx_reset = '1' then
        incoming := '1';
      elsif my_rx_last = '1' then
        incoming := '0';
      end if;
      if rarp_mode = '1' then
        pkt_type := 1;
      elsif incoming = '1' then
        if pkt_drop_arp = '0' then
	  pkt_type := 2;
        elsif pkt_drop_ping = '0' then
	  pkt_type := 3;
        elsif pkt_drop_status = '0' then
	  pkt_type := 4;
        else
	  pkt_type := 0;
        end if;
      end if;
      if ram_ready = '1' then
        case pkt_type is
          when 1 =>
            dia_int := rarp_data;
	    addra_int := rarp_addr;
	    wea_int := rarp_we;
          when 2 =>
            dia_int := arp_data;
	    addra_int := arp_addr;
	    wea_int := arp_we;
          when 3 =>
            dia_int := ping_data;
	    addra_int := ping_addr;
	    wea_int := ping_we;
          when 4 =>
            dia_int := status_data;
	    addra_int := status_addr;
	    wea_int := status_we;
        when Others =>
          dia_int := (Others => '0');
	  addra_int := (Others => '0');
	  wea_int := '0';
        end case;
      else
        dia_int := (Others => '0');
	addra_int := (Others => '0');
	wea_int := '0';
      end if;
      dia <= dia_int;
      addra <= addra_int;
      wea <= wea_int;
    end if;
  end process;

end rtl;
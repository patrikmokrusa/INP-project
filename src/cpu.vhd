-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2024 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): jmeno <login AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (1) / zapis (0)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_INV  : out std_logic;                      -- pozadavek na aktivaci inverzniho zobrazeni (1)
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
  signal ptr_reset, tmp_reset, pc_reset, cnt_reset : std_logic;

  signal cnt_out : std_logic_vector(12 downto 0);
  signal cnt_inc : std_logic;
  signal cnt_dec : std_logic;
  signal cnt_null : std_logic;

  signal tmp_out : std_logic_vector(7 downto 0);
  signal tmp_ld : std_logic;

  signal ptr_out : std_logic_vector(12 downto 0);
  signal ptr_inc : std_logic;
  signal ptr_dec : std_logic;

  signal pc_out : std_logic_vector(12 downto 0);
  signal pc_inc : std_logic;
  signal pc_dec : std_logic;

  signal mx1_sel : std_logic;
  -- signal mx1 : std_logic_vector(12 downto 0);

  signal mx2_sel : std_logic_vector(1 downto 0);
  -- signal mx2 : std_logic_vector(7 downto 0);

  type t_decode is (greater, lesser, plus, minus, l_bracket, r_bracket, dollar, exclamation, dot, dash, at, nothing);
  signal decode : t_decode;

  type t_fsm is (sreset, init_start, init_valid, init_load, init_read, init_done, sfetch, sload, sread, sgreater, slesser, splus, splus_load, splus_load2, sminus, sminus_load, sminus_load2, sl_bracket, sl_bracket2, sl_bracket3, sl_bracket_load, sl_bracket_load2, sr_bracket, sr_bracket_read, sr_bracket2, sr_bracket3, sr_bracket_load, sr_bracket_load2, sdollar, sdollar_load, sexclamation, sdot, sdot_load, sdash, sdash_load, shalt);
  signal nstate, pstate : t_fsm;
begin

 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly. 

 cnt: process(CLK, cnt_reset)
 begin
   if (cnt_reset='1') then
     cnt_out <= "0000000000001";
   elsif (rising_edge(CLK)) then
     if (cnt_inc = '1') then
       cnt_out <= cnt_out + 1;
     elsif (cnt_dec = '1') then
       cnt_out <= cnt_out - 1;
     end if;
   end if;
 end process;
 

 tmp: process(CLK, tmp_reset)
 begin
   if (tmp_reset='1') then
     tmp_out <= (others=>'0');
   elsif (rising_edge(CLK)) then
     if (tmp_ld = '1') then
       tmp_out <= DATA_RDATA;
     end if;
   end if;
 end process;


 ptr: process(CLK, ptr_reset)
 begin
   if (ptr_reset='1') then
     ptr_out <= (others=>'0');
   elsif (rising_edge(CLK)) then
     if (ptr_inc = '1') then
       ptr_out <= ptr_out + 1;
     elsif (ptr_dec = '1') then
       ptr_out <= ptr_out - 1;
     end if;
   end if;
 end process;


 pc: process(CLK, pc_reset)
 begin
   if (pc_reset ='1') then
     pc_out <= (others=>'0');
   elsif (rising_edge(CLK)) then
     if (pc_inc = '1') then
       pc_out <= pc_out + 1;
     elsif (pc_dec = '1') then
       pc_out <= pc_out - 1;
     end if;
   end if;
 end process;

 with cnt_out select
 cnt_null <= '1' when "0000000000000",
             '0' when others;
 
 with mx1_sel select
 DATA_ADDR <= ptr_out when '0',
        pc_out when '1',
        "0000000000000" when others;
 
 with mx2_sel select
 DATA_WDATA <= IN_DATA when "00",
        tmp_out when "01",
        DATA_RDATA - 1 when "10",
        DATA_RDATA + 1 when "11",
        "00000000" when others;

 with DATA_RDATA select
 decode <= greater when "00111110",
           lesser when "00111100",
           plus when "00101011",
           minus when "00101101",
           l_bracket when "01011011",
           r_bracket when "01011101",
           dollar when "00100100",
           exclamation when "00100001",
           dot when "00101110",
           dash when "00101100",
           at when "01000000",
           nothing when others;

  OUT_DATA <= DATA_RDATA;


 
 
 process (RESET, CLK, EN) is
 begin
  if EN = '1' then
    if (RESET = '1') then
      pstate <= sreset;
    elsif (rising_edge(CLK)) then
      pstate <= nstate;
    end if;
  end if ;
 end process;
 
 
 process (pstate, IN_VLD, decode, cnt_null, DATA_RDATA) is
 begin
  nstate <= sreset;
  cnt_inc <= '0';
  cnt_dec <= '0';
  tmp_ld <= '0';
  ptr_inc <= '0';
  ptr_dec <= '0';
  pc_inc <= '0';
  pc_dec <= '0';
  DONE <= '0';
  -- READY <= '0';
  IN_REQ <= '0';
  DATA_EN <= '0';
  DATA_RDWR <= '0';
  OUT_WE <= '0';
  OUT_INV <= '0';
  mx1_sel <= '0';
  mx2_sel <= "00";

  ptr_reset <= '0';
  tmp_reset <= '0';
  pc_reset <= '0';
  cnt_reset <= '0';


  case( pstate ) is
    when sreset =>
      READY <= '0';
      ptr_reset <= '1';
      tmp_reset <= '1';
      pc_reset <= '1';
      cnt_reset <= '1';

      nstate <= init_start;

  
    -- when init_start =>
    --   IN_REQ <='1';

    --   -- nstate <= init_valid;
    --   if IN_VLD = '1' then
    --     nstate <= init_load;
    --   elsif IN_VLD = '0' then
    --     nstate <= init_start;
    --   end if;
      
      
    -- when init_valid =>
    --   if IN_VLD = '1' then
    --     nstate <= init_load;
    --   elsif IN_VLD = '0' then
    --     nstate <= init_valid;
    --   end if;
      
    
    -- when init_load =>
    --     mx1_sel <= '1';
    --     mx2_sel <= "00";
    --     DATA_RDWR <= '0';
    --     DATA_EN <= '1';

    --     nstate <= init_read;

    
    when init_start =>
    mx1_sel <= '1';
    DATA_EN <= '1';
    DATA_RDWR <= '1';
    nstate <= init_load;

    when init_load =>
      nstate <= init_read;
    
    when init_read =>
        ptr_inc <= '1';
        pc_inc <= '1';

        if decode = at then
          nstate <= init_done;
        else
          nstate <= init_start;
        end if;
    
    
    when init_done =>
        READY <= '1';
        pc_reset <= '1';
        nstate <= sfetch;
    
    when sfetch =>
        mx1_sel <= '1';
        DATA_RDWR <= '1';
        DATA_EN <= '1';
        nstate <= sload;
    
    when sload =>
        nstate <= sread;
    
    when sread =>
        case( decode ) is
        
          when greater =>
            ptr_inc <= '1';
            pc_inc <= '1';
            nstate <= sfetch;

          when lesser =>
            ptr_dec <= '1';
            pc_dec <= '1';
            nstate <= sfetch;

          when plus =>
            mx1_sel <= '0';
            DATA_EN <= '1';
            DATA_RDWR <= '1';
            nstate <= splus_load;

          when minus =>
            mx1_sel <= '0';
            DATA_EN <= '1';
            DATA_RDWR <= '1';
            nstate <= sminus_load;

          when l_bracket =>
            pc_inc <= '1';
            mx1_sel <= '0';
            DATA_EN <= '1';
            DATA_RDWR <= '1';

            nstate <= sl_bracket_load;

          when r_bracket =>
            mx1_sel <= '0';
            DATA_EN <= '1';
            DATA_RDWR <= '1';

            nstate <= sr_bracket_load;

          when dollar  =>
            mx1_sel <= '0';
            DATA_EN <= '1';
            DATA_RDWR <= '1';
            nstate <= sdollar_load;

          when exclamation =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            mx1_sel <= '0';
            mx2_sel <= "01";
            pc_inc <= '1';

            nstate <= sexclamation;

          when dot =>
            DATA_EN <= '1';
            DATA_RDWR <= '1';
            mx1_sel <= '0';

            nstate <= sdot_load;

          when dash =>
            IN_REQ <= '1';
            if IN_VLD = '0' then
              nstate <= sread;
            elsif IN_VLD = '1' then
              nstate <= sdash;
            end if;

          when at =>
            nstate <= shalt;
        
          when others =>
            pc_inc <= '1';
            nstate <= sfetch;
        
        end case ;

    when sl_bracket_load =>
        nstate <= sl_bracket;

    when sl_bracket =>
        if DATA_RDATA = "0000000000000" then
          cnt_reset <= '1';
          nstate <= sl_bracket2;
        else
          nstate <= sfetch;
        end if ;
    
    when sl_bracket2 =>
        if cnt_null = '1' then
          nstate <= sfetch;
        else
          DATA_EN <= '1';
          DATA_RDWR <= '1';
          mx1_sel <= '1';
          nstate <= sl_bracket_load2;
        end if ;

    when sl_bracket_load2 =>
        nstate <= sl_bracket3;
    
    when sl_bracket3 => 
        if decode = l_bracket then
          cnt_inc <= '1';
        elsif decode = r_bracket then
          cnt_dec <= '1';
        end if ;
        pc_inc <= '1';
        nstate <= sl_bracket2;

    when sr_bracket_load =>
        nstate <= sr_bracket;

    when sr_bracket =>
        if DATA_RDATA = "0000000000000" then
          pc_inc <= '1';
          nstate <= sfetch;
        else
          cnt_reset <= '1';
          -- pc_dec <= '1';
          nstate <= sr_bracket2;
        end if ;

    when sr_bracket2 =>
        if cnt_null = '1' then
          nstate <= sfetch;
        else
          pc_dec <= '1';
          nstate <= sr_bracket_read;
        end if ;
          
    when sr_bracket_read =>
          DATA_EN <= '1';
          DATA_RDWR <= '1';
          mx1_sel <= '1';
          nstate <= sr_bracket_load2;

    when sr_bracket_load2 =>
        nstate <= sr_bracket3;

    when sr_bracket3 =>
        if decode = r_bracket then
          cnt_inc <= '1';
        elsif decode = l_bracket then
          cnt_dec <= '1';
        end if ;
        nstate <= sr_bracket2;

    when splus_load =>
        nstate <= splus;

    when splus =>
        DATA_EN <= '1';
        DATA_RDWR <= '0';

        mx1_sel <= '0';
        mx2_sel <= "11";

        pc_inc <= '1';

        nstate <= splus_load2;
    
    when splus_load2 =>
        DATA_EN <= '1';
        DATA_RDWR <= '1';

        mx1_sel <= '0';
        nstate <= sfetch;
    
    when sminus_load =>
        nstate <= sminus;
      
    when sminus =>
        DATA_EN <= '1';
        DATA_RDWR <= '0';

        mx1_sel <= '0';
        mx2_sel <= "10";

        pc_inc <= '1';

        nstate <= sminus_load2;

    when sminus_load2 =>
        DATA_EN <= '1';
        DATA_RDWR <= '1';

        mx1_sel <= '0';
        nstate <= sfetch;

    when sdot_load =>
        nstate <= sdot;
    
    when sdot =>
        if OUT_BUSY = '1' then
          nstate <= sdot_load;
        else
          OUT_WE <= '1';
          pc_inc <= '1';
          nstate <= sfetch;
        end if;
    
    when sdash =>
        mx1_sel <= '0';
        mx2_sel <= "00";
        DATA_EN <= '1';
        DATA_RDWR <= '0';

        pc_inc <= '1';
        nstate <= sdash_load;
    
    when sdash_load =>
        mx1_sel <= '0';
        mx2_sel <= "00";
        DATA_EN <= '1';
        DATA_RDWR <= '1';
        nstate <= sfetch;

    when sexclamation =>
        nstate <= sfetch;

    when sdollar_load =>
        nstate <= sdollar;

    when sdollar =>
        tmp_ld <= '1';
        pc_inc <= '1';

        nstate <= sfetch;

    when shalt =>
        DONE <= '1';
  
    when others => null;
  end case ;
 

 end process;



end behavioral;


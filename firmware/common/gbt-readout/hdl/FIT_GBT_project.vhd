----------------------------------------------------------------------------------
-- Company: INR RAS
-- Engineer: Finogeev D.A. dmitry-finogeev@yandex.ru
-- 
-- Create Date:    10:29:21 01/09/2017 
-- Design Name: 	FIT GBT
-- Module Name:    FIT_GBT_project - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use work.all;
use work.fit_gbt_common_package.all;
use work.fit_gbt_board_package.all;

entity FIT_GBT_project is
	generic (
		GENERATE_GBT_BANK	: integer := 0
	);

    Port (		
		RESET_I				: in  STD_LOGIC;
		SysClk_I 			: in  STD_LOGIC; -- 320MHz system clock
		DataClk_I 			: in  STD_LOGIC; -- 40MHz data clock
		MgtRefClk_I 		: in  STD_LOGIC; -- 200MHz ref clock
		RxDataClk_I			: in STD_LOGIC; -- 40MHz data clock in RX domain
--		FabricClk_I 		: in STD_LOGIC;	-- GBT fabric clk
		GBT_RxFrameClk_O	: out STD_LOGIC; --Rx GBT frame clk 40MHz
		
		Board_data_I		: in board_data_type; --PM or TCM data
		Control_register_I	: in CONTROL_REGISTER_type;
		
		MGT_RX_P_I 		: in  STD_LOGIC;
		MGT_RX_N_I 		: in  STD_LOGIC;
		MGT_TX_P_O 		: out  STD_LOGIC;
		MGT_TX_N_O		: out  STD_LOGIC;
		MGT_TX_dsbl_O 	: out  STD_LOGIC;
		
		-- GBT data to/from FIT readout 
		RxData_rxclk_to_FITrd_I 	: in  std_logic_vector(GBT_data_word_bitdepth-1 downto 0);
		IsRxData_rxclk_to_FITrd_I	: in  STD_LOGIC;
		Data_from_FITrd_O 			: out  std_logic_vector(GBT_data_word_bitdepth-1 downto 0);
		IsData_from_FITrd_O			: out  STD_LOGIC;
		
		-- GBT data to/from GBT project
		Data_to_GBT_I 	: in  std_logic_vector(GBT_data_word_bitdepth-1 downto 0);
		IsData_to_GBT_I	: in  STD_LOGIC;
		RxData_rxclk_from_GBT_O 	: out  std_logic_vector(GBT_data_word_bitdepth-1 downto 0);
		IsRxData_rxclk_from_GBT_O	: out  STD_LOGIC;

		-- FIT readour status, including BCOR_ID to PM/TCM
		FIT_GBT_status_O : out FIT_GBT_status_type;
		rx_ph320 : out std_logic_vector(2 downto 0);
		ph_error320 : out std_logic;
		
		
		GPIO_O : out std_logic_vector(15 downto 0)
	);
end FIT_GBT_project;

architecture Behavioral of FIT_GBT_project is

-- reset signals
signal FSM_Clocks 				: FSM_Clocks_type;
signal reset_to_syscount, reset_to_syscount40  : std_logic;
signal gbt_reset, reset_l : std_logic;
signal Is_SysClkCounter_ready   : std_logic;

-- from rx sync
signal RX_IsData_DataClk		:  std_logic; 
signal RX_exData_from_RXsync    :  std_logic_vector(GBT_data_word_bitdepth+GBT_slowcntr_bitdepth-1 downto 0);

signal RX_Data_DataClk 			:  std_logic_vector(GBT_data_word_bitdepth-1 downto 0); 
signal RX_Phase_Counter 		:  std_logic_vector(rx_phase_bitdepth-1 downto 0);

-- status
signal from_gbt_bank_prj_GBT_status : Type_GBT_status;
signal FIT_GBT_STATUS 				: FIT_GBT_status_type;

-- from data generator
signal Board_data_from_main_gen		: board_data_type;

signal RX_IsData_from_datagen 		:  std_logic; 
signal RX_Data_from_datagen 		:  std_logic_vector(GBT_data_word_bitdepth-1 downto 0); 

-- from rx data decoder
signal ORBC_ID_from_RXdecoder 			: std_logic_vector(Orbit_id_bitdepth + BC_id_bitdepth-1 downto 0); -- EVENT ID from CRUS
signal ORBC_ID_corrected_from_RXdecoder : std_logic_vector(Orbit_id_bitdepth + BC_id_bitdepth-1 downto 0); -- EVENT ID to PM/TCM
signal Trigger_from_RXdecoder 			: std_logic_vector(Trigger_bitdepth-1 downto 0);
signal Readout_Mode_from_RXdecoder 		: Type_Readout_Mode;
signal Start_run_from_RXdecoder			: std_logic;
signal Stop_run_from_RXdecoder			: std_logic;
signal BCIDsync_Mode_from_RXdecoder 	: Type_BCIDsync_Mode;

-- from data packajer
signal TX_IsData_from_packager 		:  std_logic; 
signal TX_Data_from_packager 		:  std_logic_vector(GBT_data_word_bitdepth-1 downto 0); 

-- from GBT Rx
signal RX_IsData_rxclk_from_GBT		:  std_logic; 
signal RX_Data_rxclk_from_GBT 		:  std_logic_vector(GBT_data_word_bitdepth-1 downto 0); 
signal RX_ErrDet_latch, RX_ErrDet_latch_next : std_logic;

attribute mark_debug : string;	
attribute mark_debug of Board_data_from_main_gen : signal is "true";

attribute mark_debug of RX_IsData_DataClk : signal is "true";
attribute mark_debug of RX_Data_DataClk : signal is "true";

attribute mark_debug of RX_IsData_from_datagen : signal is "true";
attribute mark_debug of RX_Data_from_datagen : signal is "true";

attribute mark_debug of TX_IsData_from_packager : signal is "true";
attribute mark_debug of TX_Data_from_packager : signal is "true";

begin
-- WIRING ======================================================
	FSM_Clocks.System_Clk 	<= SysClk_I;
	FSM_Clocks.Data_Clk 	<= DataClk_I;

	-- SFP turned ON
	MGT_TX_dsbl_O <= '0';

	-- Status
	FIT_GBT_status_O 							<= FIT_GBT_STATUS;
	
	FIT_GBT_STATUS.GBT_status 					<= from_gbt_bank_prj_GBT_status;
	FIT_GBT_STATUS.Readout_Mode 				<= Readout_Mode_from_RXdecoder;
	FIT_GBT_STATUS.BCIDsync_Mode 				<= BCIDsync_Mode_from_RXdecoder;
	FIT_GBT_STATUS.Start_run 					<= Start_run_from_RXdecoder;
	FIT_GBT_STATUS.Stop_run 					<= Stop_run_from_RXdecoder;
	
	FIT_GBT_STATUS.Trigger_from_CRU 			<= Trigger_from_RXdecoder;
	FIT_GBT_STATUS.BCID_from_CRU 				<= ORBC_ID_from_RXdecoder(BC_id_bitdepth-1 downto 0);
	FIT_GBT_STATUS.ORBIT_from_CRU 				<= ORBC_ID_from_RXdecoder(Orbit_id_bitdepth + BC_id_bitdepth-1 downto BC_id_bitdepth);
	FIT_GBT_STATUS.BCID_from_CRU_corrected 		<= ORBC_ID_corrected_from_RXdecoder(BC_id_bitdepth-1 downto 0);
	FIT_GBT_STATUS.ORBIT_from_CRU_corrected 	<= ORBC_ID_corrected_from_RXdecoder(Orbit_id_bitdepth + BC_id_bitdepth-1 downto BC_id_bitdepth);
		
	FIT_GBT_STATUS.rx_phase 					<= RX_Phase_Counter;

	
	
	
	
	RX_Data_DataClk <= RX_exData_from_RXsync(GBT_data_word_bitdepth-1 downto 0);
	
	Data_from_FITrd_O 	<= TX_Data_from_packager;
	IsData_from_FITrd_O	<= TX_IsData_from_packager;
	
	RxData_rxclk_from_GBT_O <= RX_Data_rxclk_from_GBT;
	IsRxData_rxclk_from_GBT_O <= RX_IsData_rxclk_from_GBT;

-- =============================================================

-- Reset FSM =================================================
Reset_Generator_comp: entity work.Reset_Generator
port map(
			RESET_I => RESET_I,
			SysClk_I => SysClk_I,
			DataClk_I => DataClk_I,
			Sys_Cntr_ready_I => Is_SysClkCounter_ready,
			Reset_DClk_O => reset_to_syscount,
			General_reset_O => FSM_Clocks.Reset,
			Reset_DClk40_O => reset_to_syscount40,
			General_reset40_O => FSM_Clocks.Reset40
		);
-- ===========================================================

-- Data Clk strobe ===========================================
DataClk_I_strobe_comp: entity work.DataClk_strobe
port map(
			RESET_I => reset_to_syscount,
			RESET40_I => reset_to_syscount40,
			SysClk_I => SysClk_I,
			DataClk_I => DataClk_I,
			SysClk_count_O => FSM_Clocks.System_Counter,
			Counter_ready_O => Is_SysClkCounter_ready
		);
-- ===========================================================

-- RX Data Clk Sync ============================================
RxData_ClkSync_comp : entity work.RXDATA_CLKSync
port map (
			FSM_Clocks_I => FSM_Clocks,
			Control_register_I => Control_register_I,
			
			RX_CLK_I  => RxDataClk_I,
			
			RX_IS_DATA_RXCLK_I   => IsRxData_rxclk_to_FITrd_I,
			RX_DATA_RXCLK_I      => x"0" & RxData_rxclk_to_FITrd_I,
			RX_IS_DATA_DATACLK_O => RX_IsData_DataClk,
			RX_DATA_DataClk_O    => RX_exData_from_RXsync,
			CLK_PH_CNT_O         => RX_Phase_Counter,
			CLK_PH_ERROR_O 		 => FIT_GBT_STATUS.GBT_status.Rx_Phase_error,
			rx_ph320             => rx_ph320,
			ph_error320          => ph_error320
);
-- =============================================================

-- RX Data Decoder ============================================
RX_Data_Decoder_comp : entity work.RX_Data_Decoder
Port map ( 
		FSM_Clocks_I => FSM_Clocks,
		
		FIT_GBT_status_I => FIT_GBT_STATUS,
		Control_register_I => Control_register_I,
			
		RX_IsData_I => RX_IsData_from_datagen,
		RX_Data_I => RX_Data_from_datagen,
		
		ORBC_ID_from_CRU_O => ORBC_ID_from_RXdecoder,
		ORBC_ID_from_CRU_corrected_O => ORBC_ID_corrected_from_RXdecoder,
		Trigger_O => Trigger_from_RXdecoder,
		
		Readout_Mode_O => Readout_Mode_from_RXdecoder,
		Start_run_O	=> Start_run_from_RXdecoder,
		Stop_run_O => Stop_run_from_RXdecoder,
		BCIDsync_Mode_O => BCIDsync_Mode_from_RXdecoder
	 );
-- =============================================================

-- DATA GENERATOR =====================================
Module_Data_Gen_comp : entity work.Module_Data_Gen
	
	Port map(
		FSM_Clocks_I 		=> FSM_Clocks,
		
		FIT_GBT_status_I	=> FIT_GBT_STATUS,
		Control_register_I	=> Control_register_I,
		
		Board_data_I		=> Board_data_I,
		Board_data_O		=> Board_data_from_main_gen
		);		
-- =====================================================


-- CRU ORBC GENERATOR ==================================
CRU_ORBC_Gen_comp : entity work.CRU_ORBC_Gen
	
	Port map(
		FSM_Clocks_I 		=> FSM_Clocks,
		
		FIT_GBT_status_I	=> FIT_GBT_STATUS,
		Control_register_I	=> Control_register_I,
		
		RX_IsData_I 		=> RX_IsData_DataClk,
		RX_Data_I 			=> RX_Data_DataClk,
		
		RX_IsData_O 		=> RX_IsData_from_datagen,
		RX_Data_O 			=> RX_Data_from_datagen,
		
		Current_BCID_from_O => open,
		Current_ORBIT_from_O=> open,
		Current_Trigger_from_O => open

		);		
-- =====================================================


-- Data Packager ===============================================
Data_Packager_comp : entity work.Data_Packager
port map (
		FSM_Clocks_I 		=> FSM_Clocks,
		
		FIT_GBT_status_I 	=> FIT_GBT_STATUS,
		Control_register_I 	=> Control_register_I,
		
		Board_data_I => Board_data_from_main_gen,
		
		fifo_status_O 				=> FIT_GBT_STATUS.fifo_status,
		hits_rd_counter_converter_O	=> FIT_GBT_STATUS.hits_rd_counter_converter,
		hits_rd_counter_selector_O 	=> FIT_GBT_STATUS.hits_rd_counter_selector,

		TX_Data_O 			=> TX_Data_from_packager,
		TX_IsData_O 		=> TX_IsData_from_packager,
		GPIO_O => GPIO_O
);
-- =============================================================




-- Data ff data clk **********************************
	process (FSM_Clocks.Data_Clk)
	begin
	
	   
		IF(rising_edge(FSM_Clocks.Data_Clk) )THEN
	     reset_l<=Control_register_I.reset_gbt;

			IF (FSM_Clocks.Reset40 = '1') THEN
				RX_ErrDet_latch <= '0';
			ELSE
				RX_ErrDet_latch <= RX_ErrDet_latch_next;	
			END IF;
		END IF;
		
	end process;			
	
	FIT_GBT_STATUS.GBT_status.gbtRx_ErrorLatch <= RX_ErrDet_latch;
	
	RX_ErrDet_latch_next <= '0' WHEN FSM_Clocks.Reset = '1' ELSE
							'0' WHEN (Control_register_I.reset_gbt_rxerror = '1') ELSE
							'1' WHEN (FIT_GBT_STATUS.GBT_status.gbtRx_ErrorDet = '1') ELSE
							'1' WHEN (RX_ErrDet_latch = '1') ELSE
							'0' WHEN (Control_register_I.strt_rdmode_lock = '1') ELSE
							'0';
-- ***************************************************

gbt_reset <=    RESET_I or reset_l;


 gbtBankDsgn : entity work.GBT_TX_RX
     port map (
     RESET => gbt_reset,
            MgtRefClk => MgtRefClk_I,
            MGT_RX_P =>  MGT_RX_P_I,
            MGT_RX_N => MGT_RX_N_I,
            MGT_TX_P => MGT_TX_P_O,
            MGT_TX_N => MGT_TX_N_O,
            TXDataClk => DataClk_I,
            TXData => Data_to_GBT_I,
            TXData_SC => x"0",
            IsTXData => IsData_to_GBT_I,
            RXDataClk => GBT_RxFrameClk_O,
            RXData => RX_Data_rxclk_from_GBT,
            RXData_SC => open,
            IsRXData => RX_IsData_rxclk_from_GBT,
            GBT_Status_O => from_gbt_bank_prj_GBT_status
            );
			
			


 -- =============================================================

end Behavioral;


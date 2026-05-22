
// Here we define the inputs / outputs
module Main(
    input  logic         MAX10_CLK1_50,  // 50 MHz clock
    input  logic[1:0]    KEY,            // Buttons
    inout  logic[9:0]    ARDUINO_IO,     // Header pins
    output logic[1:0]    PIN_O,          // Digital out pin
    output logic[9:0]    LEDR,           // LEDs
    input  logic[9:0]    SW,             // Switches
    output logic[7:0]    HEX0,           // 7-segment display
    output logic[7:0]    HEX1,           // 7-segment display
    output logic[7:0]    HEX2,           // 7-segment display
    output logic[7:0]    HEX3,           // 7-segment display
    output logic[7:0]    HEX4            // 7-segment display
);
    
   // This project implements the following signal processing chain
   //
   // R:ADC --> R:CIC decimator --> R:FIR 
   // L:ADC --> L:CIC decimator --> L:FIR
   // --> L+R and L-R 
   // --> L+R : --> + pilot frequency
   // --> L-R : --> *sin(w_side t) 
   // --> Both lines + --> DDS that frequency modulates --> Threshold to get sqare wave of DDS frequency --> Sqare wave on a I/O pin 

   // The ADC (and DAC) are both run at their proper update rate of 1 MHz for which their analog filters (anti-aliasing & reconstruction) were designed.
   // The CIC decimator internally lowers the sampling rate by a factor of 10 from 1 MHz down to 100 kHz
   // The FIR can compensate for the frequency response of the CIC, and additionally also do whatever filtering YOU might want
   // 
   // 
   //
   // 

   
   // Internal signals along signal processing chain
   logic signed[15:0] signal_from_adc_R;
   logic signed[15:0] signal_cic_decimated_R;
   logic signed[15:0] signal_fir_filtered_R;
   logic signed[15:0] signal_from_adc_L;
   logic signed[15:0] signal_cic_decimated_L;
   logic signed[15:0] signal_fir_filtered_L;
   logic signed[15:0] signal_LpR;
   logic signed[15:0] signal_LmR;
   // signals within the modulation block
   logic signed[15:0] signal_LpR_withPilot;
   logic signed[15:0] signal_LmR_onSideband;
   
   logic signed[15:0] signal_added_forDDSinput;// signals to the DDS
   logic signed[20:0] signal_DDSout; // output of the DDS --> TODO: adjust the bit size of the singal such that you achieve the whished frequency of the DDS
   logic signal_out; // single digital square wave line out, with the DDS frequency modulated according to the audio input.
   

   // COMMENT: consider having a universal reduced clock so that on each tick, both the L and R line have new data. This would make the modulation block easier to handle.

   logic tick_reduced; // universal reduced clock, e.g. tick_reduced_L && tick_reduced_R

   
   // Misc. internal signals
   logic reset;
   logic clk;
   logic tick;         //   1 MHz ticks from tick generator
   logic tick_reduced_L; // 100 kHz ticks from CIC decimator
   logic tick_reduced_R; // 100 kHz ticks from CIC decimator
    
   // Wire reset & Clk
   assign reset = !KEY[0]; // Pushbutton on FPGA board. Need to push this when switching filter.
   assign clk = MAX10_CLK1_50;
   
   // Internals for ADC/DAC communication
   logic              adc_clk_R;        // SPI clk
   logic              adc_mosi_R;       // MOSI: always 1
   logic              adc_cnv_R;        // Start conversion (SPI CS)
   logic              adc_miso_R;       // MISO: The DAC data

   logic              adc_clk_L;        // SPI clk
   logic              adc_mosi_L;       // MOSI: always 1
   logic              adc_cnv_L;        // Start conversion (SPI CS)
   logic              adc_miso_L;       // MISO: The DAC data
   
 
   
   
   // FIR Filter L: CIC compensation
   // TODO: Implement the actually needed FIR filter!!!! Use the simulation programm from the exercises to extract the needed FIR coefficients
   parameter num_of_stages_f1 = 40; // don't need many stages to compensate for CIC
   parameter logic signed [18-1:0] coeffs_f1[num_of_stages_f1] = '{-1470, 293, 596, -3015, 4029, -5425, 1666, 2570, -12645, 16702, -19881, 6435, 10109, -39622, 52964, -53914, 8434, 64223, -162061, 164102, 164102, -162061, 64223, 8434, -53914, 52964, -39622, 10109, 6435, -19881, 16702, -12645, 2570, 1666, -5425, 4029, -3015, 596, 293, -1470};
   
   // FIR Filter L: CIC compensation
   // TODO: Implement the actually needed FIR filter!!!! Use the simulation programm from the exercises to extract the needed FIR coefficients
   parameter num_of_stages_f2 = 40; // don't need many stages to compensate for CIC
   parameter logic signed [18-1:0] coeffs_f2[num_of_stages_f2] = '{-1470, 293, 596, -3015, 4029, -5425, 1666, 2570, -12645, 16702, -19881, 6435, 10109, -39622, 52964, -53914, 8434, 64223, -162061, 164102, 164102, -162061, 64223, 8434, -53914, 52964, -39622, 10109, 6435, -19881, 16702, -12645, 2570, 1666, -5425, 4029, -3015, 596, 293, -1470};


   // Tick generator to divide the 50 MHz clock down to 1 MHz used to run the ADC & DAC
   TickGen #(50) tickGen (
      .clk_i(clk),
      .reset_i(reset),
      .tick_o(tick)
   );

   
   // Instantiate the AdcReader for communication with the ADC - L
   AdcReader reader_L(
      .clk_i(clk),
      .reset_i(reset),
      .start_i(tick),
      .data_o(signal_from_adc_L),
      .spi_clk_o(adc_clk_L),
      .spi_mosi_o(adc_mosi_L),
      .cnv_o(adc_cnv_L),
      .spi_miso_i(adc_miso_L),
      .is_idle_o()
   );

   // Instantiate the AdcReader for communication with the ADC - R
   AdcReader reader_R(
      .clk_i(clk),
      .reset_i(reset),
      .start_i(tick),
      .data_o(signal_from_adc_R),
      .spi_clk_o(adc_clk_R),
      .spi_mosi_o(adc_mosi_R),
      .cnv_o(adc_cnv_R),
      .spi_miso_i(adc_miso_R),
      .is_idle_o()
   );
   
   // CIC decimator to reduce the effective sampling rate by a factor of 10, from 1 MHz down to 100 kHz - L
   CicDecimator decimator_L(
      .clk_i(clk),
      .reset_i(reset),
      .tick_i(tick),
      .signal_i(signal_from_adc_L),
      .signal_o(signal_cic_decimated_L),
      .tick_reduced_o(tick_reduced_L)
   );

   // CIC decimator to reduce the effective sampling rate by a factor of 10, from 1 MHz down to 100 kHz - R
   CicDecimator decimator_R(
      .clk_i(clk),
      .reset_i(reset),
      .tick_i(tick),
      .signal_i(signal_from_adc_R),
      .signal_o(signal_cic_decimated_R),
      .tick_reduced_o(tick_reduced_R)
   );
   
   // Instantiate FIR compensation filter - L
   FirFSM #(
      .num_of_stages(num_of_stages_f1),
      .coeffs(coeffs_f1)
   ) fir1(
      .clk_i(clk),
      .reset_i(reset),
      .tick_i(tick_reduced_L),
      .signal_i(signal_cic_decimated_L),
      .signal_o(signal_fir_filtered_L)
   );

   // Instantiate FIR compensation filter - R
   FirFSM #(
      .num_of_stages(num_of_stages_f2),
      .coeffs(coeffs_f2)
   ) fir2(
      .clk_i(clk),
      .reset_i(reset),
      .tick_i(tick_reduced_R),
      .signal_i(signal_cic_decimated_R),
      .signal_o(signal_fir_filtered_R)
   );

   // Add the L and R line, requiring  tick_reduced_R and tick_reduced_L to agree
   //LineAdd addr1(
   //               .clk_i(clk),
   //               .reset_i(reset),
   //               .tick_ione(tick_reduced_L),
   //               .tick_itwo(tick_reduced_R),
   //               .signal_ione(signal_fir_filtered_L),
   //               .signal_itwo(signal_fir_filtered_R),
   //               .signal_o(signal_LpR) 
   //               ); // 
   assign signal_LpR = signal_fir_filtered_L + signal_fir_filtered_R;

   // Subtract the L and R line, requiring  tick_reduced_R and tick_reduced_L to agree
   //LineSub subtractr1(
   //               .clk_i(clk),
   //               .reset_i(reset),
   //               .tick_ione(tick_reduced_L),
   //               .tick_itwo(tick_reduced_R),
   //               .signal_ione(signal_fir_filtered_L),
   //               .signal_itwo(signal_fir_filtered_R),
   //               .signal_o(signal_LmR) 
   //               );// 
   assign signal_LmR = signal_fir_filtered_L - signal_fir_filtered_R;
 
   // TODO: Block where you can do the audio manipulation. You can grab the L+R and L-R lines. The timing of the data update happens on the tick_reduced_L && tick_reduced_R
   //
   // FYI: I reserved two lines for the data transmission between modules of the L+R and L-R line. You can use them, else we can also delet them if this is handled within your modules.
   //
   //
   // --> output: give the output on to the line "signal_added_forDDSinput" (16bit signed logic)
   //
   //

   FullSinePackage sinePackage(
    .clk_i(tick_reduced),      // use the universal reduced 100 kHz clock
    .reset_i(reset),
    .tick_i(pilot_signal),   // or tick_reduced_R, they should be the same
    .sine_o(stereo_modulation_signal) // 16-bit signed sine wave at 38 kHz
   );

   StereoEncoder stereoEncoder(
    .clk_i(tick_reduced),
    .reset_i(reset),
    .l_i(audio_L),
    .r_i(audio_R),
    .pilot_i(pilot_signal),
    .subcarrier_i(stereo_modulation_signal),
    .mpx_o(stereo_signal) // TODO: we need better naming conventions
   );

   

   // TODO: implement the DDS, threshold -> sqare wave generator


   // TODO: we might want to change the naming of on the FPGA Display
   always_comb begin
        HEX0 = ~8'd120; // T
        HEX1 = ~8'd113; // F
        HEX2 = ~8'd4; // I
        HEX3 = ~8'd116; // H
        HEX4 = ~8'd109; // S
   end
   
   // TODO: update this to 2 adc's and a single line for our square wave output.
   // Wire the ADC to the FPGA via Arduino pins
   assign ARDUINO_IO[0] = dac_cs;
   assign ARDUINO_IO[1] = dac_clk;
   assign ARDUINO_IO[2] = dac_mosi;
   assign ARDUINO_IO[3] = dac_reset_n;
   
   assign ARDUINO_IO[4] = adc_cnv;
   assign ARDUINO_IO[5] = adc_clk;
   assign ARDUINO_IO[6] = adc_mosi;
   assign adc_miso = ARDUINO_IO[7]; // note that the order matters!

endmodule

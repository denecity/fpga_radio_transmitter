// Top-level for the FM stereo radio FPGA project.
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

    // Signal chain (per lane, l = left, r = right):
    //   l_adc / r_adc   -- 1 MHz samples from the two ADCs
    //   l_cic / r_cic   -- 100 kHz after the CIC decimators
    //   l_fir / r_fir   -- 100 kHz after the FIR CIC-compensation filters
    //   mpx             -- 100 kHz stereo composite (L+R, pilot, (L-R)*subcarrier)
    //   fm_square       -- digital FM square wave out to the antenna pin
    //
    // The ADCs run at 1 MHz (the rate their analog anti-aliasing filters were
    // designed for); the CICs decimate by 10 down to 100 kHz; the FIRs
    // compensate the CIC droop and apply any extra audio shaping.

    // --- Clock / reset
    logic clk;
    logic reset;
    assign clk   = MAX10_CLK1_50;
    assign reset = !KEY[0];

    // --- Ticks (one-cycle pulses at the named rate)
    logic tick_1MHz;        // ADC sample tick
    logic tick_125kHz_l;    // L-lane decimated tick from CIC
    logic tick_125kHz_r;    // R-lane decimated tick from CIC
    logic tick_125kHz;
    assign tick_125kHz = tick_125kHz_l; // L, R should always be in sync since they share the same ADC sample tick

    // --- Audio chain signals
    logic signed [15:0] l_adc, r_adc;   // ADC outputs (1 MHz)
    logic signed [15:0] l_cic, r_cic;   // CIC outputs (100 kHz)
    logic signed [15:0] l_fir, r_fir;   // FIR outputs (100 kHz)

    // --- Modulation signals
    logic signed [15:0] pilot_19k;      // 19 kHz pilot tone
    logic signed [15:0] subcarrier_38k; // 38 kHz suppressed subcarrier
    logic signed [15:0] mpx;            // composite stereo, fed into the DDS

    // --- DDS / output
    logic signed [15:0] dds_phase;      // DDS accumulator high bits (debug)
    logic               fm_square;      // square wave to the antenna pin

    // --- ADC SPI lines
    logic adc_clk_l,  adc_clk_r;        // SPI clk
    logic adc_mosi_l, adc_mosi_r;       // MOSI: always 1
    logic adc_cnv_l,  adc_cnv_r;        // Start conversion (SPI CS)
    logic adc_miso_l, adc_miso_r;       // MISO: the ADC data

    // --- FIR coefficients (shared L/R)
    parameter num_of_stages_fir = 80;
    parameter logic signed [18-1:0] coeffs_fir [num_of_stages_fir] = '{-25, 2, 30, 39, 19, -25, -61, -56, 2, 80, 114, 57, -71, -177, -161, 2, 212, 299, 151, -167, -428, -390, -11, 475, 681, 361, -345, -941, -897, -80, 1035, 1599, 974, -706, -2419, -2767, -845, 3062, 7454, 10343, 10343, 7454, 3062, -845, -2767, -2419, -706, 974, 1599, 1035, -80, -897, -941, -345, 361, 681, 475, -11, -390, -428, -167, 151, 299, 212, 2, -161, -177, -71, 57, 114, 80, 2, -56, -61, -25, 19, 39, 30, 2, -25};

    // --- 1 MHz tick generator
    TickGen #(50) tickGen (
        .clk_i  (clk),
        .reset_i(reset),
        .tick_o (tick_1MHz)
    );

    // --- ADCs (L / R)
    AdcReader adc_l (
        .clk_i     (clk),
        .reset_i   (reset),
        .start_i   (tick_1MHz),
        .data_o    (l_adc),
        .spi_clk_o (adc_clk_l),
        .spi_mosi_o(adc_mosi_l),
        .cnv_o     (adc_cnv_l),
        .spi_miso_i(adc_miso_l),
        .is_idle_o ()
    );

    AdcReader adc_r (
        .clk_i     (clk),
        .reset_i   (reset),
        .start_i   (tick_1MHz),
        .data_o    (r_adc),
        .spi_clk_o (adc_clk_r),
        .spi_mosi_o(adc_mosi_r),
        .cnv_o     (adc_cnv_r),
        .spi_miso_i(adc_miso_r),
        .is_idle_o ()
    );

    // --- CIC decimators: 1 MHz -> 100 kHz
    CicDecimator cic_l ( 
        .clk_i         (clk),
        .reset_i       (reset),
        .tick_i        (tick_1MHz),
        .signal_i      (l_adc),
        .signal_o      (l_cic),
        .tick_reduced_o(tick_125kHz_l)
    );

    CicDecimator cic_r (
        .clk_i         (clk),
        .reset_i       (reset),
        .tick_i        (tick_1MHz),
        .signal_i      (r_adc),
        .signal_o      (r_cic),
        .tick_reduced_o(tick_125kHz_r)
    );

    // --- FIR CIC-compensation filters
    FirFSM #(
        .num_of_stages(num_of_stages_fir),
        .coeffs       (coeffs_fir)
    ) fir_l (
        .clk_i   (clk),
        .reset_i (reset),
        .tick_i  (tick_125kHz_l),
        .signal_i(l_cic),
        .signal_o(l_fir)
    );

    FirFSM #(
        .num_of_stages(num_of_stages_fir),
        .coeffs       (coeffs_fir)
    ) fir_r (
        .clk_i   (clk),
        .reset_i (reset),
        .tick_i  (tick_125kHz_r),
        .signal_i(r_cic),
        .signal_o(r_fir)
    );

    // --- Pilot (19 kHz) + subcarrier (38 kHz) generator
    FullSinePackage #(
        .SAMPLE_FREQ(100_000),
        .OUT_FREQ   (19_000)
    ) sineGen (
        .clk_i       (clk),
        .reset_i     (reset),
        .tick_i      (tick_125kHz),
        .sin_o       (pilot_19k),
        .sin_double_o(subcarrier_38k)
    );

    // --- Stereo MPX encoder: L+R, pilot, (L-R)*subcarrier
    StereoEncoder stereoEncoder (
        .clk_i       (clk),
        .reset_i     (reset),
        .tick_i      (tick_125kHz),
        .l_i         (l_fir),
        .r_i         (r_fir),
        .pilot_i     (pilot_19k),
        .subcarrier_i(subcarrier_38k),
        .mpx_o       (mpx)
    );

    // --- DDS FM modulator: mpx -> square wave on antenna pin
    DDS ddsGen (
        .clk_i   (clk),
        .reset_i (reset),
        .signal_i(mpx),
        .square_o(fm_square)
    );

    // --- HEX displays (active-low 7-seg)
    // TODO: spell "RADIO" once we agree on the segment patterns.
    always_comb begin
        HEX0 = 8'hFF;
        HEX1 = 8'hFF;
        HEX2 = 8'hFF;
        HEX3 = ~8'd4;   // 'I' placeholder
        HEX4 = 8'hFF;
    end

    // --- Arduino header pin map
    // TODO: confirm against the board pin-out spreadsheet.
    assign ARDUINO_IO[0] = adc_cnv_r;
    assign ARDUINO_IO[1] = adc_clk_r;
    assign ARDUINO_IO[2] = adc_mosi_r;
    assign adc_miso_r    = ARDUINO_IO[3];

    assign ARDUINO_IO[4] = adc_cnv_l;
    assign ARDUINO_IO[5] = adc_clk_l;
    assign ARDUINO_IO[6] = adc_mosi_l;
    assign adc_miso_l    = ARDUINO_IO[7];   // note that the order matters!

    assign ARDUINO_IO[9] = fm_square;       // FM square wave output

endmodule

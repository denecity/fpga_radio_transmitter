/*
    Turns a signed 16-bit input signal into a DDS-based FM modulator output
*/

/*
module DDS #(
    parameter int N_bits     =  32,
    parameter logic [N_bits-1:0] CARRIER_INC = 0,
    parameter int MOD_SHIFT = 6
    parameter logic signed [N_bits-1:0] threshold = 1 << (N_bits-1) // 2^31 is half of max positive int
)(
    input logic                 clk_i,
    input logic                 reset_i,
    input logic                 tick_i,
    input logic signed[15:0]    signal_i,
    output logic signed [15:0]  signal_o,
    output logic                square_o
);
    // calculate the number of internal bits:    
    logic [N_bits-1:0] phase;
    logic signed [N_bits-1:0] mod_term;
    assign mod_term = N_bits'(signal_i) <<< MOD_SHIFT;

    always_ff @(posedge clk_i) begin
        if (reset_i)
            phase <= '0;
        else if (tick_i)
            phase <= phase + CARRIER_INC + mod_term;
    end

    assign signal_o = phase[N_bits-1 -: 16];
    assign square_o = (phase > threshold);
endmodule
*/
/*
    Decimator with integrated tick_i generator for the reduced sampling rate
*/
module DDS #(
    parameter N_bits     =  32, // the number of bits before overflow
    parameter logic [N_bits-1:0] TUNING_WORD = 1717986918, // round(F_carrier * 2^N_bits / SAMPLE_FREQ)
    parameter logic [N_bits-1:0] SIGNAL_MULTIPLIER = 39, // we have a signal_i with +.- 32768, the correct modulation is 1/1333 signed, which means TUNING_WORD / 1333 = 1288072, 1288072 / 32768 = 39, which is the value we need to multiply the input signal by to get the correct modulation index (frequency deviation) for the FM signal.
    parameter logic [N_bits-1:0] SIGNAL_STRENGTH_MULTIPLIER = 1,
    parameter logic signed [16-1:0] threshold = 1 << (N_bits-1) 
)(
    input logic         clk_i,
    input logic         reset_i,
    input logic signed[15:0] signal_i,
    output logic        square_o  // output signal for be detected
);
    // calculate the number of internal bits:    
    logic signed [N_bits-1:0] added_value;
    logic signed [N_bits-1:0] next_added_value;

    assign next_added_value = (added_value + TUNING_WORD + (signal_i * SIGNAL_MULTIPLIER * SIGNAL_STRENGTH_MULTIPLIER));

    always_ff @(posedge clk_i) begin
        if (reset_i == 1) begin
            added_value <= 0;
        end
        else begin
            added_value <= next_added_value;
        end
    end
    
    
    
    // just use the upper bits for the output (scale it to the number of bits available fot the output)
    assign square_o = (added_value > threshold) ? 1'b0 : 1'b1;

endmodule



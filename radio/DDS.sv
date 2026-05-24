/*
    Turns a signed 16-bit input signal into a DDS-based FM modulator output
*/
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
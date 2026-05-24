/*
    Turns a signed 16-bit input signal into a DDS-based FM modulator output
*/
module DDS #(
    parameter int N_bits     =  16,
    parameter logic signed [N_bits-1:0] threshold = 0
)(
    input logic                 clk_i,
    input logic                 reset_i,
    input logic                 tick_i,
    input logic signed[15:0]    signal_i,
    output logic signed [15:0]  signal_o,
    output logic                square_o
);
    // calculate the number of internal bits:    
    logic signed [N_bits-1:0] phase;

    always_ff @(posedge clk_i) begin
        if (reset_i)
            phase <= '0;
        else if (tick_i)
            phase <= phase + N_bits'(signal_i);
    end

    assign signal_o = phase[N_bits-1 -: 16];
    assign square_o = (phase > threshold);

endmodule



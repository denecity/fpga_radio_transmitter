/*
    Decimator with integrated tick_i generator for the reduced sampling rate
*/
module DDS #(
    parameter N_bits     =  16 // the number of bits before overflow
    parameter logic signed [16-1:0] threshold;
)(
    input logic         clk_i,
    input logic         reset_i,
    input logic         tick_i,   // tick_i of the input sampling rate
    input logic signed[15:0] signal_i,
    output logic signed [15:0] signal_o,
    output logic        square_o  // output signal for be detected
);
    // calculate the number of internal bits:    
    logic signed [N_bits-1:0] added_value;
    logic signed [N_bits-1:0] next_added_value;

    logic sqare;
    
    
    assign next_added_value = tick_i ? 0 : (added_value + signal_i + 1);

    always_ff @(posedge clk_i) begin
        if (reset_i == 1)
            added_value <= 0;
        else if (tick_i == 1) begin // is this right? not sure.... maybe we have to do this always as long as there is no change in the input signal....
            added_value <= next_added_value;
        end
    end
    
    if (added_value > threshold) begin
       assign square_o = 0;
    end 
    else begin
        assign square_o = 1;
    end
    
    
    
    // just use the upper bits for the output (scale it to the number of bits available fot the output)
    assign signal_o = added_value;
    assign square_o = ;

endmodule



/*
    Decimator with integrated tick_i generator for the reduced sampling rate
*/
module CicDecimator #(
    parameter num_of_stages     =  6, // the number of stages
    parameter decimation_factor =  8, // the reduction factor of the sampling rate
    parameter num_bits_input    = 16,
    parameter num_bits_output   = 16
)(
    input logic         clk_i,
    input logic         reset_i,
    input logic         tick_i,   // tick_i of the input sampling rate
    input logic signed  [num_bits_input-1:0]  signal_i,
    output logic signed [num_bits_output-1:0] signal_o,
    output logic        tick_reduced_o  // tick_i for the output samping rate
);
    // calculate the number of internal bits:
    parameter num_bits_internal = $clog2(decimation_factor ** num_of_stages) + num_bits_input;
    
    logic signed [num_bits_internal-1:0] signal_integrated;
    logic signed [num_bits_internal-1:0] comb_in;
    logic signed [num_bits_internal-1:0] result;
    
    // the integrator:
    Integrators #(
            .num_of_stages(num_of_stages),
            .num_bits(num_bits_internal))
        integrators (
            .clk_i(clk_i),
            .reset_i(reset_i),
            .tick_i(tick_i),
            .signal_i(num_bits_internal'(signal_i)),
            .signal_o(signal_integrated)
        );
    
    
    // the decimator tick_i generator:
    parameter size_decimator_counter = $clog2(decimation_factor);
    logic unsigned [size_decimator_counter-1:0] decimator_counter, next_decimator_counter;
    logic decimated_tick;
    always_ff @(posedge clk_i) begin
        if (reset_i == 1)
            decimator_counter <= 0;
        else if (tick_i == 1) begin
            decimator_counter <= next_decimator_counter;
        end
    end // always_ff
    // the decimated tick_i output assignment: Careful: The decimated tick_i must only be one clock cycle long!
    // For this reason we use an and with the tick_i.
    assign decimated_tick = (decimator_counter == size_decimator_counter'(decimation_factor-1)) & tick_i;
    
    // combinational part (just using a conditional assignment):
    assign next_decimator_counter = decimated_tick ? 0 : (decimator_counter + 1);
    
    // the sample rate reduction stage:
    always_ff @(posedge clk_i) begin
        if (reset_i == 1)
            comb_in <= 0;
        else if (decimated_tick == 1) begin
            comb_in <= signal_integrated;
        end
    end // always_ff
    
    // the comb filters:
    Combs #(
            .num_of_stages(num_of_stages),
            .num_bits(num_bits_internal))
        combs (
            .clk_i(clk_i),
            .reset_i(reset_i),
            .tick_i(decimated_tick),
            .signal_i(comb_in),
            .signal_o(result)
        );
    
    // just use the upper bits for the output (scale it to the number of bits available fot the output)
    assign signal_o = result[num_bits_internal-1:num_bits_internal-num_bits_output];
    assign tick_reduced_o = decimated_tick;

endmodule



/*
  Interpolator using an input running at the reduced sampling rate and interpolating
  it to the full rate.
*/
module CicInterpolator #(
    parameter num_of_stages        =  4, // the number of stages
    parameter num_bits_input       = 16,
    parameter num_bits_output      = 16,
    parameter interpolation_factor =  20 // (only used to calculate the number of bits needed internally)
)(
    input logic         clk_i,
    input logic         reset_i,
    input logic         tick_reduced_i,   // tick_i for the input sampling rate
    input logic         tick_i,           // tick_i for the output sampling rate
    input logic signed  [num_bits_input-1:0]  signal_i,
    output logic signed [num_bits_output-1:0] signal_o
);
    // calculate the number of internal bits:
    parameter num_bits_internal = $clog2(interpolation_factor ** num_of_stages) + num_bits_input;
    
    // output of the comb stages
    logic signed [num_bits_internal-1:0] comb_out;
    
    // the comb output re-sampled
    logic signed [num_bits_internal-1:0] comb_out_resampled;
    
    // the result
    logic signed [num_bits_internal-1:0] result;
    
    // the comb filters:
    Combs #(
            .num_of_stages(num_of_stages),
            .num_bits(num_bits_internal))
        combs (
            .clk_i(clk_i),
            .reset_i(reset_i),
            .tick_i(tick_reduced_i),
            .signal_i(num_bits_internal'(signal_i)),
            .signal_o(comb_out)
        );
    
    // here we add a flipflop to reduce the length of the combinational chain:
    always_ff @(posedge clk_i)
    begin
        if (reset_i == 1)
            comb_out_resampled <= 0;
        else if (tick_reduced_i == 1)
            comb_out_resampled <= comb_out;
    end
    
    // the integrators (running at the higher sampling rate):
    Integrators #(
            .num_of_stages(num_of_stages),
            .num_bits(num_bits_internal))
        integrators (
            .clk_i(clk_i),
            .reset_i(reset_i),
            .tick_i(tick_i),
            .signal_i(comb_out_resampled),
            .signal_o(result)
        );
    
    assign signal_o = result[num_bits_internal-1:num_bits_internal-num_bits_output];

endmodule







/////////////////////////////////////////////////////////
//  INTERNALS
/////////////////////////////////////////////////////////


/*
    Internally used integrator stages
*/
module Integrators #(
    parameter num_of_stages,
    parameter num_bits
)(
    input logic         clk_i,
    input logic         reset_i,
    input logic         tick_i,
    input logic signed  [num_bits-1:0] signal_i,
    output logic signed [num_bits-1:0] signal_o
);
    logic signed [num_bits-1:0] inte [num_of_stages:0];
    logic signed [num_bits-1:0] inte_delayed [num_of_stages:1];
    
    assign inte[0] = signal_i;
    genvar k;
    generate
        for(k = 0; k < num_of_stages; k++) begin : gen_int
            // the adders:
            assign inte[k+1] = inte[k] + inte_delayed[k+1];
            
            // the flipflops:
            always_ff @(posedge clk_i) begin
                if (reset_i == 1)
                    inte_delayed[k+1] <= 0;
                else if (tick_i == 1)
                    inte_delayed[k+1] <= inte[k+1];
            end // always_ff
        end // gen_int
    endgenerate
    assign signal_o = inte_delayed[num_of_stages];
endmodule


/*
    Internally used comb filter stages
*/
module Combs #(
    parameter num_of_stages,
    parameter num_bits
)(
    input logic         clk_i,
    input logic         reset_i,
    input logic         tick_i,
    input logic signed  [num_bits-1:0] signal_i,
    output logic signed [num_bits-1:0] signal_o
);
    logic signed [num_bits-1:0] comb[num_of_stages:0];
    logic signed [num_bits-1:0] comb_delayed [num_of_stages-1:0];
    
    // comb filter stages
    assign comb[0] = signal_i;
    genvar k;
    generate
        for(k = 0; k < num_of_stages; k++) begin : gen_comb
            // the subtractors:
            assign comb[k+1] = comb[k] - comb_delayed[k];
            
            // the flipflops:
            always_ff @(posedge clk_i) begin
                if (reset_i == 1)
                    comb_delayed[k] <= 0;
                else if (tick_i == 1) begin
                    comb_delayed[k] <= comb[k];
                end
            end // always_ff
        end // gen_int
    endgenerate
    assign signal_o = comb[num_of_stages];

endmodule

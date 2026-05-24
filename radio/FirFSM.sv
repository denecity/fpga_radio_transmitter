/**
  FIR filter implemented as a finite state machine
  The coefficients are passed on as a signal in the format
  Qx.num_of_bits_io-1. For example, in the case of 16 signal bits,
  a coefficient of 1.0 is represented as 2**15.
  
  The number of internally used bits can be higher than the number of signal
  bits in order to avoid overflows.
**/
module FirFSM #(
        parameter num_of_bits_internal = 18,
        parameter num_of_bits_io       = 16,
        parameter num_of_stages        =  3,
        parameter logic signed[num_of_bits_internal-1:0] 
            coeffs[num_of_stages] = '{0,0,0}
    )
    (
        input logic                                   clk_i,
        input logic                                   reset_i,
        input logic                                   tick_i,
        
        input  logic signed[num_of_bits_io-1:0]       signal_i,   
        output logic signed[num_of_bits_io-1:0]       signal_o
    );
    
    // THE DATA PATH
    /////////////////
    
    // the accumulator:
    logic signed [num_of_bits_internal-1:0] sum;
    logic clear_accumulator; // (controlled by the FSM)
    logic accumulate; // (controlled by the FSM)
    
    // the sum output of the multiply-add unit
    logic signed [num_of_bits_internal-1:0] calc_sum;
    
    
    // the registered input signal (a shift register for the inputs):
    logic signed [num_of_bits_io-1:0] in_reg [num_of_stages];
    logic shift; // (controlled by the FSM)
    
    // the counter for the iteration (controlled by the FSM)
    logic unsigned [$clog2(num_of_stages)-1:0] iteration, next_iteration;
    
    // the registered output signal:
    logic signed [num_of_bits_internal-1:0] out_reg, next_out_reg;
    logic register_output; // (controlled by the FSM)
    
    
    // the input shift register:
    genvar i;
    generate
        for (i = 0; i < num_of_stages-1; i++) begin: gen_shiftreg
            always_ff @(posedge clk_i) begin
                if (reset_i == 1)
                    in_reg[i+1] <= 0;
                else if (shift == 1) begin
                    in_reg[i+1] <= in_reg[i];
                    // the input to the SR:
                    if (i == 0) in_reg[0] <= signal_i;
                end // if
            end // always_ff
        end // for
    endgenerate
    
    
    // the multiply / add unit:
    MultiphyAddSaturated #(
        .num_of_bits_internal(num_of_bits_internal),
        .num_of_bits_io(num_of_bits_io)
    ) multAdd (
        .signal_in(in_reg[iteration]),
        .coeff(coeffs[iteration]),
        .summand(sum),
        .sum(calc_sum)
    );
    
    
    // the accumulator register (sum)
    always_ff @(posedge clk_i) begin
        if (reset_i == 1) begin
            sum <= 0;
        end else begin
            if (clear_accumulator == 1)
                sum <= 0;
            else if (accumulate == 1)
                sum <= calc_sum;
        end // if
    end //always_ff
    
    
    // the output register
    always_ff @(posedge clk_i) begin
        if (reset_i == 1) begin
            out_reg <= 0;
        end else begin
            if (register_output == 1)
                out_reg <= sum;
        end // if
    end //always_ff
    
    
    // the output saturation:
    parameter max =  2**(num_of_bits_io-1)-1;
    parameter min = -2**(num_of_bits_io-1);
    always_comb begin
        signal_o = num_of_bits_io'(out_reg);
        if (out_reg > max)
            signal_o = max;
        if (out_reg < min)
            signal_o = min;
    end
    
    
    // THE FSM
    ///////////
    
    // the states of the FSM
    typedef enum logic [1:0] {
        IDLE,
        ITERATE,
        FINISH
    } state_t;
    
    // the state of the FSM
    state_t  state, next_state;
    
    // flipflops of the FSM:
    always_ff @(posedge clk_i) begin
        if (reset_i == 1) begin
            state <= IDLE;
            iteration <= 0;
        end else begin
            state <= next_state;
            iteration <= next_iteration;
        end // if
    end //always_ff
    
    
    // Combinational part of the FSM
    always_comb begin
        // defaults:
        next_state = state;
        next_iteration = 0;
        
        shift = 0;
        accumulate = 0;
        clear_accumulator = 0;
        register_output = 0;
        
        case(state)
            IDLE: begin
                    clear_accumulator = 1;
                    if (tick_i == 1) begin
                        next_state = ITERATE;
                        shift = 1;
                    end
                end
            
            ITERATE: begin
                    accumulate = 1;
                    // here we need to convert both operands to the same number of bits (ugly, I know...)
                    if ($bits(num_of_stages-1)'(iteration) == num_of_stages-1)
                        next_state = FINISH;
                    else
                        next_iteration = iteration + 1;
                end
                
            FINISH: begin
                    register_output = 1;
                    next_state = IDLE;
                end
            
            default:
                next_state = IDLE;
        endcase
    end // always_comb
    
endmodule



/**
 This module performs the multiplication and addition and saturates the
 result to the max. possible value (without wrapping).
 
 sum = signal_in*coeff + summand
 
**/
module MultiphyAddSaturated #(
    parameter num_of_bits_internal = 18,
    parameter num_of_bits_io       = 16 
)(
    input  logic signed[num_of_bits_io-1:0]       signal_in,
    input  logic signed[num_of_bits_internal-1:0] coeff,
    input  logic signed[num_of_bits_internal-1:0] summand,
    output logic signed[num_of_bits_internal-1:0] sum
);

    // the min / max value for the signed internal signals
    parameter max =  2**(num_of_bits_internal-1)-1;
    parameter min = -2**(num_of_bits_internal-1);
    // multiplier result:
    logic signed [num_of_bits_internal+num_of_bits_io-1:0] mult_out;
    // adder result: Needs an additional bit!
    logic signed [num_of_bits_internal:0] add_out;
    // the adder and multiplier
    assign mult_out = coeff * signal_in;
    assign add_out  = (num_of_bits_internal+1)'(mult_out >> (num_of_bits_io-1)) + summand;
    // saturation:
    always_comb begin
        sum = num_of_bits_internal'(add_out);
        if (add_out > max)
            sum = max;
        if (add_out < min)
            sum = min;
    end
endmodule


// Here is another implementation of the FIR as a pipeline, we don't need it for this exercise, but feel free to take a look.
//It is clearly more sophisticated than the automatically generated one!

/**
  FIR filter implemented as a pipeline
  The coefficients are passed on as a signal in the format
  Qx.num_of_bits_io-1. For example, in the case of 16 signal bits,
  a coefficient of 1.0 is represented as 2**15.
  
  The number of internally used bits can be higher than the number of signal
  bits in order to avoid overflows.
**/
module FirPipeline #(
        parameter num_of_bits_internal = 18,
        parameter num_of_bits_io       = 16,
        parameter num_of_stages        =  5,
        parameter logic signed[num_of_bits_internal-1:0]
            coeffs[num_of_stages] = '{32768, 0, 0, 0, -32768}
    )
    (
        input logic                                   clk,
        input logic                                   reset,
        input logic                                   tick,    // only run if 1
        
        input  logic signed[num_of_bits_io-1:0]       signal_in,   
        output logic signed[num_of_bits_io-1:0]       signal_out
    );
    
    
    // pipeline signals
    logic signed [num_of_bits_internal-1:0] sum_out  [num_of_stages:0];
    logic signed [num_of_bits_internal-1:0] del_out  [num_of_stages:0];
    
    
    genvar i;
    // generate the registers (for delaying the signal):
    generate
        for (i = 0; i < num_of_stages-1; i++) begin : loop_ff
        
            // the flipflop:
            always_ff @(posedge clk) begin
                if (reset == 1)
                    del_out[i] <= 0;
                else if (tick == 1) begin
                    del_out[i] <= sum_out[i+1];
                end // else if tick
            end // always_ff
            
        end // loop
    endgenerate
    // trick to simplify the structure: Add an additional stage and set it to 0
    assign del_out[num_of_stages-1] = 0;
    
    
    // generate the combinational part: The multiply-add units
    generate
        for (i = 0; i < num_of_stages; i++) begin : loop_comb
            MultiphyAddSaturated #(
                .num_of_bits_internal(num_of_bits_internal),
                .num_of_bits_io(num_of_bits_io)
            ) multAdd (
                .signal_in(signal_in),
                .coeff(coeffs[i]),
                .summand(del_out[i]),
                .sum(sum_out[i])
            );	
        end // for
    endgenerate
    
    
    // the output (including saturation):
    always_comb begin
        signal_out = num_of_bits_io'(sum_out[0]);
        if (sum_out[0] > (2**(num_of_bits_io-1)-1))
            signal_out = 2**(num_of_bits_io-1)-1;
        if (sum_out[0] < -(2**(num_of_bits_io-1)))
            signal_out = -(2**(num_of_bits_io-1));
    end

endmodule

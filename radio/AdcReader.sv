/*
    Interface to the ADC (AD7004) in turbo mode without busy indicator
    (see data Rev. B, page 29)
    
    The read-out is started by setting start to 1.
    The result is available at data once the DONE state is reached.
    To get back to IDLE, set start to 0.
    
    Yves Acremann, 30.12.2020
*/
    
module AdcReader(    
    input                   clk_i,      // clock
    input                   reset_i,    // reset
    output signed [15:0]    data_o,     // received data
    input                   start_i,    // start the readout
    output                  is_idle_o,  // 1 if in idle state
    output                  spi_clk_o,  // SPI clk
    output                  spi_mosi_o, // MOSI: always 1
    output                  cnv_o,      // Start conversion (SPI CS)
    input                   spi_miso_i  // MISO: The DAC data
    );
    
    
    typedef enum logic [4:0] {
        IDLE,           // wait for start = 1
        CNV_DOWN,       // put the conv line to 0
        CLK_SET,        // set the clock
        CLK_LOW,        // clock low, read the data on the falling edge
        DONE            // wait for the start signal to go to 0
    } state_t;
    
    // state signals
    state_t state_q, state_d;
    // the bit counter
    logic [3:0] bit_counter_q, bit_counter_d;
    // signals for bit register
    logic [15:0] data_rx_q, data_rx_d;
    // signals for register holding the output data
    logic signed [15:0] out_data_q, out_data_d;
    
    
    // all flipflops with sync. reset
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            state_q <= IDLE;
            bit_counter_q <= 0;
            data_rx_q <= 0;
            out_data_q <= 0;
        end else begin
            state_q <= state_d;
            bit_counter_q <= bit_counter_d;
            data_rx_q <= data_rx_d;
            out_data_q <= out_data_d;
        end // if not reset
    end // always_ff
    
    
    
    // next-state logic
    always_comb begin
        // default: stay where you are
        state_d = state_q;
        bit_counter_d = bit_counter_q;
        data_rx_d = data_rx_q;
        out_data_d = out_data_q;
        
        // if in idle: wait for the start to go '1'
        if (state_q == IDLE) begin
            bit_counter_d = 15;
            if (start_i) state_d = CNV_DOWN;
        end
        
        // start the readout
        if (state_q == CNV_DOWN) begin
            state_d = CLK_SET;
        end
        
        // set the clock and on the falling edge: read the miso
        if (state_q == CLK_SET) begin
            data_rx_d[bit_counter_q] = spi_miso_i;
            state_d = CLK_LOW;
        end
        
        // falling edge of the clock, increment the bit counter
        if (state_q == CLK_LOW) begin
            if (bit_counter_q > 0) begin
                bit_counter_d = bit_counter_q - 4'd1;
                state_d = CLK_SET;
            end else state_d = DONE;
        end
        
        // wait for the start signal to clear and store the result
        if (state_q == DONE) begin
            if (!start_i) state_d = IDLE;
            out_data_d = $signed(data_rx_q);
        end
    end // next state logic
    
    
    
    // Output signals:
    //================
    assign spi_mosi_o = 1;
    
    // clk is 0 for IDLE, CS_DOWN, WAIT and DONE;
    // clk is therefore 1 for SEL_BIT only!
    // (so the rising edge happens DURING the transition to SEL_BIT!)
    assign spi_clk_o = (state_q == CLK_SET);
    
    // the CS is 1 for IDLE and DONE, otherwise it is 0
    assign cnv_o = ((state_q == IDLE) | (state_q == DONE));
    
    // is_idle is 1 only in IDLE:
    assign is_idle_o = (state_q == IDLE);
    
    assign data_o = out_data_q;
    
endmodule

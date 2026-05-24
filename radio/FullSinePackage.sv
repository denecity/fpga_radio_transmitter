/*
    Generates a sine wave at OUT_FREQ and its double using a CORDIC pipeline.
    Already includes a NCO (phase accumulator + tuning word) to produce the desired frequency.

    Doubled with sin(2 theta) = 2 * sin(theta) * cos(theta), so the CORDIC outputs feed a multiplier.
    Both outs are in the "16384 = 1.0" convention and should be routed to the stereo encoder's pilot and subcarrier inputs, respectively.
*/


module FullSinePackage
    #(
        parameter int SAMPLE_FREQ = 100_000,   // tick rate driving the phase accumulator
        parameter int OUT_FREQ    = 19_000,    // will also get doubled
        parameter int N_BITS      = 32
    )(
        input  logic                clk_i,
        input  logic                reset_i,
        input  logic                tick_i,        // advance the phase accumulator only on tick
        output logic signed [15:0]  sin_o,         // sin(2*pi*OUT_FREQ*t)
        output logic signed [15:0]  sin_double_o   // sin(2*pi*2*OUT_FREQ*t)
    );

    // round(OUT_FREQ * 2^N_BITS / SAMPLE_FREQ).  SAMPLE_FREQ is the tick rate (one phase step per tick_i).
    localparam logic [N_BITS-1:0] TUNING_WORD =
        ((longint'(OUT_FREQ) << N_BITS) + (longint'(SAMPLE_FREQ) >> 1))
        / longint'(SAMPLE_FREQ);

    // CORDIC seed
    // The pipeline computes x_o = x_i * cos(theta) / (2K) with the
    // 16-iteration gain K ~= 0.60725.  Choosing x_i = round(2*K*2^14)
    // makes the output magnitude equal to 2^14 -> Q1.14 sin/cos.
    localparam logic signed [15:0] CORDIC_SEED = 16'sd19898;

    // Phase accumulator works in the "unsigned, 0..2*pi" convention. Overflows naturally at 2^N_BITS.
    logic [N_BITS-1:0] phase;

    always_ff @(posedge clk_i) begin
        if (reset_i)
            phase <= '0;
        else if (tick_i)
            phase <= phase + TUNING_WORD;
    end

    // Top 16 bits feed CORDIC as an angle in [0, 2*pi).
    logic [15:0] cordic_angle;
    assign cordic_angle = phase[N_BITS-1 -: 16];

    // CORDIC
    logic signed [15:0] cos_q, sin_q;

    CordicPipeline cordic_inst (
        .clk    (clk_i),
        .reset  (reset_i),
        .tick   (1'b1),               // run every cycle
        .angle  (cordic_angle),
        .x_i    (CORDIC_SEED),
        .x_o    (cos_q),
        .y_o    (sin_q)
    );

    // Doubled-frequency tone
    // sin(2 theta) = 2 * sin(theta) * cos(theta)
    //   sin_q, cos_q are Q1.14  -> product = sin(2 theta) * 2^27
    //   >>> 13 brings the result back to Q1.14.
    logic signed [31:0] mix_prod;
    assign mix_prod = sin_q * cos_q;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            sin_o        <= '0;
            sin_double_o <= '0;
        end else if (tick_i) begin
            sin_o        <= sin_q;
            sin_double_o <= 16'(mix_prod >>> 13);
        end
    end

endmodule

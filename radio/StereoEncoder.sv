/*
    Single-clock synchronous block.  Combinational arithmetic recomputes
    every cycle; the output register latches a fresh composite sample on
    each tick_i pulse.

    All i/o is 16-bit signed with +-1.0 => +-32768.

    Interface contract:
        clk_i, reset_i         : synchronous, reset is active-high
        tick_i                 : one-cycle pulse per output sample
        l_i, r_i               : sampled when tick_i is high
        pilot_i, subcarrier_i  : sampled when tick_i is high, from the
                                 same instance of FullSinePackage
        mpx_o                  : valid one cycle after the tick_i pulse
*/

module StereoEncoder (
    input  logic                clk_i,
    input  logic                reset_i,
    input  logic                tick_i,   // emit one fresh mpx sample per tick

    input  logic signed [15:0]  l_i,
    input  logic signed [15:0]  r_i,
    input  logic signed [15:0]  pilot_i,
    input  logic signed [15:0]  subcarrier_i,

    output logic signed [15:0]  mpx_o
);

    // ── Pilot amplitude constant ──────────────────────────────────────
    //   Broadcast spec: pilot peak = 9 % of composite peak.
    //   PILOT_GAIN 0.09 * 32768 approx 2949.
    //   Combined with the >>> 14 below, this gives pilot_scaled a
    //   peak of 2949 (i.e. 0.09) at the 19-bit accumulator.
    localparam logic signed [15:0] PILOT_GAIN = 16'sd2949;

    // ── Combinational arithmetic ──────────────────────────────────────
    //   All wires below are recomputed every clock from current inputs.
    //   One output register at the end makes the module single-cycle.

    // Stage 1 : L+R / L-R matrix.  +1 bit for the sum.
    logic signed [16:0] sum_lr;
    logic signed [16:0] diff_lr;
    assign sum_lr  = 17'(l_i) + 17'(r_i); // 17'(..) means that the 16-bit input is treated as 17-bit signed before the addition
    assign diff_lr = 17'(l_i) - 17'(r_i);

    // Stage 2a : scale pilot down to 9 %.
    //   pilot_i (16384 = 1.0) * PILOT_GAIN (2949 = 0.09) -> Q-mix.
    //   The >>> 14 unwinds the pilot's "16384 = 1.0" so the result
    //   sits in the "32768 = 1.0" convention.
    logic signed [31:0] pilot_prod;
    logic signed [16:0] pilot_scaled;
    assign pilot_prod   = pilot_i * PILOT_GAIN;
    assign pilot_scaled = 17'(pilot_prod >>> 14);

    // Stage 2b : DSB-SC modulation of L-R by the 38 kHz subcarrier.
    //   Same >>> 14 trick to land back in 32768 = 1.0.
    logic signed [33:0] diff_prod;
    logic signed [16:0] diff_modulated;
    assign diff_prod      = diff_lr * subcarrier_i;
    assign diff_modulated = 17'(diff_prod >>> 14);

    // Stage 3 : sum-with-pilot, then final composite.
    logic signed [17:0] lpr_with_pilot;
    logic signed [18:0] mpx_full;
    assign lpr_with_pilot = 18'(sum_lr) + 18'(pilot_scaled);
    assign mpx_full       = 19'(lpr_with_pilot) + 19'(diff_modulated);

    always_ff @(posedge clk_i) begin
        if (reset_i)      mpx_o <= '0;
        else if (tick_i)  mpx_o <= 16'(mpx_full >>> 3); //   >>> 3 leaves enough headroom that no input combination can overflow 16-bit signed.
                                                         // might need to be amplified on the FM modulator side
    end

endmodule

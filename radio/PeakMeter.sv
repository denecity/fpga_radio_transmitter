
module PeakMeter #(
    parameter int CLK_HZ = 50_000_000
)(
    input logic clk_i,
    input logic reset_i,
    input logic signed [15:0] signal_i,
    input logic [3:0] stage_i,
    output logic [7:0] HEX0, HEX1, HEX2, HEX3, HEX4
);

    logic [15:0] mag;
    always_comb mag = signal_i[15] ? ((~signal_i) + 16'd1) : signal_i;

    logic [25:0] win_cnt;
    logic [15:0] peak_run, peak_hold;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            win_cnt <= 0;
            peak_run <= 0;
            peak_hold <= 0;
        end else begin
            if (mag > peak_run) peak_run <= mag;
            if (win_cnt >= CLK_HZ - 1) begin
                win_cnt <= 0;
                peak_hold <= peak_run;
                peak_run <= mag;
            end else begin
                win_cnt <= win_cnt + 1;
            end
        end
    end

    function automatic [7:0] seg7(input [3:0] n);
        case (n)
            4'h0: seg7 = 8'hc0; 4'h1: seg7 = 8'hF9;
            4'h2: seg7 = 8'hA4; 4'h3: seg7 = 8'hB0;
            4'h4: seg7 = 8'h99; 4'h5: seg7 = 8'h92;
            4'h6: seg7 = 8'h82; 4'h7: seg7 = 8'hF8;
            4'h8: seg7 = 8'h80; 4'h9: seg7 = 8'h90;
            4'hA: seg7 = 8'h88; 4'hB: seg7 = 8'h83;
            4'hC: seg7 = 8'hC6; 4'hD: seg7 = 8'hA1;
            4'hE: seg7 = 8'h86; 4'hF: seg7 = 8'h8E;
        endcase
    endfunction


    always_comb begin
        HEX0 = seg7(peak_hold[3:0]);
        HEX1 = seg7(peak_hold[7:4]);
        HEX2 = seg7(peak_hold[11:8]);
        HEX3 = seg7(peak_hold[15:12]);
        HEX4 = seg7(stage_i);
    end
endmodule
            
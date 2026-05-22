module TickGen
    #(
        parameter DIVIDER = 50
    )(
        input clk_i,
        input reset_i, 
        
        output tick_o     // 1 for one clock cycle every DIVIDER cycles
    );



    logic unsigned [23:0] counter;
    
    
    always_ff @(posedge clk_i)
    begin
        if (reset_i)
            counter <= 0;
        else
            if (counter < DIVIDER)
                counter <= counter + 24'd1;
            else
                counter <= 0;
    end // ff

    assign tick_o = (counter == 0);

endmodule

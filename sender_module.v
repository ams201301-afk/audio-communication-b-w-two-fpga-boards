module part1 (
    CLOCK_50, CLOCK2_50, KEY,
    FPGA_I2C_SCLK, FPGA_I2C_SDAT,
    AUD_XCK, AUD_DACLRCK, AUD_ADCLRCK,
    AUD_BCLK, AUD_ADCDAT, AUD_DACDAT,
    pwm_pin
);

    input CLOCK_50, CLOCK2_50;
    input [0:0] KEY;

    output pwm_pin;

    output FPGA_I2C_SCLK;
    inout FPGA_I2C_SDAT;

    output AUD_XCK;
    input AUD_DACLRCK, AUD_ADCLRCK, AUD_BCLK;
    input AUD_ADCDAT;
    output AUD_DACDAT;

    wire reset = ~KEY[0];

    wire read_ready, write_ready;
    wire read, write;

    wire [15:0] writedata_left, writedata_right;
    wire [15:0] readdata_left, readdata_right;

    ////////////////////////////////////////////////////
    // PWM Sender Wiring
    ////////////////////////////////////////////////////

    reg start_pwm;
    wire pwm_busy;

    PWM_Sender_16bit pwm_tx (
        .clk(CLOCK_50),
        .rst(reset),
        .start(start_pwm),
        .data_in(readdata_left),
        .pwm_out(pwm_pin),
        .busy(pwm_busy)
    );

    ////////////////////////////////////////////////////
    // Trigger PWM when new audio sample available
    ////////////////////////////////////////////////////

    always @(posedge CLOCK_50 or posedge reset) begin
        if (reset)
            start_pwm <= 0;
        else begin
            if (read_ready && !pwm_busy)
                start_pwm <= 1;
            else
                start_pwm <= 0;
        end
    end

    ////////////////////////////////////////////////////
    // Audio Codec Control
    ////////////////////////////////////////////////////

    assign read  = read_ready;   // continuously read ADC
    assign write = 1'b0;         // not using DAC

    assign writedata_left  = 16'd0;
    assign writedata_right = 16'd0;

    ////////////////////////////////////////////////////
    // Clock + Config (unchanged)
    ////////////////////////////////////////////////////

    clock_generator my_clock_gen(
        CLOCK2_50,
        reset,
        AUD_XCK
    );

    audio_and_video_config cfg(
        CLOCK_50,
        reset,
        FPGA_I2C_SDAT,
        FPGA_I2C_SCLK
    );

    audio_codec codec(
        CLOCK_50,
        reset,
        read, write,
        writedata_left, writedata_right,
        AUD_ADCDAT,
        AUD_BCLK,
        AUD_ADCLRCK,
        AUD_DACLRCK,
        read_ready, write_ready,
        readdata_left, readdata_right,
        AUD_DACDAT
    );

endmodule

module PWM_Sender_16bit (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire [15:0] data_in,
    output reg  pwm_out,
    output reg  busy
);

    // ==========================
    // PARAMETERS (Match Receiver)
    // ==========================
    parameter PWM_PERIOD = 390;
    parameter WIDTH_ONE  = 260;   // >170
    parameter WIDTH_ZERO = 100;   // <170

    // ==========================
    // INTERNAL REGISTERS
    // ==========================
    reg [8:0] counter;          // 0 to 389
    reg [4:0] bit_index;        // 0 to 15
    reg [8:0] current_width;
    reg [15:0] data_reg;
    reg sending;

    // ==========================
    // MAIN LOGIC
    // ==========================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter       <= 0;
            bit_index     <= 0;
            current_width <= 0;
            pwm_out       <= 0;
            busy          <= 0;
            sending       <= 0;
            data_reg      <= 0;
        end
        else begin

            // ======================
            // START TRANSMISSION
            // ======================
            if (start && !sending) begin
                sending   <= 1;
                busy      <= 1;
                bit_index <= 0;
                counter   <= 0;
                data_reg  <= data_in;
            end

            // ======================
            // DURING TRANSMISSION
            // ======================
            if (sending) begin

                // Select width based on current bit
                if (data_reg[15 - bit_index])
                    current_width <= WIDTH_ONE;
                else
                    current_width <= WIDTH_ZERO;

                // PWM generation
                if (counter < current_width)
                    pwm_out <= 1;
                else
                    pwm_out <= 0;

                // Counter increment
                if (counter < PWM_PERIOD - 1)
                    counter <= counter + 1;
                else begin
                    counter <= 0;

                    // Move to next bit after full period
                    if (bit_index < 15)
                        bit_index <= bit_index + 1;
                    else begin
                        // Transmission complete
                        sending <= 0;
                        busy    <= 0;
                        pwm_out <= 0;
                    end
                end
            end
            else begin
                pwm_out <= 0;
            end
        end
    end

endmodule



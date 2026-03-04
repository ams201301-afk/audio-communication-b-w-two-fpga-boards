module part1 (
    CLOCK_50, CLOCK2_50, KEY,
    FPGA_I2C_SCLK, FPGA_I2C_SDAT,
    AUD_XCK, AUD_DACLRCK, AUD_ADCLRCK,
    AUD_BCLK, AUD_ADCDAT, AUD_DACDAT,
    pwm_pin
);

    input CLOCK_50, CLOCK2_50;
    input [0:0] KEY;
    input pwm_pin;

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
    // PWM Receiver Wiring
    ////////////////////////////////////////////////////

    wire [15:0] pwm_sample;
    wire pwm_valid;

    PWM_Receiver_16bit pwm_rx (
        .clk(CLOCK_50),
        .rst(reset),
        .pwm_in(pwm_pin),
        .data_out(pwm_sample),
        .data_valid(pwm_valid)
    );

    ////////////////////////////////////////////////////
    // Sample Buffer
    ////////////////////////////////////////////////////

    reg [15:0] sample_reg;
    reg sample_ready;

    always @(posedge CLOCK_50 or posedge reset) begin
        if (reset) begin
            sample_reg   <= 16'd0;
            sample_ready <= 0;
        end
        else begin
            if (pwm_valid) begin
                sample_reg   <= pwm_sample;
                sample_ready <= 1;
            end

            if (write_ready && sample_ready)
                sample_ready <= 0;
        end
    end

    ////////////////////////////////////////////////////
    // Send to Codec (Stereo Same Data)
    ////////////////////////////////////////////////////

    assign writedata_left  = sample_reg;
    assign writedata_right = sample_reg;

    assign read  = 1'b0;                         // not using ADC
    assign write = write_ready & sample_ready;

    ////////////////////////////////////////////////////
    // Codec + Clock Modules (unchanged)
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


module PWM_Receiver_16bit (
    input  wire clk,
    input  wire rst,
    input  wire pwm_in,
    output reg  [15:0] data_out,
    output reg  data_valid
);

    parameter PWM_PERIOD = 390;
    parameter THRESHOLD  = 170;

    reg [8:0]  count;        // 390 fits in 9 bits
    reg [8:0]  high_count;
    reg [4:0]  bit_index;
    reg        receiving;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count       <= 0;
            high_count  <= 0;
            bit_index   <= 0;
            data_out    <= 16'd0;
            data_valid  <= 0;
            receiving   <= 0;
        end
        else begin

            data_valid <= 0;   // default: 1-cycle pulse

            // Start reception when PWM goes high
            if (!receiving && pwm_in) begin
                receiving  <= 1;
                count      <= 0;
                high_count <= 0;
                bit_index  <= 0;
            end

            if (receiving) begin

                count <= count + 1;

                if (pwm_in)
                    high_count <= high_count + 1;

                // End of one PWM period
                if (count == PWM_PERIOD - 1) begin

                    // Bit decision
                    if (high_count > THRESHOLD)
                        data_out[15 - bit_index] <= 1;
                    else
                        data_out[15 - bit_index] <= 0;

                    bit_index  <= bit_index + 1;
                    count      <= 0;
                    high_count <= 0;

                    // If 16 bits received
                    if (bit_index == 15) begin
                        receiving  <= 0;
                        data_valid <= 1;   // pulse
                    end
                end
            end
        end
    end

endmodule



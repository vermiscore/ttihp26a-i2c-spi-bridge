/*
 * i2c_peripheral.v — I2C peripheral (slave) receiver
 *
 * Receives I2C write transactions addressed to I2C_ADDR.
 * The first byte after the address byte is treated as the SPI register
 * address; subsequent bytes are SPI data bytes.
 *
 * Output: byte_valid pulses high for one clock cycle when a full byte has
 *         been received.  is_addr_byte distinguishes the first data byte
 *         (register address) from payload data bytes.
 *
 * Open-drain model:
 *   scl_in / sda_in  — sampled line levels (after external pull-up)
 *   scl_oe / sda_oe  — drive line LOW when asserted (1 = pull low)
 *   Clock stretching is NOT implemented (kept simple for TT tile area).
 */

`default_nettype none

module i2c_peripheral #(
    parameter [6:0] I2C_ADDR = 7'h28   // 7-bit I2C address (configurable)
) (
    input  wire clk,
    input  wire rst_n,

    // I2C open-drain interface
    input  wire scl_in,
    input  wire sda_in,
    output reg  scl_oe,   // unused in peripheral-only design, kept for ACK
    output reg  sda_oe,   // pull SDA low to ACK

    // Received byte interface
    output reg [7:0] rx_byte,
    output reg       byte_valid,    // 1-cycle pulse
    output reg       is_addr_byte,  // high when rx_byte is the first data byte
    output reg       bus_active     // high between START and STOP
);

    // -----------------------------------------------------------------------
    // Edge detect on SCL and SDA (two-stage synchroniser + edge detect)
    // -----------------------------------------------------------------------
    reg [2:0] scl_sr, sda_sr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_sr <= 3'b111;
            sda_sr <= 3'b111;
        end else begin
            scl_sr <= {scl_sr[1:0], scl_in};
            sda_sr <= {sda_sr[1:0], sda_in};
        end
    end

    wire scl_stable  = scl_sr[2];
    wire sda_stable  = sda_sr[2];
    wire scl_rising  = (scl_sr[2:1] == 2'b01);
    wire sda_falling = (sda_sr[2:1] == 2'b10);
    wire sda_rising  = (sda_sr[2:1] == 2'b01);

    // START: SDA falls while SCL is high
    wire start_det = sda_falling & scl_stable;
    // STOP:  SDA rises while SCL is high
    wire stop_det  = sda_rising  & scl_stable;

    // -----------------------------------------------------------------------
    // State machine
    // -----------------------------------------------------------------------
    localparam S_IDLE    = 3'd0;
    localparam S_ADDR    = 3'd1;   // receive 7-bit addr + R/W bit
    localparam S_ACK     = 3'd2;   // pull SDA low for ACK
    localparam S_DATA    = 3'd3;   // receive data byte
    localparam S_DACK    = 3'd4;   // ACK data byte
    localparam S_NACK    = 3'd5;   // NACK (wrong address or read req)

    reg [2:0] state;
    reg [3:0] bit_cnt;    // counts 0..7 within a byte, then ACK
    reg [7:0] shift_reg;
    reg       first_data; // tracks whether next DATA byte is the addr byte

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            bit_cnt      <= 4'd0;
            shift_reg    <= 8'd0;
            rx_byte      <= 8'd0;
            byte_valid   <= 1'b0;
            is_addr_byte <= 1'b0;
            bus_active   <= 1'b0;
            sda_oe       <= 1'b0;
            scl_oe       <= 1'b0;
            first_data   <= 1'b0;
        end else begin
            byte_valid <= 1'b0;    // default: deassert

            // STOP always resets
            if (stop_det) begin
                state      <= S_IDLE;
                bus_active <= 1'b0;
                sda_oe     <= 1'b0;
                scl_oe     <= 1'b0;
            end

            // START (or repeated START) begins address reception
            else if (start_det) begin
                state      <= S_ADDR;
                bit_cnt    <= 4'd0;
                bus_active <= 1'b1;
                sda_oe     <= 1'b0;
                first_data <= 1'b1;
            end

            else begin
                case (state)
                    // ----------------------------------------------------------
                    S_ADDR: begin
                        if (scl_rising) begin
                            shift_reg <= {shift_reg[6:0], sda_stable};
                            bit_cnt   <= bit_cnt + 1;
                            if (bit_cnt == 4'd7) begin
                                // shift_reg[7:1] = addr, shift_reg[0] = R/W
                                if (shift_reg[7:1] == I2C_ADDR && shift_reg[0] == 1'b0) begin
                                    state  <= S_ACK;  // matched, write
                                    sda_oe <= 1'b1;   // pull SDA low = ACK
                                end else begin
                                    state  <= S_NACK; // mismatch or read
                                end
                                bit_cnt <= 4'd0;
                            end
                        end
                    end

                    // ----------------------------------------------------------
                    S_ACK: begin
                        // Release SDA after SCL falls
                        if (!scl_stable) begin
                            sda_oe <= 1'b0;
                            state  <= S_DATA;
                        end
                    end

                    // ----------------------------------------------------------
                    S_DATA: begin
                        if (scl_rising) begin
                            shift_reg <= {shift_reg[6:0], sda_stable};
                            bit_cnt   <= bit_cnt + 1;
                            if (bit_cnt == 4'd7) begin
                                rx_byte      <= {shift_reg[6:0], sda_stable};
                                byte_valid   <= 1'b1;
                                is_addr_byte <= first_data;
                                first_data   <= 1'b0;
                                state        <= S_DACK;
                                sda_oe       <= 1'b1;
                                bit_cnt      <= 4'd0;
                            end
                        end
                    end

                    // ----------------------------------------------------------
                    S_DACK: begin
                        if (!scl_stable) begin
                            sda_oe <= 1'b0;
                            state  <= S_DATA;
                        end
                    end

                    // ----------------------------------------------------------
                    S_NACK: begin
                        // Stay here until STOP
                        sda_oe <= 1'b0;
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule

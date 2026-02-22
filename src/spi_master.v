/*
 * spi_master.v — Simple SPI master (Mode 0, MSB-first)
 *
 * Clocks out 8-bit bytes on MOSI and simultaneously captures MISO.
 * SPI clock = clk / (2 * CLK_DIV).  With CLK_DIV=5 and clk=10MHz → SPI=1MHz.
 *
 * Usage:
 *   1. Assert tx_start for 1 clock with tx_byte set.
 *   2. Wait for tx_done (1-cycle pulse).
 *   3. Read rx_byte.
 */

`default_nettype none

module spi_master #(
    parameter CLK_DIV = 5   // SCK = clk / (2 * CLK_DIV)
) (
    input  wire       clk,
    input  wire       rst_n,

    // Control
    input  wire [7:0] tx_byte,
    input  wire       tx_start,   // 1-cycle pulse to begin transfer
    output reg        tx_done,    // 1-cycle pulse when transfer complete

    // Received data
    output reg [7:0]  rx_byte,

    // SPI bus
    output reg        spi_sck,
    output reg        spi_mosi,
    input  wire       spi_miso,
    output reg        spi_cs_n
);

    localparam IDLE = 2'd0, ASSERT_CS = 2'd1, TRANSFER = 2'd2, DEASSERT = 2'd3;

    reg [1:0]  state;
    reg [7:0]  clk_cnt;
    reg [3:0]  bit_cnt;    // 0..7
    reg [7:0]  shift_tx;
    reg [7:0]  shift_rx;
    reg        sck_phase;  // 0 = about to rise, 1 = about to fall

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            clk_cnt   <= 8'd0;
            bit_cnt   <= 4'd0;
            shift_tx  <= 8'd0;
            shift_rx  <= 8'd0;
            sck_phase <= 1'b0;
            spi_sck   <= 1'b0;
            spi_mosi  <= 1'b0;
            spi_cs_n  <= 1'b1;
            tx_done   <= 1'b0;
            rx_byte   <= 8'd0;
        end else begin
            tx_done <= 1'b0;

            case (state)
                // ----------------------------------------------------------
                IDLE: begin
                    spi_sck  <= 1'b0;
                    spi_cs_n <= 1'b1;
                    if (tx_start) begin
                        shift_tx  <= tx_byte;
                        bit_cnt   <= 4'd0;
                        clk_cnt   <= 8'd0;
                        sck_phase <= 1'b0;
                        state     <= ASSERT_CS;
                    end
                end

                // ----------------------------------------------------------
                // Half-cycle CS setup before first SCK edge
                ASSERT_CS: begin
                    spi_cs_n <= 1'b0;
                    spi_mosi <= shift_tx[7];   // pre-load MSB
                    clk_cnt  <= clk_cnt + 1;
                    if (clk_cnt >= CLK_DIV - 1) begin
                        clk_cnt <= 8'd0;
                        state   <= TRANSFER;
                    end
                end

                // ----------------------------------------------------------
                TRANSFER: begin
                    clk_cnt <= clk_cnt + 1;
                    if (clk_cnt >= CLK_DIV - 1) begin
                        clk_cnt   <= 8'd0;
                        sck_phase <= ~sck_phase;
                        spi_sck   <= sck_phase; // toggle

                        if (sck_phase == 1'b0) begin
                            // Rising edge — sample MISO
                            shift_rx <= {shift_rx[6:0], spi_miso};
                        end else begin
                            // Falling edge — shift out next MOSI bit
                            if (bit_cnt == 4'd7) begin
                                state   <= DEASSERT;
                                rx_byte <= {shift_rx[6:0], spi_miso}; // last sample
                                tx_done <= 1'b1;
                            end else begin
                                bit_cnt  <= bit_cnt + 1;
                                shift_tx <= {shift_tx[6:0], 1'b0};
                                spi_mosi <= shift_tx[6];  // next bit
                            end
                        end
                    end
                end

                // ----------------------------------------------------------
                DEASSERT: begin
                    spi_sck  <= 1'b0;
                    clk_cnt  <= clk_cnt + 1;
                    if (clk_cnt >= CLK_DIV - 1) begin
                        spi_cs_n <= 1'b1;
                        state    <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

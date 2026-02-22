/*
 * tt_um_vermiscore_i2c_spi_bridge — Top-level wrapper for Tiny Tapeout IHP
 *
 * Ported from tt10-i2c-spi-bridge (Sky130) to TTIHP26a (IHP sg13g2 130nm).
 * The RTL itself is fully process-independent; only the wrapper and
 * build-system files change.
 *
 * Pinout (TT standard 24-pin interface):
 *   ui_in[0]  — i2c_scl_in   (pull high externally; drive low to pull SCL)
 *   ui_in[1]  — i2c_sda_in   (pull high externally; drive low to pull SDA)
 *   ui_in[2]  — spi_miso
 *   ui_in[7:3]— unused (tie low)
 *
 *   uo_out[0] — i2c_scl_oe   (1 → pull SCL low via external open-drain FET)
 *   uo_out[1] — i2c_sda_oe   (1 → pull SDA low)
 *   uo_out[2] — spi_sck
 *   uo_out[3] — spi_mosi
 *   uo_out[4] — spi_cs_n
 *   uo_out[7:5]— unused (driven 0)
 *
 *   uio_*     — unused bidirectional bus
 */

`default_nettype none

module tt_um_vermiscore_i2c_spi_bridge (
    // TT standard interface
    input  wire [7:0] ui_in,     // dedicated inputs
    output wire [7:0] uo_out,    // dedicated outputs
    input  wire [7:0] uio_in,    // bidirectional port — inputs
    output wire [7:0] uio_out,   // bidirectional port — outputs
    output wire [7:0] uio_oe,    // bidirectional port — direction (1 = output)
    input  wire       ena,       // always 1 when the design is powered on
    input  wire       clk,       // system clock (from TT mux)
    input  wire       rst_n      // active-low synchronous reset (from TT mux)
);

    // -----------------------------------------------------------------------
    // Internal signal wiring
    // -----------------------------------------------------------------------
    wire scl_in   = ui_in[0];
    wire sda_in   = ui_in[1];
    wire miso     = ui_in[2];

    wire scl_oe, sda_oe;
    wire spi_sck, spi_mosi, spi_cs_n;

    // -----------------------------------------------------------------------
    // Bridge instantiation
    // -----------------------------------------------------------------------
    bridge_ctrl u_bridge (
        .clk        (clk),
        .rst_n      (rst_n),
        // I2C
        .scl_in     (scl_in),
        .sda_in     (sda_in),
        .scl_oe     (scl_oe),
        .sda_oe     (sda_oe),
        // SPI
        .spi_sck    (spi_sck),
        .spi_mosi   (spi_mosi),
        .spi_miso   (miso),
        .spi_cs_n   (spi_cs_n)
    );

    // -----------------------------------------------------------------------
    // Output assignment
    // -----------------------------------------------------------------------
    assign uo_out  = {3'b000, spi_cs_n, spi_mosi, spi_sck, sda_oe, scl_oe};

    // Bidirectional bus unused — drive all outputs to 0, direction = input
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    // Suppress unused-signal warnings
    wire _unused = &{ena, uio_in};

endmodule

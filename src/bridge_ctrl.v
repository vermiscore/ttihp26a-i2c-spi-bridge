/*
 * bridge_ctrl.v — I2C-to-SPI bridge controller
 *
 * Connects the i2c_peripheral and spi_master modules.
 * Protocol (I2C write transaction):
 *   [I2C START] [ADDR+W] [ACK] [reg_byte] [ACK] [data0] [ACK] ... [STOP]
 *
 * The first data byte after the I2C address is the SPI target register address.
 * Every subsequent byte (until STOP) is clocked out as SPI data with the
 * SPI CS asserted for each byte individually.
 *
 * A small 8-byte TX FIFO buffers incoming bytes so the I2C and SPI state
 * machines can run at their own rates.
 */

`default_nettype none

module bridge_ctrl (
    input  wire clk,
    input  wire rst_n,

    // I2C (open-drain)
    input  wire scl_in,
    input  wire sda_in,
    output wire scl_oe,
    output wire sda_oe,

    // SPI
    output wire spi_sck,
    output wire spi_mosi,
    input  wire spi_miso,
    output wire spi_cs_n
);

    // -----------------------------------------------------------------------
    // I2C peripheral
    // -----------------------------------------------------------------------
    wire [7:0] rx_byte;
    wire       byte_valid;
    wire       is_addr_byte;
    wire       bus_active;

    i2c_peripheral #(.I2C_ADDR(7'h28)) u_i2c (
        .clk         (clk),
        .rst_n       (rst_n),
        .scl_in      (scl_in),
        .sda_in      (sda_in),
        .scl_oe      (scl_oe),
        .sda_oe      (sda_oe),
        .rx_byte     (rx_byte),
        .byte_valid  (byte_valid),
        .is_addr_byte(is_addr_byte),
        .bus_active  (bus_active)
    );

    // -----------------------------------------------------------------------
    // Simple 8-entry FIFO (shift register style)
    // -----------------------------------------------------------------------
    localparam FIFO_DEPTH = 8;
    reg [7:0] fifo [0:FIFO_DEPTH-1];
    reg [3:0] fifo_wr_ptr;   // next write position (0..7)
    reg [3:0] fifo_rd_ptr;   // next read position  (0..7)
    reg [3:0] fifo_count;
    wire      fifo_full  = (fifo_count == FIFO_DEPTH[3:0]);
    wire      fifo_empty = (fifo_count == 4'd0);

    // Push on byte_valid (drop if full — shouldn't happen at normal speeds)
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr <= 4'd0;
            fifo_rd_ptr <= 4'd0;
            fifo_count  <= 4'd0;
            for (i = 0; i < FIFO_DEPTH; i = i+1)
                fifo[i] <= 8'd0;
        end else begin
            if (byte_valid && !fifo_full) begin
                fifo[fifo_wr_ptr[2:0]] <= rx_byte;
                fifo_wr_ptr <= (fifo_wr_ptr == FIFO_DEPTH-1) ? 4'd0 : fifo_wr_ptr + 1;
                fifo_count  <= fifo_count + 1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // SPI master
    // -----------------------------------------------------------------------
    reg  [7:0] spi_tx_byte;
    reg        spi_tx_start;
    wire       spi_tx_done;

    spi_master #(.CLK_DIV(5)) u_spi (
        .clk       (clk),
        .rst_n     (rst_n),
        .tx_byte   (spi_tx_byte),
        .tx_start  (spi_tx_start),
        .tx_done   (spi_tx_done),
        .rx_byte   (),           // RX not used in write-only bridge
        .spi_sck   (spi_sck),
        .spi_mosi  (spi_mosi),
        .spi_miso  (spi_miso),
        .spi_cs_n  (spi_cs_n)
    );

    // -----------------------------------------------------------------------
    // Bridge control — drains FIFO into SPI master
    // -----------------------------------------------------------------------
    localparam BS_IDLE    = 2'd0;
    localparam BS_LOAD    = 2'd1;
    localparam BS_WAIT    = 2'd2;

    reg [1:0] bstate;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bstate      <= BS_IDLE;
            spi_tx_byte  <= 8'd0;
            spi_tx_start <= 1'b0;
            fifo_rd_ptr  <= 4'd0;
            // fifo_count decremented here when we pop
        end else begin
            spi_tx_start <= 1'b0;  // default

            case (bstate)
                BS_IDLE: begin
                    if (!fifo_empty) begin
                        spi_tx_byte  <= fifo[fifo_rd_ptr[2:0]];
                        fifo_rd_ptr  <= (fifo_rd_ptr == FIFO_DEPTH-1) ? 4'd0 : fifo_rd_ptr + 1;
                        fifo_count   <= fifo_count - 1;
                        bstate       <= BS_LOAD;
                    end
                end

                BS_LOAD: begin
                    spi_tx_start <= 1'b1;
                    bstate       <= BS_WAIT;
                end

                BS_WAIT: begin
                    if (spi_tx_done)
                        bstate <= BS_IDLE;
                end

                default: bstate <= BS_IDLE;
            endcase
        end
    end

endmodule

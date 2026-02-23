`default_nettype none

module i2c_peripheral #(
    parameter [6:0] I2C_ADDR = 7'h28
) (
    input  wire clk,
    input  wire rst_n,
    input  wire scl_in,
    input  wire sda_in,
    output reg  scl_oe,
    output reg  sda_oe,
    output reg [7:0] rx_byte,
    output reg       byte_valid,
    output reg       is_addr_byte,
    output reg       bus_active
);

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
    wire scl_falling = (scl_sr[2:1] == 2'b10);
    wire sda_falling = (sda_sr[2:1] == 2'b10);
    wire sda_rising  = (sda_sr[2:1] == 2'b01);

    wire start_det = sda_falling & scl_stable;
    wire stop_det  = sda_rising  & scl_stable;

    localparam S_IDLE = 3'd0;
    localparam S_ADDR = 3'd1;
    localparam S_ACK  = 3'd2;
    localparam S_DATA = 3'd3;
    localparam S_DACK = 3'd4;
    localparam S_NACK = 3'd5;

    reg [2:0] state;
    reg [3:0] bit_cnt;
    reg [7:0] shift_reg;
    reg       first_data;
    reg       scl_seen_high;  // tracks that SCL went high in ACK state

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            bit_cnt        <= 4'd0;
            shift_reg      <= 8'd0;
            rx_byte        <= 8'd0;
            byte_valid     <= 1'b0;
            is_addr_byte   <= 1'b0;
            bus_active     <= 1'b0;
            sda_oe         <= 1'b0;
            scl_oe         <= 1'b0;
            first_data     <= 1'b0;
            scl_seen_high  <= 1'b0;
        end else begin
            byte_valid <= 1'b0;

            if (stop_det) begin
                state      <= S_IDLE;
                bus_active <= 1'b0;
                sda_oe     <= 1'b0;
                scl_oe     <= 1'b0;
            end else if (start_det) begin
                state         <= S_ADDR;
                bit_cnt       <= 4'd0;
                shift_reg     <= 8'd0;
                bus_active    <= 1'b1;
                sda_oe        <= 1'b0;
                first_data    <= 1'b1;
                scl_seen_high <= 1'b0;
            end else begin
                case (state)
                    S_ADDR: begin
                        if (scl_rising) begin
                            shift_reg <= {shift_reg[6:0], sda_stable};
                            if (bit_cnt == 4'd7) begin
                                if ({shift_reg[6:0], sda_stable} == {I2C_ADDR, 1'b0}) begin
                                    state         <= S_ACK;
                                    sda_oe        <= 1'b1;
                                    scl_seen_high <= 1'b0;
                                end else begin
                                    state <= S_NACK;
                                end
                                bit_cnt <= 4'd0;
                            end else begin
                                bit_cnt <= bit_cnt + 1;
                            end
                        end
                    end

                    S_ACK: begin
                        if (scl_rising)  scl_seen_high <= 1'b1;
                        if (scl_falling && scl_seen_high) begin
                            sda_oe        <= 1'b0;
                            state         <= S_DATA;
                            shift_reg     <= 8'd0;
                            bit_cnt       <= 4'd0;
                            scl_seen_high <= 1'b0;
                        end
                    end

                    S_DATA: begin
                        if (scl_rising) begin
                            shift_reg <= {shift_reg[6:0], sda_stable};
                            if (bit_cnt == 4'd7) begin
                                rx_byte      <= {shift_reg[6:0], sda_stable};
                                byte_valid   <= 1'b1;
                                is_addr_byte <= first_data;
                                first_data   <= 1'b0;
                                state        <= S_DACK;
                                sda_oe       <= 1'b1;
                                scl_seen_high <= 1'b0;
                                bit_cnt      <= 4'd0;
                            end else begin
                                bit_cnt <= bit_cnt + 1;
                            end
                        end
                    end

                    S_DACK: begin
                        if (scl_rising)  scl_seen_high <= 1'b1;
                        if (scl_falling && scl_seen_high) begin
                            sda_oe        <= 1'b0;
                            state         <= S_DATA;
                            shift_reg     <= 8'd0;
                            bit_cnt       <= 4'd0;
                            scl_seen_high <= 1'b0;
                        end
                    end

                    S_NACK: begin
                        sda_oe <= 1'b0;
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule

# I2C-to-SPI Bridge — TTIHP26a

**Author:** vermiscore  
**Process:** IHP sg13g2 130 nm BiCMOS (via Tiny Tapeout IHP 26a shuttle)  
**Shuttle deadline:** 2026-03-23  
**Original design:** [tt10-i2c-spi-bridge](https://github.com/vermiscore/tt10-i2c-spi-bridge) (Sky130)

---

## How it works

This design acts as a bridge between an I2C bus (as a peripheral/slave device
at address **0x28**) and an SPI bus (as the master).

```
Host MCU ──(I2C)──► [I2C Peripheral FSM] ──► [8-byte FIFO] ──► [SPI Master] ──► SPI device
```

### I2C write protocol

```
START  ADDR(0x28)+W  ACK  reg_addr  ACK  data[0]  ACK  data[1]  ACK …  STOP
```

1. The first data byte after the address phase is treated as the **SPI register
   address** (passed through as the first SPI byte).
2. Every subsequent byte is a **SPI data byte**, each sent as an independent
   SPI transaction (CS asserted per byte).

### SPI parameters

| Parameter | Value |
|-----------|-------|
| Mode | Mode 0 (CPOL=0, CPHA=0) |
| Bit order | MSB-first |
| Clock | clk / 10 (default: 1 MHz at 10 MHz system clock) |
| CS polarity | Active-low |

### Open-drain I2C model

The design implements the open-drain model:
- `scl_oe` / `sda_oe` in **uo_out** are **active-high pull-down enables**.
- You need **external pull-up resistors** (typically 4.7 kΩ to 3.3 V) on SCL
  and SDA on the demo PCB.

---

## Pinout

| Pin | Direction | Signal | Description |
|-----|-----------|--------|-------------|
| `ui_in[0]` | IN | `i2c_scl_in` | SCL sampled level |
| `ui_in[1]` | IN | `i2c_sda_in` | SDA sampled level |
| `ui_in[2]` | IN | `spi_miso` | SPI MISO |
| `uo_out[0]` | OUT | `i2c_scl_oe` | 1 → pull SCL low |
| `uo_out[1]` | OUT | `i2c_sda_oe` | 1 → pull SDA low (ACK) |
| `uo_out[2]` | OUT | `spi_sck` | SPI clock |
| `uo_out[3]` | OUT | `spi_mosi` | SPI data out |
| `uo_out[4]` | OUT | `spi_cs_n` | SPI chip-select (active-low) |

---

## How to test

1. Apply a 10 MHz clock on `clk` and hold `rst_n` low for ≥ 5 cycles, then
   release.
2. Connect pull-up resistors on SCL/SDA.
3. Send an I2C write transaction:

```
START  0x50 (0x28<<1 | W)  ACK
       0x01 (register address)  ACK
       0xA5 (data)  ACK
STOP
```

4. Observe `spi_sck`, `spi_mosi`, `spi_cs_n` on an oscilloscope or logic
   analyser.  You should see CS go low, then 16 SPI clocks (2 bytes: 0x01,
   0xA5), then CS go high.

---

## Sky130 → IHP migration notes

The RTL is fully process-independent standard Verilog.  No PDK-specific
primitives (sky130_fd_sc_hd cells, etc.) were used in the original design, so
the only changes required for TTIHP26a were:

- **Build system:** switched from OpenLane / Sky130 to **LibreLane / sg13g2**.
- **info.yaml:** updated `top_module` name prefix convention (already using
  `tt_um_` prefix — no change needed).
- **GitHub Actions:** uses the `ttihp-verilog-template` workflow (LibreLane).

If you need to verify timing at IHP, note:
- sg13g2 is 130 nm BiCMOS; typical cell delays are faster than Sky130.
- The 10 MHz target clock has ample margin.

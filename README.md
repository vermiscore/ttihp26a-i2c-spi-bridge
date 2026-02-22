[![GDS](../../actions/workflows/gds.yaml/badge.svg)](../../actions/workflows/gds.yaml)
[![Test](../../actions/workflows/test.yaml/badge.svg)](../../actions/workflows/test.yaml)
[![Docs](../../actions/workflows/docs.yaml/badge.svg)](../../actions/workflows/docs.yaml)

# I2C-to-SPI Bridge — TTIHP26a

**Ported from:** [tt10-i2c-spi-bridge](https://github.com/vermiscore/tt10-i2c-spi-bridge) (Tiny Tapeout 10 / Sky130)  
**Target shuttle:** [TTIHP26a](https://app.tinytapeout.com/shuttles/ttihp26a) — IHP sg13g2 130 nm  
**Submission deadline:** 2026-03-23

---

Implements an **I2C peripheral → SPI master bridge** in synthesisable Verilog.

- I2C device address: **0x28**
- SPI Mode 0, MSB-first, CS active-low
- SPI clock ≈ 1 MHz (system clock / 10, parameterisable)
- 8-entry byte FIFO decouples I2C and SPI timing

See [docs/info.md](docs/info.md) for full documentation, pinout and test
instructions.

## Quick start

1. **Use this template** → create `ttihp26a-i2c-spi-bridge` in your GitHub account.
2. Replace the Verilog source files in `src/` with your versions if you have
   modifications from the TT10 repo.
3. The `gds` GitHub Action will automatically synthesise and place-and-route
   using LibreLane + IHP sg13g2 PDK.
4. Submit to TTIHP26a via [app.tinytapeout.com](https://app.tinytapeout.com).

## Repository structure

```
src/
  project.v          Top-level TT wrapper
  i2c_peripheral.v   I2C peripheral state machine
  spi_master.v       SPI master (Mode 0)
  bridge_ctrl.v      Bridge controller + FIFO
test/
  test.py            cocotb testbench
  Makefile           cocotb Makefile (Icarus Verilog)
docs/
  info.md            Project documentation
info.yaml            Tiny Tapeout project metadata
```

## Sky130 → IHP migration summary

The RTL required **zero changes** — all modules use standard synthesisable
Verilog with no PDK-specific primitives.  Only the build system and workflow
files were updated:

| Item | TT10 (Sky130) | TTIHP26a (IHP) |
|------|--------------|----------------|
| PDK | Sky130 | IHP sg13g2 |
| Flow | OpenLane | LibreLane |
| GH Action ref | `@sky130` | `@ihp` |
| `info.yaml` | (same structure) | (same structure) |

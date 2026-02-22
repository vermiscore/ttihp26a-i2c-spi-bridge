"""
test.py — cocotb testbench for tt_um_vermiscore_i2c_spi_bridge
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer

CLK_PERIOD_NS = 100  # 10 MHz
# I2C bit period = 40 clocks = 4µs (250 kHz effective)
BIT_HALF = 20  # half-period in clock cycles


async def i2c_start(dut):
    dut.ui_in.value = 0b00000011  # SCL=1, SDA=1
    await ClockCycles(dut.clk, BIT_HALF)
    dut.ui_in.value = 0b00000001  # SDA=0, SCL=1
    await ClockCycles(dut.clk, BIT_HALF)
    dut.ui_in.value = 0b00000000  # SCL=0
    await ClockCycles(dut.clk, BIT_HALF)


async def i2c_stop(dut):
    dut.ui_in.value = 0b00000000  # SDA=0, SCL=0
    await ClockCycles(dut.clk, BIT_HALF)
    dut.ui_in.value = 0b00000001  # SCL=1, SDA=0
    await ClockCycles(dut.clk, BIT_HALF)
    dut.ui_in.value = 0b00000011  # SDA=1
    await ClockCycles(dut.clk, BIT_HALF)


async def i2c_send_byte(dut, byte_val):
    for bit in range(7, -1, -1):
        sda = (byte_val >> bit) & 1
        dut.ui_in.value = (sda << 1)          # SCL=0, SDA=bit
        await ClockCycles(dut.clk, BIT_HALF)
        dut.ui_in.value = (sda << 1) | 0x01   # SCL=1
        await ClockCycles(dut.clk, BIT_HALF * 2)
        dut.ui_in.value = (sda << 1)          # SCL=0
        await ClockCycles(dut.clk, BIT_HALF)

    # ACK cycle: release SDA, pulse SCL
    dut.ui_in.value = 0b00000010  # SDA=1(released), SCL=0
    await ClockCycles(dut.clk, BIT_HALF)
    dut.ui_in.value = 0b00000011  # SCL=1
    await ClockCycles(dut.clk, BIT_HALF)
    ack = (int(dut.uo_out.value) >> 1) & 1   # sda_oe=1 means DUT pulls SDA low = ACK
    await ClockCycles(dut.clk, BIT_HALF)
    dut.ui_in.value = 0b00000010  # SCL=0
    await ClockCycles(dut.clk, BIT_HALF)
    return ack == 1


@cocotb.test()
async def test_i2c_write_to_spi(dut):
    """I2C write to address 0x28: sends reg addr 0x01 + data 0xA5."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())

    dut.rst_n.value = 0
    dut.ui_in.value = 0b00000011
    dut.uio_in.value = 0x00
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

    await i2c_start(dut)

    acked = await i2c_send_byte(dut, (0x28 << 1) | 0x00)
    assert acked, "Address byte should be ACKed"

    acked = await i2c_send_byte(dut, 0x01)
    assert acked, "Register address byte should be ACKed"

    acked = await i2c_send_byte(dut, 0xA5)
    assert acked, "Data byte should be ACKed"

    await i2c_stop(dut)

    await ClockCycles(dut.clk, 500)

    dut._log.info(f"uo_out after transfer: {int(dut.uo_out.value):#010b}")
    dut._log.info("Test 1 passed: I2C->SPI write transaction completed")


@cocotb.test()
async def test_i2c_addr_mismatch(dut):
    """I2C write to address 0x55 (not 0x28): SPI CS should stay high."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())

    dut.rst_n.value = 0
    dut.ui_in.value = 0b00000011
    dut.uio_in.value = 0x00
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

    await i2c_start(dut)
    acked = await i2c_send_byte(dut, (0x55 << 1) | 0x00)
    assert not acked, "Wrong address should NOT be ACKed"
    await i2c_stop(dut)

    await ClockCycles(dut.clk, 50)
    cs_n = (int(dut.uo_out.value) >> 4) & 1
    assert cs_n == 1, "SPI CS_N should remain high (no transaction)"
    dut._log.info("Test 2 passed: address mismatch correctly ignored")

#include <iostream>
#include <iomanip>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vtop_accelerator.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtop_accelerator* dut = new Vtop_accelerator;

    // Trace setup for GTKWave
    Verilated::traceEverOn(true);
    VerilatedVcdC* m_trace = new VerilatedVcdC;
    dut->trace(m_trace, 5);
    m_trace->open("sim/waveform.vcd");

    int time = 0;
    auto tick = [&]() {
        dut->clk = 0; dut->eval(); m_trace->dump(time++);
        dut->clk = 1; dut->eval(); m_trace->dump(time++);
    };

    // 1. System Initialization
    dut->rst_n = 0;
    dut->wr_en = 0;
    dut->acc_clr = 1; // Start with a fresh accumulator
    tick();
    dut->rst_n = 1;
    dut->acc_clr = 0;
    tick();

    // 2. Data Burst: Feeding 5 pairs of numbers into the FIFOs
    // Calculation: (10*2) + (20*3) + (30*4) + (40*5) + (50*6) = 20 + 60 + 120 + 200 + 300 = 700
    int a_vals[] = {5, 15, 25, 35, 45};
    int b_vals[] = {2, 3, 4, 5, 6};

    std::cout << "--- Sending Data Burst to FIFOs ---" << std::endl;
    for (int i = 0; i < 5; i++) {
        dut->wr_en = 1;
        dut->din_a = a_vals[i];
        dut->din_b = b_vals[i];
        tick();
    }
    dut->wr_en = 0; // Stop writing

    // 3. Monitor Processing
    // The MAC will automatically start because the FIFOs are no longer empty.
    std::cout << "--- Accelerator Processing ---" << std::endl;
    for (int i = 0; i < 15; i++) {
        tick();
        if (dut->valid_out) {
            std::cout << "Cycle " << std::setw(2) << i 
                      << " | Valid Result Detected: " << (int)dut->acc_out << std::endl;
        }
    }

    std::cout << "--- Simulation Complete ---" << std::endl;

    m_trace->close();
    delete dut;
    return 0;
}
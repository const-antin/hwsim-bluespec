# Bluespec Counter Project

This is a classic Bluespec SystemVerilog (BSV) project that demonstrates:
- Module design with interfaces
- Testbench creation
- Verilog generation
- Simulation and testing

## Project Structure

```
hwsim-bluespec/
├── Makefile          # Build configuration
├── README.md         # This file
└── src/
    └── Top.bsv       # Main program with counter and test
```

## Prerequisites

You need to have Bluespec SystemVerilog (BSV) compiler installed. You can download it from:
- [Bluespec Inc.](https://www.bluespec.com/) (commercial)
- [Bluespec SystemVerilog](https://github.com/B-Lang-org/bsc) (open source)

## Building and Running

### Bluesim Simulation (Recommended)
```bash
make b_all
```
This will compile, link, and run the simulation using Bluesim.

### Generate Verilog
```bash
make v_compile
```
This will generate Verilog files in the `verilog_RTL/` directory.

### Run Verilog Simulation
```bash
make v_all
```
This will compile, link, and run the simulation using a Verilog simulator.

### Clean Build Artifacts
```bash
make clean
```

### Show Help
```bash
make help
```

## Available Make Targets

- `b_compile` - Compile for Bluesim
- `b_link` - Link a Bluesim executable
- `b_sim` - Run the Bluesim simulation
- `b_all` - Complete Bluesim workflow (compile + link + simulate)
- `v_compile` - Compile for Verilog generation
- `v_link` - Link a Verilog simulation executable
- `v_sim` - Run the Verilog simulation
- `v_all` - Complete Verilog workflow (compile + link + simulate)
- `clean` - Remove build artifacts
- `help` - Show this help information

## Module Description

### Top Module (`src/Top.bsv`)
Contains:
1. **Counter Interface**: Defines the API for the counter module
2. **Counter Implementation**: A simple 8-bit counter with increment, reset, and getValue methods
3. **Test Sequence**: Comprehensive testbench that verifies:
   - Initial value is 0
   - Increment functionality
   - Reset functionality
   - Overflow behavior (255 + 1 = 0)

## Generated Files

After running `make v_compile`, you'll find:
- `verilog_RTL/mkTop.v` - Verilog for the top module
- `build_v/` - Build artifacts
- `build_b_sim/` - Bluesim build artifacts

## Bluespec Features Demonstrated

1. **Interfaces**: The `Counter_IFC` interface defines the module's API
2. **Registers**: Using `mkReg` for state storage
3. **Methods**: Action methods for side effects, value methods for reading
4. **FSM**: Using `StmtFSM` for test sequence control
5. **Packages**: Proper package organization

## Extending the Project

To add new modules:
1. Create new modules in `src/Top.bsv` or create separate `.bsv` files
2. Update the `TOPMODULE` variable in the Makefile if needed
3. Add new test sequences as needed

## Troubleshooting

- If `bsc` command is not found, ensure Bluespec is properly installed and in your PATH
- If compilation fails, check that all imports are correct
- For simulation issues, ensure all dependencies are satisfied
- For Verilog simulation, ensure you have a Verilog simulator installed (iverilog, vcs, etc.) 
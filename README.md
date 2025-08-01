# HWSIM Bluespec

## Prerequisites

- Bluespec SystemVerilog (BSV) compiler
- C++ compiler (for DPI components)
- CMake (for Ramulator2 build)

## Building

1. **Build Ramulator2** (required for memory simulation):
   ```bash
   cd ramulator2
   mkdir build && cd build
   cmake ..
   make -j$(nproc)
   cd ../..
   ```
## Running Tests

### Run All Tests

To run all available tests:

```bash
make auto_tests
```

This will:
- Automatically discover all test modules in the codebase
- Run each test with a 4-minute timeout
- Generate output files in `test_results/` directory
- Report pass/fail status for each test

### Run Specific Tests

To run a specific test module:

```bash
make b_all TOPFILE=test/ReconfigurabilityTest.bsv TOPMODULE=mkReconfigurabilityTest
make b_all TOPFILE=test/ArbiterStressTest.bsv TOPMODULE=mkArbiterStressTest
make b_all TOPFILE=test/AccumBigTileTest.bsv TOPMODULE=mkAccumBigTileTest
```

### Test Output

Test results are stored in the `test_results/` directory:
- `{ModuleName}.out`: Standard output from the test
- `{ModuleName}.err`: Error output from the test


## Configuration

The system can be configured through various parameters defined in `src/Parameters.bsv`:
- Number of PCUs
- Input/output port counts
- Memory system parameters
- Interconnect configuration

## Memory System Integration

The project integrates with Ramulator2 for realistic memory system simulation:
- Supports various DRAM standards (DDR4, DDR5, HBM, etc.)
- Configurable memory controllers and schedulers
- Performance analysis and trace recording

## Troubleshooting

### Common Issues

1. **Build failures**: Ensure Ramulator2 is built first
2. **Test timeouts**: Increase timeout in `run_tests.sh` if needed

## Contributing

When adding new tests:
1. Create a new BSV file in the `test/` directory
2. Define a module with `Empty` interface
3. The test will be automatically discovered by `run_tests.sh`
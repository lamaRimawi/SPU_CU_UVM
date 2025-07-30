# SPN Cryptographic Unit UVM Verification Environment

A comprehensive SystemVerilog-based verification environment using Universal Verification Methodology (UVM) for Substitution-Permutation Network (SPN) cryptographic unit verification and validation.

## About

This project implements a complete UVM-based verification environment for a Substitution-Permutation Network (SPN) cryptographic unit. The project demonstrates advanced verification techniques for cryptographic hardware, including encryption/decryption operations, S-box transformations, and key scheduling verification.

## Project Overview

This SPN Crypto Unit verification project includes:
- **SPN Cryptographic Design** - Complete 16-bit block cipher implementation with 32-bit keys
- **UVM Verification Framework** - Industry-standard verification methodology
- **Cryptographic Testing** - Comprehensive encryption/decryption validation
- **Golden Reference Model** - Bit-accurate reference implementation
- **Functional Verification** - Complete algorithm and edge case testing
- **Professional Documentation** - Complete verification planning and results

## Cryptographic Algorithm Overview

### Substitution-Permutation Network (SPN)
The SPN is a foundational cryptographic structure that combines:
- **Substitution (S-Box)** - Non-linear confusion operations
- **Permutation (P-Box)** - Linear diffusion operations  
- **Key Mixing** - Round key XOR operations
- **Multi-Round Structure** - 3-round encryption/decryption

### Key Features
- **Block Size**: 16-bit data blocks
- **Key Size**: 32-bit symmetric keys
- **Rounds**: 3 encryption/decryption rounds
- **S-Box**: 4-bit to 4-bit substitution tables
- **Permutation**: Rotate left/right by 2 bits
- **Operations**: Encrypt (01), Decrypt (10), No-op (00), Error (11)

## File Structure

```
SPU_CU_UVM/
├── README.md                  # Project documentation
├── design.sv                  # SPN Crypto Unit DUT implementation (spn_cu module)
└── UVM_CODE.sv               # Complete UVM verification environment
```

### File Descriptions

#### Cryptographic Design (`design.sv`)
- **`spn_cu` module** - Complete SPN implementation featuring:
  - 4-state FSM (IDLE, PROCESS, DONE, ERROR)
  - Forward and inverse S-box lookup tables
  - Key schedule generation (3 round keys from 32-bit master key)
  - Substitution and permutation functions
  - Complete 3-round encryption/decryption algorithms
  - Error handling for undefined opcodes

#### UVM Verification Environment (`UVM_CODE.sv`)
- **Interface Definition** - `spn_interface` with proper clocking blocks
- **Transaction Class** - `spn_transaction` with constrained randomization
- **UVM Components** - Driver, monitor, sequencer, agent, environment
- **Golden Reference Model** - Bit-accurate cryptographic reference
- **Scoreboard** - Automated result checking and validation
- **Test Sequences** - Multiple test scenarios and edge cases
- **Complete Testbench** - Top-level module with DUT instantiation

## Technologies Used

- **Hardware Description Language**: SystemVerilog
- **Verification Methodology**: UVM (Universal Verification Methodology)
- **Cryptographic Domain**: Substitution-Permutation Networks
- **Simulation Tools**: QuestaSim/ModelSim, VCS, or Xcelium
- **Verification Techniques**: Functional verification and golden model comparison
- **Version Control**: Git

## Cryptographic Implementation Details

### S-Box Design
```systemverilog
// Forward S-Box (encryption)
logic [3:0] sbox [16] = '{
    4'hA, 4'h5, 4'h8, 4'h2, 4'h6, 4'hC, 4'h4, 4'h3,
    4'h1, 4'h0, 4'hB, 4'h9, 4'hF, 4'hD, 4'h7, 4'hE
};

// Inverse S-Box (decryption)
logic [3:0] inv_sbox [16] = '{
    4'h9, 4'h8, 4'h3, 4'h7, 4'h6, 4'h1, 4'h4, 4'hE,
    4'h2, 4'hB, 4'h0, 4'hA, 4'h5, 4'hD, 4'hF, 4'hC
};
```

### Key Schedule
```systemverilog
function logic [15:0] get_round_key(input logic [31:0] key, input logic [1:0] round_num);
    case (round_num)
        2'b00: get_round_key = {key[7:0], key[23:16]};   // Round 0
        2'b01: get_round_key = key[15:0];                // Round 1  
        2'b10: get_round_key = {key[7:0], key[31:24]};   // Round 2
        default: get_round_key = 16'h0000;
    endcase
endfunction
```

### Permutation Operations
```systemverilog
// Forward permutation (rotate left by 2)
function logic [15:0] apply_pbox(input logic [15:0] data_in);
    apply_pbox = {data_in[13:0], data_in[15:14]};
endfunction

// Inverse permutation (rotate right by 2)  
function logic [15:0] apply_inv_pbox(input logic [15:0] data_in);
    apply_inv_pbox = {data_in[1:0], data_in[15:2]};
endfunction
```

## UVM Verification Features

### Comprehensive Test Coverage
- **Encryption Testing** - All encryption paths validated
- **Decryption Testing** - Complete decryption verification  
- **Round-by-Round Validation** - Each cryptographic round tested
- **Key Schedule Testing** - All round key derivations verified
- **Error Condition Testing** - Invalid opcode handling
- **Edge Case Testing** - Boundary conditions and corner cases

### Advanced UVM Implementation
- **Constrained Randomization** - Intelligent stimulus generation with cryptographic constraints
- **Golden Reference Model** - Bit-accurate reference implementation matching DUT exactly
- **Assertion-Based Verification** - Property-based checking for cryptographic properties
- **Comprehensive Scoreboard** - Automated pass/fail analysis with detailed reporting
- **Multiple Test Sequences** - Basic, random, edge case, and corner case testing

### Test Sequences Implemented
1. **`spn_basic_sequence`** - Basic encrypt/decrypt/no-op/error testing
2. **`spn_encrypt_decrypt_sequence`** - Paired encryption/decryption validation
3. **`spn_random_sequence`** - 30 randomized test cases
4. **`spn_edge_case_sequence`** - Boundary value testing (0x0000, 0xFFFF, etc.)
5. **`spn_corner_case_sequence`** - Alternating bits, single bit patterns

## Getting Started

### Prerequisites
- SystemVerilog simulator (QuestaSim, VCS, Xcelium)
- UVM library (typically included with simulator)
- Understanding of cryptographic concepts
- Knowledge of UVM methodology

### Environment Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/lamaRimawi/SPU_CU_UVM.git
   cd SPU_CU_UVM
   ```

2. **Compile and run:**
   ```bash
   # Compile design and testbench
   vlog -sv +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv
   vlog -sv +incdir+. design.sv UVM_CODE.sv
   
   # Run specific tests
   vsim -c spn_cu_uvm_tb +UVM_TESTNAME=spn_basic_test -do "run -all; quit"
   ```

## Usage

### Running Verification Tests

#### Basic Test Execution
```bash
# Run basic functionality test
vsim -c spn_cu_uvm_tb +UVM_TESTNAME=spn_basic_test -do "run -all; quit"

# Run encrypt-decrypt validation
vsim -c spn_cu_uvm_tb +UVM_TESTNAME=spn_encrypt_decrypt_test -do "run -all; quit"

# Run random testing
vsim -c spn_cu_uvm_tb +UVM_TESTNAME=spn_random_test -do "run -all; quit"
```

#### Advanced Test Scenarios
```bash
# Run edge case testing
vsim -c spn_cu_uvm_tb +UVM_TESTNAME=spn_edge_case_test -do "run -all; quit"

# Run corner case testing  
vsim -c spn_cu_uvm_tb +UVM_TESTNAME=spn_corner_case_test -do "run -all; quit"

# Default test (corner case)
vsim -c spn_cu_uvm_tb -do "run -all; quit"
```

#### GUI Debug Mode
```bash
# Open simulator GUI for debugging
vsim spn_cu_uvm_tb +UVM_TESTNAME=spn_basic_test

# Generate waveforms (VCD format)
vsim spn_cu_uvm_tb +UVM_TESTNAME=spn_basic_test -wlf waves.wlf
```

## Test Scenarios

### Cryptographic Verification
1. **Algorithm Correctness**
   - S-box substitution accuracy
   - Permutation operation validation
   - Key schedule generation testing
   - Multi-round encryption/decryption

2. **Cryptographic Properties**
   - Encryption/decryption symmetry
   - Key sensitivity testing
   - Avalanche effect validation
   - Non-linearity verification

3. **Edge Cases**
   - All-zero data and keys
   - All-one data and keys  
   - Boundary value testing
   - Single-bit pattern analysis

### Functional Testing
1. **State Machine Verification**
   - IDLE → PROCESS → DONE transitions
   - Error state handling
   - Reset behavior validation

2. **Interface Protocol**
   - Opcode interpretation (00, 01, 10, 11)
   - Valid signal generation
   - Timing behavior verification

## Verification Implementation

### Golden Reference Model
The verification includes a comprehensive golden reference model that exactly matches the DUT implementation:

```systemverilog
class spn_golden_model extends uvm_component;
    // Exact S-box and inverse S-box matching DUT
    // Identical key schedule implementation  
    // Bit-accurate encryption/decryption algorithms
    // Precise state machine modeling
endclass
```

### Constrained Randomization
```systemverilog
class spn_transaction extends uvm_sequence_item;
    rand logic [1:0]  opcode;
    rand logic [15:0] data_in; 
    rand logic [31:0] secret_key;
    
    constraint opcode_c {
        opcode inside {2'b00, 2'b01, 2'b10, 2'b11};
        opcode dist {2'b01 := 40, 2'b10 := 40, 2'b00 := 10, 2'b11 := 10};
    }
    
    constraint data_c { data_in != 16'h0000; }  // Meaningful test data
    constraint key_c { secret_key != 32'h00000000; }  // Non-zero keys
endclass
```

## Key Learning Outcomes

### Technical Skills Developed
- **Cryptographic Hardware Design** - Understanding of SPN cipher architecture
- **UVM Expertise** - Advanced verification methodology mastery
- **SystemVerilog Proficiency** - Modern hardware verification language
- **Golden Model Development** - Reference implementation techniques
- **Functional Verification** - Comprehensive test strategy execution

### Cryptographic Knowledge
- **Block Cipher Design** - Substitution-permutation network principles
- **S-Box Implementation** - Non-linear substitution techniques
- **Key Scheduling** - Cryptographic key derivation methods
- **Encryption/Decryption** - Symmetric cryptography implementation
- **Security Verification** - Cryptographic property validation

### Industry Applications
- **Hardware Security** - Cryptographic IP verification
- **ASIC/FPGA Crypto** - Custom cryptographic accelerator validation
- **Security Chip Testing** - Hardware security module verification
- **Blockchain Hardware** - Cryptocurrency mining chip verification

## Challenges Overcome

1. **Cryptographic Accuracy** - Ensuring bit-perfect implementation matching
2. **S-Box Verification** - Validating complex lookup table operations
3. **Multi-Round Testing** - Comprehensive round-by-round validation
4. **Golden Model Precision** - Creating exact reference implementation
5. **Edge Case Coverage** - Testing cryptographic boundary conditions

## Future Enhancements

- [ ] **AES Implementation** - Advanced Encryption Standard verification
- [ ] **Side-Channel Analysis** - Power and timing attack resistance testing
- [ ] **Formal Verification** - Mathematical proof of cryptographic properties
- [ ] **Performance Analysis** - Throughput and latency optimization
- [ ] **Key Management** - Secure key storage and handling verification
- [ ] **DPA Protection** - Differential power analysis countermeasures

## Industry Relevance

### Professional Applications
- **Cryptographic IP Companies** - Hardware security verification
- **Semiconductor Security** - Secure chip design and validation
- **Defense Contractors** - Military-grade cryptographic systems
- **Financial Technology** - Hardware security modules for banking
- **IoT Security** - Embedded cryptographic verification

### Career Paths
- **Security Verification Engineer** - Cryptographic hardware validation specialist
- **Hardware Security Architect** - Secure system design leadership
- **Cryptographic Engineer** - Algorithm implementation and optimization
- **ASIC Security Designer** - Custom security chip development

## Academic Significance

This project demonstrates mastery of:
- **Advanced Cryptographic Concepts** - SPN cipher design and implementation
- **Professional Verification Skills** - Industry-standard UVM methodology
- **Hardware Security Knowledge** - Cryptographic hardware verification
- **Golden Model Development** - Reference implementation techniques
- **Comprehensive Testing** - Systematic verification approach

## Contact

**Lama Rimawi**  
GitHub: [@lamaRimawi](https://github.com/lamaRimawi)  
Repository: [SPU_CU_UVM](https://github.com/lamaRimawi/SPU_CU_UVM)

This project showcases advanced cryptographic hardware verification capabilities using professional UVM methodology for secure system validation.

---

*Project Type: Cryptographic Hardware Verification | Algorithm: SPN Block Cipher | Methodology: UVM | Language: SystemVerilog | Status: Complete*

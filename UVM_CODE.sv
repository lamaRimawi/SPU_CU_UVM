interface spn_interface(input logic clk);
    logic        reset;
    logic [1:0]  opcode;
    logic [15:0] data_in;
    logic [31:0] secret_key;
    logic [15:0] data_out;
    logic [1:0]  valid;

    clocking driver_cb @(posedge clk);
        output reset, opcode, data_in, secret_key;
        input data_out, valid;
    endclocking
    
    clocking monitor_cb @(posedge clk);
        input reset, opcode, data_in, secret_key, data_out, valid;
    endclocking
    
    modport DRIVER (clocking driver_cb);
    modport MONITOR (clocking monitor_cb);
    
endinterface

// ==============================================================================
// Transaction Class
// ==============================================================================
class spn_transaction extends uvm_sequence_item;
    
    // Input fields
    rand logic [1:0]  opcode;
    rand logic [15:0] data_in;
    rand logic [31:0] secret_key;
    
    // Output fields
    logic [15:0] data_out;
    logic [1:0]  valid;
    
    // Constraints
    constraint opcode_c {
        opcode inside {2'b00, 2'b01, 2'b10, 2'b11};
       opcode dist {2'b01 := 40, 2'b10 := 40, 2'b00 := 10, 2'b11 := 10};
    }
    
    constraint data_c {
        data_in != 16'h0000; // Avoid all-zero data for meaningful tests
    }
    
    constraint key_c {
        secret_key != 32'h00000000; // Avoid all-zero key
    }
    
    `uvm_object_utils_begin(spn_transaction)
        `uvm_field_int(opcode, UVM_ALL_ON)
        `uvm_field_int(data_in, UVM_ALL_ON)
        `uvm_field_int(secret_key, UVM_ALL_ON)
        `uvm_field_int(data_out, UVM_ALL_ON)
        `uvm_field_int(valid, UVM_ALL_ON)
    `uvm_object_utils_end
    
    function new(string name = "spn_transaction");
        super.new(name);
    endfunction
    
endclass

// ==============================================================================
// Sequencer
// ==============================================================================
class spn_sequencer extends uvm_sequencer #(spn_transaction);
    `uvm_component_utils(spn_sequencer)
    
    function new(string name = "spn_sequencer", uvm_component parent);
        super.new(name, parent);
    endfunction
    
endclass

// ==============================================================================
// Driver
// ==============================================================================
class spn_driver extends uvm_driver #(spn_transaction);
    
    virtual spn_interface vif;
    
    `uvm_component_utils(spn_driver)
    
    function new(string name = "spn_driver", uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual spn_interface)::get(this, "", "vif", vif))
            `uvm_fatal("DRIVER", "Could not get vif")
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        spn_transaction req;
        
        // Initialize signals
        vif.reset <= 1;
        vif.opcode <= 2'b00;
        vif.data_in <= 16'h0000;
        vif.secret_key <= 32'h00000000;
        
        // Wait for clock and release reset
        repeat(5) @(posedge vif.clk);
        vif.reset <= 0;
        repeat(2) @(posedge vif.clk);
        
        forever begin
            seq_item_port.get_next_item(req);
            drive_transaction(req);
            seq_item_port.item_done();
        end
    endtask
    
    virtual task drive_transaction(spn_transaction req);
        `uvm_info("DRIVER", $sformatf("Driving transaction: opcode=%b, data_in=0x%h, key=0x%h", 
                  req.opcode, req.data_in, req.secret_key), UVM_HIGH)
        
        // Apply inputs
        @(posedge vif.clk);
        vif.opcode <= req.opcode;
        vif.data_in <= req.data_in;
        vif.secret_key <= req.secret_key;
        
        // Hold for one cycle, then go to no-op
        @(posedge vif.clk);
        vif.opcode <= 2'b00;
       if (req.opcode == 2'b11) begin
            @(posedge vif.clk);
            vif.opcode <= req.opcode;
            // Maintain opcode for 2 cycles to observe error
            repeat(2) @(posedge vif.clk);
            vif.opcode <= 2'b00;
        end 
        
        // Wait for operation to complete
        if (req.opcode == 2'b01 || req.opcode == 2'b10) begin
            // Wait for valid signal
            fork
                begin
                    wait(vif.valid != 2'b00);
                end
                begin
                    repeat(20) @(posedge vif.clk); // Timeout
                end
            join_any
            disable fork;
            repeat(2) @(posedge vif.clk); // Hold for observation
        end else begin
            repeat(5) @(posedge vif.clk);
        end
    endtask
    
endclass

// ==============================================================================
// Monitor
// ==============================================================================
class spn_monitor extends uvm_monitor;
    
    virtual spn_interface vif;
    uvm_analysis_port #(spn_transaction) item_collected_port;
    
    `uvm_component_utils(spn_monitor)
    
    function new(string name = "spn_monitor", uvm_component parent);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual spn_interface)::get(this, "", "vif", vif))
            `uvm_fatal("MONITOR", "Could not get vif")
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        spn_transaction trans;
        
        forever begin
            @(posedge vif.clk);
            
            if (!vif.reset && vif.opcode != 2'b00) begin
                trans = spn_transaction::type_id::create("trans");
                trans.opcode = vif.opcode;
                trans.data_in = vif.data_in;
                trans.secret_key = vif.secret_key;
                
                // Handle undefined opcode (11) immediately
                if (vif.opcode == 2'b11) begin
                    trans.data_out = vif.data_out;
                    trans.valid = vif.valid;
                end 
                // Handle valid operations (01/10) with timeout
                else if (vif.opcode == 2'b01 || vif.opcode == 2'b10) begin
                    fork
                        begin
                            wait(vif.valid != 2'b00);
                            trans.data_out = vif.data_out;
                            trans.valid = vif.valid;
                        end
                        begin
                            repeat(20) @(posedge vif.clk); // Timeout
                            trans.data_out = vif.data_out;
                            trans.valid = vif.valid;
                        end
                    join_any
                    disable fork;
                end
                
                `uvm_info("MONITOR", $sformatf("Collected transaction: opcode=%b, data_out=0x%h, valid=%b", 
                          trans.opcode, trans.data_out, trans.valid), UVM_HIGH)
                
                item_collected_port.write(trans);
            end
        end
    endtask
endclass

// ==============================================================================
// Golden Reference Model - CORRECTED TO MATCH DUT EXACTLY
// ==============================================================================
class spn_golden_model extends uvm_component;
    
    `uvm_component_utils(spn_golden_model)
    
    function new(string name = "spn_golden_model", uvm_component parent);
        super.new(name, parent);
    endfunction
    
    // S-Box lookup table - EXACTLY MATCHING DUT
    static logic [3:0] sbox[16] = '{
        4'hA, 4'h5, 4'h8, 4'h2, 4'h6, 4'hC, 4'h4, 4'h3,
        4'h1, 4'h0, 4'hB, 4'h9, 4'hF, 4'hD, 4'h7, 4'hE
    };
    
    // Inverse S-Box lookup table - CORRECTED TO MATCH DUT
    static logic [3:0] inv_sbox[16] = '{
        4'h9, 4'h8, 4'h3, 4'h7, 4'h6, 4'h1, 4'h4, 4'hE,
        4'h2, 4'hB, 4'h0, 4'hA, 4'h5, 4'hD, 4'hF, 4'hC
    };
    
    // Key schedule function - EXACTLY MATCHING DUT
    function logic [15:0] get_round_key(logic [31:0] key, logic [1:0] round_num);
        case (round_num)
            2'b00: return {key[7:0], key[23:16]};    // Round 0: key[7:0] || key[23:16]
            2'b01: return key[15:0];                 // Round 1: key[15:0]
            2'b10: return {key[7:0], key[31:24]};    // Round 2: key[7:0] || key[31:24]
            default: return 16'h0000;
        endcase
    endfunction
    
    // S-Box substitution
    function logic [15:0] apply_sbox(logic [15:0] data);
        return {sbox[data[15:12]], sbox[data[11:8]], sbox[data[7:4]], sbox[data[3:0]]};
    endfunction
    
    // Inverse S-Box substitution
    function logic [15:0] apply_inv_sbox(logic [15:0] data);
        return {inv_sbox[data[15:12]], inv_sbox[data[11:8]], inv_sbox[data[7:4]], inv_sbox[data[3:0]]};
    endfunction
    
    // Permutation (rotate left by 2) - EXACTLY MATCHING DUT
    function logic [15:0] apply_pbox(logic [15:0] data);
        return {data[13:0], data[15:14]};
    endfunction

    
//     // Inverse permutation (rotate right by 2) - EXACTLY MATCHING DUT
    function logic [15:0] apply_inv_pbox(logic [15:0] data);
        return {data[1:0], data[15:2]};
    endfunction
    
    // Encryption function - CORRECTED TO MATCH DUT EXACTLY
    function spn_transaction encrypt(spn_transaction req);
        logic [15:0] data = req.data_in;
        logic [15:0] round_key;
        spn_transaction result = spn_transaction::type_id::create("encrypt_result");
        
        result.copy(req);
        
        // Round 0
        round_key = get_round_key(req.secret_key, 2'b00);
        data = data ^ round_key;           // Round key mixing
        data = apply_sbox(data);           // Substitution
        data = apply_pbox(data);           // Permutation
        
        // Round 1
        round_key = get_round_key(req.secret_key, 2'b01);
        data = data ^ round_key;           // Round key mixing
        data = apply_sbox(data);           // Substitution
        data = apply_pbox(data);           // Permutation
        
        // Round 2 (final round - no permutation)
        round_key = get_round_key(req.secret_key, 2'b10);
        data = data ^ round_key;           // Round key mixing
        data = apply_sbox(data);           // Substitution (no permutation in final round)
        
        result.data_out = data;
        result.valid = 2'b01;
        return result;
    endfunction
    
    // Decryption function - CORRECTED TO MATCH DUT EXACTLY
    function spn_transaction decrypt(spn_transaction req);
        logic [15:0] data = req.data_in;
        logic [15:0] round_key;
        spn_transaction result = spn_transaction::type_id::create("decrypt_result");
        
        result.copy(req);
        
        // Reverse Round 2 (final round)
        round_key = get_round_key(req.secret_key, 2'b10);
        data = apply_inv_sbox(data);       // Inverse substitution
        data = data ^ round_key;           // Round key mixing
        
        // Reverse Round 1
        round_key = get_round_key(req.secret_key, 2'b01);
        data = apply_inv_pbox(data);       // Inverse permutation
        data = apply_inv_sbox(data);       // Inverse substitution
        data = data ^ round_key;           // Round key mixing
        
        // Reverse Round 0
        round_key = get_round_key(req.secret_key, 2'b00);
        data = apply_inv_pbox(data);       // Inverse permutation
        data = apply_inv_sbox(data);       // Inverse substitution
        data = data ^ round_key;           // Round key mixing
        
        result.data_out = data;
        result.valid = 2'b10;
        return result;
    endfunction
    
    // Predict expected output
    function spn_transaction predict(spn_transaction req);
        spn_transaction expected;
        
        case (req.opcode)
            2'b01: expected = encrypt(req);  // Encrypt
            2'b10: expected = decrypt(req);  // Decrypt
            2'b00: begin                     // No operation
                expected = spn_transaction::type_id::create("nop_result");
                expected.copy(req);
                expected.data_out = 16'h0000;
                expected.valid = 2'b00;
            end
            2'b11: begin                     // Undefined operation
                expected = spn_transaction::type_id::create("error_result");
                expected.copy(req);
                expected.data_out = 16'h0000;
                expected.valid = 2'b11;
            end
        endcase
        
        return expected;
    endfunction
    
endclass

// ==============================================================================
// Scoreboard
// ==============================================================================
class spn_scoreboard extends uvm_scoreboard;
    
    uvm_analysis_imp #(spn_transaction, spn_scoreboard) item_collected_export;
    spn_golden_model golden_model;
    
    int pass_count = 0;
    int fail_count = 0;
    
    `uvm_component_utils(spn_scoreboard)
    
    function new(string name = "spn_scoreboard", uvm_component parent);
        super.new(name, parent);
        item_collected_export = new("item_collected_export", this);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        golden_model = spn_golden_model::type_id::create("golden_model", this);
    endfunction
    
    virtual function void write(spn_transaction pkt);
        spn_transaction expected;
        string result_str;
        
        expected = golden_model.predict(pkt);
        
        if (pkt.data_out == expected.data_out && pkt.valid == expected.valid) begin
            pass_count++;
            result_str = "PASS";
            `uvm_info("SCOREBOARD", $sformatf("%s: opcode=%b, expected_out=0x%h, actual_out=0x%h, expected_valid=%b, actual_valid=%b", 
                      result_str, pkt.opcode, expected.data_out, pkt.data_out, expected.valid, pkt.valid), UVM_MEDIUM)
        end else begin
            fail_count++;
            result_str = "FAIL";
            `uvm_error("SCOREBOARD", $sformatf("%s: opcode=%b, expected_out=0x%h, actual_out=0x%h, expected_valid=%b, actual_valid=%b", 
                       result_str, pkt.opcode, expected.data_out, pkt.data_out, expected.valid, pkt.valid))
        end
    endfunction
    
    virtual function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD", $sformatf("Final Results: PASS=%0d, FAIL=%0d", pass_count, fail_count), UVM_LOW)
        if (fail_count == 0)
            `uvm_info("SCOREBOARD", "*** TEST PASSED ***", UVM_LOW)
        else
            `uvm_error("SCOREBOARD", "*** TEST FAILED ***")
    endfunction
    
endclass

// ==============================================================================
// // Agent
// ==============================================================================
class spn_agent extends uvm_agent;
    
    spn_driver driver;
    spn_sequencer sequencer;
    spn_monitor monitor;
    
    `uvm_component_utils(spn_agent)
    
    function new(string name = "spn_agent", uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        driver = spn_driver::type_id::create("driver", this);
        sequencer = spn_sequencer::type_id::create("sequencer", this);
        monitor = spn_monitor::type_id::create("monitor", this);
    endfunction
    
    virtual function void connect_phase(uvm_phase phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
    
endclass

// ==============================================================================
// Environment
// ==============================================================================
class spn_env extends uvm_env;
    
    spn_agent agent;
    spn_scoreboard scoreboard;

    
    `uvm_component_utils(spn_env)
    
    function new(string name = "spn_env", uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        agent = spn_agent::type_id::create("agent", this);
        scoreboard = spn_scoreboard::type_id::create("scoreboard", this);

    endfunction
    
    virtual function void connect_phase(uvm_phase phase);
        agent.monitor.item_collected_port.connect(scoreboard.item_collected_export);

    endfunction
    
endclass

// ==============================================================================
// Test Sequences
// ==============================================================================

// Base sequence
class spn_base_sequence extends uvm_sequence #(spn_transaction);
    `uvm_object_utils(spn_base_sequence)
    
    function new(string name = "spn_base_sequence");
        super.new(name);
    endfunction
endclass

// Basic functionality test sequence
class spn_basic_sequence extends spn_base_sequence;
    `uvm_object_utils(spn_basic_sequence)
    
    function new(string name = "spn_basic_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        spn_transaction req;
        
        `uvm_info("SEQUENCE", "Starting basic sequence", UVM_MEDIUM)
        
        // Test encryption
        req = spn_transaction::type_id::create("encrypt_req");
        start_item(req);
        assert(req.randomize() with {opcode == 2'b01; data_in == 16'hABCD; secret_key == 32'h12345678;});
        finish_item(req);
        
        // Test decryption
        req = spn_transaction::type_id::create("decrypt_req");
        start_item(req);
        assert(req.randomize() with {opcode == 2'b10; data_in == 16'h1234; secret_key == 32'h12345678;});
        finish_item(req);
        
        // Test no operation
        req = spn_transaction::type_id::create("nop_req");
        start_item(req);
        assert(req.randomize() with {opcode == 2'b00;});
        finish_item(req);
        
        // Test undefined operation
        req = spn_transaction::type_id::create("undefined_req");
        start_item(req);
        assert(req.randomize() with {opcode == 2'b11;});
        finish_item(req);
        
        `uvm_info("SEQUENCE", "Basic sequence completed", UVM_MEDIUM)
    endtask
endclass

// Encrypt-Decrypt sequence to verify correctness
class spn_encrypt_decrypt_sequence extends spn_base_sequence;
    `uvm_object_utils(spn_encrypt_decrypt_sequence)
    
    function new(string name = "spn_encrypt_decrypt_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        spn_transaction req;
        logic [15:0] original_data;
        logic [31:0] test_key;
        
        `uvm_info("SEQUENCE", "Starting encrypt-decrypt sequence", UVM_MEDIUM)
        
        // Test with known values
        original_data = 16'hABCD;
        test_key = 32'h12345678;
        
        // First encrypt
        req = spn_transaction::type_id::create("encrypt_req");
        start_item(req);
        assert(req.randomize() with {opcode == 2'b01; data_in == original_data; secret_key == test_key;});
        finish_item(req);
        
        // Then decrypt the same data
        req = spn_transaction::type_id::create("decrypt_req");
        start_item(req);
        assert(req.randomize() with {opcode == 2'b10; data_in == original_data; secret_key == test_key;});
        finish_item(req);
        
        // Test with different values
        original_data = 16'h5A5A;
        test_key = 32'hDEADBEEF;
        
        // Encrypt
        req = spn_transaction::type_id::create("encrypt_req2");
        start_item(req);
        assert(req.randomize() with {opcode == 2'b01; data_in == original_data; secret_key == test_key;});
        finish_item(req);
        
        // Decrypt
        req = spn_transaction::type_id::create("decrypt_req2");
        start_item(req);
        assert(req.randomize() with {opcode == 2'b10; data_in == original_data; secret_key == test_key;});
        finish_item(req);
        
        `uvm_info("SEQUENCE", "Encrypt-decrypt sequence completed", UVM_MEDIUM)
    endtask
endclass

// Random test sequence
class spn_random_sequence extends spn_base_sequence;
    `uvm_object_utils(spn_random_sequence)
    
    function new(string name = "spn_random_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        spn_transaction req;
        
        `uvm_info("SEQUENCE", "Starting random sequence", UVM_MEDIUM)
        
        repeat(30) begin
            req = spn_transaction::type_id::create("random_req");
            start_item(req);
            assert(req.randomize());
            finish_item(req);
        end
        
        `uvm_info("SEQUENCE", "Random sequence completed", UVM_MEDIUM)
    endtask
endclass

// Additional edge case transaction sequence
class spn_edge_case_sequence extends spn_base_sequence;
    `uvm_object_utils(spn_edge_case_sequence)
    
    function new(string name = "spn_edge_case_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        spn_transaction req;
        logic [15:0] test_data;
        logic [31:0] test_key;
        
        `uvm_info("SEQUENCE", "Starting edge case sequence", UVM_MEDIUM)
        
        // Test: All zeros data, all zeros key
        test_data = 16'h0000;
        test_key = 32'h00000000;
        
        req = spn_transaction::type_id::create("zero_data_zero_key");
        start_item(req);
        assert(req.randomize() with {opcode == 2'b01; data_in == test_data; secret_key == test_key;});
        finish_item(req);
        
        // Test: All ones data, all ones key
        test_data = 16'hFFFF;
        test_key = 32'hFFFFFFFF;
        
        req = spn_transaction::type_id::create("ones_data_ones_key");
        start_item(req);
        assert(req.randomize() with {opcode == 2'b01; data_in == test_data; secret_key == test_key;});
        finish_item(req);
        
        // Test: Boundary data and key
        test_data = 16'h8000;   // Middle boundary
        test_key = 32'h80000000; // Middle boundary
        
        req = spn_transaction::type_id::create("boundary_data_key");
        start_item(req);
        assert(req.randomize() with {opcode == 2'b01; data_in == test_data; secret_key == test_key;});
        finish_item(req);
        
        // Test: Encrypt a known pattern, decrypt back
        test_data = 16'h1234;
        test_key = 32'hA1B2C3D4;
        
        req = spn_transaction::type_id::create("encrypt_decrypt_known");
        start_item(req);
        assert(req.randomize() with {opcode == 2'b01; data_in == test_data; secret_key == test_key;});
        finish_item(req);
        
        req = spn_transaction::type_id::create("decrypt_back_known");
        start_item(req);
        assert(req.randomize() with {opcode == 2'b10; data_in == test_data; secret_key == test_key;});
        finish_item(req);
        
        `uvm_info("SEQUENCE", "Edge case sequence completed", UVM_MEDIUM)
    endtask
endclass
 
class spn_corner_case_sequence extends spn_base_sequence;
    `uvm_object_utils(spn_corner_case_sequence)
    
    function new(string name = "spn_corner_case_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        spn_transaction req;
        
        `uvm_info("SEQUENCE", "Starting corner case sequence", UVM_MEDIUM)
        
        // REMOVED: All-zeros and all-ones cases (already covered in edge_case_sequence)
        
        // Unique corner cases below
        // Corner Case 1: Alternating bits
        req = spn_transaction::type_id::create("alternating_bits");
        start_item(req);
        assert(req.randomize() with {
            opcode == 2'b10;
            data_in == 16'hAAAA;
            secret_key == 32'h55555555;
        });
        finish_item(req);
        
        // Corner Case 2: Single bit set (LSB)
        req = spn_transaction::type_id::create("single_bit_lsb");
        start_item(req);
        assert(req.randomize() with {
            opcode == 2'b01;
            data_in == 16'h0001;
            secret_key == 32'h00000001;
        });
        finish_item(req);
        
        // Corner Case 3: Single bit set (MSB)
        req = spn_transaction::type_id::create("single_bit_msb");
        start_item(req);
        assert(req.randomize() with {
            opcode == 2'b10;
            data_in == 16'h8000;
            secret_key == 32'h80000000;
        });
        finish_item(req);
        
        `uvm_info("SEQUENCE", "Corner case sequence completed", UVM_MEDIUM)
    endtask
endclass
// ==============================================================================
// Base Test
// ==============================================================================
class spn_base_test extends uvm_test;
    
    spn_env env;
    
    `uvm_component_utils(spn_base_test)
    
    function new(string name = "spn_base_test", uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = spn_env::type_id::create("env", this);
    endfunction
    
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        uvm_top.print_topology();
    endfunction
    
endclass

// ==============================================================================
// Specific Tests
// ==============================================================================
      

class spn_basic_test extends spn_base_test;
    `uvm_component_utils(spn_basic_test)
    
  
    function new(string name = "spn_basic_test", uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        spn_basic_sequence seq;
        
        phase.raise_objection(this);
        
        `uvm_info("TEST", "Starting basic test", UVM_LOW)
        
        seq = spn_basic_sequence::type_id::create("seq");
        seq.start(env.agent.sequencer);
        
        #2000; // Allow time for completion
        
        `uvm_info("TEST", "Basic test completed", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
endclass

class spn_encrypt_decrypt_test extends spn_base_test;
    `uvm_component_utils(spn_encrypt_decrypt_test)
    
    function new(string name = "spn_encrypt_decrypt_test", uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        spn_encrypt_decrypt_sequence seq;
        
        phase.raise_objection(this);
        
        `uvm_info("TEST", "Starting encrypt-decrypt test", UVM_LOW)
        
        seq = spn_encrypt_decrypt_sequence::type_id::create("seq");
        seq.start(env.agent.sequencer);
        
        #3000; // Allow time for completion
        
        `uvm_info("TEST", "Encrypt-decrypt test completed", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
endclass
      class spn_random_test extends spn_base_test;
    `uvm_component_utils(spn_random_test)
      
      
      function new(string name = "spn_random_test", uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        spn_random_sequence seq;
        
        phase.raise_objection(this);
        
        `uvm_info("TEST", "Starting random test", UVM_LOW)
        
        seq = spn_random_sequence::type_id::create("seq");
        seq.start(env.agent.sequencer);
        
        #5000; // Allow time for completion
        
        `uvm_info("TEST", "Random test completed", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
endclass
      
// Directed test (edge case sequence)
class spn_edge_case_test extends spn_base_test;
    `uvm_component_utils(spn_edge_case_test)
    
    function new(string name = "spn_edge_case_test", uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        spn_edge_case_sequence seq;
        
        phase.raise_objection(this);
        
        `uvm_info("TEST", "Starting edge case test", UVM_LOW)
        
        seq = spn_edge_case_sequence::type_id::create("seq");
        seq.start(env.agent.sequencer);
        
        #5000; // Allow time for completion
        
        `uvm_info("TEST", "Edge case test completed", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
endclass

 class spn_corner_case_test extends spn_base_test;
    `uvm_component_utils(spn_corner_case_test)
    
    function new(string name = "spn_corner_case_test", uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        spn_corner_case_sequence seq;
        
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting corner case test", UVM_LOW)
        seq = spn_corner_case_sequence::type_id::create("seq");
        seq.start(env.agent.sequencer);
        #1000;
        `uvm_info("TEST", "Corner case test completed", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass     

// ==============================================================================
// Top-level Testbench Module with Edge Case Testing
// ==============================================================================

module spn_cu_uvm_tb;
    
    logic clk;
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100 MHz clock
    end
    
    // Interface instantiation
    spn_interface intf(clk);
    
    // Instantiate the Device Under Test (DUT)
    spn_cu dut (
        .clk(intf.clk),
        .reset(intf.reset),
        .opcode(intf.opcode),
        .data_in(intf.data_in),
        .secret_key(intf.secret_key),
        .data_out(intf.data_out),
        .valid(intf.valid)
    );
    
    // UVM configuration and test execution
    initial begin
        // Set interface in config DB
        uvm_config_db#(virtual spn_interface)::set(null, "*", "vif", intf);
        
        // Enable waveform dumping
        $dumpfile("spn_cu_uvm.vcd");
        $dumpvars(0, spn_cu_uvm_tb);
        

        if ($test$plusargs("UVM_TESTNAME")) begin
            // Test name provided via command line
            run_test();
        end else begin
            // Default to edge case test
            run_test("spn_corner_case_test");
        end
    end
    

    initial begin
        #100000;
        `uvm_error("TIMEOUT", "Test timed out!")
        $finish;
    end
    
endmodule

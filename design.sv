module spn_cu (
    input  logic        clk,
    input  logic        reset,           // Active high reset
    input  logic [1:0]  opcode,          // 00: no op, 01: encrypt, 10: decrypt, 11: undefined
    input  logic [15:0] data_in,         // Input data block (plaintext or ciphertext)
    input  logic [31:0] secret_key,      // 32-bit symmetric secret key
    output logic [15:0] data_out,        // Output data block (ciphertext or plaintext)
    output logic [1:0]  valid            // 00: no valid, 01: encrypt success, 10: decrypt success, 11: error
);

    // =========================================================================
    // Internal Signals and State Machine
    // =========================================================================
    
    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        PROCESS     = 3'b001,
        DONE        = 3'b010,
        ERROR       = 3'b011
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal registers
    logic [15:0] data_reg, result_reg;
    logic [1:0]  operation_reg;
    logic [31:0] key_reg;
    logic [1:0]  round_counter;
    logic        processing;
    
    // =========================================================================
    // S-Box and Inverse S-Box Lookup Tables
    // =========================================================================
    
    // Forward S-Box (for encryption)
    logic [3:0] sbox [16] = '{
        4'hA, 4'h5, 4'h8, 4'h2, 4'h6, 4'hC, 4'h4, 4'h3,
        4'h1, 4'h0, 4'hB, 4'h9, 4'hF, 4'hD, 4'h7, 4'hE
    };
    
    // Inverse S-Box (for decryption) - CORRECTED
    logic [3:0] inv_sbox [16] = '{
        4'h9, 4'h8, 4'h3, 4'h7, 4'h6, 4'h1, 4'h4, 4'hE,
        4'h2, 4'hB, 4'h0, 4'hA, 4'h5, 4'hD, 4'hF, 4'hC
    };
    
    // =========================================================================
    // Key Schedule Generation - CORRECTED
    // =========================================================================
    
    function logic [15:0] get_round_key(input logic [31:0] key, input logic [1:0] round_num);
        case (round_num)
            2'b00: get_round_key = {key[7:0], key[23:16]};      // Round 0: key[7:0] || key[23:16]
            2'b01: get_round_key = key[15:0];                   // Round 1: key[15:0]
            2'b10: get_round_key = {key[7:0], key[31:24]};      // Round 2: key[7:0] || key[31:24]
            default: get_round_key = 16'h0000;
        endcase
    endfunction
    
    // =========================================================================
    // Substitution Functions
    // =========================================================================
    
    function logic [15:0] apply_sbox(input logic [15:0] data_in);
        apply_sbox = {sbox[data_in[15:12]], sbox[data_in[11:8]], 
                     sbox[data_in[7:4]], sbox[data_in[3:0]]};
    endfunction
    
    function logic [15:0] apply_inv_sbox(input logic [15:0] data_in);
        apply_inv_sbox = {inv_sbox[data_in[15:12]], inv_sbox[data_in[11:8]], 
                         inv_sbox[data_in[7:4]], inv_sbox[data_in[3:0]]};
    endfunction
    
    // =========================================================================
    // Permutation Functions (Rotate left by 2 bits)
    // =========================================================================
    
    function logic [15:0] apply_pbox(input logic [15:0] data_in);
        apply_pbox = {data_in[13:0], data_in[15:14]};  // Rotate left by 2
    endfunction
    
    function logic [15:0] apply_inv_pbox(input logic [15:0] data_in);
        apply_inv_pbox = {data_in[1:0], data_in[15:2]};  // Rotate right by 2
    endfunction
    
    // =========================================================================
    // Encryption Process (3 rounds)
    // =========================================================================
    
    function logic [15:0] encrypt_round(input logic [15:0] data, input logic [31:0] key, input logic [1:0] round_num);
        logic [15:0] temp_data;
        logic [15:0] round_key;
        
        round_key = get_round_key(key, round_num);
        temp_data = data ^ round_key;           // Round key mixing
        temp_data = apply_sbox(temp_data);      // Substitution
        
        if (round_num != 2'b10) begin          // No permutation in final round
            temp_data = apply_pbox(temp_data);  // Permutation
        end
        
        encrypt_round = temp_data;
    endfunction
    
    // =========================================================================
    // Decryption Process (reverse of encryption)
    // =========================================================================
    
    function logic [15:0] decrypt_round(input logic [15:0] data, input logic [31:0] key, input logic [1:0] round_num);
        logic [15:0] temp_data;
        logic [15:0] round_key;
        
        temp_data = data;
        
        case (round_num)
            2'b10: begin  // Reverse final round (Round 2)
                round_key = get_round_key(key, 2'b10);
                temp_data = apply_inv_sbox(temp_data);
                temp_data = temp_data ^ round_key;
            end
            2'b01: begin  // Reverse Round 1
                round_key = get_round_key(key, 2'b01);
                temp_data = apply_inv_pbox(temp_data);
                temp_data = apply_inv_sbox(temp_data);
                temp_data = temp_data ^ round_key;
            end
            2'b00: begin  // Reverse Round 0
                round_key = get_round_key(key, 2'b00);
                temp_data = apply_inv_pbox(temp_data);
                temp_data = apply_inv_sbox(temp_data);
                temp_data = temp_data ^ round_key;
            end
        endcase
        
        decrypt_round = temp_data;
    endfunction
    
    // =========================================================================
    // Complete Encryption/Decryption Functions
    // =========================================================================
    
    function logic [15:0] full_encrypt(input logic [15:0] plaintext, input logic [31:0] key);
        logic [15:0] temp_data;
        
        temp_data = plaintext;
        temp_data = encrypt_round(temp_data, key, 2'b00);  // Round 0
        temp_data = encrypt_round(temp_data, key, 2'b01);  // Round 1
        temp_data = encrypt_round(temp_data, key, 2'b10);  // Round 2 (final)
        
        full_encrypt = temp_data;
    endfunction
    
    function logic [15:0] full_decrypt(input logic [15:0] ciphertext, input logic [31:0] key);
        logic [15:0] temp_data;
        
        temp_data = ciphertext;
        temp_data = decrypt_round(temp_data, key, 2'b10);  // Reverse Round 2
        temp_data = decrypt_round(temp_data, key, 2'b01);  // Reverse Round 1
        temp_data = decrypt_round(temp_data, key, 2'b00);  // Reverse Round 0
        
        full_decrypt = temp_data;
    endfunction
    
    // =========================================================================
    // State Machine - Sequential Logic
    // =========================================================================
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
            data_reg <= 16'h0000;
            result_reg <= 16'h0000;
            operation_reg <= 2'b00;
            key_reg <= 32'h00000000;
            round_counter <= 2'b00;
            processing <= 1'b0;
        end else begin
            current_state <= next_state;
            
            case (current_state)
                IDLE: begin
                    if (opcode == 2'b01 || opcode == 2'b10) begin
                        data_reg <= data_in;
                        operation_reg <= opcode;
                        key_reg <= secret_key;
                        round_counter <= 2'b00;
                        processing <= 1'b1;
                    end
                end
                
                PROCESS: begin
                    // Perform complete encryption or decryption in one cycle
                    if (operation_reg == 2'b01) begin
                        result_reg <= full_encrypt(data_reg, key_reg);
                    end else begin
                        result_reg <= full_decrypt(data_reg, key_reg);
                    end
                    processing <= 1'b0;
                end
                
                DONE: begin
                    // Outputs are handled in combinational logic
                end
                
                ERROR: begin
                    // Outputs are handled in combinational logic
                end
                
                default: begin
                    // Default state
                end
            endcase
        end
    end
    
    // =========================================================================
    // Output Logic - Combinational
    // =========================================================================
    
    always_comb begin
        case (current_state)
            IDLE: begin
                data_out = 16'h0000;
                if (opcode == 2'b11) begin
                    valid = 2'b11;  // Error for undefined opcode
                end else begin
                    valid = 2'b00;  // No valid output
                end
            end
            
            PROCESS: begin
                data_out = 16'h0000;
                valid = 2'b00;
            end
            
            DONE: begin
                data_out = result_reg;
                valid = (operation_reg == 2'b01) ? 2'b01 : 2'b10;
            end
            
            ERROR: begin
                data_out = 16'h0000;
                valid = 2'b11;
            end
            
            default: begin
                data_out = 16'h0000;
                valid = 2'b00;
            end
        endcase
    end
    
    // =========================================================================
    // State Machine - Next State Logic
    // =========================================================================
    
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (opcode == 2'b01 || opcode == 2'b10) begin
                    next_state = PROCESS;
                end else if (opcode == 2'b11) begin
                    next_state = ERROR;
                end
            end
            
            PROCESS: begin
                next_state = DONE;
            end
            
            DONE: begin
                next_state = IDLE;
            end
            
            ERROR: begin
                next_state = IDLE;
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule
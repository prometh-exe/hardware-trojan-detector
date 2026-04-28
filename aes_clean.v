// ============================================================================
// File       : aes_clean.v
// Description: Lightweight AES-128 Encryption Module (Clean — No Trojan)
//              Implements full 10-round AES-128 encryption.
//              Uses iterative (round-by-round) architecture.
// Ports      : clk, rst, key[127:0], plaintext[127:0], ciphertext[127:0]
// Depends on : aes_sbox.v
// ============================================================================

module aes_clean (
    input  wire         clk,
    input  wire         rst,
    input  wire [127:0] key,
    input  wire [127:0] plaintext,
    output reg  [127:0] ciphertext
);

    // ---- Internal State ----
    reg [3:0]   round;
    reg         busy;
    reg         done_flag;
    reg [127:0] state;
    reg [127:0] round_key;

    // ---- S-Box wires for SubBytes (16 instances) ----
    wire [7:0] sb_in  [0:15];
    wire [7:0] sb_out [0:15];

    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : SBOX_INST
            aes_sbox u_sbox (
                .in_byte(sb_in[gi]),
                .out_byte(sb_out[gi])
            );
        end
    endgenerate

    // Connect S-Box inputs from state
    assign sb_in[0]  = state[7:0];     assign sb_in[1]  = state[15:8];
    assign sb_in[2]  = state[23:16];   assign sb_in[3]  = state[31:24];
    assign sb_in[4]  = state[39:32];   assign sb_in[5]  = state[47:40];
    assign sb_in[6]  = state[55:48];   assign sb_in[7]  = state[63:56];
    assign sb_in[8]  = state[71:64];   assign sb_in[9]  = state[79:72];
    assign sb_in[10] = state[87:80];   assign sb_in[11] = state[95:88];
    assign sb_in[12] = state[103:96];  assign sb_in[13] = state[111:104];
    assign sb_in[14] = state[119:112]; assign sb_in[15] = state[127:120];

    // ---- SubBytes result ----
    wire [127:0] after_sub;
    assign after_sub = {sb_out[15], sb_out[14], sb_out[13], sb_out[12],
                        sb_out[11], sb_out[10], sb_out[9],  sb_out[8],
                        sb_out[7],  sb_out[6],  sb_out[5],  sb_out[4],
                        sb_out[3],  sb_out[2],  sb_out[1],  sb_out[0]};

    // ---- ShiftRows ----
    // Column-major: byte[i] = state[i*8 +: 8], i=0..15
    // Row r, Col c -> byte index = c*4 + r
    wire [127:0] after_shift;
    // Row 0: no shift  (indices 0, 4, 8, 12)
    // Row 1: left by 1 (1->5->9->13->1)
    // Row 2: left by 2 (2->10, 6->14, 10->2, 14->6)
    // Row 3: left by 3 (3->15->11->7->3)
    assign after_shift[7:0]     = after_sub[7:0];       // b0  -> b0  (row0,col0)
    assign after_shift[15:8]    = after_sub[47:40];      // b5  -> b1  (row1,col0<-col1)
    assign after_shift[23:16]   = after_sub[87:80];      // b10 -> b2  (row2,col0<-col2)
    assign after_shift[31:24]   = after_sub[127:120];    // b15 -> b3  (row3,col0<-col3)
    assign after_shift[39:32]   = after_sub[39:32];      // b4  -> b4  (row0,col1)
    assign after_shift[47:40]   = after_sub[79:72];      // b9  -> b5  (row1,col1<-col2)
    assign after_shift[55:48]   = after_sub[119:112];    // b14 -> b6  (row2,col1<-col3)
    assign after_shift[63:56]   = after_sub[31:24];      // b3  -> b7  (row3,col1<-col0)
    assign after_shift[71:64]   = after_sub[71:64];      // b8  -> b8  (row0,col2)
    assign after_shift[79:72]   = after_sub[111:104];    // b13 -> b9  (row1,col2<-col3)
    assign after_shift[87:80]   = after_sub[23:16];      // b2  -> b10 (row2,col2<-col0)
    assign after_shift[95:88]   = after_sub[63:56];      // b7  -> b11 (row3,col2<-col1)
    assign after_shift[103:96]  = after_sub[103:96];     // b12 -> b12 (row0,col3)
    assign after_shift[111:104] = after_sub[15:8];       // b1  -> b13 (row1,col3<-col0)
    assign after_shift[119:112] = after_sub[55:48];      // b6  -> b14 (row2,col3<-col1)
    assign after_shift[127:120] = after_sub[95:88];      // b11 -> b15 (row3,col3<-col2)

    // ---- xtime helper (GF(2^8) multiply by 2) ----
    function [7:0] xtime;
        input [7:0] b;
        begin
            xtime = b[7] ? ({b[6:0], 1'b0} ^ 8'h1b) : {b[6:0], 1'b0};
        end
    endfunction

    // ---- MixColumns ----
    wire [127:0] after_mix;
    genvar ci;
    generate
        for (ci = 0; ci < 4; ci = ci + 1) begin : MIX_COL
            wire [7:0] s0 = after_shift[ci*32 +  0 +: 8];
            wire [7:0] s1 = after_shift[ci*32 +  8 +: 8];
            wire [7:0] s2 = after_shift[ci*32 + 16 +: 8];
            wire [7:0] s3 = after_shift[ci*32 + 24 +: 8];
            assign after_mix[ci*32 +  0 +: 8] = xtime(s0) ^ (xtime(s1) ^ s1) ^ s2 ^ s3;
            assign after_mix[ci*32 +  8 +: 8] = s0 ^ xtime(s1) ^ (xtime(s2) ^ s2) ^ s3;
            assign after_mix[ci*32 + 16 +: 8] = s0 ^ s1 ^ xtime(s2) ^ (xtime(s3) ^ s3);
            assign after_mix[ci*32 + 24 +: 8] = (xtime(s0) ^ s0) ^ s1 ^ s2 ^ xtime(s3);
        end
    endgenerate

    // ---- Key Expansion S-Box (4 instances for RotWord+SubWord) ----
    wire [7:0] ks_in [0:3];
    wire [7:0] ks_out[0:3];
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : KS_SBOX
            aes_sbox u_ks_sbox (
                .in_byte(ks_in[gi]),
                .out_byte(ks_out[gi])
            );
        end
    endgenerate

    // RotWord: rotate w3 bytes left by 1, then SubWord
    wire [31:0] w3 = round_key[31:0];
    assign ks_in[0] = w3[23:16]; // byte1 -> pos0
    assign ks_in[1] = w3[15:8];  // byte2 -> pos1
    assign ks_in[2] = w3[7:0];   // byte3 -> pos2
    assign ks_in[3] = w3[31:24]; // byte0 -> pos3

    // Round constants
    reg [7:0] rcon_val;
    always @(*) begin
        case (round)
            4'd0:  rcon_val = 8'h01; 4'd1:  rcon_val = 8'h02;
            4'd2:  rcon_val = 8'h04; 4'd3:  rcon_val = 8'h08;
            4'd4:  rcon_val = 8'h10; 4'd5:  rcon_val = 8'h20;
            4'd6:  rcon_val = 8'h40; 4'd7:  rcon_val = 8'h80;
            4'd8:  rcon_val = 8'h1b; 4'd9:  rcon_val = 8'h36;
            default: rcon_val = 8'h00;
        endcase
    end

    wire [31:0] sub_rot_word = {(ks_out[0] ^ rcon_val), ks_out[1], ks_out[2], ks_out[3]};
    wire [31:0] nw0 = round_key[127:96] ^ sub_rot_word;
    wire [31:0] nw1 = round_key[95:64]  ^ nw0;
    wire [31:0] nw2 = round_key[63:32]  ^ nw1;
    wire [31:0] nw3 = round_key[31:0]   ^ nw2;
    wire [127:0] next_round_key = {nw0, nw1, nw2, nw3};

    // ---- Main AES State Machine ----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            round      <= 4'd0;
            busy       <= 1'b0;
            done_flag  <= 1'b0;
            state      <= 128'd0;
            round_key  <= 128'd0;
            ciphertext <= 128'd0;
        end else begin
            if (!busy) begin
                // Load: AddRoundKey with initial key
                state     <= plaintext ^ key;
                round_key <= key;
                round     <= 4'd0;
                busy      <= 1'b1;
                done_flag <= 1'b0;
            end else begin
                if (round < 4'd9) begin
                    // Rounds 1-9: SubBytes+ShiftRows+MixColumns+AddRoundKey
                    state     <= after_mix ^ next_round_key;
                    round_key <= next_round_key;
                    round     <= round + 4'd1;
                end else begin
                    // Round 10: SubBytes+ShiftRows+AddRoundKey (no MixColumns)
                    ciphertext <= after_shift ^ next_round_key;
                    busy       <= 1'b0;
                    done_flag  <= 1'b1;
                    round      <= 4'd0;
                end
            end
        end
    end

endmodule

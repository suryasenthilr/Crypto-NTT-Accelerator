`timescale 1ns / 1ps

// ============================================================================
// Module: modular_multiplier
// Description: Reconfigurable Dual-Mode Constant-Time Modular Multiplier (R-MAU)
//              - Dilithium Mode (mode_kyber = 0): q = 8380417, Solinas Reduction
//              - Kyber Mode     (mode_kyber = 1): q = 3329, Montgomery Reduction
// Latency: 2 clock cycles (pipelined)
// Constant-Time: Side-channel resistant against timing attacks
// ============================================================================

module modular_multiplier (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mode_kyber, // 1: Kyber (mod 3329), 0: Dilithium (mod 8380417)
    input  wire [23:0] in_a,
    input  wire [23:0] in_b,
    output reg  [23:0] out_p
);

    localparam [23:0] Q_DILITHIUM = 24'd8380417; // 2^23 - 2^13 + 1
    localparam [23:0] Q_KYBER     = 24'd3329;
    localparam [15:0] KYBER_Q_PRIME = 16'd3327;  // -Q^-1 mod 2^16

    // ========================================================================
    // Pipeline Stage 1: Multiplication
    // ========================================================================
    reg        mode_k_r1;
    reg [47:0] prod_dilithium;
    reg [23:0] prod_kyber;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode_k_r1      <= 1'b0;
            prod_dilithium <= 48'd0;
            prod_kyber     <= 24'd0;
        end else begin
            mode_k_r1      <= mode_kyber;
            if (mode_kyber) begin
                // 12-bit x 12-bit multiplication
                prod_kyber <= in_a[11:0] * in_b[11:0];
            end else begin
                // 23-bit x 23-bit multiplication
                prod_dilithium <= in_a[22:0] * in_b[22:0];
            end
        end
    end

    // ========================================================================
    // Stage 1 -> 2: Intermediate Reduction Signals
    // ========================================================================
    // Dilithium Solinas Reduction Steps:
    wire [22:0] p0 = prod_dilithium[22:0];
    wire [22:0] p1 = prod_dilithium[45:23];
    // (p1 << 13) - p1 is always >= 0
    wire [36:0] t1 = p0 + ({p1, 13'd0} - p1);

    wire [22:0] t1_lo = t1[22:0];
    wire [13:0] t1_hi = t1[36:23];
    wire [27:0] t2 = t1_lo + ({t1_hi, 13'd0} - t1_hi);

    wire [22:0] t2_lo = t2[22:0];
    wire [4:0]  t2_hi = t2[27:23];
    wire [24:0] t3 = t2_lo + ({t2_hi, 13'd0} - t2_hi);

    // Kyber Montgomery Reduction Steps:
    // m = (P * 3327) mod 2^16
    wire [15:0] m_kyber = (prod_kyber[15:0] * KYBER_Q_PRIME);
    wire [31:0] mont_t  = {8'd0, prod_kyber} + ({16'd0, m_kyber} * 32'd3329);
    wire [15:0] t_kyber = mont_t[31:16];

    // ========================================================================
    // Pipeline Stage 2: Constant-Time Output Selection
    // ========================================================================
    // Dilithium conditional bounds
    wire [24:0] sub_2q = t3 - (2 * Q_DILITHIUM);
    wire [24:0] sub_1q = t3 - Q_DILITHIUM;
    wire [23:0] dilithium_reduced = (t3 >= (2 * Q_DILITHIUM)) ? sub_2q[23:0] :
                                    (t3 >= Q_DILITHIUM)       ? sub_1q[23:0] :
                                                                t3[23:0];

    // Kyber conditional bound
    wire [15:0] kyber_sub = t_kyber - 16'd3329;
    wire [11:0] kyber_reduced = (t_kyber >= 16'd3329) ? kyber_sub[11:0] : t_kyber[11:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_p <= 24'd0;
        end else begin
            if (mode_k_r1) begin
                out_p <= {12'd0, kyber_reduced};
            end else begin
                out_p <= dilithium_reduced;
            end
        end
    end

endmodule

`timescale 1ns / 1ps

// ============================================================================
// Module: ntt_butterfly_unit
// Description: Unified Cooley-Tukey (CT) and Gentleman-Sande (GS) Butterfly Unit
//              Supports both NIST FIPS 203 (Kyber) and FIPS 204 (Dilithium)
// Pipelined: 3 clock cycles total latency, 1 butterfly per cycle throughput
// ============================================================================

module ntt_butterfly_unit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mode_kyber, // 1: Kyber, 0: Dilithium
    input  wire        is_gs,      // 0: Forward NTT (CT), 1: Inverse INTT (GS)
    input  wire [23:0] u_in,
    input  wire [23:0] v_in,
    input  wire [23:0] twiddle,
    output reg  [23:0] u_out,
    output reg  [23:0] v_out
);

    wire [23:0] q = mode_kyber ? 24'd3329 : 24'd8380417;

    // ------------------------------------------------------------------------
    // Pre-multiplier Modular Adder and Subtractor (for GS mode)
    // Both FIPS 203 and FIPS 204 require (v - u) * zeta mod q
    wire [24:0] add_pre = u_in + v_in;
    wire [23:0] gs_add_val = (add_pre >= q) ? (add_pre - q) : add_pre[23:0];

    wire [23:0] gs_sub_val = (v_in >= u_in) ? (v_in - u_in) : (v_in + q - u_in);

    // ------------------------------------------------------------------------
    // Multiplier Input Muxing
    // ------------------------------------------------------------------------
    // In CT mode: multiply v_in * twiddle
    // In GS mode: multiply gs_sub_val * twiddle
    wire [23:0] mult_in_a = is_gs ? gs_sub_val : v_in;
    wire [23:0] mult_in_b = twiddle;
    wire [23:0] mult_out;

    modular_multiplier u_multiplier (
        .clk(clk),
        .rst_n(rst_n),
        .mode_kyber(mode_kyber),
        .in_a(mult_in_a),
        .in_b(mult_in_b),
        .out_p(mult_out)
    );

    // ------------------------------------------------------------------------
    // Delay Pipelines to match 2-cycle Multiplier Latency
    // ------------------------------------------------------------------------
    reg [23:0] u_pipe1, u_pipe2;
    reg [23:0] gs_add_pipe1, gs_add_pipe2;
    reg        mode_k_p1, mode_k_p2;
    reg        is_gs_p1, is_gs_p2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            u_pipe1       <= 24'd0;
            u_pipe2       <= 24'd0;
            gs_add_pipe1  <= 24'd0;
            gs_add_pipe2  <= 24'd0;
            mode_k_p1     <= 1'b0;
            mode_k_p2     <= 1'b0;
            is_gs_p1      <= 1'b0;
            is_gs_p2      <= 1'b0;
        end else begin
            u_pipe1       <= u_in;
            u_pipe2       <= u_pipe1;
            gs_add_pipe1  <= gs_add_val;
            gs_add_pipe2  <= gs_add_pipe1;
            mode_k_p1     <= mode_kyber;
            mode_k_p2     <= mode_k_p1;
            is_gs_p1      <= is_gs;
            is_gs_p2      <= is_gs_p1;
        end
    end

    // ------------------------------------------------------------------------
    // Post-multiplier Arithmetic (for CT mode) & Final Stage Output Muxing
    // ------------------------------------------------------------------------
    wire [23:0] q_p2 = mode_k_p2 ? 24'd3329 : 24'd8380417;

    // CT mode additions/subtractions:
    // u' = (u_pipe2 + mult_out) mod q
    // v' = (u_pipe2 - mult_out) mod q
    wire [24:0] ct_add = u_pipe2 + mult_out;
    wire [23:0] ct_u_val = (ct_add >= q_p2) ? (ct_add - q_p2) : ct_add[23:0];
    wire [23:0] ct_v_val = (u_pipe2 >= mult_out) ? (u_pipe2 - mult_out) : (u_pipe2 + q_p2 - mult_out);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            u_out <= 24'd0;
            v_out <= 24'd0;
        end else begin
            if (is_gs_p2) begin
                // GS mode: u_out = add result, v_out = mult_out
                u_out <= gs_add_pipe2;
                v_out <= mult_out;
            end else begin
                // CT mode: u_out = ct_u_val, v_out = ct_v_val
                u_out <= ct_u_val;
                v_out <= ct_v_val;
            end
        end
    end

endmodule

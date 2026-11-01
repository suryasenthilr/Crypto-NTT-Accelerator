`timescale 1ns / 1ps

// ============================================================================
// Module: polyflex_top
// Description: PolyFlex-NTT Top-Level Dual-Mode NTT/INTT Accelerator
//              Supports NIST FIPS 203 (ML-KEM) and NIST FIPS 204 (ML-DSA)
// Architecture: Conflict-Free Dual-Bank SRAM, Unified CT/GS Butterfly,
//               Reconfigurable Constant-Time Solinas/Montgomery Modular Engine
// ============================================================================

module polyflex_top (
    input  wire        clk,
    input  wire        rst_n,
    
    // Configuration & Control
    input  wire        mode_kyber,  // 1: Kyber, 0: Dilithium
    input  wire        is_gs,       // 0: Forward NTT (CT), 1: Inverse INTT (GS)
    input  wire        start,
    output wire        busy,
    output wire        done,
    
    // Host Interface (Coefficients Load / Store)
    input  wire        host_we,
    input  wire [7:0]  host_addr,
    input  wire [23:0] host_wdata,
    output wire [23:0] host_rdata
);

    // ------------------------------------------------------------------------
    // Host Address Decoding (Parity-based)
    // ------------------------------------------------------------------------
    wire host_bank = ^host_addr;
    wire [6:0] host_sub_addr = host_addr[7:1];

    // ------------------------------------------------------------------------
    // Address Generator Wires
    // ------------------------------------------------------------------------
    wire        ag_ren0, ag_ren1;
    wire [6:0]  ag_raddr0, ag_raddr1;
    wire        ag_read_u_from_bank1;
    wire [7:0]  ag_twiddle_addr;
    wire        ag_wen0, ag_wen1;
    wire [6:0]  ag_waddr0, ag_waddr1;
    wire        ag_write_u_to_bank1;

    address_generator u_addr_gen (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .mode_kyber(mode_kyber),
        .is_gs(is_gs),
        .busy(busy),
        .done(done),
        .ren0(ag_ren0),
        .raddr0(ag_raddr0),
        .ren1(ag_ren1),
        .raddr1(ag_raddr1),
        .read_u_from_bank1(ag_read_u_from_bank1),
        .twiddle_addr(ag_twiddle_addr),
        .wen0(ag_wen0),
        .waddr0(ag_waddr0),
        .wen1(ag_wen1),
        .waddr1(ag_waddr1),
        .write_u_to_bank1(ag_write_u_to_bank1)
    );

    // ------------------------------------------------------------------------
    // Twiddle Factor ROM
    // ------------------------------------------------------------------------
    wire [23:0] twiddle_data;
    twiddle_rom u_twiddle_rom (
        .clk(clk),
        .mode_kyber(mode_kyber),
        .addr(ag_twiddle_addr),
        .twiddle_out(twiddle_data)
    );

    // ------------------------------------------------------------------------
    // Butterfly Unit
    // ------------------------------------------------------------------------
    wire [23:0] sram_rdata0, sram_rdata1;
    wire [23:0] bf_u_in = ag_read_u_from_bank1 ? sram_rdata1 : sram_rdata0;
    wire [23:0] bf_v_in = ag_read_u_from_bank1 ? sram_rdata0 : sram_rdata1;
    wire [23:0] bf_u_out, bf_v_out;

    ntt_butterfly_unit u_butterfly (
        .clk(clk),
        .rst_n(rst_n),
        .mode_kyber(mode_kyber),
        .is_gs(is_gs),
        .u_in(bf_u_in),
        .v_in(bf_v_in),
        .twiddle(twiddle_data),
        .u_out(bf_u_out),
        .v_out(bf_v_out)
    );

    // ------------------------------------------------------------------------
    // SRAM Port Multiplexing (Host vs Compute Engine)
    // ------------------------------------------------------------------------
    // Port A (Read):
    wire ren0 = busy ? ag_ren0 : 1'b1;
    wire ren1 = busy ? ag_ren1 : 1'b1;
    wire [6:0] raddr0 = busy ? ag_raddr0 : host_sub_addr;
    wire [6:0] raddr1 = busy ? ag_raddr1 : host_sub_addr;

    // Port B (Write):
    wire wen0 = busy ? ag_wen0 : (host_we && !host_bank);
    wire wen1 = busy ? ag_wen1 : (host_we && host_bank);
    wire [6:0] waddr0 = busy ? ag_waddr0 : host_sub_addr;
    wire [6:0] waddr1 = busy ? ag_waddr1 : host_sub_addr;

    wire [23:0] wdata0 = busy ? (ag_write_u_to_bank1 ? bf_v_out : bf_u_out) : host_wdata;
    wire [23:0] wdata1 = busy ? (ag_write_u_to_bank1 ? bf_u_out : bf_v_out) : host_wdata;

    dual_bank_sram u_sram (
        .clk(clk),
        .ren0(ren0),
        .raddr0(raddr0),
        .rdata0(sram_rdata0),
        .ren1(ren1),
        .raddr1(raddr1),
        .rdata1(sram_rdata1),
        .wen0(wen0),
        .waddr0(waddr0),
        .wdata0(wdata0),
        .wen1(wen1),
        .waddr1(waddr1),
        .wdata1(wdata1)
    );

    // Host readback routing
    assign host_rdata = host_bank ? sram_rdata1 : sram_rdata0;

endmodule

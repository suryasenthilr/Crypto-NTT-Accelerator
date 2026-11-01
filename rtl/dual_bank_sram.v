`timescale 1ns / 1ps

// ============================================================================
// Module: dual_bank_sram
// Description: Dual-Bank, Dual-Port SRAM Memory Subsystem for PolyFlex-NTT
//              - Bank 0: 128 words x 24 bits
//              - Bank 1: 128 words x 24 bits
// Port A: Read port (dual independent bank access)
// Port B: Write port (dual independent bank access)
// ============================================================================

module dual_bank_sram (
    input  wire        clk,
    
    // Read Port A (Bank 0)
    input  wire        ren0,
    input  wire [6:0]  raddr0,
    output reg  [23:0] rdata0,
    
    // Read Port A (Bank 1)
    input  wire        ren1,
    input  wire [6:0]  raddr1,
    output reg  [23:0] rdata1,
    
    // Write Port B (Bank 0)
    input  wire        wen0,
    input  wire [6:0]  waddr0,
    input  wire [23:0] wdata0,
    
    // Write Port B (Bank 1)
    input  wire        wen1,
    input  wire [6:0]  waddr1,
    input  wire [23:0] wdata1
);

    // Memory Arrays
    reg [23:0] bank0 [0:127];
    reg [23:0] bank1 [0:127];

    // Synchronous Read/Write for Bank 0
    always @(posedge clk) begin
        if (wen0) begin
            bank0[waddr0] <= wdata0;
        end
        if (ren0) begin
            rdata0 <= bank0[raddr0];
        end
    end

    // Synchronous Read/Write for Bank 1
    always @(posedge clk) begin
        if (wen1) begin
            bank1[waddr1] <= wdata1;
        end
        if (ren1) begin
            rdata1 <= bank1[raddr1];
        end
    end

endmodule

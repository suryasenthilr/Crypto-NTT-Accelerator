"""
Twiddle Factor Generator for PolyFlex-NTT
Generates bit-exact precomputed twiddle factors for:
- NIST FIPS 203 (ML-KEM / Kyber): q = 3329, n = 256
- NIST FIPS 204 (ML-DSA / Dilithium): q = 8380417, n = 256
Outputs Verilog ROM implementation.
"""

import os

KYBER_Q = 3329
KYBER_ZETA = 17

DILITHIUM_Q = 8380417
DILITHIUM_ZETA = 1753

def bit_reverse(x: int, bits: int) -> int:
    res = 0
    for _ in range(bits):
        res = (res << 1) | (x & 1)
        x >>= 1
    return res

def generate_tables():
    # Kyber twiddle factors in Montgomery domain (128 entries, 12 bits each)
    # omega_mont = (zeta^bitrev(i, 7) * 2^16) mod 3329
    kyber_zetas = [
        (pow(KYBER_ZETA, bit_reverse(i, 7), KYBER_Q) * 65536) % KYBER_Q 
        for i in range(128)
    ]
    
    # Dilithium twiddle factors in standard domain (256 entries, 23 bits each)
    # Solinas reduction operates directly in standard domain
    dilithium_zetas = [
        pow(DILITHIUM_ZETA, bit_reverse(i, 8), DILITHIUM_Q) 
        for i in range(256)
    ]
    
    return kyber_zetas, dilithium_zetas

def write_verilog_rom(kyber_zetas, dilithium_zetas, filepath):
    with open(filepath, 'w') as f:
        f.write("`timescale 1ns / 1ps\n")
        f.write("// Auto-generated Twiddle ROM for PolyFlex-NTT\n")
        f.write("// Supports Dual-Mode: Dilithium (256x23) and Kyber (128x12)\n\n")
        f.write("module twiddle_rom (\n")
        f.write("    input  wire        clk,\n")
        f.write("    input  wire        mode_kyber, // 1: Kyber, 0: Dilithium\n")
        f.write("    input  wire [7:0]  addr,       // 0-255 for Dilithium, 0-127 for Kyber\n")
        f.write("    output reg  [23:0] twiddle_out // [22:0] for Dilithium, [11:0] for Kyber\n")
        f.write(");\n\n")
        f.write("    always @(posedge clk) begin\n")
        f.write("        if (mode_kyber) begin\n")
        f.write("            case (addr[6:0])\n")
        for i, val in enumerate(kyber_zetas):
            f.write(f"                7'd{i}: twiddle_out <= 24'd{val};\n")
        f.write("                default: twiddle_out <= 24'd0;\n")
        f.write("            endcase\n")
        f.write("        end else begin\n")
        f.write("            case (addr)\n")
        for i, val in enumerate(dilithium_zetas):
            f.write(f"                8'd{i}: twiddle_out <= 24'd{val};\n")
        f.write("                default: twiddle_out <= 24'd0;\n")
        f.write("            endcase\n")
        f.write("        end\n")
        f.write("    end\n")
        f.write("endmodule\n")

if __name__ == "__main__":
    k_z, d_z = generate_tables()
    out_path = os.path.join(os.path.dirname(__file__), "..", "rtl", "twiddle_rom.v")
    write_verilog_rom(k_z, d_z, out_path)
    print(f"Twiddle ROM written successfully to {out_path}")

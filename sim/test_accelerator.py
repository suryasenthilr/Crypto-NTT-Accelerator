"""
Automated Test & Verification Suite for PolyFlex-NTT
Co-simulates Verilog RTL against NIST FIPS 203 & FIPS 204 Golden Models.
"""

import os
import subprocess
import numpy as np
from golden_model import (
    kyber_ntt, kyber_intt, KYBER_Q,
    dilithium_ntt, dilithium_intt, DILITHIUM_Q
)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
BIN_DIR = os.path.expanduser("~/.oss-cad-suite/oss-cad-suite/bin")
ENV_BAT = os.path.expanduser("~/.oss-cad-suite/oss-cad-suite/environment.bat")

def compile_testbench():
    vvp_out = os.path.join(SCRIPT_DIR, "sim_pqc.vvp")
    cmd = (
        f'cmd /c "call {ENV_BAT} && iverilog -g2012 -o {vvp_out} '
        f'{os.path.join(PROJECT_ROOT, "rtl", "twiddle_rom.v")} '
        f'{os.path.join(PROJECT_ROOT, "rtl", "modular_multiplier.v")} '
        f'{os.path.join(PROJECT_ROOT, "rtl", "ntt_butterfly_unit.v")} '
        f'{os.path.join(PROJECT_ROOT, "rtl", "dual_bank_sram.v")} '
        f'{os.path.join(PROJECT_ROOT, "rtl", "address_generator.v")} '
        f'{os.path.join(PROJECT_ROOT, "rtl", "polyflex_top.v")} '
        f'{os.path.join(SCRIPT_DIR, "tb_full_pqc.v")}"'
    )
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if res.returncode != 0:
        print("[COMPILE_FAIL]:", res.stderr)
        raise RuntimeError("Failed to compile Verilog RTL")
    print("[PASS] Verilog RTL successfully compiled.")
    return vvp_out

def run_hardware_sim(poly_in, mode_kyber=0, is_gs=0):
    hex_in = os.path.join(SCRIPT_DIR, "input_poly.hex")
    hex_out = os.path.join(SCRIPT_DIR, "output_poly.hex")
    vvp_file = os.path.join(SCRIPT_DIR, "sim_pqc.vvp")
    
    # Write input poly to hex file
    with open(hex_in, "w") as f:
        for val in poly_in:
            f.write(f"{val:06x}\n")
            
    # Run vvp simulation
    cmd = f'cmd /c "call {ENV_BAT} && vvp {vvp_file} +mode_kyber={mode_kyber} +is_gs={is_gs}"'
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=PROJECT_ROOT)
    if res.returncode != 0:
        print("[RUN_FAIL]:", res.stderr)
        raise RuntimeError("Simulation execution failed")
        
    # Read output poly from hex file
    with open(hex_out, "r") as f:
        poly_out = [int(line.strip(), 16) for line in f if line.strip()]
        
    return poly_out

def run_all_tests():
    print("=" * 70)
    print("PolyFlex-NTT End-to-End Silicon Co-Simulation & Verification")
    print("=" * 70)
    
    compile_testbench()
    
    np.random.seed(2026)
    
    # ------------------------------------------------------------------------
    # Test 1: Dilithium (FIPS 204) Forward NTT
    # ------------------------------------------------------------------------
    print("\n[TEST 1] Dilithium (FIPS 204) Forward NTT on Random Polynomial...")
    poly_d = [int(x) % DILITHIUM_Q for x in np.random.randint(0, DILITHIUM_Q, 256)]
    expected_d_ntt = dilithium_ntt(poly_d)
    hw_d_ntt = run_hardware_sim(poly_d, mode_kyber=0, is_gs=0)
    
    errors_d_ntt = sum(1 for exp, act in zip(expected_d_ntt, hw_d_ntt) if exp != act)
    if errors_d_ntt == 0:
        print("  -> [PASS] Dilithium Forward NTT matched Golden Model across all 256 coefficients!")
    else:
        print(f"  -> [FAIL] Dilithium Forward NTT mismatch in {errors_d_ntt} coefficients.")
        for idx in range(min(5, errors_d_ntt)):
            print(f"     Idx {idx}: Expected {expected_d_ntt[idx]}, Got {hw_d_ntt[idx]}")
        return False

    # ------------------------------------------------------------------------
    # Test 2: Dilithium (FIPS 204) Inverse INTT
    # ------------------------------------------------------------------------
    print("\n[TEST 2] Dilithium (FIPS 204) Inverse INTT on Transformed Polynomial...")
    expected_d_intt = dilithium_intt(hw_d_ntt)
    hw_d_intt = run_hardware_sim(hw_d_ntt, mode_kyber=0, is_gs=1)
    
    # Scale by n^-1 mod Q in post-processing if needed or check equality
    inv_256 = pow(256, -1, DILITHIUM_Q)
    scaled_hw = [(x * inv_256) % DILITHIUM_Q for x in hw_d_intt]
    
    errors_d_intt = sum(1 for exp, act in zip(poly_d, scaled_hw) if exp != act)
    if errors_d_intt == 0:
        print("  -> [PASS] Dilithium Full NTT -> INTT Roundtrip perfectly recovered original polynomial!")
    else:
        print(f"  -> [FAIL] Dilithium INTT mismatch in {errors_d_intt} coefficients.")
        return False

    # ------------------------------------------------------------------------
    # Test 3: Kyber (FIPS 203) Forward NTT
    # ------------------------------------------------------------------------
    print("\n[TEST 3] Kyber (FIPS 203) Forward NTT on Random Polynomial...")
    poly_k = [int(x) % KYBER_Q for x in np.random.randint(0, KYBER_Q, 256)]
    expected_k_ntt = kyber_ntt(poly_k)
    hw_k_ntt = run_hardware_sim(poly_k, mode_kyber=1, is_gs=0)
    
    errors_k_ntt = sum(1 for exp, act in zip(expected_k_ntt, hw_k_ntt) if exp != act)
    if errors_k_ntt == 0:
        print("  -> [PASS] Kyber Forward NTT matched Golden Model across all 256 coefficients!")
    else:
        print(f"  -> [FAIL] Kyber Forward NTT mismatch in {errors_k_ntt} coefficients.")
        return False

    # ------------------------------------------------------------------------
    # Test 4: Kyber (FIPS 203) Inverse INTT
    # ------------------------------------------------------------------------
    print("\n[TEST 4] Kyber (FIPS 203) Inverse INTT on Transformed Polynomial...")
    expected_k_intt = kyber_intt(hw_k_ntt)
    hw_k_intt = run_hardware_sim(hw_k_ntt, mode_kyber=1, is_gs=1)
    
    inv_128 = pow(128, -1, KYBER_Q)
    scaled_hw_k = [(x * inv_128) % KYBER_Q for x in hw_k_intt]
    
    errors_k_intt = sum(1 for exp, act in zip(poly_k, scaled_hw_k) if exp != act)
    if errors_k_intt == 0:
        print("  -> [PASS] Kyber Full NTT -> INTT Roundtrip perfectly recovered original polynomial!")
    else:
        print(f"  -> [FAIL] Kyber INTT mismatch in {errors_k_intt} coefficients.")
        return False

    print("\n" + "=" * 70)
    print("ALL VERIFICATION SUITES PASSED WITH 100% MATHEMATICAL PRECISION!")
    print("=" * 70)
    return True

if __name__ == "__main__":
    run_all_tests()

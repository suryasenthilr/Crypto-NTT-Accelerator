"""
Golden Reference Model for Dual-Mode NIST PQC NTT/INTT Engine:
- FIPS 203: ML-KEM (Kyber)   -- q = 3329, n = 256, 7-stage NTT, degree-1 base rings
- FIPS 204: ML-DSA (Dilithium) -- q = 8380417, n = 256, 8-stage NTT, full point-wise ring
"""

import numpy as np

# --------------------------------------------------------------------------
# Parameters
# --------------------------------------------------------------------------
KYBER_Q = 3329
KYBER_N = 256
KYBER_ZETA = 17

DILITHIUM_Q = 8380417
DILITHIUM_N = 256
DILITHIUM_ZETA = 1753

def bit_reverse(x: int, bits: int) -> int:
    res = 0
    for _ in range(bits):
        res = (res << 1) | (x & 1)
        x >>= 1
    return res

# --------------------------------------------------------------------------
# NIST FIPS 203 (ML-KEM / Kyber) Forward & Inverse NTT Reference
# --------------------------------------------------------------------------
# NIST FIPS 203 Table of zetas for Kyber
KYBER_ZETAS = [pow(KYBER_ZETA, bit_reverse(i, 7), KYBER_Q) for i in range(128)]

def kyber_ntt(f_in):
    """
    FIPS 203 Algorithm 8: NTT(f)
    In-place Cooley-Tukey butterfly across 7 stages (len = 128 down to 2).
    Leaves 128 polynomials of degree 1.
    """
    f = list(f_in)
    k = 1
    length = 128
    while length >= 2:
        start = 0
        while start < 256:
            zeta = KYBER_ZETAS[k]
            k += 1
            for j in range(start, start + length):
                t = (zeta * f[j + length]) % KYBER_Q
                f[j + length] = (f[j] - t) % KYBER_Q
                f[j] = (f[j] + t) % KYBER_Q
            start = start + 2 * length
        length = length // 2
    return f

def kyber_intt(f_in):
    """
    FIPS 203 Algorithm 9: NTT^-1(f)
    In-place Gentleman-Sande butterfly across 7 stages (len = 2 up to 128).
    """
    f = list(f_in)
    k = 127
    length = 2
    while length <= 128:
        start = 0
        while start < 256:
            zeta = KYBER_ZETAS[k]
            k -= 1
            for j in range(start, start + length):
                t = f[j]
                f[j] = (t + f[j + length]) % KYBER_Q
                f[j + length] = (zeta * (f[j + length] - t)) % KYBER_Q
            start = start + 2 * length
        length = length * 2
    
    # Scale by f = 128^-1 mod 3329 = 3303
    f_inv = pow(128, -1, KYBER_Q)
    for i in range(256):
        f[i] = (f[i] * f_inv) % KYBER_Q
    return f

def kyber_base_mul(a0, a1, b0, b1, zeta):
    """
    Polynomial multiplication of (a0 + a1*X) * (b0 + b1*X) mod (X^2 - zeta) mod q
    """
    c0 = (a0 * b0 + a1 * b1 * zeta) % KYBER_Q
    c1 = (a0 * b1 + a1 * b0) % KYBER_Q
    return c0, c1

# --------------------------------------------------------------------------
# NIST FIPS 204 (ML-DSA / Dilithium) Forward & Inverse NTT Reference
# --------------------------------------------------------------------------
DILITHIUM_ZETAS = [pow(DILITHIUM_ZETA, bit_reverse(i, 8), DILITHIUM_Q) for i in range(256)]

def dilithium_ntt(w_in):
    """
    FIPS 204 Algorithm 36: NTT(w)
    Cooley-Tukey butterfly across 8 stages (len = 128 down to 1).
    Full point-wise decomposition.
    """
    w = list(w_in)
    k = 1
    length = 128
    while length >= 1:
        start = 0
        while start < 256:
            zeta = DILITHIUM_ZETAS[k]
            k += 1
            for j in range(start, start + length):
                t = (zeta * w[j + length]) % DILITHIUM_Q
                w[j + length] = (w[j] - t) % DILITHIUM_Q
                w[j] = (w[j] + t) % DILITHIUM_Q
            start = start + 2 * length
        length = length // 2
    return w

def dilithium_intt(w_in):
    """
    FIPS 204 Algorithm 37: NTT^-1(w)
    Gentleman-Sande butterfly across 8 stages (len = 1 up to 128).
    """
    w = list(w_in)
    k = 255
    length = 1
    while length <= 128:
        start = 0
        while start < 256:
            zeta = (-DILITHIUM_ZETAS[k]) % DILITHIUM_Q
            k -= 1
            for j in range(start, start + length):
                t = w[j]
                w[j] = (t + w[j + length]) % DILITHIUM_Q
                w[j + length] = (t - w[j + length]) % DILITHIUM_Q
                w[j + length] = (zeta * w[j + length]) % DILITHIUM_Q
            start = start + 2 * length
        length = length * 2
        
    # Scale by 256^-1 mod 8380417 = 8347681
    inv_n = pow(256, -1, DILITHIUM_Q)
    for i in range(256):
        w[i] = (w[i] * inv_n) % DILITHIUM_Q
    return w

# --------------------------------------------------------------------------
# Self-Test Verification
# --------------------------------------------------------------------------
if __name__ == "__main__":
    np.random.seed(42)
    # Test Kyber NTT -> INTT roundtrip
    poly_k = [int(x) % KYBER_Q for x in np.random.randint(0, KYBER_Q, 256)]
    ntt_k = kyber_ntt(poly_k)
    recovered_k = kyber_intt(ntt_k)
    assert poly_k == recovered_k, "Kyber NTT/INTT roundtrip failed!"
    print("[PASS] Kyber (FIPS 203) NTT -> INTT roundtrip verified perfectly!")

    # Test Dilithium NTT -> INTT roundtrip
    poly_d = [int(x) % DILITHIUM_Q for x in np.random.randint(0, DILITHIUM_Q, 256)]
    ntt_d = dilithium_ntt(poly_d)
    recovered_d = dilithium_intt(ntt_d)
    assert poly_d == recovered_d, "Dilithium (FIPS 204) NTT/INTT roundtrip failed!"
    print("[PASS] Dilithium (FIPS 204) NTT -> INTT roundtrip verified perfectly!")

# Mathematical Foundations of PolyFlex-NTT

## 1. Introduction and Ring Arithmetic

Post-Quantum Cryptography (PQC) standardized by NIST in August 2024 relies on the hardness of the Module Learning With Errors (M-LWE) and Module Short Integer Solution (M-SIS) problems over polynomial rings:
$$\mathcal{R}_q = \mathbb{Z}_q[X]/(X^n + 1)$$

### 1.1 NIST FIPS 203: ML-KEM (Kyber)
- Modulus: $q = 3329$ ($12$ bits).
- Degree: $n = 256$.
- Ring factorization: Since $q - 1 = 3328 = 256 \times 13$, $512 \nmid (q-1)$. Therefore, $\mathbb{Z}_q$ contains primitive $256$-th roots of unity, but **not** $512$-th roots of unity.
- Factorization of $X^{256} + 1$:
  $$X^{256} + 1 = \prod_{i=0}^{127} \left(X^2 - \zeta^{2 \cdot \text{bitrev}_7(i) + 1}\right)$$
- The NTT decomposes the 256-coefficient polynomial into $128$ degree-1 polynomials over $7$ stages of Cooley-Tukey butterflies.

### 1.2 NIST FIPS 204: ML-DSA (Dilithium)
- Modulus: $q = 8380417 = 2^{23} - 2^{13} + 1$ ($23$ bits).
- Degree: $n = 256$.
- Ring factorization: Since $512 \mid (q - 1)$ ($8380416 / 512 = 16368$), $\mathbb{Z}_q$ contains primitive $512$-th roots of unity ($\zeta = 1753$).
- The NTT decomposes $X^{256} + 1$ completely into $256$ degree-0 polynomials (linear factors) over $8$ stages of Cooley-Tukey butterflies:
  $$X^{256} + 1 = \prod_{i=0}^{255} \left(X - \zeta^{2 \cdot \text{bitrev}_8(i) + 1}\right)$$

---

## 2. Conflict-Free Parity Address Mapping: Formal Proof

### Theorem 1 (Guaranteed Conflict-Free Dual-Bank Access)
Let the coefficient index $i \in [0, 255]$ be represented by its 8-bit binary vector:
$$i = \sum_{b=0}^{7} i_b 2^b, \quad i_b \in \{0, 1\}$$
Define the bank allocation function $\mathcal{B}: [0, 255] \rightarrow \{0, 1\}$ as the XOR parity of the index:
$$\mathcal{B}(i) = \bigoplus_{b=0}^{7} i_b$$
And the intra-bank address mapping $\mathcal{A}: [0, 255] \rightarrow [0, 127]$ as:
$$\mathcal{A}(i) = \lfloor i / 2 \rfloor = (i_7, i_6, i_5, i_4, i_3, i_2, i_1)_2$$

**Assertion**: For every stage $s \in [0, 7]$ of both Cooley-Tukey Forward NTT and Gentleman-Sande Inverse INTT, every butterfly pair $(u, v)$ satisfies:
$$\mathcal{B}(u) \neq \mathcal{B}(v)$$
And the combined mapping $\Phi(i) = (\mathcal{B}(i), \mathcal{A}(i))$ is a strict bijection from $[0, 255]$ onto $\{0, 1\} \times [0, 127]$.

### Proof:
1. **Bijection**:
   Suppose $\Phi(i) = \Phi(j)$. Then $\mathcal{A}(i) = \mathcal{A}(j)$, which implies $i_b = j_b$ for all $b \in \{1, \dots, 7\}$.
   Furthermore, $\mathcal{B}(i) = \mathcal{B}(j)$ implies:
   $$\left(\bigoplus_{b=1}^{7} i_b\right) \oplus i_0 = \left(\bigoplus_{b=1}^{7} j_b\right) \oplus j_0 \implies i_0 = j_0$$
   Therefore, $i = j$. Since the domain and codomain both have cardinality $256$, $\Phi$ is a bijection.

2. **Conflict Freedom**:
   In Cooley-Tukey and Gentleman-Sande algorithms, any butterfly pair $(u, v)$ at stage $s$ differs by a stride of length $L = 2^m$ where $m \in \{0, 1, \dots, 7\}$.
   Specifically, $v = u \oplus 2^m$.
   The Hamming distance between the binary representations of $u$ and $v$ is exactly $1$:
   $$u \oplus v = 2^m = (0, \dots, 0, \underbrace{1}_{m\text{-th bit}}, 0, \dots, 0)_2$$
   Applying the parity operator:
   $$\mathcal{B}(v) = \bigoplus_{b=0}^{7} v_b = \left(\bigoplus_{b \neq m} u_b\right) \oplus (u_m \oplus 1) = \left(\bigoplus_{b=0}^{7} u_b\right) \oplus 1 = \mathcal{B}(u) \oplus 1$$
   Since $\mathcal{B}(u) \in \{0, 1\}$, $\mathcal{B}(v) = 1 - \mathcal{B}(u) \neq \mathcal{B}(u)$.
   Therefore, $u$ and $v$ are **always mapped to opposite memory banks**. This guarantees zero bank conflicts for all stages without pipeline bubbles. $\blacksquare$

---

## 3. Modular Reduction Formulations

### 3.1 Non-Negative Solinas Reduction for Dilithium
Dilithium modulus $q = 8380417 = 2^{23} - 2^{13} + 1$.
Consequently:
$$2^{23} \equiv 2^{13} - 1 \pmod q$$
For any product $P = A \cdot B < q^2 < 2^{46}$, partition $P$ into 23-bit limbs:
$$P = P_1 \cdot 2^{23} + P_0, \quad P_0, P_1 \in [0, 2^{23} - 1]$$
Substituting $2^{23}$:
$$P \equiv P_0 + P_1 \cdot (2^{13} - 1) = P_0 + (P_1 \ll 13) - P_1 \pmod q$$

**Lemma (Non-Negativity)**:
Since $P_1 \ge 0$ and $2^{13} = 8192 > 1$:
$$(P_1 \ll 13) - P_1 = 8191 \cdot P_1 \ge 0$$
Hence, intermediate accumulator terms are **strictly non-negative**, eliminating signed arithmetic and overflow vulnerabilities in hardware.

### 3.2 Montgomery Multiplier for Kyber
Kyber modulus $q = 3329$. Montgomery radix $R = 2^{16} = 65536$.
$$R^{-1} \equiv 169 \pmod q, \quad q' = -q^{-1} \bmod R = 3327$$
Given $A < q$ and twiddle factor precomputed in Montgomery domain $\omega_{Mont} = (\omega \cdot R) \bmod q$:
$$P = A \cdot \omega_{Mont}$$
Montgomery reduction:
$$m = (P \cdot 3327) \bmod 2^{16}$$
$$T = \lfloor (P + m \cdot 3329) / 2^{16} \rfloor$$
$$T \equiv P \cdot R^{-1} \equiv A \cdot (\omega \cdot R) \cdot R^{-1} \equiv A \cdot \omega \pmod{3329}$$
The result emerges directly in the standard domain without post-scaling.

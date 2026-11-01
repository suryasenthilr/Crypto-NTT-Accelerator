# PolyFlex-NTT Hardware Architecture & IP Specification

## 1. Top-Level IP Overview

PolyFlex-NTT is a dual-mode hardware cryptographic accelerator IP core optimized for polynomial arithmetic in the finalized NIST Post-Quantum Cryptography standards:
- **NIST FIPS 203: ML-KEM (CRYSTALS-Kyber)** — Key Encapsulation ($q = 3329, n = 256$)
- **NIST FIPS 204: ML-DSA (CRYSTALS-Dilithium)** — Digital Signatures ($q = 8380417, n = 256$)

The core provides an industry-standard **AMBA AXI4-Lite Slave Interface**, enabling plug-and-play integration into RISC-V, ARM, or x86 SoC interconnects with hardware interrupt (`irq`) signaling and memory-mapped register access.

```
                          PolyFlex-NTT IP Core Block Diagram
  ┌─────────────────────────────────────────────────────────────────────────────┐
  │                           polyflex_axi_wrapper                              │
  │                                                                             │
  │   AXI4-Lite Slave Interface                                                 │
  │   (AW, W, B, AR, R channels) ────────┐                                     │
  │                                      │                                      │
  │   IRQ Line ◄─────────────────────────┼──────────────────┐                   │
  │                                      ▼                  │                   │
  │                           ┌────────────────────┐        │                   │
  │                           │   AXI Controller   │        │                   │
  │                           │   & CSR Decoder    │        │                   │
  │                           └────────┬───────────┘        │                   │
  │                                    │                    │                   │
  │              ┌─────────────────────┼────────────────────┘                   │
  │              │ (Host WE, Addr, WData)                                       │
  │              ▼                                                              │
  │     ┌──────────────────┐                                                    │
  │     │ Dual-Bank SRAM   │◄────────────────────────┐                          │
  │     │ Bank 0: 128x24   │                         │ (Writeback: 5-cycle delay)│
  │     │ Bank 1: 128x24   │                         │                          │
  │     └────────┬─────────┘                         │                          │
  │              │ (rdata0, rdata1)                  │                          │
  │              ▼                                   │                          │
  │     ┌──────────────────┐                         │                          │
  │     │ Unified CT / GS  ├─────────────────────────┘                          │
  │     │  Butterfly Unit  │ (Throughput: 1 butterfly / clock cycle)            │
  │     └────────▲─────────┘                                                    │
  │              │                                                              │
  │     ┌────────┴─────────┐       ┌──────────────────┐                         │
  │     │ Conflict-Free    │       │ Canonical        │                         │
  │     │ Address Gen      │       │ Twiddle ROM      │                         │
  │     │ (Parity + Split) │       │ (Kyber/Dilithium)│                         │
  │     └──────────────────┘       └──────────────────┘                         │
  │                                                                             │
  └─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. AXI4-Lite Memory Map & Register Specification

The IP core occupies a 4KB address space (`0x000` to `0xFFF`) with a 32-bit data bus.

| Offset | Register Name | Access | Reset Value | Description |
| :--- | :--- | :--- | :--- | :--- |
| `0x000` | `REG_CONTROL` | R/W | `0x00000000` | Core Execution Control Register |
| `0x004` | `REG_STATUS` | R/W | `0x00000000` | Status & Interrupt Enable Register |
| `0x008` | `REG_PERF_CYCLES`| RO | `0x00000000` | 32-bit Hardware Cycle Latency Counter |
| `0x00C` | `REG_IP_VERSION` | RO | `0x50514331` | Core Identification (`"PQC1"`) |
| `0x100 - 0x4FC` | `COEFF_WINDOW` | R/W | `0x00000000` | 256-Word Polynomial Coefficient Window |

### 2.1 Bitfield Definitions

#### `REG_CONTROL` (`0x000`)
```
 31                                         4   3      2       1     0
┌────────────────────────────────────────────┬──────┬──────┬──────┬──────┐
│                  RESERVED                  │IS_GS │ MODE │ S_RST│START │
└────────────────────────────────────────────┴──────┴──────┴──────┴──────┘
```
- **Bit 0 (`START`)**: Write `1` to trigger transform execution. Self-clearing.
- **Bit 1 (`SOFT_RESET`)**: Write `1` to synchronously reset internal state machines.
- **Bit 2 (`MODE`)**: Transform parameter select:
  - `0`: ML-DSA (Dilithium, modulus $q = 8380417$, 8 stages)
  - `1`: ML-KEM (Kyber, modulus $q = 3329$, 7 stages)
- **Bit 3 (`IS_GS`)**: Transform direction select:
  - `0`: Forward NTT (Cooley-Tukey butterfly)
  - `1`: Inverse INTT (Gentleman-Sande butterfly)

#### `REG_STATUS` (`0x004`)
- **Bit 0 (`BUSY`)**: `1` when compute engine is running; `0` when idle.
- **Bit 1 (`DONE`)**: Asserted on transform completion. Write `1` to clear.
- **Bit 2 (`IRQ_EN`)**: Hardware interrupt enable. When set, `irq` pulses high on completion.

#### `REG_PERF_CYCLES` (`0x008`)
- Real-time 32-bit hardware performance counter. Increments every clock cycle while the compute engine is active. Captures the exact cycle count for software benchmarking.

---

## 3. Submodule Datapath Specifications

### 3.1 Conflict-Free In-Place Address Generator (`address_generator.v`)
To eliminate memory bank collisions without expensive multi-stage crossbar networks, the generator maps an 8-bit coefficient index to memory banks using XOR parity:

$$\text{Bank}(i) = i_7 \oplus i_6 \oplus i_5 \oplus i_4 \oplus i_3 \oplus i_2 \oplus i_1 \oplus i_0$$
$$\text{Internal Address}(i) = i \gg 1$$

- **Dynamic Split-Position Scheduling**:
  Because Kyber and Dilithium have asymmetric stage counts and stride origins:
  - Cooley-Tukey (Forward NTT): `split_pos = 7 - stage`
  - Gentleman-Sande (Inverse INTT, Dilithium): `split_pos = stage`
  - Gentleman-Sande (Inverse INTT, Kyber): `split_pos = stage + 1`
- **Dynamic Bit Insertion**:
  Operand pairs are generated on the fly from a 7-bit pair counter without lookup tables:
  - `u` = `pair_cnt` with bit 0 inserted at `split_pos`
  - `v` = `pair_cnt` with bit 1 inserted at `split_pos`
  Because `u` and `v` differ by exactly 1 bit, $\text{Bank}(u) \neq \text{Bank}(v)$ is guaranteed for every stage.

### 3.2 Unified CT / GS Butterfly Unit (`ntt_butterfly_unit.v`)
- **Latency**: 3 clock cycles fully pipelined (continuous throughput of 1 butterfly per cycle).
- **Forward Cooley-Tukey (CT)**:
  $$u' = (u + v \cdot \omega) \bmod q$$
  $$v' = (u - v \cdot \omega) \bmod q$$
- **Inverse Gentleman-Sande (GS)**:
  $$u' = (u + v) \bmod q$$
  $$v' = ((v - u) \cdot \omega) \bmod q$$
- Datapath reuse: Exactly 1 modular multiplier, 1 modular adder, and 1 modular subtractor with multiplexed routing.

### 3.3 Reconfigurable Modular Multiplier (`modular_multiplier.v`)
- **Latency**: 2 clock cycles (pipelined).
- **Execution**: Strictly constant-time (side-channel timing attack immune).
- **Dilithium Mode ($q = 8380417 = 2^{23} - 2^{13} + 1$)**:
  Solinas reduction replaces multi-word division with shifts and additions:
  $$P = P_1 \cdot 2^{23} + P_0 \equiv P_0 + (P_1 \ll 13) - P_1 \pmod q$$
  Because $(P_1 \ll 13) - P_1 = 8191 \cdot P_1 \ge 0$, intermediate arithmetic is strictly non-negative.
- **Kyber Mode ($q = 3329$)**:
  Montgomery reduction with radix $R = 2^{16}$ ($q' = 3327$). Twiddle factors are stored pre-scaled by $R \bmod q$, allowing standard-domain output directly without post-scaling.

---

## 4. Execution Timing & Latency Metrics

```
  Cycle   0     1     2     3     4     5     6     ...   1024  1025  1026  1027  1028  1029  1030
  clk    ┌─┐   ┌─┐   ┌─┐   ┌─┐   ┌─┐   ┌─┐   ┌─┐         ┌─┐   ┌─┐   ┌─┐   ┌─┐   ┌─┐   ┌─┐   ┌─┐
         ┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───        ─┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └──
  start  ┌─────┐
         ┘     └────────────────────────────────────────────────────────────────────────────────
  busy   ──────┌───────────────────────────────────────────────────────────────────────────┐
               │                                                                           └────
  read         │ Pair 0│ Pair 1│ Pair 2│ ...                                       │
  mult                 │ Pair 0│ Pair 1│ ...                                       │
  write                        │ Pair 0│ Pair 1│ ...                               │
  done   ──────────────────────────────────────────────────────────────────────────────────┌────
                                                                                           │
  irq    ──────────────────────────────────────────────────────────────────────────────────┌────
                                                                                           │
```

| Parameter | ML-DSA (Dilithium) | ML-KEM (Kyber) | Unit |
| :--- | :--- | :--- | :--- |
| **Number of Stages** | 8 | 7 | stages |
| **Butterflies / Stage** | 128 | 128 | operations |
| **Active Compute Cycles** | 1,024 | 896 | clock cycles |
| **Pipeline Drain Latency** | 5 | 5 | clock cycles |
| **Total Transform Latency**| **1,029** | **901** | clock cycles |
| **Pipeline Efficiency** | **100%** (zero stalls) | **100%** (zero stalls) | duty cycle |

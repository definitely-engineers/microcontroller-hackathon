# Definitely CPU

Team implementation for the 2026 Microcontroller Hackathon.
This directory contains our CPU RTL, ISA tooling, tests, compiler backend work,
benchmarks and related project files.

## Stage 1: addition

The first working RTL slice implements `LI`, register-register/register-immediate
`ADD`, and the `HALT` pseudo-instruction needed by the testbench. The test loads
21 into `r8` and `r9`, writes their sum to `r10`, and checks that `r10 == 42`.

Run it inside the hackathon Dev Container:

```bash
cd /workspaces/microcontroller-hackathon
python3 resources/software/scripts/simulate.py definitely_cpu/add.simulate.yml
```

The expected result is `ALL 1 checks PASSED`.

## Stage 3: data memory

The memory slice implements little-endian `LOAD`, `STORE`, `LOADB`, and
`STOREB` with absolute address16 and base-register + signed offset11 modes.
Run the assembly-level RTL regression inside the Dev Container:

```bash
python3 resources/software/scripts/simulate.py \
  definitely_cpu/load_store.simulate.yml
```

The test covers word/byte accesses, positive and negative offsets, byte
zero-extension, and byte-store preservation within an existing word.

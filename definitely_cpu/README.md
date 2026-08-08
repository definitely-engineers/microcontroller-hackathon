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

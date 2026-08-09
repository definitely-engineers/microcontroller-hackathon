#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "[1/4] Encoding regression tests"
python3 -m unittest discover \
  -s definitely_cpu/tests \
  -p 'test_*_encoding.py' -v

echo "[2/4] Incremental LLVM backend build/install"
python3 resources/software/scripts/build_compiler.py \
  --build-tree-only \
  definitely_cpu/definitely.build-compiler.yml

echo "[3/4] Compile Stage 2 sum_to_n C acceptance test"
python3 resources/software/scripts/compile.py \
  definitely_cpu/sum_to_n.compile.yml

echo "[4/4] Simulate compiler-generated control flow"
python3 resources/software/scripts/simulate.py \
  definitely_cpu/sum_to_n_compiled.simulate.yml

echo "Compiler control-flow validation: PASS"

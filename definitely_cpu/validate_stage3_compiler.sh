#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "[1/7] Encoding regression tests"
python3 -m unittest discover \
  -s definitely_cpu/tests \
  -p 'test_*_encoding.py' -v

echo "[2/7] Incremental LLVM backend build/install"
python3 resources/software/scripts/build_compiler.py \
  --build-tree-only \
  definitely_cpu/definitely.build-compiler.yml

tests=(leaf nonleaf locals recursion fib)
step=3
for test_name in "${tests[@]}"; do
  echo "[$step/7] Compile and simulate Stage 3 ${test_name}"
  python3 resources/software/scripts/compile.py \
    "definitely_cpu/stage3_${test_name}.compile.yml"
  python3 resources/software/scripts/simulate.py \
    "definitely_cpu/stage3_${test_name}_compiled.simulate.yml"
  step=$((step + 1))
done

echo "Stage 3 compiler validation: PASS"

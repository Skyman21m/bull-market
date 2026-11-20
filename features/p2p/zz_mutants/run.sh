#!/bin/bash
# Run inside the container from features/p2p: each mutant against its tests, then restore.
cd /work/features/p2p
start=${1:-1}; end=${2:-999}
n=0
while IFS='|' read -r name path tests; do
  n=$((n+1)); [ $n -lt $start ] && continue; [ $n -gt $end ] && break
  cp "$path" "zz_mutants/orig.dart"
  cp "zz_mutants/$name.dart" "$path"
  if fvm flutter test --no-pub $tests >"zz_mutants/$name.log" 2>&1; then echo "SURVIVED $name"; else
    if grep -q "Compilation failed\|Error: " "zz_mutants/$name.log"; then echo "COMPILE? $name"; else echo "KILLED $name"; fi
  fi
  cp "zz_mutants/orig.dart" "$path"
done < zz_mutants/list.txt
echo MUTANTS-DONE

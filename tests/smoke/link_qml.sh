#!/usr/bin/env bash
# Preserve production relative imports and resource URLs inside a smoke harness.
set -euo pipefail
root="$1"
harness="$2"
while IFS= read -r -d '' source; do
  relative="${source#"$root/"}"
  mkdir -p "$harness/$(dirname "$relative")"
  ln -s "$source" "$harness/$relative"
done < <(find "$root/qml" -type f \( -name '*.qml' -o -name '*.js' \) -print0)
mkdir -p "$harness/bin"
ln -s "$root/bin/read-clipboard.py" "$harness/bin/read-clipboard.py"

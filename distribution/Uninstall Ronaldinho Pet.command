#!/bin/zsh
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
echo -n "Move Ronaldinho Pet and its local state to Trash? [y/N] "
read -k 1 answer
echo
if [[ "$answer" != [yY] ]]; then
  echo "Cancelled."
  exit 0
fi
"$ROOT/uninstall.sh"

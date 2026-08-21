#!/bin/zsh
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
if "$ROOT/install.sh"; then
  echo
  echo "Ronaldinho Pet is ready. You can close this window."
else
  status=$?
  echo
  echo "Installation failed. Press any key to close."
  read -k 1
  exit $status
fi

#!/bin/bash
# Builds lua-lgi for Lua 5.4 (what Xournal++ uses) and installs it below ~/.local,
# where the Lernordner plugin looks for it. Ubuntu only packages lgi for Lua 5.1/5.3.
# Needs: sudo apt install build-essential pkg-config git liblua5.4-dev libgirepository1.0-dev
set -euo pipefail
PREFIX="$HOME/.local"
SRC="$HOME/.cache/lgi-src"

if [ -f "$PREFIX/lib/lua/5.4/lgi/corelgilua51.so" ]; then
  echo "lgi for Lua 5.4 is already installed in $PREFIX - nothing to do."
  exit 0
fi
for t in git make gcc pkg-config; do
  command -v "$t" >/dev/null || { echo "Missing: $t  (sudo apt install build-essential pkg-config git liblua5.4-dev libgirepository1.0-dev)" >&2; exit 1; }
done
pkg-config --exists lua5.4 || { echo "Missing: liblua5.4-dev (sudo apt install liblua5.4-dev libgirepository1.0-dev)" >&2; exit 1; }

[ -d "$SRC/.git" ] || git clone https://github.com/lgi-devs/lgi "$SRC"
make -C "$SRC" LUA_VERSION=5.4 LUA_CFLAGS="$(pkg-config --cflags lua5.4)"
make -C "$SRC" install LUA_VERSION=5.4 PREFIX="$PREFIX"
echo "Done: lgi for Lua 5.4 installed in $PREFIX. Now run: bash install.sh"

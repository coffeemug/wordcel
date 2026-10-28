#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
swift build --build-system native
.build/debug/XWriter --self-test

#!/usr/bin/env bash
set -euo pipefail

sed -nE \
  '/iPhone .*\([0-9A-Fa-f-]{36}\) \(Booted\)[[:space:]]*$/ s/.*\(([0-9A-Fa-f-]{36})\) \(Booted\)[[:space:]]*$/\1/p'

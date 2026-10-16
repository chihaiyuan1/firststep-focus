#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./scripts/install.sh
printf '\n安装完成。请按应用内「连接 Chrome」指引加载扩展。\n'

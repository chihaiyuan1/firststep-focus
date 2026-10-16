#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./scripts/install.sh
printf '\n安装完成。首次使用请阅读同目录的「安装说明.md」；已连接 Chrome 可直接使用。\n'

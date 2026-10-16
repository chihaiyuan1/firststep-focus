#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./scripts/install.sh
printf '\n安装完成。首次使用或升级扩展，请阅读同目录的「安装说明.md」。\n'

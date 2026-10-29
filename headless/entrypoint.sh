#!/bin/sh
# PT Manager headless 容器入口。
# 默认用 headed Chrome + Xvfb（最贴近桌面行为）；HEADLESS=1 时改用 headless=new，跳过 Xvfb。

set -e

DATA_DIR="${PT_MANAGER_DATA_DIR:-/data}"
mkdir -p "$DATA_DIR" 2>/dev/null || true
if [ ! -w "$DATA_DIR" ]; then
  echo "[entrypoint] 警告: 数据目录 $DATA_DIR 不可写。请执行: chown -R 1000:1000 $DATA_DIR" >&2
fi
export PT_HEADLESS="${HEADLESS:-0}"

if [ "$PT_HEADLESS" = "1" ]; then
  echo "[entrypoint] HEADLESS=1 -> Chrome headless=new，不启动 Xvfb"
  exec /opt/pt-manager-headless "$@"
fi

echo "[entrypoint] 使用 Xvfb 虚拟显示 + headed Chrome"
exec xvfb-run -a -s "-screen 0 1280x800x24" /opt/pt-manager-headless "$@"

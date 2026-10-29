#!/bin/sh
# PT Manager 容器专用 Chrome 启动包装脚本。
#
# 原因：
#  1) 容器内常以非 root 运行，Chrome 需要 --no-sandbox；
#  2) 容器默认 /dev/shm 偏小，需要 --disable-dev-shm-usage，避免渲染崩溃；
#  3) PT_HEADLESS=1 时追加 --headless=new（更省资源，无需 Xvfb）。
#
# 应用通过 CHROME 环境变量（/usr/local/bin/google-chrome）调用本脚本。

set -e

REAL="/usr/bin/google-chrome-stable"
if [ ! -x "$REAL" ]; then
  REAL="$(command -v google-chrome 2>/dev/null || true)"
fi
if [ -z "$REAL" ] || [ ! -x "$REAL" ]; then
  echo "chrome-wrapper: 找不到真实 Chrome 可执行文件" >&2
  exit 127
fi

if [ "${PT_HEADLESS:-0}" = "1" ]; then
  exec "$REAL" --no-sandbox --disable-dev-shm-usage --headless=new "$@"
fi
exec "$REAL" --no-sandbox --disable-dev-shm-usage "$@"

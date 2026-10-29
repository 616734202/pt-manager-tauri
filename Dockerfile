# syntax=docker/dockerfile:1
#
# PT Manager headless 保活服务镜像
# 构建 headless 二进制 + google-chrome + Xvfb，运行在 Linux 容器内，无 GUI。
#
# 用法见 docs/docker-headless.md

# ---------- 构建阶段 ----------
FROM rust:1-bookworm AS builder

# headless 只用 tauri 核心类型；tauri 在 Linux 上无条件依赖 gtk3，但不需要 webkit2gtk。
# reqwest 默认走 native-tls(openssl)，因此需要 libssl-dev + pkg-config。
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential \
       pkg-config \
       libgtk-3-dev \
       libssl-dev \
       ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .

WORKDIR /build/headless
RUN cargo build --release \
    && cp /build/headless/target/release/pt-manager-headless /build/pt-manager-headless

# ---------- 运行阶段 ----------
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# 安装 Google Chrome（真实 headed 模式跑在 Xvfb 虚拟显示上）与 Xvfb、字体。
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       curl \
       ca-certificates \
       wget \
       gnupg \
       unzip \
       xvfb \
       libssl3 \
       fonts-liberation \
       fonts-noto-cjk \
       libgtk-3-0 \
    && wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get install -y /tmp/chrome.deb \
    && rm -f /tmp/chrome.deb \
    && rm -rf /var/lib/apt/lists/*

# 非 root 用户：Chrome 以 root 运行会拒绝启动（--no-sandbox 由 wrapper 注入）。
# 固定 uid/gid 1000，方便宿主对挂载目录执行 chown（见 docs/docker-headless.md）。
RUN groupadd -g 1000 ptm \
    && useradd -m -u 1000 -g 1000 -d /home/ptm ptm \
    && mkdir -p /data \
    && chown -R ptm:ptm /data

# Chrome 专用包装脚本：注入容器必需参数（非 root 需 --no-sandbox、/dev/shm 需 --disable-dev-shm-usage），
# 可选 PT_HEADLESS=1 追加 --headless=new。通过 CHROME 环境变量让应用显式调用它。
COPY --chmod=0755 headless/chrome-wrapper.sh /usr/local/bin/google-chrome
COPY --chmod=0755 headless/entrypoint.sh /opt/entrypoint.sh
COPY --from=builder --chmod=0755 /build/pt-manager-headless /opt/pt-manager-headless

# 持久化数据目录（配置 + 日志 + Chrome 登录 Profile）
ENV PT_MANAGER_DATA_DIR=/data
ENV PT_MANAGER_CHROME_PROFILE_DIR=/data
# 让应用优先使用我们的 chrome wrapper
ENV CHROME=/usr/local/bin/google-chrome
ENV HOME=/home/ptm

USER ptm
WORKDIR /home/ptm
VOLUME ["/data"]

ENTRYPOINT ["/opt/entrypoint.sh"]

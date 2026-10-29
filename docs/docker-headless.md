# PT Manager 无界面（headless）Docker 部署

把桌面保活工具的核心逻辑（Cron 调度 + Chrome CDP 保活 + 自动登录 + CookieCloud + OCR + Gotify/Bark 通知）
跑成一个**无 GUI 的 Linux 容器服务**，适合丢到服务器/NAS 上 24 小时挂机。

## 原理

- 项目核心逻辑全部在 Rust 端（`scheduler.rs` / `cdp.rs` / `cookiecloud.rs` / `ocr.rs` / `gotify.rs` 等），
  Tauri 只是“窗口 + 前端命令桥”。
- 新增 `headless/` 独立 crate，通过 `#[path]` **复用同一份源码**，不复制、不 fork，只加一个无窗口入口 `src/main.rs`。
- 桌面端代码与构建**完全不受影响**，仍可正常 `npm run tauri:build`。
- 容器内用 Xvfb 提供虚拟显示，让 Chrome 以真实 headed 模式运行（最贴近桌面行为，减少被 PT 站风控的概率）；
  也支持 `HEADLESS=1` 改用 `--headless=new` 以更省资源。

## 改造内容（对原仓库的最小改动）

| 文件 | 改动 |
|---|---|
| `src-tauri/src/store.rs` | 新增 `PT_MANAGER_DATA_DIR` 环境变量覆盖；配置加载/保存抽成 dir 版本；新增 `load_config_headless()` |
| `src-tauri/src/cdp.rs` | 新增 `PT_MANAGER_CHROME_PROFILE_DIR` 覆盖，Chrome 登录 Profile 可持久化 |
| `headless/` | 新增无 GUI 服务 crate（复用核心模块） |
| `Dockerfile` | 多阶段构建：Rust 编译 → debian 运行时 + google-chrome + Xvfb |
| `docker-compose.yml` | 一键起服务 / 一次性跑一轮 |
| `headless/chrome-wrapper.sh` | 注入容器必需 Chrome 参数（`--no-sandbox`、`--disable-dev-shm-usage`） |
| `headless/entrypoint.sh` | 入口：默认 Xvfb + headed；`HEADLESS=1` 时跳过 Xvfb |

## 环境变量

| 变量 | 说明 | 默认 |
|---|---|---|
| `PT_MANAGER_DATA_DIR` | 配置 + 日志目录（挂载持久化） | `/data` |
| `PT_MANAGER_CHROME_PROFILE_DIR` | Chrome 登录 Profile 目录（登录态持久化） | `/data` |
| `HEADLESS` | `1` 用 Chrome headless=new；`0` 用 Xvfb + headed | `0` |
| `CHROME` | 指向容器内 Chrome wrapper | 镜像内已设置 |

## 快速开始

前置：Linux 主机 + Docker（含 compose 插件）。

```bash
# 1. 构建并启动定时保活服务（默认 Cron `0 9 * * *`，见 /data/config.json）
docker compose up -d --build

# 2. 查看日志
docker compose logs -f pt-manager-headless

# 3. 站点配置
#    镜像首次启动会在 /data/config.json 生成默认配置。
#    把桌面端导出的 config.json 放到 ./data/config.json 后 `docker compose restart` 即可。
#    也可以在容器内直接运行一次性命令查看/核对：
docker compose run --rm pt-manager-once
```

## 配置站点

在项目目录创建 `./data/config.json`（与桌面端导出的格式一致，站点数组或 `{ "sites": [...] }` 均可），
示例：

```json
{
  "sites": [
    {
      "name": "示例站",
      "url": "https://pt.example.com/",
      "username": "user",
      "password": "pass",
      "totp_secret": "BASE32SECRET",
      "auto_login": true
    }
  ],
  "cron": "0 9 * * *"
}
```

> 首次推荐先人工在桌面端配置好并导出完整 config.json 放进来，复用同一份配置，避免在容器里手工填密码/TOTP。
> 配置里包含明文密码与密钥，请勿提交到公开仓库。

## 登录态（Cookie）处理

- 保活需要登录态。两种来源：
  1. **CookieCloud**：在配置里填好 CookieCloud 服务地址/UUID/密码，开启“保活前自动同步”，容器会自动把 Cookie 与 LocalStorage 同步进专用 Chrome；
  2. **人工预登录**：本方案没有 GUI，不方便人工登录，强烈建议走 CookieCloud。
- 专用 Chrome Profile 落在 `/data/chrome-cdp-profile-auto`（已挂载持久化），容器重启不丢登录态。

## 两种 Chrome 运行模式

| 模式 | 设置 | 优点 | 缺点 |
|---|---|---|---|
| headed + Xvfb | `HEADLESS=0`（默认） | 最贴近真实桌面浏览器，风控风险低 | 内存占用略高 |
| headless=new | `HEADLESS=1` | 更省资源 | 部分站点可能识别 headless |

如需切换：改 `docker-compose.yml` 里的 `HEADLESS` 后 `docker compose up -d`。

## 手动立即跑一轮

```bash
docker compose run --rm pt-manager-once
```

## 常用排查

```bash
# 看容器内数据目录是否生成了 config.json / run.log
docker compose exec pt-manager-headless ls -la /data

# 进容器手动跑一轮看输出
docker compose exec pt-manager-headless /opt/pt-manager-headless --once
```

## 通过 GitHub Actions 构建镜像并直接拉取（推荐）

仓库内置了 `.github/workflows/docker-headless.yml`，`push v*` 的 Git Tag 或手动触发时，
自动在 Linux 上构建 headless 镜像并推送到 ghcr.io，产物为 **linux/amd64**：

```
ghcr.io/<你的账号>/pt-manager-tauri:latest
```

### 首次开启（一次性）
1. 把仓库推到你自己的 GitHub（本项目是别人的仓库，需要先 fork 或转到自己的仓库下）。
2. 在仓库 **Settings → Actions → General → Workflow permissions** 勾选 **Read and write permissions**（否则推送 ghcr 会 403）。
3. 推一个 `v*` tag（如 `git tag v2.0.1 && git push origin v2.0.1`），或在 Actions 页面点 **Run workflow**。

### 1Panel 直接用镜像（无需服务器编译）
镜像推好后，在 1Panel「容器 → 编排」新建编排，粘贴下面的内容即可（把 `owner` 换成你的 GitHub 账号）：

```yaml
services:
  pt-manager-headless:
    image: ghcr.io/owner/pt-manager-tauri:latest
    container_name: pt-manager-headless
    restart: unless-stopped
    environment:
      - PT_MANAGER_DATA_DIR=/data
      - PT_MANAGER_CHROME_PROFILE_DIR=/data
      - HEADLESS=0
    volumes:
      - /opt/pt-manager/data:/data
    command: []
```

首次拉取前先 `mkdir -p /opt/pt-manager/data && chown -R 1000:1000 /opt/pt-manager/data`。
ghcr.io 的公开包无需登录即可拉取；若包是私有，在 1Panel 里给该镜像配置 ghcr.io 的登录凭据。

## 已知限制与注意

1. **本机（Windows）无法编译验证**：headless 面向 Linux 目标，需在 Linux/Docker 主机上 `docker build` 完成编译与首次验证。
2. **站点风控**：headless 模式可能被部分 PT 站识别；默认 headed+Xvfb 更安全。
3. **端口**：CDP 调试端口绑定容器内 `127.0.0.1`，外部无法直接访问，属于正常设计。
4. **更新**：容器内不含自动更新逻辑（updater 为桌面专属，已排除）。
5. **配置热加载**：headless 常驻进程只在启动时读取一次 `config.json`，修改配置后需 `docker compose restart pt-manager-headless`。
6. **登录尝试计数**：桌面端会把“剩余登录尝试次数”回写配置并落盘；headless 中该计数仅在单轮保活进程内存中生效、不持久化（不改变登录尝试次数之外的行为）。

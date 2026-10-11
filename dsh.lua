-- dsh.lua · DeepSeek Harness 后端模块（Android-DIY-Sandbox 沙盒版）
--
-- 仿 agent.lua 架构：只暴露纯逻辑函数，界面由 main.lua 编排。
--   M.installed()  后端是否已就绪（Node24 + dsh 已装）
--   M.install()    一键安装/重装后端（Node24 + pnpm + dsh + 原生插件）
--   M.launch()     启动后端 + token bridge，就绪后在内嵌 WebView 打开 UI
--   M.stop()       停止后端与 bridge
--   M.running()    后端是否在跑
--
-- 原理：官方 `dsh web` 是一个带 token 鉴权的本地 HTTP 服务（桌面端 Electron 也是套它）。
-- 本模块在沙盒容器内以 host.spawn 常驻运行它，再让内嵌 WebView 打开其地址。
-- token 每次启动都会轮换（但有 30 天 cookie），故用一个本地 bridge 把当前认证 URL
-- 交给 WebView，避免把 token 写死。
--
-- 依赖：容器内可联网（apt/curl）。首次安装较重（下载 Node24 + dsh 约 100MB+）。

local M = {}

-- ============================================================
-- 配置
-- ============================================================
local NODE_VERSION = "v24.4.0"          -- dsh 需要 Node>=24 (import.meta.main)
local DSH_VERSION  = "0.2.0-rc.2"
local DSH_HOME     = "/root/.dsh"
local WEB_LOG      = "/root/dsh-web.log"
local URL_FILE     = "/root/dsh-url.txt"
local BRIDGE_LOG   = "/root/dsh-bridge.log"
local SERVE_SH     = "/root/dsh-serve.sh"
local BRIDGE_JS    = "/root/dsh-bridge.js"

local S = { port = nil, bridge_port = nil, running = false }
M.running = function() return S.running == true end

local function node_bin() return "/opt/node-" .. NODE_VERSION .. "-linux-arm64/bin" end

-- 是否已安装完整后端
function M.installed()
  local ok_node = host.exists(node_bin() .. "/node")
  local ok_dsh  = host.exists("/root/.pnpm-home/global/5/node_modules/@deepseek-ai/dsh/lib/bin.js")
  return ok_node and ok_dsh
end

-- ============================================================
-- 内嵌脚本：落地到容器
-- ============================================================
local BRIDGE_CONTENT = [==[
const http = require("node:http");
const fs = require("node:fs");
const port = Number(process.argv[2] || 3081);
const urlFile = process.argv[3] || "/root/dsh-url.txt";
function readUrl() { try { return fs.readFileSync(urlFile, "utf8").trim(); } catch { return ""; } }
const server = http.createServer((req, res) => {
  const url = new URL(req.url || "/", "http://dsh-bridge.invalid");
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Cache-Control", "no-store");
  if (url.pathname === "/url") {
    const value = readUrl();
    res.writeHead(value ? 200 : 503, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(value || "no url");
    return;
  }
  if (url.pathname === "/health") { res.writeHead(200); res.end("ok"); return; }
  res.writeHead(200); res.end("dsh token bridge\nGET /url\n");
});
server.listen(port, "127.0.0.1", () => console.log("dsh-bridge listening on 127.0.0.1:" + port));
]==]

-- 前台运行 dsh web 的守护脚本（供 host.spawn 托管），同时起 bridge 并写 URL 文件。
local SERVE_TEMPLATE = [==[
#!/bin/bash
set -uo pipefail
export PNPM_HOME=/root/.pnpm-home
export PATH=/opt/node-__NODEVER__-linux-arm64/bin:$PNPM_HOME:$PATH
export DSH_HOME=__DSHHOME__
PORT=__PORT__
BRIDGE_PORT=__BRIDGEPORT__
LOG=__WEBLOG__
URLFILE=__URLFILE__
BRIDGELOG=__BRIDGELOG__
echo "[dsh] 清理旧进程..."
pkill -f 'dsh/lib/bin.js web' 2>/dev/null || true
pkill -f 'dsh-bridge.js' 2>/dev/null || true
sleep 1
setsid node __BRIDGEJS__ "$BRIDGE_PORT" "$URLFILE" >"$BRIDGELOG" 2>&1 </dev/null &
(
  for _ in $(seq 1 120); do
    TOKEN=$(grep -o 'token=[A-Za-z0-9_-]*' "$LOG" 2>/dev/null | head -1 | cut -d= -f2)
    if [ -n "$TOKEN" ]; then
      printf 'http://127.0.0.1:%s/?token=%s' "$PORT" "$TOKEN" > "$URLFILE"
      echo "[dsh] URL 已就绪"
      break
    fi
    sleep 0.5
  done
) &
echo "[dsh] 启动 dsh web on 127.0.0.1:$PORT ..."
: > "$LOG"
exec dsh web --no-open --host 127.0.0.1 --port "$PORT"
]==]

local function write_scripts()
  host.write_file(BRIDGE_JS, BRIDGE_CONTENT)
  local serve = SERVE_TEMPLATE
    :gsub("__NODEVER__", NODE_VERSION:gsub("^v", ""))
    :gsub("__DSHHOME__", DSH_HOME)
    :gsub("__BRIDGEJS__", BRIDGE_JS)
    :gsub("__WEBLOG__", WEB_LOG)
    :gsub("__URLFILE__", URL_FILE)
    :gsub("__BRIDGELOG__", BRIDGE_LOG)
    :gsub("__PORT__", tostring(S.port))
    :gsub("__BRIDGEPORT__", tostring(S.bridge_port))
  host.write_file(SERVE_SH, serve)
end

-- ============================================================
-- 安装：与 install.sh 等价的自包含 shell
-- ============================================================
local SH_INSTALL = [==[
set -e
NODE_VER="__NODEVER__"
NODE_DIR="/opt/node-$NODE_VER-linux-arm64"
PNPM_HOME=/root/.pnpm-home
DSH_VERSION="__DSHVER__"
export DEBIAN_FRONTEND=noninteractive

echo "==> 安装基础工具 (curl/xz/keytool 等)"
command -v curl >/dev/null 2>&1 || { apt-get -o Acquire::ForceIPv4=true update -qq; apt-get -o Acquire::ForceIPv4=true install -y -qq curl xz-utils ca-certificates >/dev/null; }

echo "==> 下载 Node $NODE_VER"
if [ ! -x "$NODE_DIR/bin/node" ]; then
  cd /opt
  curl -fL "https://nodejs.org/dist/$NODE_VER/node-$NODE_VER-linux-arm64.tar.xz" -o node.tar.xz
  tar xf node.tar.xz
  rm -f node.tar.xz
fi
export PATH="$NODE_DIR/bin:$PATH"
node -v

echo "==> 安装 pnpm (standalone)"
if [ ! -f /opt/pnpm/pnpm-dist/bin/pnpm.cjs ]; then
  mkdir -p /opt/pnpm && cd /opt/pnpm
  npm pack pnpm@9 >/dev/null 2>&1
  tar xzf pnpm-9*.tgz && mv package pnpm-dist
fi
PNPM="node /opt/pnpm/pnpm-dist/bin/pnpm.cjs"
export PNPM_HOME
export PATH="$PNPM_HOME:$PATH"
mkdir -p "$PNPM_HOME"

echo "==> 安装 @deepseek-ai/dsh@$DSH_VERSION"
$PNPM add -g "@deepseek-ai/dsh@$DSH_VERSION"

echo "==> 安装原生插件 node-addon-require-builtin-linux-arm64-gnu"
$PNPM add -g "node-addon-require-builtin-linux-arm64-gnu@0.1.9" || true
RB=$(find "$PNPM_HOME/global" -type d -path '*node-addon-require-builtin@*/node_modules/node-addon-require-builtin' 2>/dev/null | head -1)
PKG=$(find "$PNPM_HOME/global" -type d -name "node-addon-require-builtin-linux-arm64-gnu" 2>/dev/null | head -1)
if [ -n "$RB" ] && [ -n "$PKG" ]; then
  mkdir -p "$RB/node_modules"
  ln -sfn "$PKG" "$RB/node_modules/node-addon-require-builtin-linux-arm64-gnu"
  echo "已链接原生插件"
fi
echo "==> 安装完成"
]==]

function M.install(reinstall)
  local pre = table.concat({
    'export TMPDIR="' .. host.tmp_path() .. '"',
  }, "\n")
  local body = SH_INSTALL
    :gsub("__NODEVER__", NODE_VERSION)
    :gsub("__DSHVER__", DSH_VERSION)
  if reinstall then
    body = 'rm -rf /opt/node-* /root/.pnpm-home /opt/pnpm\n' .. body
  end
  host.spawn(pre .. "\n" .. body, "DSH 后端安装", "dsh_install", function()
    host.toast("DSH 后端安装结束，可在「主页」启动")
  end)
  host.nav.go(2)  -- 跳到终端查看进度
end

-- ============================================================
-- 启动 / 健康检查 / 打开界面
-- ============================================================
local function open_webui()
  host.exec("cat " .. URL_FILE .. " 2>/dev/null", function(res)
    local url = res and res.output and res.output:gsub("%s+$", "") or ""
    if url:match("^https?://") then
      host.webview_open(url, "DSH")
    else
      host.toast("尚未拿到 DSH 地址，请稍候重试")
    end
  end)
end

local function wait_ready(tries)
  if not S.running then return end
  if tries > 90 then host.toast("DSH 启动超时，请在终端查看日志"); return end
  host.http({
    url = "http://127.0.0.1:" .. tostring(S.port) .. "/",
    timeout = 4,
    on_done = function(res)
      if res and (res.status == 200 or res.status == 401 or res.status == 303) then
        open_webui()
      else
        host.delay(1000, function() wait_ready(tries + 1) end)
      end
    end,
    on_error = function() host.delay(1000, function() wait_ready(tries + 1) end) end,
  })
end

function M.launch()
  if not M.installed() then
    host.confirm("DSH 后端尚未安装，是否现在安装？（约需下载 100MB+，请在终端查看进度）",
      function(yes) if yes then M.install(false) end end,
      { title = "未安装 DSH 后端", ok_text = "安装", cancel_text = "取消" })
    return
  end
  if S.running and S.port then
    -- 已在跑：健康检查后直接开界面
    host.http({
      url = "http://127.0.0.1:" .. tostring(S.port) .. "/",
      timeout = 3,
      on_done = function(res)
        if res and res.status then open_webui()
        else S.running = false; S.port = nil; S.bridge_port = nil; M.launch() end
      end,
      on_error = function()
        S.running = false; S.port = nil; S.bridge_port = nil
        host.toast("DSH 后端已离线，正在重启…"); M.launch()
      end,
    })
    return
  end
  host.toast("正在启动 DSH 后端…")
  host.free_port(3080, 3180, {}, function(p)
    if not p then host.toast("无可用端口"); return end
    S.port = p
    -- bridge 端口：在另一段范围里挑，且必须与 web 端口不同
    host.free_port(3181, 3280, { p }, function(bp)
      S.bridge_port = bp
      if not S.bridge_port or S.bridge_port == S.port then S.bridge_port = S.port + 1 end
      write_scripts()
      host.spawn("bash " .. SERVE_SH, "DSH 后端", "dsh_web", function()
        S.running = false; S.port = nil; S.bridge_port = nil
      end)
      S.running = true
      wait_ready(0)
    end)
  end)
end

function M.stop()
  host.stop("dsh_web")
  host.exec("pkill -f 'dsh-bridge.js' 2>/dev/null; pkill -f 'dsh/lib/bin.js web' 2>/dev/null; true")
  S.running = false; S.port = nil; S.bridge_port = nil
  host.toast("DSH 后端已停止")
end

return M

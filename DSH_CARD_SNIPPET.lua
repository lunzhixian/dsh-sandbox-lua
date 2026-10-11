-- ============================================================
-- DSH 卡片 —— 把下面这段复制进 main.lua
-- ============================================================
--
-- 1) 在 main.lua 顶部（其他 require 附近）加：
--
--      local dsh = require("dsh")
--
-- 2) 在 main.lua 里加这个卡片函数（放在 quick_start_card 之后即可）：
--

local function dsh_card(ctx)
  local running = ctx.running and ctx.running["dsh_web"]
  local installed = dsh.installed and dsh.installed()
  return card("DeepSeek Harness", {
    tile("状态", {
      icon = running and "check_circle" or "power_settings_new",
      iconColor = running and "green" or "grey",
      subtitle = installed and (running and "运行中" or "已安装，未启动") or "未安装",
    }),
    spacer(12),
    row({
      expanded(button(running and "停止" or (installed and "启动" or "安装"),
        function()
          if running then dsh.stop()
          elseif installed then dsh.launch()
          else dsh.install(false) end
        end,
        { icon = running and "stop" or "play_arrow" })),
      expanded(button("打开界面", function()
        if running then dsh.launch() else host.toast("请先启动 DSH 后端") end
      end, { variant = "tonal", icon = "language" })),
    }, { gap = 12 }),
  })
end

--
-- 3) 在 main.lua 末尾的 app.page("home", ...) 里，把 dsh_card(ctx) 加进列表，例如：
--
--      app.page("home", function(ctx)
--        return {
--          quick_start_card(ctx),
--          dsh_card(ctx),         -- ← 新增这一行
--          napcat_card(ctx),
--          env_card(),
--          manage_section(),
--        }
--      end)
--
-- 4) 重载脚本（主页顶栏刷新键，或 `bash agent/sandbox reload`）。
--
-- 说明：
--   · 首次点「安装」会在终端标签跑安装流程（Node24 + pnpm + dsh），需联网、耗时数分钟。
--   · 安装完成后点「启动」，就绪后会自动在内嵌 WebView 打开 DSH 界面。
--   · 「打开界面」可随时重新打开 WebView（后端已在跑时）。

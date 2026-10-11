-- apps/dsh.lua · 整屏应用：DeepSeek Harness 控制台
-- 约定: 返回 { title=显示名, build=function(ctx) return 组件 end, dispose=可选清理 }
-- 依赖同目录上一级的 dsh.lua 模块（require("dsh")）。
--
-- 安装方式（任选其一）：
--   A. 放到脚本根目录的 apps/ 下，并在 main.lua 的 DYN_APPS 里加一行：
--        { label = "DSH", icon = "smart_toy_outlined", path = SCRIPTS .. "/apps/dsh.lua" },
--   B. 直接把它当作主页某处 loadlua 的内容。
--
-- 前提：脚本根目录已放置 dsh.lua（本包提供）。

local dsh = require("dsh")

return {
  title = "DSH",

  build = function(ctx)
    local running = ctx and ctx.running and ctx.running["dsh_web"]
    local installed = dsh.installed and dsh.installed()

    local status_text = installed and (running and "运行中" or "已安装，未启动") or "未安装"
    local status_icon = running and "check_circle" or (installed and "power_settings_new" or "error_outline")
    local status_color = running and "green" or (installed and "orange" or "red")

    return column({
      text("DeepSeek Harness", { size = 24, weight = "bold" }),
      text("开源的 harness 架构 · 一切皆插件", { size = 13, color = "grey" }),
      spacer(16),

      card("状态", {
        tile("后端", {
          icon = status_icon,
          iconColor = status_color,
          subtitle = status_text,
        }),
      }),

      spacer(12),

      card("操作", {
        row({
          expanded(button(running and "停止后端" or (installed and "启动后端" or "安装后端"),
            function()
              if running then dsh.stop()
              elseif installed then dsh.launch()
              else dsh.install(false) end
            end,
            { icon = running and "stop" or "play_arrow" })),
        }, { gap = 12 }),
        spacer(8),
        row({
          expanded(button("打开界面", function()
            if installed then dsh.launch() else host.toast("请先安装 DSH 后端") end
          end, { variant = "tonal", icon = "language" })),
          expanded(button("重装", function()
            host.confirm("确定要重装 DSH 后端吗？将重新下载 Node 与 dsh。", function(yes)
              if yes then dsh.install(true) end
            end)
          end, { variant = "text", icon = "refresh" })),
        }, { gap = 12 }),
      }),

      spacer(12),

      expansion("使用说明", {
        text("1. 首次点『安装后端』，在终端标签查看进度（需联网，数分钟）。"),
        spacer(6),
        text("2. 安装完成后点『启动后端』，就绪后自动在内嵌 WebView 打开界面。"),
        spacer(6),
        text("3. 之后点『打开界面』即可直接打开（后端已在跑时）。"),
        spacer(6),
        text("后端是官方 dsh web 服务（与桌面端同源），运行在沙盒容器内。"),
      }, { icon = "help_outline" }),
    }, { cross = "stretch" })
  end,
}

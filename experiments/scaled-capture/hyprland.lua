-- Disposable compositor only. No autostart or user configuration imports.
hl.monitor({ output = "CAPTURE-BENCH", mode = "2560x1440@60", position = "0x0", scale = 1 })
hl.monitor({ output = "", disabled = true })
hl.config({
    general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
    decoration = { rounding = 0, blur = { enabled = false }, shadow = { enabled = false } },
    animations = { enabled = false },
    misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
    ecosystem = { enforce_permissions = false },
})
hl.window_rule({ name = "capture-probes", match = { title = "^Capture probe .*" }, float = true })

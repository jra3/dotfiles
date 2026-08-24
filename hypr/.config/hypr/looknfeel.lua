-- Change the default Omarchy look'n'feel.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/

hl.config({
  decoration = {
    -- Omarchy ships square corners.
    rounding = 8,
  },
})

-- Float the fgtr worktree picker, reusing Omarchy's floating-window tag
-- (default/hypr/apps/system.lua turns that tag into float + center + size).
o.window("org.omarchy.worktree-workspace", { tag = "+floating-window" })

-- frame: EllesmereUIBagsAltsTooltip
-- Location icons on a second line, bank tabs named after their bank.
local t = ns.db.settings.tooltip
t.otherRealms, t.detail, t.showTabs = "always", "icons", true
local f = VisualScene("*all", "all")
VisualHover(f.grid.buttons, f.grid.used, function(b) return b.itemID == 2589 end)

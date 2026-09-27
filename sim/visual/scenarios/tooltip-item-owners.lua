-- frame: EllesmereUIBagsAltsTooltip
local f = VisualScene("*all", "all")
VisualHover(f.grid.buttons, f.grid.used, function(b) return b.itemID == 2589 end)

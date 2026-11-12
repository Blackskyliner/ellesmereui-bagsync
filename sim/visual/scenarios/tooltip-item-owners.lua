-- frame: EllesmereUIBagsAltsTooltip
-- The fixture's characters live on realms the simulator's player is not
-- connected to: other realms are listed always.
ns.db.settings.tooltip.otherRealms = "always"
local f = VisualScene("*all", "all")
VisualHover(f.grid.buttons, f.grid.used, function(b) return b.itemID == 2589 end)

-- frame: NotGameTooltipEllesmereUIBagsAlts
-- A value list row's tooltip: the item and every price source.
ns.db.settings.tooltip.otherRealms = "always"
VisualScene(EUIAltsSimFixture.MAIN, "value")
local pool = ns.ValueList.pool
VisualHover(pool, #pool, function(r) return r:IsShown() and r.data and r.data.id == 2589 end)

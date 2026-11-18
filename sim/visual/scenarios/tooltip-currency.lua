-- clients: retail
-- frame: NotGameTooltipEllesmereUIBagsAlts
local f = VisualScene("*all", "currency")
VisualHover(f.currencies.items, f.currencies.used, function(r) return r.currencyID == 3008 end)

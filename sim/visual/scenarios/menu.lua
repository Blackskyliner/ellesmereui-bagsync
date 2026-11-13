-- frame: EllesmereUIBagsAltsMenu
local f = VisualScene(EUIAltsSimFixture.MAIN, "bags")
VisualHover(f.sideRows.items, f.sideRows.used, function(row) return row.ownerKey == EUIAltsSimFixture.SECOND end)
for i = 1, f.sideRows.used do
    local row = f.sideRows.items[i]
    if row.ownerKey == EUIAltsSimFixture.SECOND then row:GetScript("OnClick")(row, "RightButton") end
end

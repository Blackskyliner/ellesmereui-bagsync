local ns = EllesmereUIBagsAlts._ns

simtest("settings category is registered in the real Settings panel", function()
    assertNotNil(ns.Options.category)
    assertType("number", ns.Options.category:GetID())
end)

simtest("self-test runs against the simulator surface", function()
    local ok, report = EllesmereUIBagsAlts.RunSelfTest()
    assertType("boolean", ok)
    assertTrue(report.indexConsistent)
    if #report.missingAPIs > 0 then
        print("simulator lacks: " .. table.concat(report.missingAPIs, ", "))
    end
end)

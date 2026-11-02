-- Runs last: every stand-in of SimGaps.lua for this client is still missing
-- in the simulator, was called during the run (unless marked rarely), and
-- returned what the client's API docs promise (SimGapSignatures.lua).
simtest("simulator stand-ins are still needed, used and documented", function()
    local problems = {}
    for _, gap in ipairs(SimGapRegistry) do
        if gap.applies then
            if not gap.installed then
                problems[#problems + 1] = gap.name .. ": the simulator implements it now, remove the stand-in"
            elseif gap.calls == 0 and not gap.rarely then
                problems[#problems + 1] = gap.name .. ": never called, remove the stand-in"
            end
            if gap.mismatch then problems[#problems + 1] = gap.name .. ": " .. gap.mismatch end
        end
    end
    assertEquals("", table.concat(problems, "; "))
end)

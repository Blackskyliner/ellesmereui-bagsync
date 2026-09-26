-- wow-ui-sim runs tests/*.lua of this addon after startup. Sync test failures
-- are reported through print(), which the simulator does not always flush;
-- async tests report on stderr, so every test is wrapped as an async test.
function simtest(name, fn)
    async_test(name, function(done) done(fn) end)
end

-- Like simtest, but waits (one check per simulator frame) until cond() is
-- true, e.g. for EllesmereUI Bags, which builds its window 0.5 s after login.
-- Never true -> the simulator reports a timeout, i.e. a failure.
function simtest_when(cond, name, fn)
    async_test(name, function(done)
        local f = CreateFrame("Frame")
        f:SetScript("OnUpdate", function(self)
            if cond() then
                self:SetScript("OnUpdate", nil)
                done(fn)
            end
        end)
    end)
end

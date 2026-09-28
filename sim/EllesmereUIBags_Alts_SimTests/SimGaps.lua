-- Client APIs that EllesmereUI calls and wow-ui-sim does not implement.
-- EllesmereUI's gamepad support asks them whenever its bag window opens; the
-- stand-ins answer like a player on mouse and keyboard. Each one is defined
-- only while the simulator lacks it, so a simulator that adds it takes over.
if IsUsingGamepad == nil then
    IsUsingGamepad = function() return false end
end
C_GamePad = C_GamePad or {}
if C_GamePad.IsEnabled == nil then
    C_GamePad.IsEnabled = function() return false end
end

-------------------------------------------------------------------------------
--  Locales/enUS.lua
--  Base locale. Keys ARE the English strings: a missing translation falls back
--  to the key itself, so enUS needs no table entries.
-------------------------------------------------------------------------------
local _, ns = ...

ns.L = setmetatable({}, {
    __index = function(_, key) return key end,
})

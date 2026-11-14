-- probe_main.lua — hand-written probe entry for the kwxLuaJIT probe lane.
--
-- probe.wxui (../../quick/tests/quick_probe/probe.wxui) generates
-- gen/probe_mainframe.lua and gen/probe_dlg.lua. Probe output never goes to
-- tests/quick.

local function script_directory()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    local dir = src:match("^(.*)[/\\][^/\\]*$")
    return dir or "."
end

local dir = script_directory()

local wx = require("wx")
local frame_module = dofile(dir .. "/gen/probe_mainframe.lua")
local dialog_module = dofile(dir .. "/gen/probe_dlg.lua")

local app = wx.App()

local frame = frame_module.create(nil)
frame:Show(true)

local dialog = dialog_module.create(frame)
if dialog ~= nil then
    dialog:ShowModal()
end

app:MainLoop()

-- quick_main.lua — hand-written entry point for the kwxLuaJIT quick test app.
--
-- quick.wxui generates quick_mainframe.lua and quick_dlg.lua into this folder;
-- the generated files only build the (hidden) forms. This file owns the
-- application bootstrap: create the frame, show it, run the modal dialog and
-- then enter the event loop.
--
-- Run from the repository root:
--   bin\Release\kwxlua.exe tests\quick\quick_main.lua
-- or check only:
--   build_quick.cmd

local function script_directory()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    local dir = src:match("^(.*)[/\\][^/\\]*$")
    return dir or "."
end

local dir = script_directory()

local wx = require("wx")
-- The per-class wrapper modules; used here only to reach wxEvent:Skip().
local wx_classes = require("kwxffi_idiomatic_gen")

local frame_module = dofile(dir .. "/quick_mainframe.lua")

-- The dialog form is only generated while quick.wxui still contains the dialog,
-- so a missing file is expected rather than fatal.
local dialog_ok, dialog_module = pcall(dofile, dir .. "/quick_dlg.lua")

local app = wx.App()

local frame = frame_module.create(nil)
frame:Show(true)

-- The dialog runs modally before the main loop starts, so a close request on the
-- frame has to unwind it: the bridge records the request, ends the modal loop and
-- stops the handler chain (Skip(false)) so wxWidgets cannot run its default close
-- handler while the dialog is still up. The frame is destroyed below, once
-- ShowModal has returned -- the shape quick_main.f90 and quick_main.go use.
local dialog = nil
local dialog_modal = false
local close_requested = false

frame:Connect(wx.EVT_CLOSE_WINDOW, function(event)
    if not dialog_modal then
        return
    end
    close_requested = true
    if event ~= nil then
        wx_classes.wxEvent.FromPtr(event):Skip(false)
    end
    local pending = dialog
    dialog_modal = false
    if pending ~= nil then
        pending:EndModal(wx.ID_CANCEL)
    end
end)

if dialog_ok and type(dialog_module) == "table" and dialog_module.create ~= nil then
    dialog = dialog_module.create(frame)
    if dialog ~= nil then
        dialog_modal = true
        dialog:ShowModal()
        dialog_modal = false
    end
end

if close_requested then
    frame:Destroy()
    return
end

app:MainLoop()

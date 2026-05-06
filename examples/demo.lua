--[[
    demo.lua - kwxLuaJit Demo Application

    Demonstrates the core features of kwxLuaJit:
    - Application lifecycle (kwxApp_*)
    - Frame with menu bar, status bar, and sizer layout
    - Panel, labels, text input, and button
    - Event handling: button click, menu commands, window close
    - Message boxes

    UI specification: .shared/demo_instructions.md

    Usage:
        kwxlua examples/demo.lua
--]]

local ffi = require("ffi")
local wx = require("wx")

-- Generated class modules for Menu / MenuBar
local wxMenu    = require("wxmenu_gen")
local wxMenuBar = require("wxmenubar_gen")

--------------------------------------------------------------------------------
-- Stock IDs not yet in wx namespace — resolve from kwxFFI constants
--------------------------------------------------------------------------------

local C = ffi.C

local function C_const(name, fallback)
    local ok, val = pcall(function() return C[name]() end)
    return ok and val or fallback
end

local ID_NEW   = C_const("expwxID_NEW",   5002)
local ID_OPEN  = C_const("expwxID_OPEN",  5001)
local ID_SAVE  = C_const("expwxID_SAVE",  5003)
local ID_UNDO  = C_const("expwxID_UNDO",  5007)
local ID_REDO  = C_const("expwxID_REDO",  5008)
local ID_CUT   = C_const("expwxID_CUT",   5031)
local ID_COPY  = C_const("expwxID_COPY",  5032)
local ID_PASTE = C_const("expwxID_PASTE", 5033)

--------------------------------------------------------------------------------
-- Application
--------------------------------------------------------------------------------

local app = wx.App()
app:SetAppName("kwxLuaJit Demo")

--------------------------------------------------------------------------------
-- Main Frame (480 x 320, centered)
--------------------------------------------------------------------------------

local frame = wx.Frame(nil, "kwxLuaJit Demo", -1, -1, 480, 320,
                       wx.DEFAULT_FRAME_STYLE)

--------------------------------------------------------------------------------
-- Menu Bar
--------------------------------------------------------------------------------

-- File menu
local file_menu = wxMenu.Create("", 0)
file_menu:Append(ID_NEW,     "&New",  "Create new")
file_menu:Append(ID_OPEN,    "&Open", "Open file")
file_menu:Append(ID_SAVE,    "&Save", "Save file")
file_menu:AppendSeparator()
file_menu:Append(wx.ID_EXIT, "E&xit", "Exit application")

-- Edit menu
local edit_menu = wxMenu.Create("", 0)
edit_menu:Append(ID_UNDO,  "&Undo")
edit_menu:Append(ID_REDO,  "&Redo")
edit_menu:AppendSeparator()
edit_menu:Append(ID_CUT,   "Cu&t")
edit_menu:Append(ID_COPY,  "&Copy")
edit_menu:Append(ID_PASTE, "&Paste")

-- Help menu
local help_menu = wxMenu.Create("", 0)
help_menu:Append(wx.ID_ABOUT, "&About", "About this demo")

-- Assemble menu bar
local menubar = wxMenuBar.Create(0)
menubar:Append(file_menu, "&File")
menubar:Append(edit_menu, "&Edit")
menubar:Append(help_menu, "&Help")
frame:SetMenuBar(menubar)

--------------------------------------------------------------------------------
-- Status Bar
--------------------------------------------------------------------------------

frame:CreateStatusBar()
frame:SetStatusText("Ready")

--------------------------------------------------------------------------------
-- Panel + Sizer Layout
--------------------------------------------------------------------------------

local panel = wx.Panel(frame)

-- Top-level vertical sizer
local vsizer = wx.BoxSizer(wx.VERTICAL)

-- Horizontal sizer: label + text control
local hsizer = wx.BoxSizer(wx.HORIZONTAL)

local label    = wx.StaticText(panel, "Text:")
local textctrl = wx.TextCtrl(panel, "")

-- Set placeholder / hint text (wxTextEntry mixin provides SetHint on wxTextCtrl)
textctrl:SetHint("hint text")

hsizer:Add(label,    0, wx.ALL + wx.ALIGN_CENTER_VERTICAL, 5)
hsizer:Add(textctrl, 1, wx.ALL + wx.EXPAND,                5)

-- Button
local button = wx.Button(panel, "Click Me")

-- Populate vertical sizer
vsizer:Add(hsizer, 0, wx.EXPAND + wx.ALL, 5)
vsizer:Add(button, 0, wx.ALL,             10)

panel:SetSizer(vsizer)

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------

-- "Click Me" button
button:Connect(wx.EVT_BUTTON, function()
    local text = textctrl:GetValue()
    if text == "" then
        wx.MessageBox("(no text entered)", "Demo",
                      wx.OK + wx.ICON_INFORMATION)
    else
        wx.MessageBox(text, "You typed",
                      wx.OK + wx.ICON_INFORMATION)
    end
end)

-- File > Exit
frame:Connect(wx.EVT_MENU, function()
    frame:Close(true)
end, wx.ID_EXIT)

-- Help > About
frame:Connect(wx.EVT_MENU, function()
    wx.MessageBox("kwxLuaJit Demo\nLuaJIT bindings for wxWidgets via kwxFFI",
                  "About Demo",
                  wx.OK + wx.ICON_INFORMATION)
end, wx.ID_ABOUT)

-- Window close (X button or programmatic)
frame:Connect(wx.EVT_CLOSE_WINDOW, function()
    app:ExitMainLoop()
end)

--------------------------------------------------------------------------------
-- Show and Run
--------------------------------------------------------------------------------

frame:Center()
app:SetTopWindow(frame)
frame:Show(true)

app:MainLoop()

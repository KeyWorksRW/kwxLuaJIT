--[[
    hello.lua - kwxLuaJit Hello World Demo

    This demo demonstrates the core features of kwxLuaJit:
    - Application lifecycle
    - Window creation with standard frame style (min, max, close buttons)
    - Panel, sizer, and control layout
    - Event handling with Lua callbacks
    - Message boxes
    - Status bar

    Usage:
        wxluajit examples/hello.lua
--]]

local wx = require("wx")

-- Create application (already initialized by C++ launcher)
local app = wx.App()

-- Create main frame with standard system buttons (minimize, maximize, close)
local frame = wx.Frame(nil, "kwxLuaJit Demo", -1, -1, 800, 600,
                       wx.DEFAULT_FRAME_STYLE)

-- Add a status bar
frame:CreateStatusBar()
frame:SetStatusText("Welcome to kwxLuaJit")

-- Create a panel to hold controls
local panel = wx.Panel(frame)

-- Create a vertical box sizer for layout
local sizer = wx.BoxSizer(wx.VERTICAL)

-- Create a label
local label = wx.StaticText(panel, "Welcome to kwxLuaJit!")

-- Create a button
local button = wx.Button(panel, "Click Me")

-- Connect button click event to a Lua function
button:Connect(wx.EVT_BUTTON, function()
    wx.MessageBox("Hello from Lua!", "kwxLuaJit")
end)

-- Add controls to sizer with spacing
sizer:Add(label, 0, wx.ALL, 10)
sizer:Add(button, 0, wx.ALL + wx.ALIGN_CENTER, 10)

-- Set the sizer on the panel
panel:SetSizer(sizer)

-- Show and center the frame
frame:Show(true)
frame:Center()

-- Enter the event loop
app:MainLoop()

--[[
    lua/wx/app.lua — Application class for wxLuaJit

    Provides the wx.App class for managing the application lifecycle.
    kwxApp functions are statically linked into the wxLuaJit executable;
    their ffi.cdef declarations are provided by lua/wx/init.lua.

    Usage:
        local app = wx.App()
        -- ... create windows ...
        app:MainLoop()
]]

local ffi = require("ffi")
local C = ffi.C

-- ============================================================================
-- App Class
-- ============================================================================

local App = {}
App.__index = App

-- Create a new wxApp wrapper
-- Note: The actual wxApp is created and managed by the C++ side (main.cpp).
-- This Lua object just provides access to the application methods.
function App.new()
    local self = setmetatable({}, App)
    return self
end

-- Run the main event loop
function App:MainLoop()
    return C.kwxApp_MainLoop()
end

-- Request to exit the main loop
function App:ExitMainLoop()
    C.kwxApp_ExitMainLoop()
end

-- Exit the application (alias for ExitMainLoop)
function App:Exit()
    C.kwxApp_ExitMainLoop()
end

-- Process pending events without blocking
-- @return boolean true if there are more events to process
function App:Yield()
    return C.kwxApp_Yield() ~= 0
end

-- Check if there are pending events
-- @return boolean
function App:Pending()
    return C.kwxApp_Pending() ~= 0
end

-- Process a single event
function App:Dispatch()
    C.kwxApp_Dispatch()
end

-- Get the application name
-- @return string|nil
function App:GetAppName()
    local cstr = C.kwxApp_GetAppName()
    if cstr == nil then return nil end
    return ffi.string(cstr)
end

-- Set the application name
-- @param name string
function App:SetAppName(name)
    C.kwxApp_SetAppName(name)
end

-- Get the top window
-- @return cdata void* pointer
function App:GetTopWindow()
    return C.kwxApp_GetTopWindow()
end

-- Set the top window
-- @param window table with _ptr field, or nil
function App:SetTopWindow(window)
    local ptr = window and window._ptr or nil
    C.kwxApp_SetTopWindow(ptr)
end

-- Initialize all image handlers (called automatically by wxLuaJit main.cpp)
function App:InitAllImageHandlers()
    C.kwxApp_InitAllImageHandlers()
end

-- Ring the system bell
function App:Bell()
    C.kwxApp_Bell()
end

-- Sleep for specified milliseconds
-- @param ms number
function App:MilliSleep(ms)
    C.kwxApp_MilliSleep(ms)
end

-- Sleep for specified seconds
-- @param seconds number
function App:Sleep(seconds)
    C.kwxApp_Sleep(seconds)
end

return App

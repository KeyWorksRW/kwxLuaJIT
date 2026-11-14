--[[
    lua/wx/init.lua — Main entry point for wxLuaJit

    Thin wrapper over kwxgen-generated modules providing:
    - Named constants (via runtime kwxFFI constant functions)
    - Lazy EVT_* event type resolution
    - Idiomatic Connect/Disconnect via the event callback bridge
    - Convenience constructors with sensible defaults

    Generated modules in wx/ provide the full wxWidgets class API.
    This file only adds Lua-friendly defaults and the event system.

    Usage:
        local wx = require("wx")

        local frame = wx.Frame(nil, "My App")
        frame:Show()
]]

local ffi = require("ffi")

-- Bootstrap: load all kwxgen-generated FFI declarations and the kwxFFI DLL.
-- This loads kwxffi_events_gen, kwxffi_keys_gen, kwxffi_constants_gen,
-- kwxffi_classes_gen, and kwxffi_freefuncs_gen via their ffi.cdef blocks,
-- then returns the library handle from ffi.load("kwxFFI").
require("kwxffi_gen")

-- kwxApp functions are statically linked into the wxLuaJit executable.
-- kwxgen does not generate bindings for these — declare them here.
ffi.cdef[[
    int   kwxApp_MainLoop(void);
    void  kwxApp_ExitMainLoop(void);
    int   kwxApp_IsTerminating(void);

    const char* kwxApp_GetAppName(void);
    void  kwxApp_SetAppName(const char* name);
    const char* kwxApp_GetVendorName(void);
    void  kwxApp_SetVendorName(const char* name);

    void* kwxApp_GetTopWindow(void);
    void  kwxApp_SetTopWindow(void* window);
    void  kwxApp_SetExitOnFrameDelete(int flag);
    int   kwxApp_GetExitOnFrameDelete(void);

    void  kwxApp_GetDisplaySize(int* width, int* height);
    void  kwxApp_GetMousePosition(int* x, int* y);
    void  kwxApp_GetOsVersion(int* major, int* minor, int* micro);
    const char* kwxApp_GetOsDescription(void);
    const char* kwxApp_GetUserId(void);
    const char* kwxApp_GetUserName(void);

    int   kwxApp_Pending(void);
    void  kwxApp_Dispatch(void);
    int   kwxApp_Yield(void);
    int   kwxApp_SafeYield(void* window, int onlyIfNeeded);

    void  kwxApp_InitAllImageHandlers(void);
    void  kwxApp_EnableTooltips(int flag);
    void  kwxApp_SetTooltipDelay(long msec);
    void  kwxApp_Bell(void);
    void  kwxApp_Sleep(int secs);
    void  kwxApp_MilliSleep(unsigned long ms);

    void* kwxApp_FindWindowById(long id, void* parent);
    void* kwxApp_FindWindowByLabel(const char* label, void* parent);
    void* kwxApp_FindWindowByName(const char* name, void* parent);
    void  kwxApp_FreeString(const char* str);
]]

-- Default C namespace — includes exe symbols + all loaded DLLs (Windows).
-- kwxFFI DLL symbols are available here after kwxffi_gen loads the DLL.
local C = ffi.C

-- Generated helpers: wxs(), wxs_free(), wxs_to_str(), ptr(), to_bool(), from_bool()
local _H = require("kwxffi_helpers_gen")

-- Generated symbol tables.
--
-- kwxgen appends a lazy lookup table to kwxffi_{events,keys,constants}_gen:
-- each name maps to the export that backs it, the export is called on first
-- use and the value is cached in the table.  Nothing is resolved at require
-- time, so an unknown name simply returns nil.
--
--     event     wxEVT_MENU           -> events_gen.EVT_MENU
--     key       K_BACK               -> keys_gen.K_BACK
--     constant  STB_DEFAULT_STYLE    -> constants_gen.STB_DEFAULT_STYLE
--               RIBBON_BAR_DEFAULT_STYLE -> constants_gen.RIBBON_BAR_DEFAULT_STYLE
--
-- Constants whose accessor returns an owned wxString* (the wxART_* art ids and
-- a few default strings) are converted to Lua strings by the generated module,
-- which also releases the wxString, so no raw pointer reaches the `wx` namespace.
local constants_gen = require("kwxffi_constants_gen")
local events_gen    = require("kwxffi_events_gen")
local keys_gen      = require("kwxffi_keys_gen")

--------------------------------------------------------------------------------
-- Event System
--------------------------------------------------------------------------------

local events = require("wx.events")

-- Inject idiomatic event methods into the generated wxEvtHandler prototype.
-- All subclasses (Window, Frame, Button, ...) inherit them automatically
-- via metatable chaining.
local wxEvtHandler = require("wxevthandler_gen")

-- Override the generated raw Connect/Disconnect with idiomatic versions.
-- The raw C-level Connect(first, last, type, closure) is not useful from Lua;
-- users always go through the events module callback bridge.
function wxEvtHandler:Connect(event_type, handler, id)
    return events.connect(self._ptr, event_type, handler, id)
end

function wxEvtHandler:Disconnect(cb_id)
    return events.disconnect(cb_id)
end

function wxEvtHandler:DisconnectAll()
    events.disconnect_all(self._ptr)
end

-- Modern wxWidgets naming aliases
wxEvtHandler.Bind = wxEvtHandler.Connect
wxEvtHandler.Unbind = wxEvtHandler.Disconnect
wxEvtHandler.UnbindAll = wxEvtHandler.DisconnectAll

--------------------------------------------------------------------------------
-- wxWindow overrides — Lua-friendly defaults for commonly-used methods
--------------------------------------------------------------------------------

local wxWindow = require("wxwindow_gen")

-- Center: default direction = wxBOTH
local _raw_Center = wxWindow.Center
function wxWindow:Center(direction)
    return _raw_Center(self, direction or C.expwxBOTH())
end
wxWindow.Centre = wxWindow.Center

-- Show: support optional bool argument (wxWidgets Show(bool) idiom)
local _raw_Show = wxWindow.Show
function wxWindow:Show(show)
    if show == false then
        return self:Hide()
    end
    return _raw_Show(self)
end

-- Close: default force = false
local _raw_Close = wxWindow.Close
function wxWindow:Close(force)
    return _raw_Close(self, force or false)
end

-- Refresh: default eraseBackground = true
local _raw_Refresh = wxWindow.Refresh
function wxWindow:Refresh(eraseBackground)
    if eraseBackground == nil then eraseBackground = true end
    return _raw_Refresh(self, eraseBackground)
end

-- SetSizer: default deleteOld = true
local _raw_SetSizer = wxWindow.SetSizer
function wxWindow:SetSizer(sizer, deleteOld)
    if deleteOld == nil then deleteOld = true end
    return _raw_SetSizer(self, sizer, deleteOld)
end

--------------------------------------------------------------------------------
-- wxTopLevelWindow overrides
--------------------------------------------------------------------------------

local wxTopLevelWindow = require("wxtoplevelwindow_gen")

-- Maximize: default maximize = true
local _raw_Maximize = wxTopLevelWindow.Maximize
function wxTopLevelWindow:Maximize(maximize)
    if maximize == nil then maximize = true end
    return _raw_Maximize(self, maximize)
end

-- Iconize: default iconize = true
local _raw_Iconize = wxTopLevelWindow.Iconize
function wxTopLevelWindow:Iconize(iconize)
    if iconize == nil then iconize = true end
    return _raw_Iconize(self, iconize)
end

--------------------------------------------------------------------------------
-- wxFrame overrides
--------------------------------------------------------------------------------

local wxFrame_gen = require("wxframe_gen")

-- CreateStatusBar: default number=1, style=0
-- wxFrame_CreateStatusBar(pObject, number, style, id) takes a trailing id;
-- the override must forward it (wxID_ANY when omitted).
local _raw_CreateStatusBar = wxFrame_gen.CreateStatusBar
function wxFrame_gen:CreateStatusBar(number, style, id)
    return _raw_CreateStatusBar(self, number or 1, style or 0, id or -1)
end

-- SetStatusText: default field=0
local _raw_SetStatusText = wxFrame_gen.SetStatusText
function wxFrame_gen:SetStatusText(text, field)
    return _raw_SetStatusText(self, text or "", field or 0)
end

-- CreateToolBar: default style=0
-- wxFrame_CreateToolBar(pObject, style, id) takes a trailing id; forward it.
local _raw_CreateToolBar = wxFrame_gen.CreateToolBar
function wxFrame_gen:CreateToolBar(style, id)
    return _raw_CreateToolBar(self, style or 0, id or -1)
end

--------------------------------------------------------------------------------
-- wxSizer overrides — polymorphic Add() matching wxWidgets C++ overloads
--------------------------------------------------------------------------------

local wxSizer = require("wxsizer_gen")

local _raw_Add       = wxSizer.Add
local _raw_AddWindow = wxSizer.AddWindow
local _raw_AddSizer  = wxSizer.AddSizer

-- Dispatch Add based on first argument type:
--   table with _ptr → AddWindow or AddSizer (duck-type via GetOrientation)
--   number           → Add(width, height, proportion, flag, border, userData)
function wxSizer:Add(arg1, proportion, flag, border, userData)
    if type(arg1) == "table" and arg1._ptr then
        if arg1.GetOrientation then  -- sizer (has orientation)
            return _raw_AddSizer(self, arg1, proportion or 0, flag or 0, border or 0, userData)
        else
            return _raw_AddWindow(self, arg1, proportion or 0, flag or 0, border or 0, userData)
        end
    else
        -- Numeric: Add(width, height, proportion, flag, border, userData)
        return _raw_Add(self, arg1, proportion, flag, border, userData)
    end
end

--------------------------------------------------------------------------------
-- Import remaining generated modules for convenience constructors
--------------------------------------------------------------------------------

local wxPanel_gen      = require("wxpanel_gen")
local wxButton_gen     = require("wxbutton_gen")
local wxStaticText_gen = require("wxstatictext_gen")
local wxTextCtrl_gen   = require("wxtextctrl_gen")
local wxBoxSizer_gen   = require("wxboxsizer_gen")

--------------------------------------------------------------------------------
-- The wx namespace
--------------------------------------------------------------------------------

local wx = {}

--------------------------------------------------------------------------------
-- String Helpers (delegating to generated helpers)
--------------------------------------------------------------------------------

function wx.wxString(str) return _H.wxs(str or "") end
wx.wxStringDelete = _H.wxs_free
wx.toLuaString = _H.wxs_to_str

--------------------------------------------------------------------------------
-- Constants — fetched at runtime from kwxFFI to stay in sync with wxWidgets.
-- Each call names the historical export symbol ("expwxOK"); C_const strips the
-- prefix and resolves it through the constant resolver above. When kwxFFI has
-- no such export the hardcoded fallback is used.
--------------------------------------------------------------------------------

local function C_const(name, fallback)
    -- `name` is the historical export symbol name, e.g. "expwxOK" or
    -- "expwxSTB_DEFAULT_STYLE"; strip the export prefix to get the bare
    -- wxWidgets name used by the generated constant table.
    local key = name:match("^expwx(.*)$") or name:match("^exp_(.*)$") or name:match("^exp(.*)$") or name
    local val = constants_gen[key]
    if val == nil then return fallback end
    return val
end

-- Window IDs
wx.ID_ANY       = C_const("expwxID_ANY", -1)
wx.ID_NONE      = C_const("expwxID_NONE", -3)
wx.ID_SEPARATOR = C_const("expwxID_SEPARATOR", -2)
wx.ID_OK        = C_const("expwxID_OK", 5100)
wx.ID_CANCEL    = C_const("expwxID_CANCEL", 5101)
wx.ID_APPLY     = C_const("expwxID_APPLY", 5102)
wx.ID_YES       = C_const("expwxID_YES", 5103)
wx.ID_NO        = C_const("expwxID_NO", 5104)
wx.ID_CLOSE     = C_const("expwxID_CLOSE", 5105)
wx.ID_EXIT      = C_const("expwxID_EXIT", 5106)
wx.ID_HELP      = C_const("expwxID_HELP", 5107)
wx.ID_ABOUT     = C_const("expwxID_ABOUT", 5014)

-- Default position / size sentinel
wx.DEFAULT_POSITION = -1
wx.DEFAULT_SIZE     = -1

-- Orientation
wx.HORIZONTAL = C_const("expwxHORIZONTAL", 0x0004)
wx.VERTICAL   = C_const("expwxVERTICAL",   0x0008)
wx.BOTH       = C_const("expwxBOTH",       0x000C)

-- Direction / Sizer flags
wx.TOP    = C_const("expwxTOP",    0x0040)
wx.BOTTOM = C_const("expwxBOTTOM", 0x0080)
wx.LEFT   = C_const("expwxLEFT",   0x0010)
wx.RIGHT  = C_const("expwxRIGHT",  0x0020)
wx.ALL    = C_const("expwxALL",    0x00F0)

wx.EXPAND                       = C_const("expwxEXPAND",       0x2000)
wx.SHAPED                       = C_const("expwxSHAPED",       0x4000)
wx.FIXED_MINSIZE                = C_const("expwxFIXED_MINSIZE", 0x8000)
wx.RESERVE_SPACE_EVEN_IF_HIDDEN = C_const("expwxRESERVE_SPACE_EVEN_IF_HIDDEN", 0x0002)

-- Alignment
wx.ALIGN_CENTER            = C_const("expwxALIGN_CENTER",            0x0900)
wx.ALIGN_CENTRE            = wx.ALIGN_CENTER
wx.ALIGN_LEFT              = C_const("expwxALIGN_LEFT",              0x0000)
wx.ALIGN_TOP               = C_const("expwxALIGN_TOP",               0x0000)
wx.ALIGN_RIGHT             = C_const("expwxALIGN_RIGHT",             0x0200)
wx.ALIGN_BOTTOM            = C_const("expwxALIGN_BOTTOM",            0x0400)
wx.ALIGN_CENTER_VERTICAL   = C_const("expwxALIGN_CENTER_VERTICAL",   0x0800)
wx.ALIGN_CENTRE_VERTICAL   = wx.ALIGN_CENTER_VERTICAL
wx.ALIGN_CENTER_HORIZONTAL = C_const("expwxALIGN_CENTER_HORIZONTAL", 0x0100)
wx.ALIGN_CENTRE_HORIZONTAL = wx.ALIGN_CENTER_HORIZONTAL

-- Frame styles
wx.DEFAULT_FRAME_STYLE   = C_const("expwxDEFAULT_FRAME_STYLE",   0x20C20420)
wx.MINIMIZE_BOX          = C_const("expwxMINIMIZE_BOX",           0x0400)
wx.MAXIMIZE_BOX          = C_const("expwxMAXIMIZE_BOX",           0x0200)
wx.RESIZE_BORDER         = C_const("expwxRESIZE_BORDER",          0x0040)
wx.SYSTEM_MENU           = C_const("expwxSYSTEM_MENU",            0x0800)
wx.CAPTION               = C_const("expwxCAPTION",                0x20000000)
wx.CLOSE_BOX             = C_const("expwxCLOSE_BOX",              0x1000)
wx.CLIP_CHILDREN         = C_const("expwxCLIP_CHILDREN",          0x00400000)
wx.STAY_ON_TOP           = C_const("expwxSTAY_ON_TOP",            0x0008)
wx.FRAME_TOOL_WINDOW     = C_const("expwxFRAME_TOOL_WINDOW",      0x0004)
wx.FRAME_NO_TASKBAR      = C_const("expwxFRAME_NO_TASKBAR",       0x0002)
wx.FRAME_FLOAT_ON_PARENT = C_const("expwxFRAME_FLOAT_ON_PARENT",  0x0008)

-- Dialog styles (computed from runtime constants)
wx.DEFAULT_DIALOG_STYLE  = wx.CAPTION + wx.SYSTEM_MENU + wx.CLOSE_BOX

-- Button styles
wx.BU_LEFT     = C_const("expwxBU_LEFT",     0x0040)
wx.BU_TOP      = C_const("expwxBU_TOP",      0x0080)
wx.BU_RIGHT    = C_const("expwxBU_RIGHT",    0x0100)
wx.BU_BOTTOM   = C_const("expwxBU_BOTTOM",   0x0200)
wx.BU_EXACTFIT = C_const("expwxBU_EXACTFIT", 0x0001)

-- Text control styles
wx.TE_MULTILINE  = C_const("expwxTE_MULTILINE",  0x0020)
wx.TE_READONLY   = C_const("expwxTE_READONLY",   0x0010)
wx.TE_RICH       = C_const("expwxTE_RICH",       0x0080)
wx.TE_RICH2      = C_const("expwxTE_RICH2",      0x8000)
wx.TE_PASSWORD   = C_const("expwxTE_PASSWORD",   0x0800)
wx.TE_LEFT       = C_const("expwxTE_LEFT",       0x0000)
wx.TE_CENTRE     = C_const("expwxTE_CENTRE",     0x0100)
wx.TE_CENTER     = wx.TE_CENTRE  -- American spelling alias
wx.TE_RIGHT      = C_const("expwxTE_RIGHT",      0x0200)
wx.TE_WORDWRAP   = C_const("expwxTE_WORDWRAP",   0x0001)
wx.TE_NO_VSCROLL = C_const("expwxTE_NO_VSCROLL", 0x0002)

-- Panel / Border styles
wx.TAB_TRAVERSAL  = C_const("expwxTAB_TRAVERSAL",  0x00080000)
wx.BORDER_NONE    = C_const("expwxBORDER_NONE",    0x00200000)
wx.BORDER_STATIC  = C_const("expwxBORDER_STATIC",  0x01000000)
wx.BORDER_SIMPLE  = C_const("expwxBORDER_SIMPLE",  0x02000000)
wx.BORDER_RAISED  = C_const("expwxBORDER_RAISED",  0x04000000)
wx.BORDER_SUNKEN  = C_const("expwxBORDER_SUNKEN",  0x08000000)
wx.BORDER_DOUBLE  = C_const("expwxBORDER_DOUBLE",  0x10000000)
wx.BORDER_DEFAULT = C_const("expwxBORDER_DEFAULT",  0x00000000)

-- Message box styles
wx.OK               = C_const("expwxOK",               0x00000004)
wx.CANCEL           = C_const("expwxCANCEL",           0x00000010)
wx.YES              = C_const("expwxYES",              0x00000002)
wx.NO               = C_const("expwxNO",               0x00000008)
wx.YES_NO           = C_const("expwxYES_NO",           0x0000000A)
wx.HELP             = C_const("expwxHELP",             0x00008000)
wx.NO_DEFAULT       = C_const("expwxNO_DEFAULT",       0x00000080)
wx.CANCEL_DEFAULT   = C_const("expwxCANCEL_DEFAULT",   0x80000000)
wx.YES_DEFAULT      = C_const("expwxYES_DEFAULT",      0x00000000)
wx.ICON_ERROR       = C_const("expwxICON_ERROR",       0x00000200)
wx.ICON_QUESTION    = C_const("expwxICON_QUESTION",    0x00000400)
wx.ICON_INFORMATION = C_const("expwxICON_INFORMATION",  0x00000800)
wx.ICON_WARNING     = C_const("expwxICON_WARNING",      0x00000100)
-- wxWidgets alias names; kwxFFI exports neither, so derive them from the
-- constants that do resolve rather than freezing numeric literals here.
wx.ICON_EXCLAMATION = wx.ICON_WARNING
wx.ICON_HAND        = wx.ICON_ERROR

-- Center flags
wx.CENTRE           = C_const("expwxCENTRE",           0x0001)
wx.CENTER           = wx.CENTRE
wx.CENTRE_ON_SCREEN = C_const("expwxCENTRE_ON_SCREEN", 0x0001)
wx.CENTER_ON_SCREEN = wx.CENTRE_ON_SCREEN

--------------------------------------------------------------------------------
-- Event types, key codes and remaining wxWidgets constants — resolved lazily
-- through the __index metamethod and cached in the wx table.
--   wx.EVT_BUTTON          -> events_gen.EVT_BUTTON
--   wx.K_BACK              -> keys_gen.K_BACK
--   wx.STB_DEFAULT_STYLE   -> constants_gen.STB_DEFAULT_STYLE
--   wx.ART_MISSING_IMAGE   -> constants_gen.ART_MISSING_IMAGE (a Lua string)
-- Unknown names resolve to nil (not 0), so a typo fails loudly instead of
-- silently turning into wxEVT_NULL.
--------------------------------------------------------------------------------

setmetatable(wx, {
    __index = function(t, k)
        local val
        if k:sub(1, 4) == "EVT_" then
            val = events_gen[k]
        elseif k:sub(1, 2) == "K_" then
            val = keys_gen[k]
        else
            val = constants_gen[k]
        end
        if val ~= nil then rawset(t, k, val) end
        return val
    end
})

--------------------------------------------------------------------------------
-- App Class (delegated to separate module for customization)
--------------------------------------------------------------------------------

local App = require("wx.app")

function wx.App()
    return App.new()
end

--------------------------------------------------------------------------------
-- Convenience Constructors
-- Provide sensible defaults, delegate to generated Create methods.
-- Returned objects have full generated method chains via metatable inheritance.
-- (wxFrame → wxTopLevelWindow → wxWindow → wxEvtHandler)
--------------------------------------------------------------------------------

function wx.Frame(parent, title, x, y, w, h, style)
    local frame = wxFrame_gen.Create(
        parent, wx.ID_ANY, title or "wxLuaJit",
        x or -1, y or -1, w or 800, h or 600,
        style or wx.DEFAULT_FRAME_STYLE
    )
    if not frame then error("Failed to create wxFrame") end
    return frame
end

function wx.Panel(parent, x, y, w, h, style)
    local panel = wxPanel_gen.Create(
        parent, wx.ID_ANY,
        x or -1, y or -1, w or -1, h or -1,
        style or wx.TAB_TRAVERSAL
    )
    if not panel then error("Failed to create wxPanel") end
    return panel
end

function wx.Button(parent, label, x, y, w, h, style)
    local btn = wxButton_gen.Create(
        parent, wx.ID_ANY, label or "",
        x or -1, y or -1, w or -1, h or -1,
        style or 0
    )
    if not btn then error("Failed to create wxButton") end
    return btn
end

function wx.StaticText(parent, label, x, y, w, h, style)
    local st = wxStaticText_gen.Create(
        parent, wx.ID_ANY, label or "",
        x or -1, y or -1, w or -1, h or -1,
        style or 0
    )
    if not st then error("Failed to create wxStaticText") end
    return st
end

function wx.TextCtrl(parent, value, x, y, w, h, style)
    local tc = wxTextCtrl_gen.Create(
        parent, wx.ID_ANY, value or "",
        x or -1, y or -1, w or -1, h or -1,
        style or 0
    )
    if not tc then error("Failed to create wxTextCtrl") end
    return tc
end

function wx.BoxSizer(orient)
    local sizer = wxBoxSizer_gen.Create(orient or wx.HORIZONTAL)
    if not sizer then error("Failed to create wxBoxSizer") end
    return sizer
end

--------------------------------------------------------------------------------
-- MessageBox convenience function
--------------------------------------------------------------------------------

function wx.MessageBox(message, caption, style, parent)
    local msg_ws = _H.wxs(message)
    local cap_ws = _H.wxs(caption or "Message")
    local result = C.kwxMessageBox(msg_ws, cap_ws, style or wx.OK, _H.ptr(parent), -1, -1)
    _H.wxs_free(msg_ws)
    _H.wxs_free(cap_ws)
    return result
end

--------------------------------------------------------------------------------
-- Expose sub-modules for advanced use
--------------------------------------------------------------------------------

wx.events = events

return wx

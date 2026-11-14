--[[
    splash.lua — LuaJIT port of wxWidgets samples/splash/splash.cpp

    Source: C:/rwCode/wxSamples/src/splash/splash.cpp
    Output: samples/splash/splash.lua

    Reproduces:
      - MyApp::OnInit                 -> wx.App() + PNG handler + frame
      - MyFrame::MyFrame(title)       -> wxFrame(NULL, wxID_ANY, title),
                                         m_isPda, SetIcon(wxICON(sample)),
                                         File/Help menu bar, 2-pane status bar
      - MyFrame::OnQuit               -> Close(true)

    NOT implemented — blocked on unbound wxWidgets constants:
      wxSplashScreen_Create() requires a splashStyle argument built from
      wxSPLASH_CENTRE_ON_SCREEN / wxSPLASH_CENTRE_ON_PARENT /
      wxSPLASH_TIMEOUT / wxSPLASH_NO_TIMEOUT. None of those four names is
      bound: kwxFFI exports no expwxSPLASH_* symbol, wx/kwxffi_constants_gen.lua
      has no entry for them, and `wx.SPLASH_*` is nil at runtime. They therefore
      cannot be passed without inventing symbols, so the two splash-screen
      creations (and everything that only exists to serve them) are left out:

        MyApp::OnInit          -> bitmap load, DecorateSplashScreen(), wxYield(),
                                  new wxSplashScreen(... wxSPLASH_CENTRE_ON_SCREEN
                                  |wxSPLASH_TIMEOUT, 6000, ...)
        MyApp::DecorateSplashScreen() -> the orange banner drawn onto the bitmap
        MyFrame::OnAbout       -> half-size bitmap, new wxSplashScreen(... 
                                  wxSPLASH_CENTRE_ON_PARENT|wxSPLASH_NO_TIMEOUT, 0,
                                  ...) and the wxMediaCtrl placed in it

      Everything those paths need *is* bound (wxMemoryDC, wxDC drawing, wxFont,
      wxMediaCtrl, wxSplashScreen itself); only the four style constants are
      missing. See the port report.

    Generated modules used because the `wx` wrapper has no equivalent:
      wxmenu_gen / wxmenubar_gen  menu construction
      wximage_gen                 wxImage::AddHandler (static)
      wxpnghandler_gen            wxPNGHandler for bitmap.LoadFile(..., PNG)
      wxbitmapbundle_gen          wxBitmapBundle::FromSVGFile (static)
      wxbitmap_gen                wxBitmapBundle::GetBitmap result
      wxicon_gen                  frame icon
      wxsystemsettings_gen        wxSystemSettings::GetScreenType (static)
]]

local wx = require("wx")

local wxmenu_gen           = require("wxmenu_gen")
local wxmenubar_gen        = require("wxmenubar_gen")
local wximage_gen          = require("wximage_gen")
local wxpngHandler_gen     = require("wxpnghandler_gen")
local wxbitmapbundle_gen   = require("wxbitmapbundle_gen")
local wxbitmap_gen         = require("wxbitmap_gen")
local wxicon_gen           = require("wxicon_gen")
local wxsystemsettings_gen = require("wxsystemsettings_gen")

-- The C++ launcher owns wxApp initialisation; this is MyApp::OnInit.
local app = wx.App()

-- ---------------------------------------------------------------------------
-- MyApp::OnInit: wxImage::AddHandler(new wxPNGHandler);
-- @see wxBitmap::LoadFile("splash.png", wxBITMAP_TYPE_PNG)
-- ---------------------------------------------------------------------------
wximage_gen.AddHandler(wxpngHandler_gen.Create())

-- ---------------------------------------------------------------------------
-- MyFrame::MyFrame("wxSplashScreen sample application")
--     : wxFrame(nullptr, wxID_ANY, title)   (default position/size/style)
-- ---------------------------------------------------------------------------
local frame = wx.Frame(nil, "wxSplashScreen sample application",
                       wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
                       wx.DEFAULT_SIZE, wx.DEFAULT_SIZE,
                       wx.DEFAULT_FRAME_STYLE)

-- bool MyFrame::m_isPda =
--     (wxSystemSettings::GetScreenType() <= wxSYS_SCREEN_PDA);
-- Consumed only by the two blocked splash-screen paths (on this desktop it is
-- false: GetScreenType() returns wxSYS_SCREEN_DESKTOP > wxSYS_SCREEN_PDA).
local m_isPda = (wxsystemsettings_gen.GetScreenType() <= wx.SYS_SCREEN_PDA)

-- ---------------------------------------------------------------------------
-- Asset helpers. sample.svg / mobile.svg live beside this script; the C++
-- sample loads splash.png and press.mpg relative to the working directory,
-- so those stay resolved the same way.
-- ---------------------------------------------------------------------------
local function script_directory()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    local dir = src:match("^(.*)[/\\][^/\\]*$")
    return dir or ""
end

local SCRIPT_DIR = script_directory()

local function asset_path(name)
    if SCRIPT_DIR == "" then return name end
    return SCRIPT_DIR .. "/" .. name
end

-- ---------------------------------------------------------------------------
-- SetIcon(wxICON(sample))
--
-- The C++ sample uses the resource icon on MSW and ../sample.xpm elsewhere; the
-- artwork is shipped here as sample.svg, converted pixel-for-pixel from
-- C:/rwCode/wxSamples/src/sample.xpm (32x32).
-- ---------------------------------------------------------------------------
local frame_icon  -- kept reachable for the whole run

local function apply_frame_icon(win)
    local bundle = wxbitmapbundle_gen.FromPtr(
        wxbitmapbundle_gen.FromSVGFile(asset_path("sample.svg"), 32, 32), true)
    if bundle == nil then return end   -- asset absent: keep the default icon

    -- wxBitmapBundle_GetBitmap() returns a newly allocated wxBitmap.
    local bitmap = wxbitmap_gen.FromPtr(bundle:GetBitmap(32, 32), true)
    if bitmap ~= nil then
        frame_icon = wxicon_gen.CreateDefault()
        if frame_icon ~= nil then
            frame_icon:CopyFromBitmap(bitmap)
            win:SetIcon(frame_icon)
        end
        bitmap:Delete()
    end
    bundle:Delete()
end

apply_frame_icon(frame)

-- ---------------------------------------------------------------------------
-- Menu bar: File -> E&xit\tAlt-X, Help -> &About\tF1 (same order, labels,
-- accelerators and help strings as splash.cpp)
-- ---------------------------------------------------------------------------
local fileMenu = wxmenu_gen.Create("", 0)
local helpMenu = wxmenu_gen.Create("", 0)

-- helpMenu->Append(wxID_ABOUT, "&About\tF1", "Show about frame");
helpMenu:Append(wx.ID_ABOUT, "&About\tF1", "Show about frame", false)

-- menuFile->Append(wxID_EXIT, "E&xit\tAlt-X", "Quit this program");
fileMenu:Append(wx.ID_EXIT, "E&xit\tAlt-X", "Quit this program", false)

local menuBar = wxmenubar_gen.Create(0)
menuBar:Append(fileMenu, "&File")
menuBar:Append(helpMenu, "&Help")
frame:SetMenuBar(menuBar)

-- ---------------------------------------------------------------------------
-- CreateStatusBar(2); SetStatusText("Welcome to wxWidgets!");
-- ---------------------------------------------------------------------------
frame:CreateStatusBar(2, wx.STB_DEFAULT_STYLE)
frame:SetStatusText("Welcome to wxWidgets!")

-- ---------------------------------------------------------------------------
-- OnInit: the splash screen would be created here, then wxYield(), then
-- frame->Show(true). The splash screen itself is blocked (see the file
-- header), so the frame is simply shown.
-- ---------------------------------------------------------------------------
frame:Show(true)

-- ---------------------------------------------------------------------------
-- Event handlers (wxBEGIN_EVENT_TABLE entries)
-- ---------------------------------------------------------------------------

-- void MyFrame::OnQuit(wxCommandEvent&) { Close(true); }
frame:Connect(wx.EVT_MENU, function(evt)
    if not evt then return end
    frame:Close(true)
end, wx.ID_EXIT)

-- void MyFrame::OnAbout(wxCommandEvent&)
--
-- The whole body builds a wxSplashScreen (wxSPLASH_CENTRE_ON_PARENT |
-- wxSPLASH_NO_TIMEOUT) and puts a wxMediaCtrl("press.mpg") inside it, so it is
-- blocked on the same four unbound constants. The connection is kept so the
-- menu item and event wiring match the C++ event table.
frame:Connect(wx.EVT_MENU, function(evt)
    if not evt then return end
    -- BLOCKED: wxSPLASH_CENTRE_ON_PARENT / wxSPLASH_NO_TIMEOUT are not bound.
end, wx.ID_ABOUT)

app:MainLoop()

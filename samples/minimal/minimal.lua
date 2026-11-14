--[[
    minimal.lua — LuaJIT port of wxWidgets samples/minimal/minimal.cpp

    Source: C:/rwCode/wxSamples/src/minimal/minimal.cpp

    Reproduces:
      - MyApp::OnInit          -> wx.App() + frame construction + MainLoop
      - MyFrame(title)         -> wx.Frame(nullptr, wxID_ANY, title) with
                                  wxDefaultPosition / wxDefaultSize
      - SetIcon(wxICON(sample))-> sample.svg (converted from ../sample.xpm)
      - File > E&xit\tAlt-X    -> Close(true)
      - Help > &About\tF1      -> information message box
      - CreateStatusBar(2)     -> two panes, pane 0 = "Welcome to wxWidgets!"

    Generated modules used because the `wx` wrapper has no equivalent:
      - wxmenu_gen / wxmenubar_gen : menu construction (the wrapper has no
        wx.Menu / wx.MenuBar convenience constructors)
      - wxbitmapbundle_gen        : wxBitmapBundle::FromSVGFile, a static
        factory, returns an owned bundle wrapper; GetIcon() returns an owned
        wxIcon wrapper
      - kwxffi_freefuncs_idiomatic_gen : wxVersionString() and
        wxGetOsDescription(), needed for the C++ wxString::Format text.
]]

local wx = require("wx")

local wxmenu_gen          = require("wxmenu_gen")
local wxmenubar_gen       = require("wxmenubar_gen")
local wxbitmapbundle_gen  = require("wxbitmapbundle_gen")
local F                   = require("kwxffi_freefuncs_idiomatic_gen")

-- The C++ launcher owns wxApp initialisation; this is MyApp::OnInit.
local app = wx.App()

-- IDs for the controls and the menu commands (minimal.cpp enum).
--   Minimal_Quit  = wxID_EXIT
--   Minimal_About = wxID_ABOUT
local Minimal_Quit  = wx.ID_EXIT
local Minimal_About = wx.ID_ABOUT

-- MyFrame::MyFrame(title) : wxFrame(nullptr, wxID_ANY, title)
-- The C++ constructor uses the default position and size, so pass the
-- wxWidgets sentinels rather than the wrapper's 800x600 default.
local frame = wx.Frame(nil, "Minimal wxWidgets App",
                       wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
                       wx.DEFAULT_SIZE, wx.DEFAULT_SIZE,
                       wx.DEFAULT_FRAME_STYLE)

-- ---------------------------------------------------------------------------
-- Frame icon: SetIcon(wxICON(sample))
--
-- The C++ sample includes ../sample.xpm when the platform has no images in
-- resources. The 32x32 artwork is shipped here as sample.svg, converted
-- pixel-for-pixel from that XPM.
--
-- wxBitmapBundle::FromSVGFile is a static factory; the generated module calls
-- it without a receiver and returns an owned wrapper. GetIcon() and GetBitmap()
-- also return owned wrappers in this binding generation.
-- ---------------------------------------------------------------------------

local function script_directory()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    local dir = src:match("^(.*)[/\\][^/\\]*$")
    return dir or ""
end

local frame_icon  -- kept reachable for the whole run

local function apply_frame_icon(win)
    local dir = script_directory()
    local path = (dir ~= "" and (dir .. "/") or "") .. "sample.svg"

    local bundle = wxbitmapbundle_gen.FromSVGFile(path, 32, 32)
    if bundle == nil then return end        -- asset absent: keep default icon

    local icon = bundle:GetIcon(32, 32)
    bundle:Delete()                         -- owned by this script
    if icon == nil then return end

    frame_icon = icon
    win:SetIcon(icon)                       -- SetIcon copies the icon
    icon:Delete()                           -- owned by this script
end

apply_frame_icon(frame)

-- ---------------------------------------------------------------------------
-- Menu bar (same order, labels, accelerators and help strings as minimal.cpp)
-- ---------------------------------------------------------------------------

local fileMenu = wxmenu_gen.Create("", 0)
local helpMenu = wxmenu_gen.Create("", 0)

-- helpMenu->Append(Minimal_About, "&About\tF1", "Show about dialog");
helpMenu:Append(Minimal_About, "&About\tF1", "Show about dialog", false)

-- fileMenu->Append(Minimal_Quit, "E&xit\tAlt-X", "Quit this program");
fileMenu:Append(Minimal_Quit, "E&xit\tAlt-X", "Quit this program", false)

local menuBar = wxmenubar_gen.Create(0)
menuBar:Append(fileMenu, "&File")
menuBar:Append(helpMenu, "&Help")
frame:SetMenuBar(menuBar)

-- ---------------------------------------------------------------------------
-- Status bar: CreateStatusBar(2); SetStatusText("Welcome to wxWidgets!");
--
-- wxFrame::CreateStatusBar(number, style = wxSTB_DEFAULT_STYLE, id = wxID_ANY)
-- now forwards the trailing id, so the wrapper call matches the C++ defaults.
-- ---------------------------------------------------------------------------

frame:CreateStatusBar(2, wx.STB_DEFAULT_STYLE)
frame:SetStatusText("Welcome to wxWidgets!")

-- ---------------------------------------------------------------------------
-- Event handlers (wxBEGIN_EVENT_TABLE entries)
-- ---------------------------------------------------------------------------

-- void MyFrame::OnQuit(wxCommandEvent&) { Close(true); }
frame:Connect(wx.EVT_MENU, function(evt)
    if not evt then return end
    frame:Close(true)
end, Minimal_Quit)

-- void MyFrame::OnAbout(wxCommandEvent&)
-- wxMessageBox(wxString::Format("Welcome to %s!\n\nThis is the minimal
--   wxWidgets sample\nrunning under %s.", wxVERSION_STRING,
--   wxGetOsDescription()), "About wxWidgets minimal sample",
--   wxOK | wxICON_INFORMATION, this);
frame:Connect(wx.EVT_MENU, function(evt)
    if not evt then return end

    -- wxVersionString() / wxGetOsDescription() each return a newly allocated
    -- wxString*; wx.toLuaString converts it and frees it.
    local version = F.wxVersionString()
    local osdesc  = F.wxGetOsDescription()

    local text = string.format(
        "Welcome to %s!\n\nThis is the minimal wxWidgets sample\nrunning under %s.",
        version, osdesc)

    wx.MessageBox(text, "About wxWidgets minimal sample",
                  wx.OK + wx.ICON_INFORMATION, frame)
end, Minimal_About)

-- ---------------------------------------------------------------------------
-- OnInit: frame->Show(true); then wxApp::OnRun() enters the message loop.
-- ---------------------------------------------------------------------------

frame:Show(true)

app:MainLoop()

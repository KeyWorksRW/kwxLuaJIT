--[[
    animate.lua — LuaJIT port of wxWidgets samples/animate/anitest.cpp

    Source: C:/rwCode/wxSamples/src/animate/anitest.cpp (+ anitest.h)
    Output: samples/animate/animate.lua

    Reproduces:
      - MyApp::OnInit        -> wx.App() + MyFrame + MainLoop
      - MyFrame ctor         -> frame, icon (sample.svg from ../sample.xpm),
                                menu bar (File / Animation / Help), status bar,
                                vertical sizer with the wxAnimationCtrl label,
                                the animation control, and the "Animation
                                frames" static box (spin control, frame count,
                                delay label, frame bitmap)
      - OnPlay / OnStop / OnSetNullAnimation / OnSetInactiveBitmap /
        OnSetNoAutoResize / OnSetBgColor / OnFrameSpin / OnOpen / OnAbout /
        OnQuit / OnUpdateUI and UpdateFrameControls / UpdateFrameInfo /
        RecreateAnimation

    Platform branch (MSW build, which this checkout builds):
      wxHAS_NATIVE_ANIMATIONCTRL is only defined for GTK (see
      wx/animate.h), so on MSW it is *not* defined.  Consequently
      - the "Use &generic animation\tCtrl+G" menu item, ID_USE_GENERIC and
        OnUseGeneric do not exist in the compiled sample,
      - RecreateAnimation never copies the current animation (its "curr"
        stays an empty wxAnimation) and always creates a plain
        wxAnimationCtrl.
      That is reproduced here: no generic-animation menu entry or handler,
      and RecreateAnimation builds a fresh wxAnimationCtrl with an empty
      animation.

    Source defect in the original: the event table contains
      EVT_SIZE(MyFrame::OnSize) but MyFrame declares and defines no OnSize
      member (a grep of the folder finds only that event-table line).  There
      is no handler body to port, so no size handler is connected here.

    Generated modules used because the `wx` wrapper has no equivalent:
      wxmenu_gen / wxmenubar_gen          menu construction, item enabling
      wxsizerflags_gen                    wxSizerFlags builders
      wxstaticboxsizer_gen / wxstaticbox_gen
      wxspinctrl_gen                      wxSpinCtrl
      wxstaticbitmap_gen                  wxStaticBitmap
      wxanimation_gen / wxanimationbundle_gen / wxanimationctrl_gen
      wximage_gen / wxbitmap_gen          animation frames -> static bitmap
      wxcolour_gen                        wxColour for Get/SetBackgroundColour
      wxartprovider_gen                   wxArtProvider::GetBitmap (static)
      wxbitmapbundle_gen                  wxBitmapBundle::FromSVGFile (static)
      wxcommandevent_gen                  wraps the raw wxEvent* the event
                                          bridge hands to a handler
      wxaboutdialoginfo_gen               wxAboutDialogInfo
      wxfiledialog_gen                    wxFileDialog for "Open Animation..."
      wxicon_gen                          frame icon
      kwxffi_freefuncs_idiomatic_gen      wxGetColourFromUserEx, wxAboutBox and
                                          LogError, which marshal their
                                          wxStrings automatically

    No raw `kwxffi_gen` entry point is called: the generated statics own the
    wxString marshalling, the free-function layer covers the free functions, and
    a factory's newly allocated result is adopted with `<class>_gen.FromPtr(ptr,
    true)` so Delete() releases exactly what this script owns.
]]

local wx = require("wx")
local bit = require("bit")

local wxmenu_gen              = require("wxmenu_gen")
local wxmenubar_gen           = require("wxmenubar_gen")
local wxsizerflags_gen        = require("wxsizerflags_gen")
local wxstaticbox_gen         = require("wxstaticbox_gen")
local wxstaticboxsizer_gen    = require("wxstaticboxsizer_gen")
local wxspinctrl_gen          = require("wxspinctrl_gen")
local wxstaticbitmap_gen      = require("wxstaticbitmap_gen")
local wxanimation_gen         = require("wxanimation_gen")
local wxanimationbundle_gen   = require("wxanimationbundle_gen")
local wxanimationctrl_gen     = require("wxanimationctrl_gen")
local wximage_gen             = require("wximage_gen")
local wxbitmap_gen            = require("wxbitmap_gen")
local wxbitmapbundle_gen      = require("wxbitmapbundle_gen")
local wxartprovider_gen       = require("wxartprovider_gen")
local wxcommandevent_gen      = require("wxcommandevent_gen")
local wxcolour_gen            = require("wxcolour_gen")
local wxaboutdialoginfo_gen   = require("wxaboutdialoginfo_gen")
local wxfiledialog_gen        = require("wxfiledialog_gen")
local wxicon_gen              = require("wxicon_gen")
-- Free functions (wxGetColourFromUserEx, wxAboutBox, LogError) with their
-- wxString parameters marshalled by kwxgen.
local freefuncs               = require("kwxffi_freefuncs_idiomatic_gen")

-- The C++ launcher owns wxApp initialisation; this is MyApp::OnInit.
local app = wx.App()

-- ---------------------------------------------------------------------------
-- IDs (anitest.cpp enum).  Values preserved exactly: the menu event
-- connections match on them.
--   ID_PLAY = 1, ID_SET_NULL_ANIMATION, ID_SET_INACTIVE_BITMAP,
--   ID_SET_NO_AUTO_RESIZE, ID_SET_BGCOLOR, ID_USE_GENERIC
-- ID_USE_GENERIC only exists under wxHAS_NATIVE_ANIMATIONCTRL (not MSW).
-- ---------------------------------------------------------------------------

local ID_PLAY                 = 1
local ID_SET_NULL_ANIMATION   = 2
local ID_SET_INACTIVE_BITMAP  = 3
local ID_SET_NO_AUTO_RESIZE   = 4
local ID_SET_BGCOLOR          = 5
-- ID_USE_GENERIC (6) is not part of the MSW build, see header comment.

-- ---------------------------------------------------------------------------
-- Script directory helper (assets live beside the script)
-- ---------------------------------------------------------------------------

local function script_directory()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    local dir = src:match("^(.*)[/\\][^/\\]*$")
    return dir or ""
end

local SCRIPT_DIR = script_directory()

local function script_path(relative)
    if SCRIPT_DIR == "" then return relative end
    return SCRIPT_DIR .. "/" .. relative
end

-- ---------------------------------------------------------------------------
-- wxAnimationCtrl window methods
--
-- wxAnimationCtrl derives from wxAnimationCtrlBase -> wxControl -> wxWindow;
-- wxanimationctrl_gen declares that chain, so GetWindowStyle,
-- Get/SetBackgroundColour and Destroy are called directly on the control.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- wxSizerFlags helpers
--
-- The C++ sample uses the wxSizerFlags builder; reading the resulting flags
-- and border keeps the exact defaults (including DPI-scaled border widths).
-- ---------------------------------------------------------------------------

local function make_sizer_flags(configure)
    local f = wxsizerflags_gen.Create(0)
    if not f then error("animate sample: failed to create wxSizerFlags") end
    configure(f)
    local flags = f:GetFlags()
    local border = f:GetBorderInPixels()
    f:Delete()
    return flags, border
end

local function center_border_flags()
    return make_sizer_flags(function(f) f:Center(); f:Border(wx.ALL) end)
end

local function expand_border_flags()
    return make_sizer_flags(function(f) f:Expand(); f:Border(wx.ALL) end)
end

local function center_vertical_right_flags()
    return make_sizer_flags(function(f)
        f:CenterVertical(); f:Border(wx.RIGHT)
    end)
end

local function center_vertical_left_flags()
    return make_sizer_flags(function(f)
        f:CenterVertical(); f:Border(wx.LEFT)
    end)
end

local function center_vertical_flags()
    return make_sizer_flags(function(f) f:CenterVertical() end)
end

-- ---------------------------------------------------------------------------
-- State (MyFrame member fields)
-- ---------------------------------------------------------------------------

local state = {
    frame          = nil,
    menu_bar       = nil,
    sizer          = nil,
    animation_ctrl = nil,
    frame_box      = nil,   -- wxStaticBox
    frame_spin     = nil,
    frame_count    = nil,
    frame_delay    = nil,
    frame_bitmap   = nil,
}

-- ---------------------------------------------------------------------------
-- wxLogError equivalents (wxLogError in anitest.cpp)
-- ---------------------------------------------------------------------------

local function log_error(text)
    freefuncs.LogError(text)            -- wxLogError(wxString*)
end

-- ---------------------------------------------------------------------------
-- Animation assets
--
-- The C++ sample loads "throbber.gif" / "throbber_2x.gif" relative to the
-- working directory.  Both files are shipped beside this script, so the plain
-- name is tried first (C++ behaviour, CWD = samples/animate) and the
-- script-relative location is used as a fallback.
-- ---------------------------------------------------------------------------

local function load_animation_file(filename)
    local anim = wxanimation_gen.CreateFromFile(filename, wx.ANIMATION_TYPE_ANY)
    if anim then return anim end
    return wxanimation_gen.CreateFromFile(script_path(filename),
                                          wx.ANIMATION_TYPE_ANY)
end

-- ---------------------------------------------------------------------------
-- UpdateFrameInfo / UpdateFrameControls
-- ---------------------------------------------------------------------------

local function get_animation()
    local anim = wxanimation_gen.Create()
    if not anim then return nil end
    state.animation_ctrl:GetAnimation(anim)
    return anim
end

local function update_frame_info()
    local anim = get_animation()
    if anim == nil then return end

    if anim:IsOk() and anim:GetFrameCount() ~= 0 then
        local frame = state.frame_spin:GetValue()

        local delay = anim:GetDelay(frame)
        if delay == -1 then
            state.frame_delay:SetLabel("Delay: forever")
        else
            state.frame_delay:SetLabel(string.format("Delay: %d ms", delay))
        end

        local image = wximage_gen.CreateDefault()
        if image then
            anim:GetFrame(frame, image)
            if image:IsOk() then
                local bmp = wxbitmap_gen.CreateFromImage(image, -1) -- wxBitmap(image)
                if bmp then
                    state.frame_bitmap:SetBitmap(bmp)
                    bmp:Delete()        -- SetBitmap() copied it; we created it
                end
            else
                log_error(string.format("Failed to get animation frame %d.", frame))
                local empty = wxbitmap_gen.CreateDefault()  -- wxBitmapBundle()
                if empty then
                    state.frame_bitmap:SetBitmap(empty)
                    empty:Delete()
                end
            end
            image:Delete()
        end
    else
        state.frame_delay:SetLabel("Delay: N/A")
        local empty = wxbitmap_gen.CreateDefault()          -- wxBitmapBundle()
        if empty then
            state.frame_bitmap:SetBitmap(empty)
            empty:Delete()
        end
    end

    anim:Delete()
    state.frame:Layout()
end

local function update_frame_controls()
    local anim = get_animation()
    if anim == nil then return end

    local count = 0
    if anim:IsOk() then count = anim:GetFrameCount() end
    anim:Delete()

    state.frame_box:Enable(count ~= 0)

    if count > 0 then
        state.frame_spin:SetRange(0, count - 1)
        state.frame_count:SetLabel(string.format("(of %d)", count))
    else
        state.frame_spin:SetRange(0, 0)
        state.frame_count:SetLabel("(no frames)")
    end

    state.frame_spin:SetValue(0)

    update_frame_info()
end

-- ---------------------------------------------------------------------------
-- MyFrame::RecreateAnimation(long style)
--
-- Non-native build: "curr" is never filled, so the new control starts with an
-- empty animation.  The inactive bitmap and background colour are carried over.
-- ---------------------------------------------------------------------------

local function recreate_animation(style)
    local old = state.animation_ctrl

    -- wxBitmap inactive = m_animationCtrl->GetInactiveBitmap();
    local inactive = wxbitmap_gen.CreateDefault()
    if inactive then old:GetInactiveBitmap(inactive) end

    -- wxColour bg = m_animationCtrl->GetBackgroundColour();
    local bg = wxcolour_gen.CreateEmpty()
    if bg then old:GetBackgroundColour(bg) end

    -- wxAnimation curr;  (never assigned without wxHAS_NATIVE_ANIMATIONCTRL)
    local curr = wxanimation_gen.Create()
    if curr == nil then
        if inactive then inactive:Delete() end
        if bg then bg:Delete() end
        log_error("Failed to recreate the animation control.")
        return
    end

    local new_ctrl = wxanimationctrl_gen.CreateWithAnimation(
        state.frame, wx.ID_ANY, curr,
        wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
        wx.DEFAULT_SIZE, wx.DEFAULT_SIZE, style)
    curr:Delete()
    if not new_ctrl then
        if inactive then inactive:Delete() end
        if bg then bg:Delete() end
        log_error("Failed to recreate the animation control.")
        return
    end

    -- GetSizer()->Replace(old, m_animationCtrl); delete old;
    state.sizer:ReplaceWindow(old, new_ctrl, false)
    old:Destroy()
    state.animation_ctrl = new_ctrl

    -- load old status in new control
    if inactive then
        new_ctrl:SetInactiveBitmap(inactive)
        inactive:Delete()
    end
    if bg then
        new_ctrl:SetBackgroundColour(bg)
        bg:Delete()
    end

    state.sizer:Layout()

    update_frame_controls()
end

-- ---------------------------------------------------------------------------
-- Menu handlers
-- ---------------------------------------------------------------------------

-- void MyFrame::OnPlay(wxCommandEvent&) { if (!Play()) wxLogError("Invalid animation"); }
local function on_play(evt)
    if not evt then return end
    if not state.animation_ctrl:Play() then
        log_error("Invalid animation")
    end
end

-- void MyFrame::OnStop(wxCommandEvent&) { m_animationCtrl->Stop(); }
local function on_stop(evt)
    if not evt then return end
    state.animation_ctrl:Stop()
end

-- void MyFrame::OnSetNullAnimation(wxCommandEvent&)
local function on_set_null_animation(evt)
    if not evt then return end

    local null_anim = wxanimation_gen.Create()   -- wxNullAnimation
    if null_anim then
        state.animation_ctrl:SetAnimation(null_anim)
        null_anim:Delete()
    end

    update_frame_controls()
end

-- void MyFrame::OnSetInactiveBitmap(wxCommandEvent& event)
local function on_set_inactive_bitmap(evt)
    if not evt then return end

    -- event.IsChecked(): the bridge hands the handler the raw wxEvent*; the
    -- generated non-owning wrapper reaches wxCommandEvent's methods from it.
    if wxcommandevent_gen.FromPtr(evt):IsChecked() then
        -- wxBitmap bmp = wxArtProvider::GetBitmap(wxART_MISSING_IMAGE);
        -- wxART_MISSING_IMAGE and wxART_OTHER are the art id / default client as
        -- Lua strings (the constant table converted and freed the wxStrings).
        -- The static returns a new, caller-owned wxBitmap*.
        local bmp_ptr = wxartprovider_gen.GetBitmap(wx.ART_MISSING_IMAGE,
                                                    wx.ART_OTHER,
                                                    wx.DEFAULT_SIZE,
                                                    wx.DEFAULT_SIZE)
        if bmp_ptr ~= nil then
            local bmp = wxbitmap_gen.FromPtr(bmp_ptr, true)
            state.animation_ctrl:SetInactiveBitmap(bmp)
            bmp:Delete()     -- the factory returned a new wxBitmap
        end
    else
        local empty = wxbitmap_gen.CreateDefault()            -- wxNullBitmap
        if empty then
            state.animation_ctrl:SetInactiveBitmap(empty)
            empty:Delete()
        end
    end
end

-- void MyFrame::OnSetNoAutoResize(wxCommandEvent& event)
local function on_set_no_auto_resize(evt)
    if not evt then return end

    local style = wx.AC_DEFAULT_STYLE
    if wxcommandevent_gen.FromPtr(evt):IsChecked() then
        style = bit.bor(style, wx.AC_NO_AUTORESIZE)
    end

    if style ~= state.animation_ctrl:GetWindowStyle() then
        recreate_animation(style)
    end
end

-- void MyFrame::OnSetBgColor(wxCommandEvent&)
local function on_set_bg_color(evt)
    if not evt then return end

    local initial = wxcolour_gen.CreateEmpty()
    local result  = wxcolour_gen.CreateEmpty()
    if initial == nil or result == nil then
        if initial then initial:Delete() end
        if result then result:Delete() end
        return
    end
    state.animation_ctrl:GetBackgroundColour(initial)

    -- wxGetColourFromUser(parent, colInit, caption) -> wxGetColourFromUserEx,
    -- with the caption wxString marshalled by the generated free-function layer.
    freefuncs.wxGetColourFromUserEx(state.frame, initial,
                                    "Choose the background colour", result)

    if result:IsOk() then
        state.animation_ctrl:SetBackgroundColour(result)
    end

    initial:Delete()
    result:Delete()
end

-- void MyFrame::OnFrameSpin(wxSpinEvent&) { UpdateFrameInfo(); }
local function on_frame_spin(evt)
    if not evt then return end
    update_frame_info()
end

-- void MyFrame::OnQuit(wxCommandEvent&) { Close(); }
local function on_quit(evt)
    if not evt then return end
    state.frame:Close()
end

-- void MyFrame::OnAbout(wxCommandEvent&)
local function on_about(evt)
    if not evt then return end

    local info = wxaboutdialoginfo_gen.Create()
    if not info then return end

    info:SetName("wxAnimationCtrl and wxAnimation sample")
    info:SetDescription("This sample program demonstrates the usage of wxAnimationCtrl")
    info:SetCopyright("(C) 2006 Julian Smart")

    info:AddDeveloper("Julian Smart")
    info:AddDeveloper("Guillermo Rodriguez Garcia")
    info:AddDeveloper("Francesco Montorsi")

    freefuncs.wxAboutBox(info, state.frame)   -- wxAboutBox(info, this)
    info:Delete()
end

-- void MyFrame::OnOpen(wxCommandEvent&)
local function on_open(evt)
    if not evt then return end

    local dialog = wxfiledialog_gen.Create(
        state.frame, "Please choose an animation",
        "",                          -- wxEmptyString (default dir)
        "",                          -- wxEmptyString (default file)
        "*.gif;*.ani;*.webp",        -- wildcard
        wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
        wx.FD_OPEN,
        wx.DEFAULT_SIZE, wx.DEFAULT_SIZE)
    if dialog == nil then return end

    if dialog:ShowModal() == wx.ID_OK then
        local filename = dialog:GetPath()

        -- wxAnimation temp(m_animationCtrl->CreateAnimation());
        local temp = wxanimation_gen.Create()
        if temp == nil then
            dialog:Destroy()
            return
        end
        state.animation_ctrl:CreateAnimation(temp)

        if not temp:LoadFile(filename, wx.ANIMATION_TYPE_ANY) then
            log_error("Sorry, this animation is not a valid format for wxAnimation.")
            temp:Delete()
            dialog:Destroy()
            return
        end

        state.animation_ctrl:SetAnimation(temp)
        state.animation_ctrl:Play()

        state.sizer:Layout()

        update_frame_controls()
        temp:Delete()
    end

    dialog:Destroy()
end

-- void MyFrame::OnUpdateUI(wxUpdateUIEvent&)
--   FindItem(wxID_STOP)->Enable(IsPlaying())
--   FindItem(ID_PLAY)->Enable(!IsPlaying())
--   FindItem(ID_SET_NO_AUTO_RESIZE)->Enable(!IsPlaying())
local function on_update_ui(evt)
    if not evt then return end

    local playing = state.animation_ctrl:IsPlaying()
    state.menu_bar:EnableItem(wx.ID_STOP, playing)
    state.menu_bar:EnableItem(ID_PLAY, not playing)
    state.menu_bar:EnableItem(ID_SET_NO_AUTO_RESIZE, not playing)
end

-- ---------------------------------------------------------------------------
-- MyFrame::MyFrame(parent, id, "Animation Demo")
-- ---------------------------------------------------------------------------

local frame = wx.Frame(nil, "Animation Demo",
                       wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
                       wx.DEFAULT_SIZE, wx.DEFAULT_SIZE,
                       wx.DEFAULT_FRAME_STYLE)
state.frame = frame

-- SetIcon(wxICON(sample)) — sample.svg converted pixel-for-pixel from
-- C:/rwCode/wxSamples/src/sample.xpm (32x32).  The wxIcon stays reachable for
-- the whole run, like the other wx objects the C++ side may still reference;
-- the bundle and bitmap are ours and are released once the icon has copied them.
local frame_icon

do
    -- wxBitmapBundle::FromSVGFile takes the path as a wxString; the generated
    -- static marshals it.  It returns a new bundle pointer that FromPtr adopts.
    local bundle_ptr = wxbitmapbundle_gen.FromSVGFile(script_path("sample.svg"), 32, 32)
    if bundle_ptr ~= nil then
        local bundle = wxbitmapbundle_gen.FromPtr(bundle_ptr, true)
        local bitmap_ptr = bundle:GetBitmap(32, 32)
        if bitmap_ptr ~= nil then
            local bitmap = wxbitmap_gen.FromPtr(bitmap_ptr, true)
            frame_icon = wxicon_gen.CreateDefault()
            if frame_icon ~= nil then
                frame_icon:CopyFromBitmap(bitmap)
                frame:SetIcon(frame_icon)
            end
            bitmap:Delete()   -- owned by this script
        end
        bundle:Delete()       -- owned by this script
    end
end

-- ---------------------------------------------------------------------------
-- Menu bar
-- ---------------------------------------------------------------------------

local file_menu = wxmenu_gen.Create("", 0)
local play_menu = wxmenu_gen.Create("", 0)
local help_menu = wxmenu_gen.Create("", 0)
if not file_menu or not play_menu or not help_menu then
    error("animate sample: failed to create the menus")
end

file_menu:Append(wx.ID_OPEN, "&Open Animation...\tCtrl+O", "Loads an animation", false)
file_menu:Append(wx.ID_EXIT, "", "", false)   -- Append(wxID_EXIT): stock label/help

play_menu:Append(ID_PLAY, "Play\tCtrl+P", "Play the animation", false)
play_menu:Append(wx.ID_STOP, "Stop\tCtrl+S", "Stop the animation", false)
play_menu:AppendSeparator()
play_menu:Append(ID_SET_NULL_ANIMATION, "Set null animation",
                 "Sets the empty animation in the control", false)
play_menu:AppendCheckItem(ID_SET_INACTIVE_BITMAP, "Set inactive bitmap",
                          "Sets an inactive bitmap for the control")
play_menu:AppendCheckItem(ID_SET_NO_AUTO_RESIZE, "Set no autoresize",
                          "Tells the control not to resize automatically")
play_menu:Append(ID_SET_BGCOLOR, "Set background colour...",
                 "Sets the background colour of the control", false)
-- wxHAS_NATIVE_ANIMATIONCTRL is not defined for MSW: no separator and no
-- "Use &generic animation" check item here.

help_menu:Append(wx.ID_ABOUT, "", "", false)  -- Append(wxID_ABOUT)

local menu_bar = wxmenubar_gen.Create(0)
if not menu_bar then error("animate sample: failed to create the menu bar") end
menu_bar:Append(file_menu, "&File")
menu_bar:Append(play_menu, "&Animation")
menu_bar:Append(help_menu, "&Help")

frame:SetMenuBar(menu_bar)
state.menu_bar = menu_bar

-- CreateStatusBar()
frame:CreateStatusBar(1, wx.STB_DEFAULT_STYLE)

-- ---------------------------------------------------------------------------
-- Controls and layout
-- ---------------------------------------------------------------------------

-- use a wxBoxSizer otherwise wxFrame would automatically resize the
-- animation control to fill its client area on user resizes
local sz = wx.BoxSizer(wx.VERTICAL)
state.sizer = sz

local ctrl_label = wx.StaticText(frame, "wxAnimationCtrl:")
do
    local flags, border = center_border_flags()
    sz:Add(ctrl_label, 0, flags, border)
end

local animation_ctrl = wxanimationctrl_gen.Create(
    frame, wx.ID_ANY,
    wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
    wx.DEFAULT_SIZE, wx.DEFAULT_SIZE,
    wx.AC_DEFAULT_STYLE)
if not animation_ctrl then
    error("animate sample: failed to create wxAnimationCtrl")
end
state.animation_ctrl = animation_ctrl

-- wxAnimationBundle animations; throbber.gif + throbber_2x.gif
do
    local bundle = wxanimationbundle_gen.Create()
    if bundle then
        local throbber = load_animation_file("throbber.gif")
        if throbber then
            bundle:Add(throbber)
            throbber:Delete()
        end
        local throbber2x = load_animation_file("throbber_2x.gif")
        if throbber2x then
            bundle:Add(throbber2x)
            throbber2x:Delete()
        end

        if bundle:IsOk() then
            animation_ctrl:SetAnimationBundle(bundle)  -- SetAnimation(bundle)
            animation_ctrl:Play()
        end
        bundle:Delete()
    end
end

do
    local flags, border = center_border_flags()
    sz:Add(animation_ctrl, 0, flags, border)
end

-- wxStaticBoxSizer frameSizer(wxVERTICAL, this, "Animation frames")
local frame_box = wxstaticbox_gen.Create(frame, wx.ID_ANY, "Animation frames",
                                        wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
                                        wx.DEFAULT_SIZE, wx.DEFAULT_SIZE, 0)
if not frame_box then error("animate sample: failed to create wxStaticBox") end
state.frame_box = frame_box

local frame_sizer = wxstaticboxsizer_gen.Create(frame_box, wx.VERTICAL)
if not frame_sizer then
    error("animate sample: failed to create wxStaticBoxSizer")
end

local spin_sizer = wx.BoxSizer(wx.HORIZONTAL)

do
    local label = wx.StaticText(frame_box, "&Frame:")
    local flags, border = center_vertical_right_flags()
    spin_sizer:Add(label, 0, flags, border)
end

local frame_spin = wxspinctrl_gen.Create(
    frame_box, wx.ID_ANY,
    "",                                 -- value
    wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
    wx.DEFAULT_SIZE, wx.DEFAULT_SIZE,
    wx.SP_ARROW_KEYS, 0, 100, 0)
if not frame_spin then error("animate sample: failed to create wxSpinCtrl") end
state.frame_spin = frame_spin

do
    local flags, border = center_vertical_flags()
    spin_sizer:Add(frame_spin, 0, flags, border)
end

local frame_count = wx.StaticText(frame_box, "")
if not frame_count then error("animate sample: failed to create wxStaticText") end
state.frame_count = frame_count

do
    local flags, border = center_vertical_left_flags()
    spin_sizer:Add(frame_count, 0, flags, border)
end

do
    local flags, border = center_border_flags()
    frame_sizer:Add(spin_sizer, 0, flags, border)
end

local frame_delay = wx.StaticText(frame_box, "")
if not frame_delay then error("animate sample: failed to create wxStaticText") end
state.frame_delay = frame_delay

do
    local flags, border = center_border_flags()
    frame_sizer:Add(frame_delay, 0, flags, border)
end

local frame_bitmap
do
    -- new wxStaticBitmap(m_frameBox, wxID_ANY, wxBitmapBundle())
    local empty = wxbitmap_gen.CreateDefault()
    if empty then
        frame_bitmap = wxstaticbitmap_gen.Create(
            frame_box, wx.ID_ANY, empty,
            wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
            wx.DEFAULT_SIZE, wx.DEFAULT_SIZE, 0)
        empty:Delete()
    end
end
if not frame_bitmap then
    error("animate sample: failed to create wxStaticBitmap")
end
state.frame_bitmap = frame_bitmap

do
    local flags, border = center_border_flags()
    frame_sizer:Add(frame_bitmap, 0, flags, border)
end

do
    local flags, border = expand_border_flags()
    sz:Add(frame_sizer, 0, flags, border)
end

frame:SetSizer(sz)

update_frame_controls()

-- SetSize(FromDIP(wxSize(500, 400))) — only the int FromDIP overload is
-- bound, so each dimension is scaled individually (same result).
do
    local w = frame:FromDIP(500)
    local h = frame:FromDIP(400)
    frame:SetSize(wx.DEFAULT_POSITION, wx.DEFAULT_POSITION, w, h,
                  wx.SIZE_USE_EXISTING)
end

-- ---------------------------------------------------------------------------
-- Event connections (wxBEGIN_EVENT_TABLE)
-- ---------------------------------------------------------------------------

frame:Connect(wx.EVT_MENU, on_play,                ID_PLAY)
frame:Connect(wx.EVT_MENU, on_set_null_animation,  ID_SET_NULL_ANIMATION)
frame:Connect(wx.EVT_MENU, on_set_inactive_bitmap, ID_SET_INACTIVE_BITMAP)
frame:Connect(wx.EVT_MENU, on_set_no_auto_resize,  ID_SET_NO_AUTO_RESIZE)
frame:Connect(wx.EVT_MENU, on_set_bg_color,        ID_SET_BGCOLOR)

frame:Connect(wx.EVT_MENU, on_stop,  wx.ID_STOP)
frame:Connect(wx.EVT_MENU, on_about, wx.ID_ABOUT)
frame:Connect(wx.EVT_MENU, on_quit,  wx.ID_EXIT)
frame:Connect(wx.EVT_MENU, on_open,  wx.ID_OPEN)

-- EVT_SIZE(MyFrame::OnSize) has no handler implementation in the C++ sample.
frame:Connect(wx.EVT_UPDATE_UI, on_update_ui, wx.ID_ANY)

-- m_frameSpin->Bind(wxEVT_SPINCTRL, &MyFrame::OnFrameSpin, this);
frame_spin:Connect(wx.EVT_SPINCTRL, on_frame_spin)

-- ---------------------------------------------------------------------------
-- OnInit: frame->Show(true); then wxApp::OnRun() enters the message loop.
-- ---------------------------------------------------------------------------

frame:Show(true)

app:MainLoop()

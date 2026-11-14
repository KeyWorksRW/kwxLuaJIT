--[[
    combo.lua — LuaJIT port of wxWidgets samples/combo/combo.cpp

    Source: C:/rwCode/wxSamples/src/combo/combo.cpp

    Reproduces:
      - MyApp::OnInit              -> wx.App() + MyFrame + MainLoop
      - MyFrame ctor               -> frame title, sample.svg icon, File/Help
                                      menus, wxPanel, log wxTextCtrl (id 105),
                                      wxLogTextCtrl active target, the two
                                      sizer columns, every combo control,
                                      Fit() + Centre()
      - OnComboBoxUpdate           -> EVT_TEXT / EVT_TEXT_ENTER / EVT_COMBOBOX
                                      log lines, filtered to wxComboCtrl sources
      - OnShowComparison           -> modal "Compare against wxComboBox" dialog
      - OnAbout / OnQuit / OnIdle

    Generated modules used (the `wx` wrapper has no equivalent):
      wxmenu_gen / wxmenubar_gen          menu construction
      wxsizerflags_gen                    wxSizerFlags builders (exact default
                                          and DPI-scaled border widths)
      wxtextctrl_gen                      log window with the literal id 105
      wxstatictext_gen                    labels (explicit creation style)
      wxsizerflags_gen, wxstaticbox_gen, wxstaticboxsizer_gen
      wxlogtextctrl_gen / wxlog_gen       wxLogTextCtrl active target
      wxownerdrawncombobox_gen            plain wxOwnerDrawnComboBox
      wxcombobox_gen                      native wxComboBox comparison column
      wxcheckbox_gen                      wxCheckBox used as a combo main control
      wxdialog_gen / wxfiledialog_gen     comparison and file dialogs
      wxicon_gen                          frame icon (sample.svg)
      wxcolour_gen / wxpen_gen / wxdc_gen / wxrect_gen /
      wxsystemsettings_gen                owner-drawn item painting
      wxfont_gen                          GetFont().Scale(1.5)
      wxtreeitemid_gen                    wxTreeItemId out-parameters
      wxcommandevent_gen / wxidleevent_gen / wxobject_gen / wxclassinfo_gen
                                          wrap the raw wxEvent* the event bridge
                                          hands to a handler
      kwxcomboctrl_gen                    wxComboCtrl subclass with the
                                          SetOnButtonClick / SetOnAnimateShow /
                                          SetOnDoSetPopupControl hooks
      kwxownerdrawncombobox_gen           wxOwnerDrawnComboBox subclass with the
                                          SetOnDrawItem / SetOnMeasureItem hooks
      kwxlistviewcombopopup_gen           ListViewComboPopup
      kwxtreectrlcombopopup_gen           TreeCtrlComboPopup
      kwxffi_freefuncs_idiomatic_gen      wxLogMessage, wxVersionString,
                                          wxGetOsDescription,
                                          wxInitAllImageHandlers
      kwxffi_gen                          the static wxBitmapBundle::FromSVGFile
                                          factory and the owned wxBitmap /
                                          wxBitmapBundle / wxSize / wxLog
                                          results it returns

    Gaps (reported, not shimmed):
      - wxPenStyleComboBox::OnDrawBackground cannot call the C++
        wxOwnerDrawnComboBox::OnDrawBackground base implementation, which is not
        bound.  The background handler is therefore not overridden at all: every
        row keeps wxWidgets' default background instead of the sample's
        alternate tint on odd, non-selected rows.  Text, selection, the pen
        preview lines and the alternating row heights are reproduced.
      - The XPM icon ../sample.xpm is shipped as pixel-for-pixel sample.svg.

    Runtime compatibility:
      The only launcher present in this checkout (bin/Release/kwxlua.exe) embeds
      generated modules older than the wx/ tree: it lacks wxDC/wxRect and
      wxCommandEvent FromPtr(), wxCheckBox default construction, and the
      generated wxClassInfo::FindClass() form.  Those paths either fall back to
      the equivalent C entry or degrade with a stderr notice.  A build of the
      current generated surface uses the full implementation with no notices.
]]

local ffi = require("ffi")
local bit = require("bit")

local wx = require("wx")

local wxmenu_gen                 = require("wxmenu_gen")
local wxmenubar_gen              = require("wxmenubar_gen")
local wxtextctrl_gen             = require("wxtextctrl_gen")
local wxstatictext_gen           = require("wxstatictext_gen")
local wxsizerflags_gen           = require("wxsizerflags_gen")
local wxstaticbox_gen            = require("wxstaticbox_gen")
local wxstaticboxsizer_gen       = require("wxstaticboxsizer_gen")
local wxlogtextctrl_gen          = require("wxlogtextctrl_gen")
local wxlog_gen                  = require("wxlog_gen")
local wxownerdrawncombobox_gen   = require("wxownerdrawncombobox_gen")
local wxcombobox_gen             = require("wxcombobox_gen")
local wxcheckbox_gen             = require("wxcheckbox_gen")
local wxdialog_gen               = require("wxdialog_gen")
local wxfiledialog_gen           = require("wxfiledialog_gen")
local wxicon_gen                 = require("wxicon_gen")
local wxcolour_gen               = require("wxcolour_gen")
local wxpen_gen                  = require("wxpen_gen")
local wxdc_gen                   = require("wxdc_gen")
local wxrect_gen                 = require("wxrect_gen")
local wxsystemsettings_gen       = require("wxsystemsettings_gen")
local wxfont_gen                 = require("wxfont_gen")
local wxcommandevent_gen         = require("wxcommandevent_gen")
local wxidleevent_gen            = require("wxidleevent_gen")
local wxobject_gen               = require("wxobject_gen")
local wxclassinfo_gen            = require("wxclassinfo_gen")
local wxwindow_gen               = require("wxwindow_gen")
local wxtreeitemid_gen           = require("wxtreeitemid_gen")
local wxgenericcomboctrl_gen     = require("wxgenericcomboctrl_gen")
local kwxcomboctrl_gen           = require("kwxcomboctrl_gen")
local kwxownerdrawncombobox_gen  = require("kwxownerdrawncombobox_gen")
local kwxlistviewcombopopup_gen  = require("kwxlistviewcombopopup_gen")
local kwxtreectrlcombopopup_gen  = require("kwxtreectrlcombopopup_gen")
local freefuncs                  = require("kwxffi_freefuncs_idiomatic_gen")
local C                          = require("kwxffi_gen")

-- ---------------------------------------------------------------------------
-- Constants (combo.cpp enum)
--   ComboCtrl_Compare = wxID_HIGHEST
--   ComboCtrl_Quit    = wxID_EXIT
--   ComboCtrl_About   = wxID_ABOUT
-- The log text control uses the literal id 105 in the original.
-- ---------------------------------------------------------------------------

local COMBOCTRL_COMPARE = wx.ID_HIGHEST
local COMBOCTRL_QUIT    = wx.ID_EXIT
local COMBOCTRL_ABOUT   = wx.ID_ABOUT
local LOG_CTRL_ID       = 105

local TITLE = "wxComboCtrl and wxOwnerDrawnComboBox Sample"

-- MyFrame::m_arrItems — common list of items for all dialogs.
local ITEMS = {
    "Solid",
    "Transparent",
    "Dot",
    "Long Dash",
    "Short Dash",
    "Dot Dash",
    "Backward Diagonal Hatch",
    "Cross-diagonal Hatch",
    "Forward Diagonal Hatch",
    "Cross Hatch",
    "Horizontal Hatch",
    "Vertical Hatch",
}

-- ---------------------------------------------------------------------------
-- Script directory (assets live beside the script)
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

-- Everything the C++ side may call back into (or that must outlive the loop).
local keep = {}

local function remember(obj)
    keep[#keep + 1] = obj
    return obj
end

local function must(obj, what)
    if obj == nil then
        error("combo sample: failed to create " .. what)
    end
    return obj
end

-- ---------------------------------------------------------------------------
-- Sizer helpers — read wxSizerFlags so the default border matches exactly
-- ---------------------------------------------------------------------------

local function sizer_flags(configure, proportion)
    local f = must(wxsizerflags_gen.Create(proportion or 0), "wxSizerFlags")
    configure(f)
    local flags = f:GetFlags()
    local border = f:GetBorderInPixels()
    f:Delete()
    return flags, border
end

local function center_vertical_right_flags()
    return sizer_flags(function(f) f:CenterVertical(); f:Border(wx.RIGHT) end)
end

local function expand_all_flags()
    return sizer_flags(function(f) f:Expand(); f:Border(wx.ALL) end)
end

local function center_vertical_all_flags()
    return sizer_flags(function(f) f:CenterVertical(); f:Border(wx.ALL) end)
end

-- ---------------------------------------------------------------------------
-- wxLogTextCtrl / wxLogMessage
-- ---------------------------------------------------------------------------

-- wxLogMessage() treats its argument as a printf format string; the kwxFFI
-- entry point takes a single wxString.  Doubling percent signs keeps user text
-- (EVT_TEXT strings can contain '%') from being interpreted as a conversion.
local function log_message(text)
    freefuncs.LogMessage((text:gsub("%%", "%%%%")))
end

local function log_error(text)
    freefuncs.LogError((text:gsub("%%", "%%%%")))
end

-- ---------------------------------------------------------------------------
-- SVG assets
-- ---------------------------------------------------------------------------

-- wxBitmapBundle::FromSVGFile is a static factory: the generated instance
-- wrapper cannot be used for it, so the kwxFFI entry point is called and the
-- newly allocated bundle is released by the caller with wxBitmapBundle_Delete.
local function load_svg_bundle(name, width, height)
    local path = wx.wxString(script_path(name))
    local ptr = C.wxBitmapBundle_FromSVGFile(path, width, height)
    wx.wxStringDelete(path)
    return ptr
end

-- ---------------------------------------------------------------------------
-- Owner-drawn pen-style combo (wxPenStyleComboBox)
-- ---------------------------------------------------------------------------

local function pen_style_for(item)
    if item == 1 then return wx.PENSTYLE_TRANSPARENT end
    if item == 2 then return wx.PENSTYLE_DOT end
    if item == 3 then return wx.PENSTYLE_LONG_DASH end
    if item == 4 then return wx.PENSTYLE_SHORT_DASH end
    if item == 5 then return wx.PENSTYLE_DOT_DASH end
    if item == 6 then return wx.PENSTYLE_BDIAGONAL_HATCH end
    if item == 7 then return wx.PENSTYLE_CROSSDIAG_HATCH end
    if item == 8 then return wx.PENSTYLE_FDIAGONAL_HATCH end
    if item == 9 then return wx.PENSTYLE_CROSS_HATCH end
    if item == 10 then return wx.PENSTYLE_HORIZONTAL_HATCH end
    if item == 11 then return wx.PENSTYLE_VERTICAL_HATCH end
    return wx.PENSTYLE_SOLID
end

-- wxPenStyleComboBox::OnDrawItem(wxDC&, const wxRect&, int item, int flags)
local function install_pen_style_hooks(combo)
    -- A launcher built before the wxDC/wxRect FromPtr helpers cannot adopt the
    -- raw pointers the hook receives.  Keep the default item rendering and
    -- report the runtime gap instead of failing inside every paint callback.
    if type(wxdc_gen.FromPtr) ~= "function"
        or type(wxrect_gen.FromPtr) ~= "function" then
        io.stderr:write("combo: wxDC/wxRect FromPtr is not available in this "
            .. "launcher; owner-drawn pen items use the default rendering.\n")
        return
    end

    local draw_item = ffi.cast(
        "void (*)(void*, void*, void*, int, int)",
        function(_, dc_ptr, rect_ptr, item, flags)
            local ok, err = pcall(function()
                if item == -1 or dc_ptr == nil or rect_ptr == nil then return end

                local dc = wxdc_gen.FromPtr(dc_ptr, false)
                local source = wxrect_gen.FromPtr(rect_ptr, false)
                local r = wxrect_gen.FromPtr(source:Deflate(3), true)
                r:SetHeight(r:GetHeight() - 2)

                local colour = wxcolour_gen.CreateEmpty()
                wxsystemsettings_gen.GetColour(wx.SYS_COLOUR_WINDOWTEXT, colour)
                local pen = wxpen_gen.CreateFromColour(colour, 3,
                                                       pen_style_for(item))
                dc:SetPen(pen)

                if bit.band(flags, wx.ODCB_PAINTING_CONTROL) == 0 then
                    local text = combo:GetString(item)
                    dc:DrawText(text, r:GetX() + 3,
                        r:GetY() + math.floor(
                            (math.floor(r:GetHeight() / 2) - dc:GetCharHeight()) / 2))
                    local line_y = r:GetY() + math.floor((r:GetHeight() / 4) * 3)
                    dc:DrawLine(r:GetX() + 5, line_y,
                                r:GetX() + r:GetWidth() - 5, line_y)
                else
                    local line_y = r:GetY() + math.floor(r:GetHeight() / 2)
                    dc:DrawLine(r:GetX() + 5, line_y,
                                r:GetX() + r:GetWidth() - 5, line_y)
                end

                pen:Delete()
                colour:Delete()
                r:Delete()
            end)
            if not ok then
                io.stderr:write("combo: OnDrawItem error: " .. tostring(err) .. "\n")
            end
        end)
    remember(draw_item)

    -- wxPenStyleComboBox::OnMeasureItem: alternate 36/24 DIP item heights.
    local measure_item = ffi.cast(
        "int (*)(void*, size_t)",
        function(_, item)
            local ok, value = pcall(function()
                local n = tonumber(item) or 0
                return combo:FromDIP((n % 2 == 1) and 36 or 24)
            end)
            if ok and type(value) == "number" then return value end
            return -1
        end)
    remember(measure_item)

    -- The hook setters take void*; convert the function pointers explicitly.
    combo:SetOnDrawItem(ffi.cast("void*", draw_item))
    combo:SetOnMeasureItem(ffi.cast("void*", measure_item))
end

local function create_pen_style_combo(parent)
    -- Two-stage creation, as the C++ derivative class requires.
    local combo = must(kwxownerdrawncombobox_gen.CreateDefault(nil),
                       "kwxOwnerDrawnComboBox")
    must(combo:Create(parent, wx.ID_ANY, "", -1, -1, -1, -1, wx.CB_READONLY),
         "kwxOwnerDrawnComboBox:Create")
    for _, item in ipairs(ITEMS) do combo:Append(item) end
    combo:SetSelection(0)
    install_pen_style_hooks(combo)
    return combo
end

-- A plain wxOwnerDrawnComboBox with the shared item list.
local function create_plain_od_combo(parent, style)
    local combo = must(wxownerdrawncombobox_gen.Create(
        parent, wx.ID_ANY, "", -1, -1, -1, -1, style), "wxOwnerDrawnComboBox")
    for _, item in ipairs(ITEMS) do combo:Append(item) end
    return combo
end

-- ---------------------------------------------------------------------------
-- ListViewComboPopup combo (wxComboCtrlWithCustomPopupAnim)
-- ---------------------------------------------------------------------------

local function create_listview_combo(parent)
    local combo = must(kwxcomboctrl_gen.CreateDefault(nil), "kwxComboCtrl")

    -- cc->SetTextCtrlStyle(wxTE_RIGHT) before Create().
    combo:SetTextCtrlStyle(wx.TE_RIGHT)
    must(combo:Create(parent, wx.ID_ANY, "", -1, -1, -1, -1, 0),
         "kwxComboCtrl:Create")

    -- Make sure we use a popup that allows focusing the listview.
    combo:UseAltPopupWindow(true)
    combo:SetPopupMinWidth(300)

    local popup = must(kwxlistviewcombopopup_gen.Create(), "kwxListViewComboPopup")
    remember(popup)
    combo:SetPopupControl(popup)

    for i = 0, 99 do
        popup:AddString(string.format("Item %02d", i))
    end

    -- wxComboCtrlWithCustomPopupAnim::AnimateShow: size + Raise + ShowWithEffect.
    local animate = ffi.cast(
        "int (*)(void*, int, int, int, int, int)",
        function(_, x, y, width, height)
            local ok = pcall(function()
                local win_ptr = combo:GetPopupWindow()
                if win_ptr == nil then return end
                local win = wxwindow_gen.FromPtr(win_ptr, false)
                if win == nil then return end
                win:SetSize(x, y, width, height, wx.SIZE_AUTO)
                win:Raise()
                win:ShowWithEffect(wx.SHOW_EFFECT_BLEND, 0)
            end)
            if ok then return 1 end
            return 0
        end)
    remember(animate)
    combo:SetOnAnimateShow(ffi.cast("void*", animate))

    return combo
end

-- ---------------------------------------------------------------------------
-- TreeCtrlComboPopup combo (wxGenericComboCtrl)
-- ---------------------------------------------------------------------------

local function create_tree_combo(parent)
    local combo = must(wxgenericcomboctrl_gen.Create(
        parent, wx.ID_ANY, "", -1, -1, -1, -1, 0), "wxGenericComboCtrl")

    -- Make sure we use a popup that allows focusing the treectrl.
    combo:UseAltPopupWindow(true)

    local popup = must(kwxtreectrlcombopopup_gen.Create(), "kwxTreeCtrlComboPopup")
    remember(popup)
    combo:SetPopupControl(popup)

    local root    = must(wxtreeitemid_gen.Create(), "wxTreeItemId(root)")
    local group   = must(wxtreeitemid_gen.Create(), "wxTreeItemId(group)")
    local scratch = must(wxtreeitemid_gen.Create(), "wxTreeItemId(scratch)")

    popup:AddRoot("<hidden_root>", root)

    for i = 0, 3 do
        popup:AppendItem(root, string.format("Branch %02d", i), group)
        for n = 0, 24 do
            popup:AppendItem(group,
                string.format("Subitem %02d", i * 25 + n), scratch)
        end
    end

    root:Delete()
    group:Delete()
    scratch:Delete()

    combo:SetValue("Subitem 05")

    -- Move button to the left - it makes more sense for a tree ctrl.
    combo:SetButtonPosition(-1, -1, wx.LEFT, 0)

    return combo
end

-- ---------------------------------------------------------------------------
-- wxFileSelectorCombo — custom button action opens a wxFileDialog
-- ---------------------------------------------------------------------------

local function create_file_selector_combo(parent)
    -- new wxFileSelectorCombo(parent, wxID_ANY, wxEmptyString,
    --                         wxDefaultPosition, wxDefaultSize,
    --                         style | wxCC_STD_BUTTON)
    local combo = must(kwxcomboctrl_gen.CreateWith(
        nil, parent, wx.ID_ANY, "", -1, -1, -1, -1, wx.CC_STD_BUTTON),
        "kwxComboCtrl(file selector)")

    local dots = load_svg_bundle("three-dots.svg", 16, 16)
    if dots ~= nil then
        combo:SetButtonBitmaps(dots, true, nil, nil, nil)
        C.wxBitmapBundle_Delete(dots)
    end

    -- wxFileSelectorCombo::OnButtonClick()
    local on_button_click = ffi.cast("void (*)(void*)", function(_)
        local ok, err = pcall(function()
            local dialog = wxfiledialog_gen.Create(
                combo,
                "Choose File",
                "",
                combo:GetValue(),
                "All files (*.*)|*.*",
                -1, -1,
                wx.FD_OPEN,
                -1, -1)
            if dialog == nil then return end
            if dialog:ShowModal() == wx.ID_OK then
                combo:SetValue(dialog:GetPath())
            end
            dialog:Destroy()
        end)
        if not ok then
            io.stderr:write("combo: OnButtonClick error: " .. tostring(err) .. "\n")
        end
    end)
    remember(on_button_click)
    combo:SetOnButtonClick(ffi.cast("void*", on_button_click))

    -- Implement an empty DoSetPopupControl to prevent the assertion failure.
    local empty_set_popup = ffi.cast("void (*)(void*, void*)", function() end)
    remember(empty_set_popup)
    combo:SetOnDoSetPopupControl(ffi.cast("void*", empty_set_popup))

    return combo
end

-- ---------------------------------------------------------------------------
-- wxComboCtrl with a wxCheckBox as main control
-- ---------------------------------------------------------------------------

local function create_checkbox_main_combo(parent)
    -- Two-stage wxCheckBox creation (wxCheckBox() + Create()) needs both
    -- generated constructors.  A launcher built before they existed cannot
    -- provide them; keep the combo functional without the custom main control
    -- and report the runtime gap on stderr.
    if type(wxcheckbox_gen.CreateDefault) ~= "function"
        or type(wxcheckbox_gen.Create2) ~= "function" then
        io.stderr:write("combo: wxCheckBox default construction is not "
            .. "available in this launcher; the checkbox main-control combo "
            .. "is built without the custom main control.\n")
        local combo = must(kwxcomboctrl_gen.CreateDefault(nil), "kwxComboCtrl")
        must(combo:Create(parent, wx.ID_ANY, "", -1, -1, -1, -1, 0),
             "kwxComboCtrl:Create")
        local popup = must(kwxlistviewcombopopup_gen.Create(),
                           "kwxListViewComboPopup")
        remember(popup)
        combo:SetPopupControl(popup)
        return combo
    end

    local combo    = must(kwxcomboctrl_gen.CreateDefault(nil), "kwxComboCtrl")
    local checkbox = must(wxcheckbox_gen.CreateDefault(), "wxCheckBox")

    -- comboCustom->SetMainControl(cbox) before creating the combo.
    combo:SetMainControl(checkbox)
    must(combo:Create(parent, wx.ID_ANY, "", -1, -1, -1, -1, 0),
         "kwxComboCtrl:Create")

    must(checkbox:Create2(combo, wx.ID_ANY, "Checkbox as main control",
                          -1, -1, -1, -1, 0), "wxCheckBox:Create2")

    local background = wxcolour_gen.CreateEmpty()
    wxsystemsettings_gen.GetColour(wx.SYS_COLOUR_WINDOW, background)
    checkbox:SetBackgroundColour(background)
    background:Delete()

    local popup = must(kwxlistviewcombopopup_gen.Create(), "kwxListViewComboPopup")
    remember(popup)
    combo:SetPopupControl(popup)

    return combo
end

-- ---------------------------------------------------------------------------
-- MyFrame::OnAbout
-- ---------------------------------------------------------------------------

local function on_about(frame)
    local version = freefuncs.wxVersionString()
    local os_name = freefuncs.wxGetOsDescription()
    local message = string.format(
        "Welcome to %s!\n\n"
        .. "This is the wxWidgets wxComboCtrl and wxOwnerDrawnComboBox sample\n"
        .. "running under %s.",
        version, os_name)

    wx.MessageBox(message, "About wxComboCtrl sample",
                  wx.OK + wx.ICON_INFORMATION, frame)
end

-- ---------------------------------------------------------------------------
-- MyFrame::OnShowComparison — modal comparison dialog
-- ---------------------------------------------------------------------------

local function scale_font(window, factor)
    local font = wxfont_gen.CreateDefault()
    if font == nil then return end
    window:GetFont(font)
    font:Scale(factor)
    window:SetFont(font)
    font:Delete()
end

local function add_group_caption(group_sizer, box, text, expand)
    local label = must(wxstatictext_gen.Create(
        box, wx.ID_ANY, text, -1, -1, -1, -1, 0), "wxStaticText")
    local flags, border = sizer_flags(function(f)
        if expand then f:Expand() end
        f:Border(wx.RIGHT)
    end)
    group_sizer:Add(label, 0, flags, border)
end

local function create_group(parent, label)
    local box = must(wxstaticbox_gen.Create(
        parent, wx.ID_ANY, label, -1, -1, -1, -1, 0), "wxStaticBox")
    local sizer = must(wxstaticboxsizer_gen.Create(box, wx.VERTICAL),
                       "wxStaticBoxSizer")
    return box, sizer
end

local function create_native_combo(parent, style)
    -- The C++ constructor takes the item array; appending afterwards produces
    -- the same list, with wxCB_SORT applied as items arrive.
    local combo = must(wxcombobox_gen.Create(
        parent, wx.ID_ANY, "", -1, -1, -1, -1, 0, nil, style), "wxComboBox")
    for _, item in ipairs(ITEMS) do combo:Append(item) end
    return combo
end

local function fill_owner_drawn_column(box, sizer)
    -- Writable, with margins, sorted
    add_group_caption(sizer, box, "Writable, with margins, sorted:", true)
    do
        local odc = create_plain_od_combo(box, wx.CB_SORT)
        odc:Append("H - Appended Item")     -- test sorting in append
        odc:SetValue("Dot Dash")
        odc:SetMargins(15, 10)
        local flags, border = sizer_flags(function(f) f:Border(wx.ALL) end)
        sizer:Add(odc, 0, flags, border)
    end
    sizer:AddStretchSpacer(1)

    -- Read-only, big font
    add_group_caption(sizer, box, "Read-only, big font:", false)
    do
        local odc = create_plain_od_combo(box, wx.CB_SORT + wx.CB_READONLY)
        scale_font(odc, 1.5)
        odc:SetValue("Dot Dash")
        odc:SetText("Dot Dash (Testing SetText)")
        local flags, border = sizer_flags(function(f) f:Border(wx.ALL) end)
        sizer:Add(odc, 0, flags, border)
    end
    sizer:AddStretchSpacer(1)

    -- Read-only disabled
    add_group_caption(sizer, box, "Read-only disabled:", false)
    do
        local odc = create_plain_od_combo(box, wx.CB_READONLY)
        odc:SetValue("Dot Dash")
        odc:Enable(false)
        local flags, border = sizer_flags(function(f)
            f:Expand(); f:Border(wx.ALL)
        end)
        sizer:Add(odc, 3, flags, border)
    end

    -- Disabled
    add_group_caption(sizer, box, "Disabled:", false)
    do
        local odc = create_plain_od_combo(box, 0)
        odc:SetValue("Dot Dash")
        odc:Enable(false)
        local flags, border = sizer_flags(function(f)
            f:Expand(); f:Border(wx.ALL)
        end)
        sizer:Add(odc, 3, flags, border)
    end
end

local function fill_native_column(box, sizer)
    -- Writable, with margins, sorted
    add_group_caption(sizer, box, "Writable, with margins, sorted:", true)
    do
        local cb = create_native_combo(box, wx.CB_SORT)
        cb:Append("H - Appended Item")      -- test sorting in append
        cb:SetValue("Dot Dash")
        cb:SetMargins(15, 10)
        local flags, border = sizer_flags(function(f) f:Border(wx.ALL) end)
        sizer:Add(cb, 0, flags, border)
    end
    sizer:AddStretchSpacer(1)

    -- Read-only, big font
    add_group_caption(sizer, box, "Read-only, big font:", false)
    do
        local cb = create_native_combo(box, wx.CB_SORT + wx.CB_READONLY)
        scale_font(cb, 1.5)
        cb:SetValue("Dot Dash")
        local flags, border = sizer_flags(function(f) f:Border(wx.ALL) end)
        sizer:Add(cb, 0, flags, border)
    end
    sizer:AddStretchSpacer(1)

    -- Read-only disabled
    add_group_caption(sizer, box, "Read-only disabled:", false)
    do
        local cb = create_native_combo(box, wx.CB_READONLY)
        cb:SetValue("Dot Dash")
        cb:Enable(false)
        local flags, border = sizer_flags(function(f)
            f:Expand(); f:Border(wx.ALL)
        end)
        sizer:Add(cb, 3, flags, border)
    end

    -- Disabled
    add_group_caption(sizer, box, "Disabled:", false)
    do
        local cb = create_native_combo(box, 0)
        cb:SetValue("Dot Dash")
        cb:Enable(false)
        local flags, border = sizer_flags(function(f)
            f:Expand(); f:Border(wx.ALL)
        end)
        sizer:Add(cb, 3, flags, border)
    end
end

local function show_comparison(frame)
    local dialog = must(wxdialog_gen.Create(
        frame, wx.ID_ANY, "Compare against wxComboBox",
        -1, -1, -1, -1,
        wx.DEFAULT_DIALOG_STYLE + wx.RESIZE_BORDER), "wxDialog")

    local col_sizer = wx.BoxSizer(wx.VERTICAL)
    local row_sizer = wx.BoxSizer(wx.HORIZONTAL)

    do
        local box, group_sizer = create_group(dialog, " wxOwnerDrawnComboBox ")
        fill_owner_drawn_column(box, group_sizer)
        local flags, border = sizer_flags(function(f)
            f:Expand(); f:Border(wx.ALL)
        end)
        row_sizer:Add(group_sizer, 1, flags, border)
    end

    do
        local box, group_sizer = create_group(dialog, " wxComboBox ")
        fill_native_column(box, group_sizer)
        local flags, border = sizer_flags(function(f)
            f:Expand(); f:Border(wx.ALL)
        end)
        row_sizer:Add(group_sizer, 1, flags, border)
    end

    do
        local flags, border = sizer_flags(function(f)
            f:Expand(); f:Border(wx.ALL)
        end)
        col_sizer:Add(row_sizer, 1, flags, border)
    end

    dialog:SetSizer(col_sizer)
    col_sizer:SetSizeHints(dialog)

    -- dlg->SetSize(60, 240) resolves to SetSize(int width, int height).
    dialog:SetSize(-1, -1, 60, 240, wx.SIZE_USE_EXISTING)
    dialog:Centre(wx.BOTH)
    dialog:ShowModal()

    -- The C++ sample leaks the dialog; destroying it keeps the port tidy.
    dialog:Destroy()
end

-- ---------------------------------------------------------------------------
-- MyFrame::MyFrame
-- ---------------------------------------------------------------------------

-- MyApp::OnInit: create and show the main application window.
local app = wx.App()

local frame = must(wx.Frame(nil, TITLE,
    wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
    wx.DEFAULT_SIZE, wx.DEFAULT_SIZE,
    wx.DEFAULT_FRAME_STYLE), "wxFrame")

-- SetIcon(wxICON(sample)) reproduced from the converted 32x32 sample.svg.
do
    local bundle = load_svg_bundle("sample.svg", 32, 32)
    if bundle ~= nil then
        local bitmap_ptr = C.wxBitmapBundle_GetBitmap(bundle, 32, 32)
        if bitmap_ptr ~= nil then
            local icon = wxicon_gen.CreateDefault()
            if icon then
                icon:CopyFromBitmap(bitmap_ptr)
                frame:SetIcon(icon)
                remember(icon)
            end
            C.wxBitmap_Delete(bitmap_ptr)
        end
        C.wxBitmapBundle_Delete(bundle)
    end
end

-- Menu bar
local file_menu = must(wxmenu_gen.Create("", 0), "wxMenu")
local help_menu = must(wxmenu_gen.Create("", 0), "wxMenu")

help_menu:Append(COMBOCTRL_ABOUT, "&About\tF1", "Show about dialog", false)

file_menu:Append(COMBOCTRL_COMPARE, "&Compare against wxComboBox...",
    "Show some wxOwnerDrawnComboBoxes side-by-side with native wxComboBoxes.",
    false)
file_menu:AppendSeparator()
file_menu:Append(COMBOCTRL_QUIT, "E&xit\tAlt-X", "Quit this program", false)

local menu_bar = must(wxmenubar_gen.Create(0), "wxMenuBar")
menu_bar:Append(file_menu, "&File")
menu_bar:Append(help_menu, "&Help")
frame:SetMenuBar(menu_bar)

local panel = wx.Panel(frame)

-- Prepare log window right away since it shows EVT_TEXTs.
local log_win = must(wxtextctrl_gen.Create(
    panel, LOG_CTRL_ID, "", -1, -1, -1, 125, wx.TE_MULTILINE), "wxTextCtrl")

local logger = nil
local old_log_target = nil
do
    logger = wxlogtextctrl_gen.Create(log_win)
    if logger then
        old_log_target = wxlog_gen.SetActiveTarget(logger)
        -- wxLog::DisableTimestamp() is implemented as SetTimestamp(""); the
        -- latter is available in every generated build, the former is not.
        if type(logger.DisableTimestamp) == "function" then
            logger:DisableTimestamp()
        else
            -- SetTimestamp() takes the raw character pointer as void*.
            local empty_format = ffi.cast("char*", "")
            logger:SetTimestamp(ffi.cast("void*", empty_format))
        end
    end
end

local top_sizer      = wx.BoxSizer(wx.VERTICAL)
local top_row_sizer  = wx.BoxSizer(wx.HORIZONTAL)
local col_sizer      = wx.BoxSizer(wx.VERTICAL)

-- ---------------------------------------------------------------------------
-- Column 1: the combo controls
-- ---------------------------------------------------------------------------

-- OwnerDrawnComboBox with owner-drawn items
do
    local row = wx.BoxSizer(wx.HORIZONTAL)
    local label = wx.StaticText(panel,
        "OwnerDrawnComboBox with owner-drawn items:")
    local flags, border = center_vertical_right_flags()
    row:Add(label, 1, flags, border)
    local rf, rb = expand_all_flags()
    col_sizer:Add(row, 0, rf, rb)
end

do
    local row = wx.BoxSizer(wx.HORIZONTAL)
    local odc = create_pen_style_combo(panel)
    local flags, border = center_vertical_all_flags()
    row:Add(odc, 1, flags, border)
    row:AddStretchSpacer(1)
    local rf, rb = expand_all_flags()
    col_sizer:Add(row, 0, rf, rb)
end

-- Same, with the button on the left
do
    local row = wx.BoxSizer(wx.HORIZONTAL)
    local label = wx.StaticText(panel,
        "OwnerDrawnComboBox with owner-drawn items and button on the left:")
    local flags, border = center_vertical_right_flags()
    row:Add(label, 1, flags, border)
    local rf, rb = expand_all_flags()
    col_sizer:Add(row, 0, rf, rb)
end

do
    local row = wx.BoxSizer(wx.HORIZONTAL)
    local odc = create_pen_style_combo(panel)

    -- Use a button size that is slightly smaller than the default.
    local button_size_ptr = odc:GetButtonSize()
    if button_size_ptr ~= nil then
        -- wxComboCtrl::GetButtonSize() returns an owned wxSize*.  The
        -- generated FromPtr() helper is absent from some launcher builds, so
        -- the C accessors are used directly.
        local width  = C.wxSize_GetWidth(button_size_ptr)  - 2
        local height = C.wxSize_GetHeight(button_size_ptr) - 6
        C.wxSize_Delete(button_size_ptr)
        odc:SetButtonPosition(width, height, wx.LEFT, 2)
    else
        odc:SetButtonPosition(-1, -1, wx.LEFT, 2)
    end

    local flags, border = center_vertical_all_flags()
    row:Add(odc, 1, flags, border)
    row:AddStretchSpacer(1)
    local rf, rb = expand_all_flags()
    col_sizer:Add(row, 0, rf, rb)
end

-- List View wxComboCtrl / Tree Ctrl wxComboCtrl
do
    local row = wx.BoxSizer(wx.HORIZONTAL)
    local flags, border = center_vertical_right_flags()
    row:Add(wx.StaticText(panel,
        "List View wxComboCtrl (custom animation):"), 1, flags, border)
    row:Add(wx.StaticText(panel, "Tree Ctrl wxComboCtrl:"), 1, flags, border)
    local rf, rb = expand_all_flags()
    col_sizer:Add(row, 0, rf, rb)
end

do
    local row = wx.BoxSizer(wx.HORIZONTAL)
    local list_combo = create_listview_combo(panel)
    local tree_combo = create_tree_combo(panel)
    local flags, border = center_vertical_all_flags()
    row:Add(list_combo, 1, flags, border)
    row:Add(tree_combo, 1, flags, border)
    local rf, rb = expand_all_flags()
    col_sizer:Add(row, 0, rf, rb)
end

-- Custom drop button bitmaps (wxUSE_IMAGE section)
freefuncs.wxInitAllImageHandlers()

do
    local row = wx.BoxSizer(wx.HORIZONTAL)
    local flags, border = center_vertical_right_flags()
    row:Add(wx.StaticText(panel,
        "OwnerDrawnComboBox with simple dropbutton graphics:"), 1, flags, border)
    local rf, rb = expand_all_flags()
    col_sizer:Add(row, 0, rf, rb)
end

do
    local row = wx.BoxSizer(wx.HORIZONTAL)
    local odc  = create_plain_od_combo(panel, 0)
    local odc2 = create_plain_od_combo(panel, 0)

    -- Load images from disk.
    local bmp_normal  = load_svg_bundle("dropbutn.svg", 16, 16)
    local bmp_pressed = load_svg_bundle("dropbutp.svg", 16, 16)
    local bmp_hover   = load_svg_bundle("dropbuth.svg", 16, 16)

    if bmp_normal ~= nil and bmp_pressed ~= nil and bmp_hover ~= nil then
        odc:SetButtonBitmaps(bmp_normal, false, bmp_pressed, bmp_hover, nil)
        odc2:SetButtonBitmaps(bmp_normal, true, bmp_pressed, bmp_hover, nil)
    else
        log_error("Dropbutton images not found")
    end

    if bmp_normal  ~= nil then C.wxBitmapBundle_Delete(bmp_normal)  end
    if bmp_pressed ~= nil then C.wxBitmapBundle_Delete(bmp_pressed) end
    if bmp_hover   ~= nil then C.wxBitmapBundle_Delete(bmp_hover)   end

    local flags, border = center_vertical_all_flags()
    row:Add(odc, 1, flags, border)
    row:Add(odc2, 1, flags, border)
    local rf, rb = expand_all_flags()
    col_sizer:Add(row, 0, rf, rb)
end

-- wxComboCtrl with custom button action and custom main control
do
    local row = wx.BoxSizer(wx.HORIZONTAL)
    local flags, border = center_vertical_right_flags()
    row:Add(wx.StaticText(panel,
        "wxComboCtrl with custom button and custom main control:"),
        1, flags, border)
    local rf, rb = expand_all_flags()
    col_sizer:Add(row, 0, rf, rb)
end

do
    local row = wx.BoxSizer(wx.HORIZONTAL)
    local file_combo = create_file_selector_combo(panel)
    local check_combo = create_checkbox_main_combo(panel)
    local flags, border = center_vertical_all_flags()
    row:Add(file_combo, 1, flags, border)
    row:Add(check_combo, 1, flags, border)
    local rf, rb = expand_all_flags()
    col_sizer:Add(row, 0, rf, rb)
end

-- wxComboCtrl::GetFeatures() is called by the original only to make sure it
-- is implemented; it has no observable effect.  The binding is a static no-op
-- whose generated form differs between builds, so no runtime call is made.

-- ---------------------------------------------------------------------------
-- Column 2: log messages
-- ---------------------------------------------------------------------------

do
    local flags, border = sizer_flags(function(f) f:Border(wx.ALL) end)
    top_row_sizer:Add(col_sizer, 1, flags, frame:FromDIP(2))
end

col_sizer = wx.BoxSizer(wx.VERTICAL)
col_sizer:AddSpacer(8)

do
    local label = wx.StaticText(panel, "Log Messages:")
    local flags, border = sizer_flags(function(f)
        f:Border(wx.TOP + wx.LEFT)
    end)
    col_sizer:Add(label, 0, flags, frame:FromDIP(3))
end

do
    local flags, border = expand_all_flags()
    col_sizer:Add(log_win, 1, flags, frame:FromDIP(3))
end

do
    local flags, border = expand_all_flags()
    top_row_sizer:Add(col_sizer, 1, flags, frame:FromDIP(2))
end

do
    local flags, border = sizer_flags(function(f) f:Expand() end)
    top_sizer:Add(top_row_sizer, 1, flags, border)
end

panel:SetSizer(top_sizer)
top_sizer:SetSizeHints(panel)

frame:Fit()
frame:Centre(wx.BOTH)

-- ---------------------------------------------------------------------------
-- MyFrame event table
-- ---------------------------------------------------------------------------

local combo_ctrl_classinfo = nil
do
    -- CLASSINFO(wxComboCtrl).  The generated static is preferred; some launcher
    -- builds predate its correct arity, in which case the same C entry is used.
    local ok, ci = pcall(wxclassinfo_gen.FindClass, "wxComboCtrl")
    if ok and ci ~= nil then
        combo_ctrl_classinfo = ci
    else
        local name = wx.wxString("wxComboCtrl")
        combo_ctrl_classinfo = C.wxClassInfo_FindClass(name)
        wx.wxStringDelete(name)
    end
end

local function on_combo_update(evt)
    if not evt then return end
    -- Runtime capability guard: the event wrappers are the public surface in
    -- current builds; an older launcher cannot wrap the raw wxEvent*.
    if type(wxcommandevent_gen.FromPtr) ~= "function" then return end

    local event = wxcommandevent_gen.FromPtr(evt, false)
    if event == nil then return end

    -- Don't show messages for the log output window (it would crash).
    local source_ptr = event:GetEventObject()
    if source_ptr == nil or combo_ctrl_classinfo == nil then return end

    local source = wxobject_gen.FromPtr(source_ptr, false)
    if source == nil or not source:IsKindOf(combo_ctrl_classinfo) then
        return
    end

    local event_type = event:GetEventType()
    if event_type == wx.EVT_COMBOBOX then
        log_message(string.format("EVT_COMBOBOX(id=%d,selection=%d)",
            event:GetId(), event:GetSelection()))
    elseif event_type == wx.EVT_TEXT then
        log_message(string.format('EVT_TEXT(id=%d,string="%s")',
            event:GetId(), event:GetString()))
    elseif event_type == wx.EVT_TEXT_ENTER then
        log_message(string.format('EVT_TEXT_ENTER(id=%d,string="%s")',
            event:GetId(), event:GetString()))
    end
end

local function on_idle(evt)
    if not evt then return end
    if type(wxidleevent_gen.FromPtr) == "function" then
        local event = wxidleevent_gen.FromPtr(evt, false)
        if event then event:Skip(true) end
    else
        -- Same effect: wxEvent::Skip(true).
        pcall(function() C.wxEvent_Skip(evt, 1) end)
    end
end

local function on_show_comparison(evt)
    if not evt then return end
    show_comparison(frame)
end

local function on_quit(evt)
    if not evt then return end
    -- true is to force the frame to close
    frame:Close(true)
end

local function on_menu_about(evt)
    if not evt then return end
    on_about(frame)
end

frame:Connect(wx.EVT_TEXT, on_combo_update, wx.ID_ANY)
frame:Connect(wx.EVT_TEXT_ENTER, on_combo_update, wx.ID_ANY)
frame:Connect(wx.EVT_COMBOBOX, on_combo_update, wx.ID_ANY)

frame:Connect(wx.EVT_MENU, on_show_comparison, COMBOCTRL_COMPARE)
frame:Connect(wx.EVT_MENU, on_quit, COMBOCTRL_QUIT)
frame:Connect(wx.EVT_MENU, on_menu_about, COMBOCTRL_ABOUT)

frame:Connect(wx.EVT_IDLE, on_idle, wx.ID_ANY)

-- ---------------------------------------------------------------------------
-- OnInit: frame->Show(true); wxApp::OnRun() enters the message loop.
-- ---------------------------------------------------------------------------

frame:Show(true)

local exit_code = app:MainLoop()

-- MyFrame::~MyFrame(): delete wxLog::SetActiveTarget(m_logOld)
if logger ~= nil then
    local previous
    local ok, result = pcall(wxlog_gen.SetActiveTarget, old_log_target)
    if ok then
        previous = result
    else
        previous = C.wxLog_SetActiveTarget(old_log_target)
    end
    if previous ~= nil then
        if type(wxlogtextctrl_gen.FromPtr) == "function" then
            local previous_logger = wxlogtextctrl_gen.FromPtr(previous, true)
            if previous_logger then previous_logger:Delete() end
        else
            C.wxLogTextCtrl_Delete(previous)
        end
    end
    logger = nil
end

return exit_code

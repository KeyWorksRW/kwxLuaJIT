--[[
    widgets.lua — LuaJIT port of wxWidgets samples/widgets

    Source: C:/rwCode/wxSamples/src/widgets  (entry widgets.cpp, widgets.h)

    Reproduces:
      WidgetsApp::OnInit        -> wx.App() + WidgetsFrame + MainLoop
      WidgetsFrame              -> wxFrame "wxMSW widgets demo", menu bar
                                   (Widget / Text / Page / Theme), wxTreebook
                                   with the 8 category nodes and one page per
                                   widget demo, and the "&Log window" pane.
      WidgetsPage               -> one wxScrolledWindow per (category, page)
                                   pair, content built lazily on first show.
      WidgetAttributes          -> `attrs`, applied by SetUpWidget().

    Generated modules used below the `wx` wrapper (the wrapper aliases only
    Frame/Panel/Button/StaticText/TextCtrl/BoxSizer):
      wxframe_gen, wxpanel_gen, wxscrolledwindow_gen, wxtreebook_gen,
      wxboxsizer_gen, wxstaticbox_gen, wxstaticboxsizer_gen, wxmenu_gen,
      wxmenubar_gen, wxbutton_gen, wxstatictext_gen, wxtextctrl_gen,
      wxlistbox_gen, wxcheckbox_gen, wxcursor_gen,
      wxcommandevent_gen, wxbookctrlevent_gen, wxfocusevent_gen,
      wxmouseevent_gen, wxcontextmenuevent_gen, wxevent_gen,
      wxupdateuievent_gen, wxtextentrydialog_gen, wxcolour_gen,
      wxfont_gen, wxapp_gen, wxbitmapbundle_gen,
      kwxffi_freefuncs_idiomatic_gen.

    Page implementations live in widgets_pages_a.lua / widgets_pages_b.lua.
]]

local wx  = require("wx")
local bit = require("bit")
local ffi = require("ffi")
-- kwxffi_gen is needed for the two borrowed-wxString* callback reads below
-- (kwxUtf8Buffer_*); it is loaded by the generated modules anyway.
local C   = require("kwxffi_gen")

-- ---------------------------------------------------------------------------
-- generated modules
-- ---------------------------------------------------------------------------

local frame_gen          = require("wxframe_gen")
local panel_gen          = require("wxpanel_gen")
local scrolled_gen       = require("wxscrolledwindow_gen")
local treebook_gen       = require("wxtreebook_gen")
local boxsizer_gen       = require("wxboxsizer_gen")
local staticbox_gen      = require("wxstaticbox_gen")
local staticboxsizer_gen = require("wxstaticboxsizer_gen")
local menu_gen           = require("wxmenu_gen")
local menubar_gen        = require("wxmenubar_gen")
local button_gen         = require("wxbutton_gen")
local statictext_gen     = require("wxstatictext_gen")
local textctrl_gen       = require("wxtextctrl_gen")
local listbox_gen        = require("wxlistbox_gen")
local checkbox_gen       = require("wxcheckbox_gen")

local cursor_gen         = require("wxcursor_gen")
local app_gen            = require("wxapp_gen")
local cmd_event          = require("wxcommandevent_gen")
local book_event         = require("wxbookctrlevent_gen")
local focus_event        = require("wxfocusevent_gen")
local mouse_event        = require("wxmouseevent_gen")
local ctx_menu_event     = require("wxcontextmenuevent_gen")
local event_gen          = require("wxevent_gen")
local updateui_event     = require("wxupdateuievent_gen")
local textentrydlg_gen   = require("wxtextentrydialog_gen")
local colour_gen         = require("wxcolour_gen")
local font_gen           = require("wxfont_gen")
local F                  = require("kwxffi_freefuncs_idiomatic_gen")

-- ---------------------------------------------------------------------------
-- script directory (Lua has no __dirname)
-- ---------------------------------------------------------------------------

local function script_directory()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    local dir = src:match("^(.*)[/\\][^/\\]*$")
    return dir or "."
end

local SDIR = script_directory()

-- ---------------------------------------------------------------------------
-- constants replicated from widgets.cpp / widgets.h
-- ---------------------------------------------------------------------------

-- control ids (widgets.cpp enum, counting stops at the ones we need)
local ID = {
    ClearLog   = 100,
    Quit       = 101,
    BookCtrl   = 102,

    SetTooltip = 103,
    SetFgColour= 104,
    SetBgColour= 105,
    SetPageBg  = 106,
    SetFont    = 107,
    Enable     = 108,
    Show       = 109,

    BorderNone    = 110,
    BorderStatic  = 111,
    BorderSimple  = 112,
    BorderRaised  = 113,
    BorderSunken  = 114,
    BorderDouble  = 115,
    BorderDefault = 116,

    VariantNormal = 117,
    VariantSmall  = 118,
    VariantMini   = 119,
    VariantLarge  = 120,

    LayoutDirection  = 121,
    GlobalBusyCursor = 122,
    BusyCursor       = 123,

    GoToPage = 124,

    TextEntryDisableAutoComplete   = 225,
    TextEntryAutoCompleteFixed     = 226,
    TextEntryAutoCompleteFilenames = 227,
    TextEntryAutoCompleteDirs      = 228,
    TextEntryAutoCompleteCustom    = 229,
    TextEntryAutoCompleteKeyLength = 230,
    TextEntrySetHint               = 231,

    ThemeLight  = 232,
    ThemeDark   = 233,
    ThemeSystem = 234,
}

-- WidgetsCategories[] order (widgets.cpp) and the page masks (widgets.h)
local CATEGORIES = {
    "Native", "Generic", "Pickers", "Comboboxes",
    "With items", "Editable", "Books", "All controls",
}

local NATIVE, GENERIC, PICKER, COMBO, ITEMS, EDITABLE, BOOKCAT, ALLC =
      1, 2, 4, 8, 16, 32, 64, 128

-- wxSizerFlags::GetDefaultBorder() is a runtime metric; the sample's own
-- spacers use FromDIP(5), so the default border is taken as 5 px here.
local D = 5

-- ---------------------------------------------------------------------------
-- WidgetAttributes (widgets.h) — the singleton behind WidgetsPage::GetAttrs()
-- ---------------------------------------------------------------------------

local attrs = {
    tooltip      = "This is a tooltip",
    enabled      = true,
    show         = true,
    dir          = wx.Layout_Default,
    variant      = wx.WINDOW_VARIANT_NORMAL,
    cursor       = nil,                    -- wxNullCursor
    defaultFlags = wx.BORDER_DEFAULT,
    font         = nil,                    -- wxFont, unset until chosen
    colFg        = nil,
    colBg        = nil,
    colPageBg    = nil,
}

-- ---------------------------------------------------------------------------
-- log window (LboxLogger)
-- ---------------------------------------------------------------------------

local logList = nil

local function log(msg)
    if not logList then return end
    logList:Append(msg)
    local n = logList:GetCount()
    if n > 0 then logList:SetFirstItem(n - 1) end
end

-- ---------------------------------------------------------------------------
-- shared page-building helpers, handed to the page modules
-- ---------------------------------------------------------------------------

local api = {
    wx = wx, D = D, ID = ID, log = log, attrs = attrs, DIR = SDIR,
    NATIVE = NATIVE, GENERIC = GENERIC, PICKER = PICKER, COMBO = COMBO,
    ITEMS = ITEMS, EDITABLE = EDITABLE, BOOKCAT = BOOKCAT, ALLC = ALLC,
}

function api.G(name) return require("wx" .. name .. "_gen") end

-- The per-page ids of the C++ enum are not part of the port's contract; every
-- page control gets a unique id so EVT_MENU/EVT_BUTTON routing stays correct.
local _nextid = 1000
function api.nid()
    _nextid = _nextid + 1
    return _nextid
end

function api.H() return boxsizer_gen.Create(wx.HORIZONTAL) end
function api.V() return boxsizer_gen.Create(wx.VERTICAL) end

-- wxStaticBoxSizer(orient, parent, label) -> sizer, static box window
function api.sb(parent, orient, label)
    local box = staticbox_gen.Create(parent, wx.ID_ANY, label, -1, -1, -1, -1, 0)
    local sz  = staticboxsizer_gen.Create(box, orient)
    return sz, box
end
function api.sbV(parent, label) return api.sb(parent, wx.VERTICAL, label) end
function api.sbH(parent, label) return api.sb(parent, wx.HORIZONTAL, label) end

function api.add(sz, item, prop, flag, border)
    sz:Add(item, prop or 0, flag or 0, border or 0)
end
function api.sp(sz, px) sz:AddSpacer(px) end
function api.stretch(sz, prop) sz:AddStretchSpacer(prop or 1) end

-- WidgetsPage::CreateCheckBoxAndAddToSizer()
function api.cbBox(parent, sz, label, id)
    local c = checkbox_gen.Create(parent, id or wx.ID_ANY, label, -1, -1, -1, -1, 0)
    sz:Add(c, 0, wx.LEFT + wx.RIGHT, D)
    sz:AddSpacer(2)
    return c
end

function api.txt(parent, value, style, id)
    return textctrl_gen.Create(parent, id or wx.ID_ANY, value or "",
                               -1, -1, -1, -1, style or 0)
end

function api.st(parent, label, style, id)
    return statictext_gen.Create(parent, id or wx.ID_ANY, label, -1, -1, -1, -1, style or 0)
end

function api.btn(parent, id, label, style)
    return button_gen.Create(parent, id or wx.ID_ANY, label, -1, -1, -1, -1, style or 0)
end

-- WidgetsPage::CreateSizerWithText(): control + text ctrl in a row
function api.cswt(parent, ctrl, id)
    local row = api.H()
    local t = textctrl_gen.Create(parent, id or wx.ID_ANY, "", -1, -1, -1, -1,
                                  wx.TE_PROCESS_ENTER)
    row:Add(ctrl, 0, wx.RIGHT + wx.ALIGN_CENTER_VERTICAL, D)
    row:Add(t, 1, wx.LEFT + wx.ALIGN_CENTER_VERTICAL, D)
    return row, t, ctrl
end

function api.cswl(parent, label, id)
    return api.cswt(parent, api.st(parent, label), id)
end

function api.cswb(parent, btnId, label, id)
    return api.cswt(parent, api.btn(parent, btnId, label), id)
end

-- The kwxFFI Create() functions that take a list of strings read the choices
-- argument as a `const char*[]` (see kwxFFI wx_radiobox.cpp / wx_choice.cpp /
-- wx_textentry.cpp), not as a wxArrayString.  Build that array and keep both it
-- and the casted strings alive until the control has copied them.
api._arrays = {}

function api.arrstr(list)
    local n = #list
    local arr = ffi.new("const char*[?]", n > 0 and n or 1)
    local keep = {}
    for i = 1, n do
        keep[i] = ffi.cast("const char*", list[i])
        arr[i - 1] = keep[i]
    end
    api._arrays[#api._arrays + 1] = { arr = arr, keep = keep }
    return arr
end

function api.flush_arrays()
    for i = #api._arrays, 1, -1 do api._arrays[i] = nil end
end

-- Owned bitmaps returned to the caller (the caller deletes them).
api.keepalive = {}

-- wxBitmapBundle::FromSVGFile for the sample's own .svg assets.
function api.icon_bitmap(name, size)
    size = size or 16
    local bundle = require("wxbitmapbundle_gen").FromSVGFile(
        SDIR .. "/" .. name .. ".svg", size, size)
    if bundle == nil then return nil end
    local bmp = bundle:GetBitmap(size, size)
    bundle:Delete()
    return bmp
end

-- wxWidgets owns the page's children; Destroy() is the sample's own
-- "recreate the demo widget" path (wxSizer::ReplaceWindow keeps the flags).
function api.replace(sz, oldw, neww)
    if oldw then
        sz:ReplaceWindow(oldw, neww, false)
        oldw:Destroy()
    else
        sz:Add(neww, 0, 0, 0)
    end
end

-- ---------------------------------------------------------------------------
-- connect-to-widget-events (WidgetsApp::ConnectToWidgetEvents)
-- ---------------------------------------------------------------------------

local function widget_class(w)
    return (w and w._cls) or "wxWindow"
end

local function connect_widget_events(w)
    if not w then return end

    w:Connect(wx.EVT_SET_FOCUS, function(evt)
        log(string.format("Widget '%s' got focus", widget_class(w)))
    end)
    w:Connect(wx.EVT_KILL_FOCUS, function(evt)
        log(string.format("Widget '%s' lost focus", widget_class(w)))
    end)
    w:Connect(wx.EVT_ENTER_WINDOW, function(evt)
        log(string.format("Mouse entered into '%s'", widget_class(w)))
        local e = evt and event_gen.FromPtr(evt)
        if e then e:Skip(true) end
    end)
    w:Connect(wx.EVT_LEAVE_WINDOW, function(evt)
        log(string.format("Mouse left '%s'", widget_class(w)))
        local e = evt and event_gen.FromPtr(evt)
        if e then e:Skip(true) end
    end)
    w:Connect(wx.EVT_CONTEXT_MENU, function(evt)
        local e = evt and ctx_menu_event.FromPtr(evt)
        if not e then return end
        local x, y = ffi.new("int[1]"), ffi.new("int[1]")
        e:GetPosition(x, y)
        log(string.format("Context menu event for '%s' at %dx%d",
                          widget_class(w), x[0], y[0]))
        e:Skip(true)
    end)
end

-- ---------------------------------------------------------------------------
-- WidgetsPage (widgets.h)
-- ---------------------------------------------------------------------------

local Page = {}
Page.__index = Page

local function new_page(def, parent)
    local self = setmetatable({}, Page)
    self.def  = def
    self.page = scrolled_gen.Create(parent, wx.ID_ANY, -1, -1, -1, -1,
                                    wx.CLIP_CHILDREN + wx.TAB_TRAVERSAL)
    self.created = false
    return self
end

function Page:Widgets()
    if not self.widgets then
        self.widgets = self.def.widgets(self) or {}
    end
    return self.widgets
end

function Page:CreateContent()
    if self.created then return end
    self.created = true

    self.def.create(self)
    api.flush_arrays()

    self.page:SetScrollRate(10, 10)
    self.page:FitInside()

    for _, w in ipairs(self:Widgets()) do
        connect_widget_events(w)
    end
end

function Page:SetUpWidget()
    for _, w in ipairs(self:Widgets()) do
        if attrs.tooltip and attrs.tooltip ~= "" then w:SetToolTip(attrs.tooltip) end
        if attrs.font then w:SetFont(attrs.font) end
        if attrs.colFg then w:SetForegroundColour(attrs.colFg) end
        if attrs.colBg then w:SetBackgroundColour(attrs.colBg) end
        if attrs.dir ~= wx.Layout_Default then w:SetLayoutDirection(attrs.dir) end
        w:Enable(attrs.enabled)
        w:Show(attrs.show)
        if attrs.cursor then w:SetCursor(attrs.cursor) end
        w:SetWindowVariant(attrs.variant)
        w:Refresh()
    end

    if attrs.colPageBg then
        self.page:SetBackgroundColour(attrs.colPageBg)
        self.page:Refresh()
    end
end

function Page:Recreate()
    if not self.def.recreate then return end
    self.def.recreate(self)

    -- NotifyWidgetRecreation(): re-apply the attributes and the event
    -- connections to the freshly created widget(s).
    self.widgets = nil
    for _, w in ipairs(self:Widgets()) do
        connect_widget_events(w)
        w:Enable(attrs.enabled)
        w:Show(attrs.show)
        w:SetWindowVariant(attrs.variant)
        if attrs.dir ~= wx.Layout_Default then w:SetLayoutDirection(attrs.dir) end
        w:Refresh()
    end
    self.page:Layout()
end

-- ---------------------------------------------------------------------------
-- page modules
-- ---------------------------------------------------------------------------

local page_defs = {}

local function load_pages()
    local lists = {
        dofile(SDIR .. "/widgets_pages_a.lua"),
        dofile(SDIR .. "/widgets_pages_b.lua"),
    }
    for _, factory in ipairs(lists) do
        for _, def in ipairs(factory(api)) do
            page_defs[#page_defs + 1] = def
        end
    end
    -- WidgetsPageInfo inserts every page in label order (wxStrcmp).
    table.sort(page_defs, function(a, b) return a.label < b.label end)
end

-- ---------------------------------------------------------------------------
-- application / frame construction (WidgetsFrame ctor)
-- ---------------------------------------------------------------------------

local app = wx.App()

local TITLE = "wxMSW widgets demo"

local frame = wx.Frame(nil, TITLE, wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
                       wx.DEFAULT_SIZE, wx.DEFAULT_SIZE, wx.DEFAULT_FRAME_STYLE)

local frame_icon -- kept reachable for the whole run

local function apply_frame_icon(win)
    local bundle = require("wxbitmapbundle_gen").FromSVGFile(
        SDIR .. "/sample.svg", 32, 32)
    if bundle == nil then return end
    local icon = bundle:GetIcon(32, 32)
    bundle:Delete()
    if icon == nil then return end
    frame_icon = icon
    win:SetIcon(icon)          -- SetIcon copies the icon
    icon:Delete()
end

apply_frame_icon(frame)

local panel = wx.Panel(frame, wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
                       wx.DEFAULT_SIZE, wx.DEFAULT_SIZE, 0)

-- ---------------------------------------------------------------------------
-- menu bar
-- ---------------------------------------------------------------------------

local mbar = menubar_gen.Create(0)

local function build_widget_menu()
    local m = menu_gen.Create("", 0)

    m:Append(ID.SetTooltip, "Set &tooltip...\tCtrl-T", "", false)
    m:AppendSeparator()
    m:Append(ID.SetFgColour, "Set &foreground...\tCtrl-F", "", false)
    m:Append(ID.SetBgColour, "Set &background...\tCtrl-B", "", false)
    m:Append(ID.SetPageBg,   "Set &page background...\tShift-Ctrl-B", "", false)
    m:Append(ID.SetFont,     "Set f&ont...\tCtrl-O", "", false)
    m:AppendCheckItem(ID.Enable, "&Enable/disable\tCtrl-E", "")
    m:AppendCheckItem(ID.Show,   "Show/Hide", "")

    local borders = menu_gen.Create("", 0)
    borders:AppendRadioItem(ID.BorderDefault, "De&fault\tCtrl-Shift-9", "")
    borders:AppendRadioItem(ID.BorderNone,    "&None\tCtrl-Shift-0", "")
    borders:AppendRadioItem(ID.BorderSimple,  "&Simple\tCtrl-Shift-1", "")
    borders:AppendRadioItem(ID.BorderDouble,  "&Double\tCtrl-Shift-2", "")
    borders:AppendRadioItem(ID.BorderStatic,  "Stati&c\tCtrl-Shift-3", "")
    borders:AppendRadioItem(ID.BorderRaised,  "&Raised\tCtrl-Shift-4", "")
    borders:AppendRadioItem(ID.BorderSunken,  "S&unken\tCtrl-Shift-5", "")
    m:AppendSubMenu(borders, "Set &border", "")

    local variants = menu_gen.Create("", 0)
    variants:AppendRadioItem(ID.VariantMini,   "&Mini\tCtrl-Shift-6", "")
    variants:AppendRadioItem(ID.VariantSmall,  "&Small\tCtrl-Shift-7", "")
    variants:AppendRadioItem(ID.VariantNormal, "&Normal\tCtrl-Shift-8", "")
    variants:AppendRadioItem(ID.VariantLarge,  "&Large\tCtrl-Shift-9", "")
    m:AppendSubMenu(variants, "Set &variant", "")

    m:AppendSeparator()
    m:AppendCheckItem(ID.LayoutDirection, "Toggle &layout direction\tCtrl-L", "")
    m:Check(ID.LayoutDirection, false)

    m:AppendSeparator()
    m:AppendCheckItem(ID.GlobalBusyCursor, "Toggle &global busy cursor\tCtrl-Shift-U", "")
    m:AppendCheckItem(ID.BusyCursor, "Toggle b&usy cursor\tCtrl-U", "")

    m:AppendSeparator()
    m:Append(wx.ID_EXIT, "&Quit\tCtrl-Q", "", false)

    mbar:Append(m, "&Widget")
end

local function build_text_menu()
    local m = menu_gen.Create("", 0)
    m:AppendRadioItem(ID.TextEntryDisableAutoComplete, "&Disable auto-completion", "")
    m:AppendRadioItem(ID.TextEntryAutoCompleteFixed,   "Fixed-&list auto-completion", "")
    m:AppendRadioItem(ID.TextEntryAutoCompleteFilenames, "&Files names auto-completion", "")
    m:AppendRadioItem(ID.TextEntryAutoCompleteDirs,    "&Directories names auto-completion", "")
    m:AppendRadioItem(ID.TextEntryAutoCompleteCustom,  "&Custom auto-completion", "")
    m:AppendRadioItem(ID.TextEntryAutoCompleteKeyLength, "Custom with &min length", "")
    m:AppendSeparator()
    m:Append(ID.TextEntrySetHint, "Set help &hint", "", false)
    mbar:Append(m, "&Text")
end

build_widget_menu()
build_text_menu()
frame:SetMenuBar(mbar)

mbar:Check(ID.Enable, true)
mbar:Check(ID.Show, true)
mbar:Check(ID.VariantNormal, true)

-- ---------------------------------------------------------------------------
-- the book and its pages (WidgetsFrame::InitBook)
-- ---------------------------------------------------------------------------

local BOOK_STYLE = wx.BK_DEFAULT

local book = treebook_gen.Create(panel, ID.BookCtrl, -1, -1,
                                 panel:FromDIP(900), panel:FromDIP(500),
                                 BOOK_STYLE)

local page_by_index = {}   -- treebook index -> Page
local goto_menu_index = {} -- treebook index -> "Page" menu id
local all_page_defs  = {}  -- defs in "All controls" order (menu id order)

load_pages()

local function has_cat(def, cat)
    return bit.band(def.cats, bit.lshift(1, cat - 1)) ~= 0
end

-- WidgetsPage::ms_widgetPages icon order: every page constructor pushes its
-- own 16x16 icon into the image list, which the treebook then indexes.
local IMAGE_FOR_LABEL = {
    ActivityIndicator  = "activityindicator", BitmapCombobox = "bmpcombobox",
    Button             = "button",            CheckBox       = "checkbox",
    Choice             = "choice",            Choicebook     = "choicebk",
    ColourPicker       = "clrpicker",         Combobox       = "combobox",
    DatePicker         = "datepick",          DirCtrl        = "dirctrl",
    DirPicker          = "dirpicker",         EditableListbox = "listbox",
    FileCtrl           = "dirctrl",           FilePicker     = "filepicker",
    FontPicker         = "fontpicker",        Gauge          = "gauge",
    Header             = "header",            Hyperlink      = "hyperlnk",
    Listbox            = "listbox",           Listbook       = "listbook",
    Native             = "native",            Notebook       = "notebook",
    OwnerDrawnCombobox = "odcombobox",        Radio          = "radiobox",
    SearchCtrl         = "text",              Slider         = "slider",
    Spin               = "spinbtn",           Static         = "statbox",
    StaticBitmap       = "statbmp",           Text           = "text",
    TimePicker         = "timepick",          ToggleButton   = "toggle",
}

local function init_book()
    local menuPages = menu_gen.Create("", 0)
    local by_cat = {}          -- [cat] = array of { def=, page= }
    local nPage  = 0

    -- the treebook image list: page 0 is the sample icon used by the category
    -- nodes, the rest are pushed in page-construction order
    local images = require("wxbitmapbundlearray_gen").Create()
    local bundle_gen = require("wxbitmapbundle_gen")
    local function add_image(name)
        local bundle = bundle_gen.FromSVGFile(SDIR .. "/" .. name .. ".svg", 16, 16)
        if bundle then
            images:Add(bundle)     -- SetImages copies the bundles
            bundle:Delete()
        end
    end
    add_image("sample")

    -- first pass: create every page object and the "Page" menu
    for cat = 1, #CATEGORIES do
        nPage = nPage + 1                       -- category parent page
        by_cat[cat] = {}
        for _, def in ipairs(page_defs) do
            if has_cat(def, cat) then
                local pg = new_page(def, book)
                add_image(IMAGE_FOR_LABEL[def.label] or "sample")
                by_cat[cat][#by_cat[cat] + 1] = { def = def, page = pg }
                if cat == #CATEGORIES then
                    menuPages:AppendRadioItem(ID.GoToPage + nPage, def.label, "")
                    goto_menu_index[nPage] = ID.GoToPage + nPage
                    all_page_defs[#all_page_defs + 1] = def
                end
                nPage = nPage + 1
            end
        end
    end

    mbar:Append(menuPages, "&Page")
    book:SetImages(images)
    images:Delete()

    -- second pass: fill the treebook
    local imageId = 1
    local index   = 0
    for cat = 1, #CATEGORIES do
        book:AddPage(nil, CATEGORIES[cat], false, 0)
        page_by_index[index] = nil
        index = index + 1
        for _, e in ipairs(by_cat[cat]) do
            book:AddSubPage(e.page.page, e.def.label, false, imageId)
            page_by_index[index] = e.page
            index = index + 1
            imageId = imageId + 1
        end
    end

    -- ensure the top of the tree is shown, with a slightly wider tree pane
    local tree = book:GetTreeCtrl()
    if tree then
        local ts = tree:GetBestSize()
        tree:SetMinSize(math.floor(ts:GetWidth() * 9 / 8), -1)
    end

    -- OnGoToPage(): one EVT_MENU per item (EVT_MENU_RANGE is a macro that
    -- expands to a Bind() id range, which the wrapper's Connect does not take)
    for idx, id in pairs(goto_menu_index) do
        frame:Connect(wx.EVT_MENU, function(evt)
            book:SetSelection(idx)
        end, id)
    end
end

local function current_page()
    local sel = book:GetSelection()
    return page_by_index[sel]
end

-- ---------------------------------------------------------------------------
-- menu handlers
-- ---------------------------------------------------------------------------

local busyCursors = 0

local function colour_from_user(parent, initial)
    local col = colour_gen.CreateEmpty()
    F.wxGetColourFromUser(parent, initial, col)
    if not col:IsOk() then return nil end
    return col
end

local function on_set_tooltip()
    local dlg = textentrydlg_gen.Create(
        frame,
        "Tooltip text (may use \\n, leave empty to remove): ",
        "Widgets sample", attrs.tooltip, 0, -1, -1, -1, -1)
    if dlg == nil then return end
    local res = dlg:ShowModal()
    if res ~= wx.ID_OK then
        dlg:Destroy()
        return
    end
    local value = dlg:GetValue()
    dlg:Destroy()
    attrs.tooltip = (value:gsub("\\n", "\n"))
    local p = current_page()
    if p then p:SetUpWidget() end
end

local function on_set_colour(which)
    local p = current_page()
    if not p then return end

    if which == "fg" and not attrs.colFg then
        local c = colour_gen.CreateEmpty()
        p.page:GetForegroundColour(c)
        attrs.colFg = c
    elseif which == "bg" and not attrs.colBg then
        local c = colour_gen.CreateEmpty()
        p.page:GetBackgroundColour(c)
        attrs.colBg = c
    end

    local cur
    if which == "fg" then cur = attrs.colFg
    elseif which == "bg" then cur = attrs.colBg
    else
        cur = colour_gen.CreateEmpty()
        p.page:GetBackgroundColour(cur)
    end

    local col = colour_from_user(frame, cur)
    if not col then return end

    if which == "fg" then attrs.colFg = col
    elseif which == "bg" then attrs.colBg = col
    else attrs.colPageBg = col end

    p:SetUpWidget()
end

local function on_set_font()
    local p = current_page()
    if not p then return end
    if not attrs.font then
        local f = font_gen.CreateDefault()
        p.page:GetFont(f)
        attrs.font = f
    end

    local out = font_gen.CreateDefault()
    F.wxGetFontFromUser(frame, attrs.font, out)
    if not out:IsOk() then return end
    attrs.font = out

    p:SetUpWidget()
    p.page:Layout()
end

local BORDER_FOR_ID = {
    [ID.BorderNone]    = wx.BORDER_NONE,
    [ID.BorderStatic]  = wx.BORDER_STATIC,
    [ID.BorderSimple]  = wx.BORDER_SIMPLE,
    [ID.BorderRaised]  = wx.BORDER_RAISED,
    [ID.BorderSunken]  = wx.BORDER_SUNKEN,
    [ID.BorderDouble]  = wx.BORDER_DOUBLE,
    [ID.BorderDefault] = wx.BORDER_DEFAULT,
}

local VARIANT_FOR_ID = {
    [ID.VariantSmall]  = wx.WINDOW_VARIANT_SMALL,
    [ID.VariantMini]   = wx.WINDOW_VARIANT_MINI,
    [ID.VariantLarge]  = wx.WINDOW_VARIANT_LARGE,
    [ID.VariantNormal] = wx.WINDOW_VARIANT_NORMAL,
}

local function on_border(id)
    local border = BORDER_FOR_ID[id]
    if border == nil then border = wx.BORDER_DEFAULT end
    attrs.defaultFlags = bit.band(attrs.defaultFlags, bit.bnot(wx.BORDER_MASK))
    attrs.defaultFlags = bit.bor(attrs.defaultFlags, border)
    local p = current_page()
    if p then p:Recreate() end
end

local function on_variant(id)
    attrs.variant = VARIANT_FOR_ID[id] or wx.WINDOW_VARIANT_NORMAL
    local p = current_page()
    if p then
        p:SetUpWidget()
        p.page:Layout()
    end
end

local function text_entry()
    local p = current_page()
    if not p or not p.def.textentry then return nil end
    return p.def.textentry(p)
end

local function autocomplete_fixed(entry)
    local choices = {}
    for c = string.byte('a'), string.byte('z') - 1 do
        local ch = string.char(c)
        choices[#choices + 1] = ch .. ch
    end
    choices[#choices + 1] = "is this string for test?"
    choices[#choices + 1] = "this is a test string"
    choices[#choices + 1] = "this is another test string"
    choices[#choices + 1] = "this string is for test"

    local ok = entry:AutoComplete(#choices, api.arrstr(choices))
    api.flush_arrays()
    return ok
end

-- Borrowed wxString* handed to a C callback: read it without taking ownership
-- (_H.wxs_to_str would delete it).
local function borrowed_wxstring(ws_ptr)
    if ws_ptr == nil then return "" end
    local buf = C.kwxUtf8Buffer_Create(ws_ptr)
    local s = ffi.string(C.kwxUtf8Buffer_Data(buf))
    C.kwxUtf8Buffer_Delete(buf)
    return s
end

local completer_gen = require("kwxtextcompletersimple_gen")
local arrstr_gen    = require("wxarraystring_gen")

-- WidgetsFrame::DoUseCustomAutoComplete(): a real wxTextCompleterSimple that
-- completes "NNN XX" strings, built lazily from the typed prefix.
local _completers = {}

local function use_custom_auto_complete(min_length)
    local entry = text_entry()
    if not entry then return end

    local completer = completer_gen.Create(nil)
    if not completer then return end

    local cb = ffi.cast("void (*)(void*, void*, void*)",
        function(pObject, prefix_ptr, result_ptr)
            local prefix = borrowed_wxstring(prefix_ptr)
            local res = arrstr_gen.FromPtr(result_ptr, false)
            local function add(s) res:Add(s) end

            local function fill()
                if #prefix < min_length then return end
                if not prefix:match("^%d") then return end
                if #prefix == 1 then
                    for i = 0, 9 do
                        for j = 0, 9 do
                            add(prefix .. string.format("%02d", 10 * i + j))
                        end
                    end
                    return
                elseif not prefix:match("^%d%d") then
                    return
                end
                if #prefix == 2 then
                    for i = 0, 9 do add(prefix .. tostring(i)) end
                    return
                elseif not prefix:match("^%d%d%d") then
                    return
                end
                local prefix2 = prefix
                if #prefix == 3 then
                    prefix2 = prefix .. " "
                elseif prefix:sub(4, 4) ~= " " then
                    return
                end
                if #prefix2 == 4 then
                    for c = string.byte('a'), string.byte('z') do
                        for d = string.byte('a'), string.byte('z') do
                            add(prefix2 .. string.char(c) .. string.char(d))
                        end
                    end
                    return
                elseif not prefix:sub(5, 5):match("%l") then
                    return
                end
                if #prefix == 5 then
                    for c = string.byte('a'), string.byte('z') do
                        add(prefix .. string.char(c))
                    end
                end
            end
            fill()

            log(string.format(
                "Returning %d possible completions for prefix \"%s\"",
                res:GetCount(), prefix))
        end)

    completer:SetOnGetCompletions(cb)
    _completers[#_completers + 1] = { completer = completer, cb = cb }

    -- The control takes ownership of the completer and deletes it.
    local ok = entry:AutoCompleteCompleter(completer)
    log(ok and "Enabled custom auto completer for \"NNN XX\" items "
                .. "(where N is a digit and X is a letter)."
            or "AutoComplete() failed.")
end

local function on_autocomplete(which)
    local entry = text_entry()
    if not entry then return end

    if which == "disable" then
        local ok = entry:AutoComplete(0, nil)
        log(ok and "Disabled auto completion." or "AutoComplete() failed.")
    elseif which == "fixed" then
        log(autocomplete_fixed(entry) and
            "Enabled auto completion of a set of fixed strings." or
            "AutoComplete() failed.")
    elseif which == "filenames" then
        log(entry:AutoCompleteFileNames() and
            "Enabled auto completion of file names." or
            "AutoCompleteFileNames() failed.")
    elseif which == "dirs" then
        log(entry:AutoCompleteDirectories() and
            "Enabled auto completion of directories." or
            "AutoCompleteDirectories() failed.")
    end
end

local function on_set_hint()
    local entry = text_entry()
    if not entry then return end
    local hint = F.wxGetTextFromUserEx("Text hint:", "Widgets sample",
                                       "Type here", frame, -1, -1, 1)
    if hint == nil or hint == "" then return end
    log(entry:SetHint(hint) and string.format('Set hint to "%s".', hint)
                            or "Text hints not supported.")
end

local function checked(evt)
    if not evt then return false end
    local e = cmd_event.FromPtr(evt)
    return e ~= nil and e:IsChecked()
end

-- Widget menu
frame:Connect(wx.EVT_MENU, function(evt) on_set_tooltip() end, ID.SetTooltip)
frame:Connect(wx.EVT_MENU, function(evt) on_set_colour("fg") end, ID.SetFgColour)
frame:Connect(wx.EVT_MENU, function(evt) on_set_colour("bg") end, ID.SetBgColour)
frame:Connect(wx.EVT_MENU, function(evt) on_set_colour("page") end, ID.SetPageBg)
frame:Connect(wx.EVT_MENU, function(evt) on_set_font() end, ID.SetFont)

frame:Connect(wx.EVT_MENU, function(evt)
    attrs.enabled = checked(evt)
    local p = current_page()
    if p then p:SetUpWidget() end
end, ID.Enable)

frame:Connect(wx.EVT_MENU, function(evt)
    attrs.show = checked(evt)
    local p = current_page()
    if p then p:SetUpWidget() end
end, ID.Show)

-- The C++ code binds EVT_MENU_RANGE; the wrapper's Connect takes one id, so
-- the same range is connected id by id here.
for _, id in ipairs({ ID.BorderNone, ID.BorderStatic, ID.BorderSimple,
                      ID.BorderRaised, ID.BorderSunken, ID.BorderDouble,
                      ID.BorderDefault }) do
    frame:Connect(wx.EVT_MENU, function(evt) on_border(id) end, id)
end

for _, id in ipairs({ ID.VariantMini, ID.VariantSmall, ID.VariantNormal,
                      ID.VariantLarge }) do
    frame:Connect(wx.EVT_MENU, function(evt) on_variant(id) end, id)
end

frame:Connect(wx.EVT_MENU, function(evt)
    local dir = attrs.dir
    if dir == wx.Layout_Default then dir = wx.Layout_LeftToRight end
    attrs.dir = (dir == wx.Layout_LeftToRight) and wx.Layout_RightToLeft
                                                 or wx.Layout_LeftToRight
    local p = current_page()
    if p then p:SetUpWidget() end
end, ID.LayoutDirection)

frame:Connect(wx.EVT_MENU, function(evt)
    if checked(evt) then
        F.wxBeginBusyCursor()
        busyCursors = busyCursors + 1
    elseif busyCursors > 0 then
        F.wxEndBusyCursor()
        busyCursors = busyCursors - 1
    end
end, ID.GlobalBusyCursor)

frame:Connect(wx.EVT_MENU, function(evt)
    if checked(evt) then
        attrs.cursor = cursor_gen.CreateFromStock(wx.CURSOR_WAIT)
    else
        attrs.cursor = nil
    end
    local p = current_page()
    if p then p:SetUpWidget() end
end, ID.BusyCursor)

-- Text menu
frame:Connect(wx.EVT_MENU, function(evt) on_autocomplete("disable") end,
              ID.TextEntryDisableAutoComplete)
frame:Connect(wx.EVT_MENU, function(evt) on_autocomplete("fixed") end,
              ID.TextEntryAutoCompleteFixed)
frame:Connect(wx.EVT_MENU, function(evt) on_autocomplete("filenames") end,
              ID.TextEntryAutoCompleteFilenames)
frame:Connect(wx.EVT_MENU, function(evt) on_autocomplete("dirs") end,
              ID.TextEntryAutoCompleteDirs)
frame:Connect(wx.EVT_MENU, function(evt) use_custom_auto_complete(1) end,
              ID.TextEntryAutoCompleteCustom)
frame:Connect(wx.EVT_MENU, function(evt)
    local res = F.wxGetNumberFromUser(
        "The auto-completion is triggered if and only if\n" ..
        "the length of the search key (prefix) is at least [LENGTH].\n" ..
        "Hint: 0 disables the length check completely.",
        "Enter the minimum key length:", "Minimum key length", 1, 0, 100,
        frame, -1, -1)
    if res == -1 then return end
    log(string.format("The minimum key length for autocomplete is %d.", res))
    use_custom_auto_complete(res)
end, ID.TextEntryAutoCompleteKeyLength)
frame:Connect(wx.EVT_MENU, function(evt) on_set_hint() end, ID.TextEntrySetHint)

-- exit (wxID_EXIT and the "E&xit" button)
local function on_exit()
    frame:Close(false)
end

frame:Connect(wx.EVT_MENU, function(evt) on_exit() end, wx.ID_EXIT)

-- ---------------------------------------------------------------------------
-- Page menu (EVT_MENU_RANGE in C++) and the book's page events
-- ---------------------------------------------------------------------------

local function on_page_changing(evt)
    if not evt then return end
    local e  = book_event.FromPtr(evt)
    if not e then return end
    local sel = e:GetSelection()
    if book:GetPage(sel) == nil then e:Veto() end
end

local function on_page_changed(evt)
    local sel = book:GetSelection()

    -- adjust the "Page" menu selection (menu id == Widgets_GoToPage + page)
    if goto_menu_index[sel] then
        mbar:Check(goto_menu_index[sel], true)
    end
    mbar:Check(ID.BusyCursor, false)

    local p = current_page()
    if p and not p.created then p:CreateContent() end
    if p then p:SetUpWidget() end
end

book:Connect(wx.EVT_TREEBOOK_PAGE_CHANGING, on_page_changing)
book:Connect(wx.EVT_TREEBOOK_PAGE_CHANGED,  on_page_changed)

-- ---------------------------------------------------------------------------
-- log pane (sizerTop / sizerDown)
-- ---------------------------------------------------------------------------

local sizerTop = boxsizer_gen.Create(wx.VERTICAL)

init_book()

-- Theme menu is appended after InitBook in the C++ ctor
local menuTheme = menu_gen.Create("", 0)
menuTheme:AppendRadioItem(ID.ThemeSystem, "&System", "")
menuTheme:AppendRadioItem(ID.ThemeLight,  "&Light", "")
menuTheme:AppendRadioItem(ID.ThemeDark,   "&Dark", "")
mbar:Append(menuTheme, "T&heme")

local THEME_APPEARANCE = {
    [ID.ThemeSystem] = wx.App_Appearance_System,
    [ID.ThemeLight]  = wx.App_Appearance_Light,
    [ID.ThemeDark]   = wx.App_Appearance_Dark,
}

local function on_theme(id)
    local the_app = app_gen.GetApp()
    if the_app == nil then return end
    if the_app:SetAppearance(THEME_APPEARANCE[id]) == wx.App_AppearanceResult_Failure then
        log("SetAppearance: failure")
    end
end
frame:Connect(wx.EVT_MENU, function(evt) on_theme(ID.ThemeSystem) end, ID.ThemeSystem)
frame:Connect(wx.EVT_MENU, function(evt) on_theme(ID.ThemeLight)  end, ID.ThemeLight)
frame:Connect(wx.EVT_MENU, function(evt) on_theme(ID.ThemeDark)   end, ID.ThemeDark)

local sizerDown, sizerDownBox = api.sbV(panel, "&Log window")

logList = listbox_gen.Create(sizerDownBox, wx.ID_ANY, -1, -1, -1, -1, 0, nil, 0)
sizerDown:Add(logList, 1, wx.EXPAND + wx.ALL, D)
sizerDown:SetMinSize(panel:FromDIP(100), panel:FromDIP(150))

local sizerBtns = boxsizer_gen.Create(wx.HORIZONTAL)
local btnClear = button_gen.Create(sizerDownBox, ID.ClearLog, "Clear &log",
                                   -1, -1, -1, -1, 0)
sizerBtns:Add(btnClear, 0, 0, 0)
sizerBtns:AddSpacer(panel:FromDIP(10))
local btnQuit = button_gen.Create(sizerDownBox, ID.Quit, "E&xit",
                                  -1, -1, -1, -1, 0)
sizerBtns:Add(btnQuit, 0, 0, 0)
sizerDown:Add(sizerBtns, 0, wx.ALL, D)

sizerTop:Add(book, 1, wx.EXPAND + wx.LEFT + wx.RIGHT, 2 * D)
sizerTop:AddSpacer(panel:FromDIP(5))
sizerTop:Add(sizerDown, 0, wx.EXPAND + wx.LEFT + wx.RIGHT + wx.BOTTOM, 2 * D)

panel:SetSizer(sizerTop)

frame:Connect(wx.EVT_BUTTON, function(evt) logList:Clear() end, ID.ClearLog)
frame:Connect(wx.EVT_BUTTON, function(evt) on_exit() end, ID.Quit)

-- ---------------------------------------------------------------------------
-- initial size and page (wxPersistentRegisterAndRestore)
-- ---------------------------------------------------------------------------

local sizeSet = F.wxPersistentRegisterAndRestore(frame, "Main")
local best = panel:GetBestSize()
local w, h = 940, 700
if best ~= nil then
    w, h = best:GetWidth(), best:GetHeight()
end
if not sizeSet then frame:SetClientSize(w, h) end
frame:SetMinClientSize(w, h)

-- for the treebook page #0 is the empty category node: select the first page
-- with contents unless a previous run's selection was restored
local pageSet = F.wxPersistentRegisterAndRestoreTreebook(book, "Book")
if not pageSet or book:GetCurrentPage() == nil then
    book:SetSelection(1)
end

frame:Show(true)
frame:Center()

app:MainLoop()

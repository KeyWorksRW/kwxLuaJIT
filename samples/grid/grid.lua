--[[
    grid.lua — LuaJIT port of wxWidgets samples/grid/griddemo.cpp

    Source: C:/rwCode/wxSamples/src/grid/griddemo.cpp (+ griddemo.h)

    Reproduces:
      GridApp::OnInit           -> wx.App() + GridFrame + MainLoop
      GridFrame                 -> "wxWidgets grid class demo", File/Grid/Colours/
                                   Edit/Select/Autosize/Help menus, wxGrid 1000x100
                                   plus the wxLogTextCtrl log window
      BigGridFrame              -> "Plugin Virtual Table", a virtual table driven by
                                   kwxGridTable callbacks
      BugsGridFrame             -> "Bugs table", typed columns over a string table
      TabularGridFrame          -> "Tabular table", sortable/reorderable columns
      OnGridRender              -> wxGrid::Render into a bitmap shown in
                                   "Grid Render"

    Generated modules used below the `wx` wrapper (the wrapper exposes only
    Frame/Panel/Button/StaticText/TextCtrl/BoxSizer/App and constants):
      kwxffi_idiomatic_gen          class tables (wxGrid, wxGridCellAttr, ...)
      kwxffi_freefuncs_idiomatic_gen wxAboutBox, wxGetNumberFromUser,
                                    wxGetColourFromUserEx, wxGetFontFromUser,
                                    LogMessage/LogError
      kwxffi_gen                    C.wxLog_SetActiveTarget / wxLog_DisableTimestamp,
                                    C.wxBitmapBundle_FromSVGFile/GetBitmap/Delete,
                                    C.wxSize_GetWidth/GetHeight (wxSize has no FromPtr)
      wxlogtextctrl_gen, wxicon_gen  log target and frame icon

    The wxWidgets extension points the sample derives from are driven through
    the kwxFFI callback hooks:
      kwxGridCellRendererHook / kwxGridCellActivatableEditorHook
          MyGridCellRenderer, MyGridStarRenderer, MyGridStarEditor
      kwxGridTable
          BigGridTable (BigGridFrame virtual table)
      kwxGridCellAttrProviderHook / kwxGridColumnHeaderRendererHook
          CustomColumnHeadersProvider + CustomColumnHeaderRenderer
            (bold italic labels, background-only border, red highlight)
]]

local ffi = require("ffi")
local bit = require("bit")
local wx  = require("wx")

local gwx = require("kwxffi_idiomatic_gen")
local C   = require("kwxffi_gen")
local ff  = require("kwxffi_freefuncs_idiomatic_gen")

local wxlogtextctrl_gen = require("wxlogtextctrl_gen")
local wxicon_gen        = require("wxicon_gen")

-- ---------------------------------------------------------------------------
-- Class tables (the `wx` namespace has no wx.Grid & co.)
-- ---------------------------------------------------------------------------

local Grid                  = gwx.wxGrid
local GridTableBase         = gwx.wxGridTableBase
local GridStringTable       = gwx.wxGridStringTable
local GridCellAttr          = gwx.wxGridCellAttr
local GridFitMode           = gwx.wxGridFitMode
local GridCellAutoWrapRend  = gwx.wxGridCellAutoWrapStringRenderer
local GridCellAutoWrapEdit  = gwx.wxGridCellAutoWrapStringEditor
local GridCellBoolRend      = gwx.wxGridCellBoolRenderer
local GridCellBoolEdit      = gwx.wxGridCellBoolEditor
local GridCellNumberEdit    = gwx.wxGridCellNumberEditor
local GridCellChoiceEdit    = gwx.wxGridCellChoiceEditor
local GridCellDateRend      = gwx.wxGridCellDateRenderer
local GridCellDateEdit      = gwx.wxGridCellDateEditor
local GridBlockCoordsArray  = gwx.wxGridBlockCoordsArray
local GridCellCoordsArray   = gwx.wxGridCellCoordsArray
local ArrayString           = gwx.wxArrayString
local Colour                = gwx.wxColour
local Brush                 = gwx.wxBrush
local Bitmap                = gwx.wxBitmap
local MemoryDC              = gwx.wxMemoryDC
local PaintDC               = gwx.wxPaintDC
local DateTime              = gwx.wxDateTime
local AboutDialogInfo       = gwx.wxAboutDialogInfo
local CheckBox              = gwx.wxCheckBox
local Button                = gwx.wxButton
local Menu                  = gwx.wxMenu
local MenuBar               = gwx.wxMenuBar
local Font                  = gwx.wxFont
local Pen                   = gwx.wxPen
local DC                    = gwx.wxDC
local GridTableHook         = gwx.kwxGridTable
local GridAttrProviderHook  = gwx.kwxGridCellAttrProviderHook
local GridHeaderRendHook    = gwx.kwxGridColumnHeaderRendererHook
local TextCtrl              = wx.TextCtrl
local StaticText            = wx.StaticText
local BoxSizer              = wx.BoxSizer

local GridEvent             = gwx.wxGridEvent
local GridSizeEvent         = gwx.wxGridSizeEvent
local GridRangeSelectEvent  = gwx.wxGridRangeSelectEvent
local CommandEvent          = gwx.wxCommandEvent
local ContextMenuEvent      = gwx.wxContextMenuEvent
local Event                 = gwx.wxEvent

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local frame_icon -- kept reachable for the whole run

local function script_directory()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    local dir = src:match("^(.*)[/\\][^/\\]*$")
    return dir or ""
end

-- wxLogMessage/wxLogError treat the text as a printf format string; the kwxFFI
-- entry points take a single wxString, so double the percent signs.
local function log_message(text)
    ff.LogMessage((tostring(text):gsub("%%", "%%%%")))
end

local function log_error(text)
    ff.LogError((tostring(text):gsub("%%", "%%%%")))
end

local function must(obj, what)
    if obj == nil then error("grid sample: failed to create " .. what) end
    return obj
end

-- wxSize has no FromPtr() in the generated bindings; read the two ints through
-- the same C entry points the wxSize wrapper uses.
local function size_parts(raw_size)
    if raw_size == nil then return 0, 0 end
    return C.wxSize_GetWidth(raw_size), C.wxSize_GetHeight(raw_size)
end

-- A wxString* handed to a callback is borrowed: convert it without freeing it.
local function wxstring_text(ws_ptr)
    if ws_ptr == nil then return "" end
    local buf = C.kwxUtf8Buffer_Create(ws_ptr)
    local text = ffi.string(C.kwxUtf8Buffer_Data(buf))
    C.kwxUtf8Buffer_Delete(buf)
    return text
end

local function new_attr()
    local ptr = GridCellAttr.Ctor()
    if ptr == nil then return nil end
    return GridCellAttr.FromPtr(ptr, true)
end

local colour_cache = {}
local function rgb(r, g, b)
    -- wx copies the colour it is given; keep one wrapper per value so the
    -- temporaries are not leaked.
    local key = r .. ":" .. g .. ":" .. b
    local c = colour_cache[key]
    if c == nil then
        c = must(Colour.CreateRGB(r, g, b, 255), "wxColour")
        colour_cache[key] = c
    end
    return c
end

local function new_renderer(module)
    local ptr = module.Ctor()
    if ptr == nil then return nil end
    return module.FromPtr(ptr, true)
end

local function new_editor(module, ...)
    local ptr = module.Ctor(...)
    if ptr == nil then return nil end
    return module.FromPtr(ptr, true)
end

local LIGHT_GREY = { 192, 192, 192 }
local RED        = { 255, 0, 0 }
local GREEN      = { 0, 255, 0 }
local BLUE       = { 0, 0, 255 }

-- wxFont_CreateFromStock ids are kwxFFI's own remapping (src/wx_font.cpp:91):
-- 0 = wxITALIC_FONT, 1 = wxNORMAL_FONT, 2 = wxSMALL_FONT, 3 = wxSWISS_FONT.
-- This is not the wxStockGDI enum, where FONT_ITALIC has a different value.
local STOCK_ITALIC_FONT = 0

-- Every frame state table, so the Lua objects C++ may call back into (event
-- handlers and FFI hook callbacks) stay reachable for the whole run.
local open_windows = {}

-- ---------------------------------------------------------------------------
-- IDs (griddemo.h enum, ID.TOGGLEROWLABELS = 100, sequential)
-- ---------------------------------------------------------------------------

-- Collapsed into one table: LuaJIT allows at most 60 upvalues per function,
-- and create_grid_frame() references every id below.
local ID = {
    TOGGLEROWLABELS        = 100,
    TOGGLECOLLABELS        = 101,
    TOGGLEEDIT             = 102,
    TOGGLEROWSIZING        = 103,
    TOGGLECOLSIZING        = 104,
    TOGGLEROWLABELSIZING   = 105,
    TOGGLECOLLABELSIZING   = 106,
    TOGGLEROWMOVING        = 107,
    TOGGLECOLMOVING        = 108,
    TOGGLECOLHIDING        = 109,
    TOGGLEGRIDSIZING       = 110,
    TOGGLEGRIDDRAGCELL     = 111,
    TOGGLEGRIDLINES        = 112,
    AUTOSIZECOLS           = 113,
    CELLOVERFLOW           = 114,
    TOGGLE_CHECKERED_CELLS = 115,
    TOGGLE_COLOURED_CELLS  = 116,
    HIDECOL                = 117,
    SHOWCOL                = 118,
    HIDEROW                = 119,
    SHOWROW                = 120,
    RESIZECELL             = 121,
    SETLABELCOLOUR         = 122,
    SETLABELTEXTCOLOUR     = 123,
    SETLABEL_FONT          = 124,
    ROWLABELALIGN          = 125,
    ROWLABELHORIZALIGN     = 126,
    ROWLABELVERTALIGN      = 127,
    COLLABELALIGN          = 128,
    COLLABELHORIZALIGN     = 129,
    COLLABELVERTALIGN      = 130,
    CORNERLABELALIGN       = 131,
    CORNERLABELHORIZALIGN  = 132,
    CORNERLABELVERTALIGN   = 133,
    CORNERLABELORIENTATION = 134,
    COLDEFAULTHEADER       = 135,
    COLNATIVEHEADER        = 136,
    COLNATIVELABELS        = 137,
    COLCUSTOMHEADER        = 138,
    TAB_STOP               = 139,
    TAB_WRAP               = 140,
    TAB_LEAVE              = 141,
    TAB_CUSTOM             = 142,
    GRIDLINECOLOUR         = 143,
    INSERTROW              = 144,
    INSERTCOL              = 145,
    DELETEROW              = 146,
    DELETECOL              = 147,
    CLEARGRID              = 148,
    EDITCELL               = 149,
    SETCORNERLABEL         = 150,
    SHOWSEL                = 151,
    CHANGESEL              = 152,
    SELCELLS               = 153,
    SELROWS                = 154,
    SELCOLS                = 155,
    SELROWSORCOLS          = 156,
    SELNONE                = 157,
    SET_CELL_FG_COLOUR     = 158,
    SET_CELL_BG_COLOUR     = 159,
    SET_CELL_HL_COLOUR     = 160,
    SET_SELECTION_FG_COLOUR = 161,
    SET_SELECTION_BG_COLOUR = 162,
    SET_FROZEN_BORDER      = 163,
    VTABLE                 = 164,
    BUGS_TABLE             = 165,
    TABULAR_TABLE          = 166,
    SELECT_OVERLAY         = 167,
    SELECT_UNSELECT        = 168,
    SELECT_ALL             = 169,
    SELECT_ROW             = 170,
    SELECT_COL             = 171,
    SELECT_CELL            = 172,
    DESELECT_ALL           = 173,
    DESELECT_ROW           = 174,
    DESELECT_COL           = 175,
    DESELECT_CELL          = 176,
    SIZE_ROW               = 177,
    SIZE_COL               = 178,
    SIZE_ROW_LABEL         = 179,
    SIZE_COL_LABEL         = 180,
    SIZE_LABELS_COL        = 181,
    SIZE_LABELS_ROW        = 182,
    SIZE_GRID              = 183,
    FREEZE_OR_THAW         = 184,
    SET_HIGHLIGHT_WIDTH    = 185,
    SET_RO_HIGHLIGHT_WIDTH = 186,
    RENDER_ROW_LABEL       = 188,
    RENDER_COL_LABEL       = 189,
    RENDER_GRID_LINES      = 190,
    RENDER_GRID_BORDER     = 191,
    RENDER_SELECT_HLIGHT   = 192,
    RENDER_LOMETRIC        = 193,
    RENDER_COORDS          = 194,
    RENDER_ZOOM            = 195,
    RENDER_MARGIN          = 196,
    RENDER_DEFAULT_SIZE    = 197,
}

-- ---------------------------------------------------------------------------
-- Frame icon (SetIcon(wxICON(sample)))
-- ---------------------------------------------------------------------------

local function apply_frame_icon(win)
    local dir = script_directory()
    local path = (dir ~= "" and (dir .. "/") or "") .. "sample.svg"

    local ws_path = wx.wxString(path)
    local bundle = C.wxBitmapBundle_FromSVGFile(ws_path, 32, 32)
    wx.wxStringDelete(ws_path)
    if bundle == nil then return end

    local bitmap = C.wxBitmapBundle_GetBitmap(bundle, 32, 32)
    if bitmap ~= nil then
        local icon = wxicon_gen.CreateDefault()
        if icon ~= nil then
            icon:CopyFromBitmap(bitmap)
            win:SetIcon(icon)
            frame_icon = icon
        end
        C.wxBitmap_Delete(bitmap)
    end
    C.wxBitmapBundle_Delete(bundle)
end

-- ---------------------------------------------------------------------------
-- GridFrame
-- ---------------------------------------------------------------------------

-- Forward declarations: the GridFrame menu handlers create these frames and
-- are defined before the frame builders below.
local create_bugs_frame
local create_tabular_frame
local create_big_grid_frame

local function create_grid_frame()
    local S = {
        add_to_sel = false,
        size_grid = 10000,     -- static long s_sizeGrid in OnVTable()
        render_bitmap = nil,
        custom_tab_cb = nil,
        checkered_on = false,  -- static bool s_checkeredOn
        coloured_on = false,   -- static bool s_colouredOn
        use_custom_headers = false, -- CustomColumnHeadersProvider::m_useCustom
    }

    local frame = wx.Frame(nil, "wxWidgets grid class demo",
                           wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
                           wx.DEFAULT_SIZE, wx.DEFAULT_SIZE,
                           wx.DEFAULT_FRAME_STYLE)
    apply_frame_icon(frame)

    -- ----------------------------------------------------------------- menus

    local file_menu = Menu.Create("", 0)
    local setup_menu = Menu.Create("", 0)
    local grid_menu = Menu.Create("", 0)
    local colours_menu = Menu.Create("", 0)
    local edit_menu = Menu.Create("", 0)
    local select_menu = Menu.Create("", 0)
    local autosize_menu = Menu.Create("", 0)
    local help_menu = Menu.Create("", 0)

    file_menu:Append(ID.VTABLE, "&Virtual table test\tCtrl-V", "", false)
    file_menu:Append(ID.BUGS_TABLE, "&Bugs table test\tCtrl-B", "", false)
    file_menu:Append(ID.TABULAR_TABLE, "&Tabular table test\tCtrl-T", "", false)
    file_menu:AppendSeparator()

    setup_menu:AppendCheckItem(ID.RENDER_ROW_LABEL, "Render row labels", "")
    setup_menu:AppendCheckItem(ID.RENDER_COL_LABEL, "Render column labels", "")
    setup_menu:AppendCheckItem(ID.RENDER_GRID_LINES, "Render grid cell lines", "")
    setup_menu:AppendCheckItem(ID.RENDER_GRID_BORDER, "Render border", "")
    setup_menu:AppendCheckItem(ID.RENDER_SELECT_HLIGHT, "Render selection highlight", "")
    setup_menu:AppendSeparator()
    setup_menu:AppendCheckItem(ID.RENDER_LOMETRIC, "Use LOMETRIC mapping mode", "")
    setup_menu:AppendCheckItem(ID.RENDER_DEFAULT_SIZE, "Use wxDefaultSize", "")
    setup_menu:AppendCheckItem(ID.RENDER_MARGIN, "Logical 50 unit margin", "")
    setup_menu:AppendCheckItem(ID.RENDER_ZOOM, "Zoom 125%", "")

    file_menu:AppendSubMenu(setup_menu, "Render setup", "")
    file_menu:Append(wx.ID_PRINT, "Render", "", false)
    file_menu:Append(ID.RENDER_COORDS, "Render G5:P30", "", false)
    file_menu:AppendSeparator()
    file_menu:Append(wx.ID_CLEAR, "Clear &log\tCtrl-L", "", false)
    file_menu:AppendSeparator()
    file_menu:Append(wx.ID_EXIT, "E&xit\tAlt-X", "", false)

    grid_menu:AppendCheckItem(ID.TOGGLEROWLABELS, "&Row labels", "")
    grid_menu:AppendCheckItem(ID.TOGGLECOLLABELS, "&Col labels", "")
    grid_menu:AppendCheckItem(ID.TOGGLEEDIT, "&Editable", "")
    grid_menu:AppendCheckItem(ID.TOGGLEROWSIZING, "Ro&w drag-resize", "")
    grid_menu:AppendCheckItem(ID.TOGGLECOLSIZING, "C&ol drag-resize", "")
    grid_menu:AppendCheckItem(ID.TOGGLEROWLABELSIZING, "Row label drag-resize", "")
    grid_menu:AppendCheckItem(ID.TOGGLECOLLABELSIZING, "Col label drag-resize", "")
    grid_menu:AppendCheckItem(ID.TOGGLEROWMOVING, "Row drag-move", "")
    grid_menu:AppendCheckItem(ID.TOGGLECOLMOVING, "Col drag-&move", "")
    grid_menu:AppendCheckItem(ID.TOGGLECOLHIDING, "Col hiding popup menu", "")
    grid_menu:AppendCheckItem(ID.TOGGLEGRIDSIZING, "&Grid drag-resize", "")
    grid_menu:AppendCheckItem(ID.TOGGLEGRIDDRAGCELL, "&Grid drag-cell", "")
    grid_menu:AppendCheckItem(ID.TOGGLEGRIDLINES, "&Grid Lines", "")
    grid_menu:AppendCheckItem(ID.SET_HIGHLIGHT_WIDTH, "&Set Cell Highlight Width...", "")
    grid_menu:AppendCheckItem(ID.SET_RO_HIGHLIGHT_WIDTH, "&Set Cell RO Highlight Width...", "")
    grid_menu:AppendCheckItem(ID.AUTOSIZECOLS, "&Auto-size cols", "")
    grid_menu:AppendCheckItem(ID.CELLOVERFLOW, "&Overflow cells", "")
    grid_menu:AppendCheckItem(ID.RESIZECELL, "&Resize cell (7,1)", "")
    grid_menu:AppendCheckItem(ID.TOGGLE_CHECKERED_CELLS, "Toggle Chec&kered Cells\tCtrl+Shift+K", "")
    grid_menu:AppendCheckItem(ID.TOGGLE_COLOURED_CELLS, "Toggle Co&loured Cells\tCtrl+Shift+L", "")
    grid_menu:Append(ID.HIDECOL, "&Hide column A", "", false)
    grid_menu:Append(ID.SHOWCOL, "&Show column A", "", false)
    grid_menu:Append(ID.HIDEROW, "&Hide row 2", "", false)
    grid_menu:Append(ID.SHOWROW, "&Show row 2", "", false)

    local row_label_menu = Menu.Create("", 0)
    grid_menu:AppendSub(ID.ROWLABELALIGN, "R&ow label alignment", row_label_menu,
                        "Change alignment of row labels")
    row_label_menu:AppendRadioItem(ID.ROWLABELHORIZALIGN, "&Horizontal", "")
    row_label_menu:AppendRadioItem(ID.ROWLABELVERTALIGN, "&Vertical", "")

    local col_label_menu = Menu.Create("", 0)
    grid_menu:AppendSub(ID.COLLABELALIGN, "Col l&abel alignment", col_label_menu,
                        "Change alignment of col labels")
    col_label_menu:AppendRadioItem(ID.COLLABELHORIZALIGN, "&Horizontal", "")
    col_label_menu:AppendRadioItem(ID.COLLABELVERTALIGN, "&Vertical", "")

    local corner_label_menu = Menu.Create("", 0)
    grid_menu:AppendSub(ID.CORNERLABELALIGN, "Corner label alignment", corner_label_menu,
                        "Change alignment of corner label")
    corner_label_menu:AppendRadioItem(ID.CORNERLABELHORIZALIGN, "&Horizontal", "")
    corner_label_menu:AppendRadioItem(ID.CORNERLABELVERTALIGN, "&Vertical", "")

    grid_menu:Append(ID.CORNERLABELORIENTATION, "Toggle corner label orientation", "", false)

    -- C++ reuses ID.ROWLABELALIGN for this submenu item as well.
    local col_header_menu = Menu.Create("", 0)
    grid_menu:AppendSub(ID.ROWLABELALIGN, "Col header style", col_header_menu,
                        "Change style of col header")
    col_header_menu:AppendRadioItem(ID.COLDEFAULTHEADER, "&Default", "")
    col_header_menu:AppendRadioItem(ID.COLNATIVEHEADER, "&Native", "")
    col_header_menu:AppendRadioItem(ID.COLNATIVELABELS, "Native-&like", "")
    col_header_menu:AppendRadioItem(ID.COLCUSTOMHEADER, "&Custom", "")

    local tab_behaviour_menu = Menu.Create("", 0)
    tab_behaviour_menu:AppendRadioItem(ID.TAB_STOP, "&Stop at the boundary", "")
    tab_behaviour_menu:AppendRadioItem(ID.TAB_WRAP, "&Wrap at the boundary", "")
    tab_behaviour_menu:AppendRadioItem(ID.TAB_LEAVE, "&Leave the grid", "")
    tab_behaviour_menu:AppendRadioItem(ID.TAB_CUSTOM, "&Custom tab handler", "")
    grid_menu:AppendSubMenu(tab_behaviour_menu, "&Tab behaviour", "")

    colours_menu:Append(ID.SETLABELCOLOUR, "Set &label colour...", "", false)
    colours_menu:Append(ID.SETLABELTEXTCOLOUR, "Set label &text colour...", "", false)
    colours_menu:Append(ID.SETLABEL_FONT, "Set label fo&nt...", "", false)
    colours_menu:Append(ID.GRIDLINECOLOUR, "&Grid line colour...", "", false)
    colours_menu:Append(ID.SET_CELL_FG_COLOUR, "Set cell &foreground colour...", "", false)
    colours_menu:Append(ID.SET_CELL_BG_COLOUR, "Set cell &background colour...", "", false)
    colours_menu:Append(ID.SET_CELL_HL_COLOUR, "Set cell &highlight colour...", "", false)
    colours_menu:Append(ID.SET_SELECTION_FG_COLOUR, "Set selection f&oreground colour...", "", false)
    colours_menu:Append(ID.SET_SELECTION_BG_COLOUR, "Set selection b&ackground colour...", "", false)
    colours_menu:Append(ID.SET_FROZEN_BORDER, "Set f&rozen border colour...", "", false)

    edit_menu:Append(ID.INSERTROW, "Insert &rows\tCtrl+I", "", false)
    edit_menu:Append(ID.INSERTCOL, "Insert &columns\tCtrl+Shift+I", "", false)
    edit_menu:Append(ID.DELETEROW, "Delete selected ro&ws\tCtrl+D", "", false)
    edit_menu:Append(ID.DELETECOL, "Delete selected co&ls\tCtrl+Shift+D", "", false)
    edit_menu:Append(ID.CLEARGRID, "Cl&ear grid cell contents", "", false)
    edit_menu:Append(ID.EDITCELL, "&Edit current cell", "", false)
    edit_menu:Append(ID.SETCORNERLABEL, "&Set corner label...", "", false)
    edit_menu:AppendCheckItem(ID.FREEZE_OR_THAW, "Freeze up to cursor\tCtrl-F", "")

    select_menu:Append(ID.SELECT_OVERLAY, "Disable &overlay selection\tCtrl+Shift+O", "", false)
    select_menu:AppendSeparator()
    select_menu:AppendCheckItem(ID.SELECT_UNSELECT, "Add new cells to the selection",
                                "When off, old selection is deselected before selecting the new cells")
    select_menu:AppendSeparator()
    select_menu:Append(ID.SELECT_ALL, "Select all", "", false)
    select_menu:Append(ID.SELECT_ROW, "Select row 2", "", false)
    select_menu:Append(ID.SELECT_COL, "Select col 2", "", false)
    select_menu:Append(ID.SELECT_CELL, "Select cell (3, 1)", "", false)
    select_menu:AppendSeparator()
    select_menu:Append(ID.DESELECT_ALL, "Deselect all", "", false)
    select_menu:Append(ID.DESELECT_ROW, "Deselect row 2", "", false)
    select_menu:Append(ID.DESELECT_COL, "Deselect col 2", "", false)
    select_menu:Append(ID.DESELECT_CELL, "Deselect cell (3, 1)", "", false)
    select_menu:AppendSeparator()

    local selection_menu = Menu.Create("", 0)
    select_menu:Append(ID.SHOWSEL, "&Show current selection\tCtrl-S", "", false)
    select_menu:AppendSub(ID.CHANGESEL, "Change &selection mode", selection_menu,
                         "Change selection mode")
    selection_menu:Append(ID.SELCELLS, "Select &cells", "", false)
    selection_menu:Append(ID.SELROWS, "Select &rows", "", false)
    selection_menu:Append(ID.SELCOLS, "Select col&umns", "", false)
    selection_menu:Append(ID.SELROWSORCOLS, "Select rows &or columns", "", false)
    selection_menu:Append(ID.SELNONE, "&Disallow selection", "", false)

    autosize_menu:Append(ID.SIZE_ROW, "Selected &row data", "", false)
    autosize_menu:Append(ID.SIZE_COL, "Selected &column data", "", false)
    autosize_menu:Append(ID.SIZE_ROW_LABEL, "Selected row la&bel", "", false)
    autosize_menu:Append(ID.SIZE_COL_LABEL, "Selected column &label", "", false)
    autosize_menu:Append(ID.SIZE_LABELS_COL, "Column la&bels", "", false)
    autosize_menu:Append(ID.SIZE_LABELS_ROW, "Row label&s", "", false)
    autosize_menu:Append(ID.SIZE_GRID, "Entire &grid", "", false)

    help_menu:Append(wx.ID_ABOUT, "&About wxGrid demo", "", false)

    local menu_bar = MenuBar.Create(0)
    menu_bar:Append(file_menu, "&File")
    menu_bar:Append(grid_menu, "&Grid")
    menu_bar:Append(colours_menu, "&Colours")
    menu_bar:Append(edit_menu, "&Edit")
    menu_bar:Append(select_menu, "&Select")
    menu_bar:Append(autosize_menu, "&Autosize")
    menu_bar:Append(help_menu, "&Help")
    frame:SetMenuBar(menu_bar)
    S.menu_bar = menu_bar

    -- ------------------------------------------------------------ widgets

    local dip_w, dip_h = frame:FromDIP(800), frame:FromDIP(450)
    local grid = must(Grid.Create(frame, wx.ID_ANY, 0, 0, dip_w, dip_h, 0), "wxGrid")
    S.grid = grid

    local log_win = must(TextCtrl(frame, "", -1, -1, -1,
                                  8 * frame:GetCharHeight(), wx.TE_MULTILINE),
                         "wxTextCtrl log window")
    S.log_win = log_win

    local logger = must(wxlogtextctrl_gen.Create(log_win), "wxLogTextCtrl")
    S.logger = logger
    S.old_log = C.wxLog_SetActiveTarget(logger._ptr)
    C.wxLog_DisableTimestamp()

    -- ------------------------------------------------- custom grid renderers
    -- The C++ sample derives wxGridCellRenderer / wxGridCellActivatableEditor.
    -- kwxFFI exposes those two extension points as callback hooks (see
    -- kwxFFI/src/wx_grid.cpp); the callbacks are kept alive in S.callbacks.

    local renderer_hook = gwx.kwxGridCellRendererHook
    local cb_keep = {}
    S.callbacks = cb_keep

    -- MyGridCellRenderer: ordinary string rendering, then a green ellipse.
    local ellipse_hook = must(renderer_hook.Create(nil), "kwxGridCellRendererHook")
    local ellipse_draw = ffi.cast(
        "void (*)(void*, void*, void*, void*, int, int, int, int, int, int, int)",
        function(_, grid_ptr, attr_ptr, dc_ptr, x, y, w, h, row, col, is_sel)
            local ok, err = pcall(function()
                local g = gwx.wxGrid.FromPtr(grid_ptr, false)
                local a = gwx.wxGridCellAttr.FromPtr(attr_ptr, false)
                local dc = gwx.wxDC.FromPtr(dc_ptr, false)
                ellipse_hook:Draw(g, a, dc, x, y, w, h, row, col, is_sel ~= 0)
                local pen = must(gwx.wxPen.CreateFromColour(
                    rgb(0, 255, 0), 1, wx.PENSTYLE_SOLID), "wxPen")
                local brush = must(gwx.wxBrush.CreateFromColour(
                    rgb(0, 0, 0), wx.BRUSHSTYLE_TRANSPARENT), "wxBrush")
                dc:SetPen(pen)
                dc:SetBrush(brush)
                dc:DrawEllipse(x, y, w, h)
                pen:Delete()
                brush:Delete()
            end)
            if not ok then
                io.stderr:write("grid: cell renderer error: " .. tostring(err) .. "\n")
            end
        end)
    ellipse_hook:SetOnDraw(ffi.cast("void*", ellipse_draw))
    cb_keep[#cb_keep + 1] = ellipse_draw

    -- MyGridStarRenderer: value 0..5 drawn as black/white stars.
    local star_hook = must(renderer_hook.Create(nil), "kwxGridCellRendererHook")
    local star_draw = ffi.cast(
        "void (*)(void*, void*, void*, void*, int, int, int, int, int, int, int)",
        function(_, grid_ptr, _, dc_ptr, x, y, w, h, row, col)
            local ok, err = pcall(function()
                local g = gwx.wxGrid.FromPtr(grid_ptr, false)
                local dc = gwx.wxDC.FromPtr(dc_ptr, false)
                local n = tonumber(g:GetCellValue(row, col)) or 0
                if n < 0 or n > 5 then n = 0 end
                local stars = string.rep("★", n) .. string.rep("☆", 5 - n)
                g:DrawTextRectangle(dc, stars, x, y, w, h, wx.ALIGN_LEFT, wx.ALIGN_TOP)
            end)
            if not ok then
                io.stderr:write("grid: star renderer error: " .. tostring(err) .. "\n")
            end
        end)
    star_hook:SetOnDraw(ffi.cast("void*", star_draw))
    cb_keep[#cb_keep + 1] = star_draw

    -- MyGridStarEditor: cycles the star value on mouse/space activation and
    -- accepts the digit keys 0..5.
    local star_editor = must(gwx.kwxGridCellActivatableEditorHook.Create(nil),
                             "kwxGridCellActivatableEditorHook")
    local star_value = "0"
    local try_activate = ffi.cast("void (*)(void*, int, int, void*, int, void*)",
        function(_, row, col, grid_ptr, origin, event_ptr)
            local ok, err = pcall(function()
                local g = gwx.wxGrid.FromPtr(grid_ptr, false)
                local num = -1
                if origin == wx.GridActivationProgram then
                    star_editor:SetTryActivateResult(wx.GridActivationIgnore)
                    return
                elseif origin == wx.GridActivationKey and event_ptr ~= nil then
                    local code = gwx.wxKeyEvent.FromPtr(event_ptr, false):GetKeyCode()
                    if code >= 48 and code <= 53 then
                        num = code - 48
                    elseif code == 32 then
                        num = -1            -- space cycles the value
                    else
                        star_editor:SetTryActivateResult(wx.GridActivationIgnore)
                        return
                    end
                end
                if num == -1 then
                    local v = tonumber(g:GetCellValue(row, col)) or 0
                    num = (v + 1) % 6
                end
                star_value = string.format("%d", num)
                star_editor:SetTryActivateResult(wx.GridActivationChange)
                star_editor:SetTryActivateValue(star_value)
            end)
            if not ok then
                io.stderr:write("grid: star editor error: " .. tostring(err) .. "\n")
            end
        end)
    local do_activate = ffi.cast("void (*)(void*, int, int, void*)",
        function(_, row, col, grid_ptr)
            local ok, err = pcall(function()
                gwx.wxGrid.FromPtr(grid_ptr, false):SetCellValue(row, col, star_value)
            end)
            if not ok then
                io.stderr:write("grid: star editor error: " .. tostring(err) .. "\n")
            end
        end)
    star_editor:SetOnTryActivate(ffi.cast("void*", try_activate))
    star_editor:SetOnDoActivate(ffi.cast("void*", do_activate))
    cb_keep[#cb_keep + 1] = try_activate
    cb_keep[#cb_keep + 1] = do_activate
    S.star_editor = star_editor

    -- ------------------------------- CustomColumnHeadersProvider (C++ line 94)
    -- Two CustomColumnHeaderRenderer instances: odd columns use yellow on blue,
    -- even columns white on black.  The provider returns them only while custom
    -- headers are enabled; otherwise it keeps the base class renderer.
    local italic_font = must(Font.CreateFromStock(STOCK_ITALIC_FONT), "wxFont")
    local bold_italic = must(Font.FromPtr(italic_font:Bold(), true), "wxFont")
    S.italic_font = italic_font
    S.bold_italic_font = bold_italic

    local shared_pen = must(Pen.CreateFromColour(rgb(0, 0, 0), 1, wx.PENSTYLE_TRANSPARENT),
                            "wxPen")
    local highlight_colour = must(Colour.CreateRGB(240, 20, 15, 180), "wxColour")
    S.header_pen = shared_pen
    S.header_highlight_colour = highlight_colour

    local function create_header_renderer(fg, bg)
        local hook = must(GridHeaderRendHook.Create(nil), "kwxGridColumnHeaderRendererHook")
        local bg_brush = must(Brush.CreateFromColour(rgb(bg[1], bg[2], bg[3]),
                                                     wx.BRUSHSTYLE_SOLID), "wxBrush")
        local hl_brush = must(Brush.CreateFromColour(highlight_colour, wx.BRUSHSTYLE_SOLID),
                              "wxBrush")
        -- the brushes must outlive the hook
        hook.brushes = { bg_brush, hl_brush }

        local draw_label = ffi.cast(
            "void (*)(void*, void*, void*, void*, int, int, int, int, int, int, int)",
            function(_, grid_ptr, dc_ptr, value_ptr, x, y, w, h, h_align, v_align)
                local ok, err = pcall(function()
                    local dc = DC.FromPtr(dc_ptr, false)
                    dc:SetTextForeground(rgb(fg[1], fg[2], fg[3]))
                    dc:SetFont(bold_italic)
                    dc:DrawLabel(wxstring_text(value_ptr), x, y, w, h,
                                 bit.bor(h_align, v_align), -1)
                end)
                if not ok then
                    io.stderr:write("grid: column header label error: " ..
                                    tostring(err) .. "\n")
                end
            end)

        local draw_border = ffi.cast("void (*)(void*, void*, void*, int, int, int, int)",
            function(_, grid_ptr, dc_ptr, x, y, w, h)
                local ok, err = pcall(function()
                    local dc = DC.FromPtr(dc_ptr, false)
                    dc:SetPen(shared_pen)
                    dc:SetBrush(bg_brush)
                    dc:DrawRectangle(x, y, w, h)
                end)
                if not ok then
                    io.stderr:write("grid: column header border error: " ..
                                    tostring(err) .. "\n")
                end
            end)

        local draw_highlighted = ffi.cast(
            "void (*)(void*, void*, void*, int, int, int, int, int, int)",
            function(_, grid_ptr, dc_ptr, x, y, w, h, row_or_col, flags)
                local ok, err = pcall(function()
                    local dc = DC.FromPtr(dc_ptr, false)
                    dc:SetPen(shared_pen)
                    dc:SetBrush(hl_brush)
                    dc:DrawRectangle(x, y, w, h)
                end)
                if not ok then
                    io.stderr:write("grid: column header highlight error: " ..
                                    tostring(err) .. "\n")
                end
            end)

        hook:SetOnDrawLabel(ffi.cast("void*", draw_label))
        hook:SetOnDrawBorder(ffi.cast("void*", draw_border))
        hook:SetOnDrawHighlighted(ffi.cast("void*", draw_highlighted))
        cb_keep[#cb_keep + 1] = draw_label
        cb_keep[#cb_keep + 1] = draw_border
        cb_keep[#cb_keep + 1] = draw_highlighted
        return hook
    end

    local odd_header = create_header_renderer({ 255, 255, 0 }, { 0, 0, 255 })
    local even_header = create_header_renderer({ 255, 255, 255 }, { 0, 0, 0 })
    S.header_renderers = { odd = odd_header, even = even_header }

    local provider_hook = must(GridAttrProviderHook.Create(nil),
                               "kwxGridCellAttrProviderHook")
    local get_header_renderer = ffi.cast("void (*)(void*, int)", function(_, col)
        -- Not calling the setter keeps the provider's own renderer.
        if not S.use_custom_headers then return end
        provider_hook:SetGetColumnHeaderRendererResult(
            col % 2 ~= 0 and odd_header or even_header)
    end)
    provider_hook:SetOnGetColumnHeaderRenderer(ffi.cast("void*", get_header_renderer))
    cb_keep[#cb_keep + 1] = get_header_renderer
    S.provider_hook = provider_hook

    -- ------------------------------------------------------------ grid data

    grid:CreateGrid(0, 0, wx.GridSelectCells)

    -- grid->GetTable()->SetAttrProvider(new CustomColumnHeadersProvider())
    local grid_table = must(GridTableBase.FromPtr(grid:GetTable(), false),
                            "wxGridTableBase")
    grid_table:SetAttrProvider(provider_hook)
    S.grid_table = grid_table
    grid:AppendRows(1000, true)
    grid:AppendCols(100, true)

    local ir = grid:GetNumberRows()
    grid:DeleteRows(0, ir, true)
    grid:AppendRows(ir, true)

    grid:SetRowSize(0, 4 * grid:GetDefaultRowSize())
    grid:SetCellValue(0, 0, "Ctrl+Home\nwill go to\nthis cell")

    grid:SetCellValue(0, 1, "A long piece of text to demonstrate wrapping.")
    grid:SetCellRenderer(0, 1, must(new_renderer(GridCellAutoWrapRend), "auto-wrap renderer"))
    grid:SetCellEditor(0, 1, must(new_editor(GridCellAutoWrapEdit), "auto-wrap editor"))

    grid:SetCellValue(0, 2, "Blah")
    grid:SetCellValue(0, 3, "Read only")
    grid:SetReadOnly(0, 3, true)

    grid:SetCellValue(0, 4, "Can veto edit this cell")

    grid:SetColSize(10, frame:FromDIP(150))
    local longtext = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ\n\n"
    longtext = longtext .. "With tabs :\n"
    longtext = longtext .. "Home,\t\thome\t\t\tagain\n"
    longtext = longtext .. "Long word at start :\n"
    longtext = longtext .. "ILikeToBeHereWhen I can\n"
    longtext = longtext .. "Long word in the middle :\n"
    longtext = longtext .. "When IComeHome,ColdAnd tired\n"
    longtext = longtext .. "Long last word :\n"
    longtext = longtext .. "It's GoodToWarmMyBonesBesideTheFire"
    grid:SetCellValue(0, 10, longtext)
    grid:SetCellRenderer(0, 10, must(new_renderer(GridCellAutoWrapRend), "auto-wrap renderer"))
    grid:SetCellEditor(0, 10, must(new_editor(GridCellAutoWrapEdit), "auto-wrap editor"))
    grid:SetCellValue(0, 11, "K1 cell editor blocker")

    grid:SetCellValue(0, 5, "Press\nCtrl+arrow\nto skip over\ncells")

    local end_row = grid:GetNumberRows() - 1
    local end_col = grid:GetNumberCols() - 1

    grid:SetRowSize(end_row, 4 * grid:GetDefaultRowSize())
    grid:SetCellValue(end_row - 1, end_col - 1, "Test background colour setting")
    grid:SetCellBackgroundColour(end_row - 1, end_col, rgb(255, 127, 127))
    grid:SetCellBackgroundColour(end_row, end_col - 1, rgb(255, 127, 127))
    grid:SetCellValue(end_row, end_col, "Ctrl+End\nwill go to\nthis cell")
    grid:SetCellValue(1, 0, "This default cell will overflow into neighboring cells, but not if you turn overflow off.")

    grid:SetCellValue(2, 0, "This one always overflows")
    grid:SetCellFitMode(2, 0, must(GridFitMode.CreateOverflow(), "wxGridFitMode"))

    grid:SetCellTextColour(1, 2, rgb(RED[1], RED[2], RED[3]))
    grid:SetCellBackgroundColour(1, 2, rgb(GREEN[1], GREEN[2], GREEN[3]))

    grid:SetCellValue(1, 4, "I'm in the middle")

    grid:SetCellValue(2, 2, "red")
    grid:SetCellTextColour(2, 2, rgb(RED[1], RED[2], RED[3]))
    grid:SetCellValue(3, 3, "green on grey")
    grid:SetCellTextColour(3, 3, rgb(GREEN[1], GREEN[2], GREEN[3]))
    grid:SetCellBackgroundColour(3, 3, rgb(LIGHT_GREY[1], LIGHT_GREY[2], LIGHT_GREY[3]))

    grid:SetCellValue(4, 4, "a weird looking cell")
    grid:SetCellAlignment(4, 4, wx.ALIGN_CENTRE, wx.ALIGN_CENTRE)
    grid:SetCellRenderer(4, 4, ellipse_hook)

    grid:SetCellValue(4, 5, "3")
    grid:SetCellRenderer(4, 5, star_hook)
    grid:SetCellEditor(4, 5, star_editor)

    grid:SetCellRenderer(3, 0, must(new_renderer(GridCellBoolRend), "bool renderer"))
    grid:SetCellEditor(3, 0, must(new_editor(GridCellBoolEdit), "bool editor"))
    grid:SetCellBackgroundColour(3, 0, rgb(255, 127, 127))

    grid:SetCellRenderer(3, 1, must(new_renderer(GridCellBoolRend), "bool renderer"))
    grid:SetCellEditor(3, 1, must(new_editor(GridCellBoolEdit), "bool editor"))
    grid:SetCellValue(3, 1, "1")

    local attr = must(new_attr(), "wxGridCellAttr")
    attr:SetTextColour(rgb(BLUE[1], BLUE[2], BLUE[3]))
    grid:SetColAttr(5, attr)

    attr = must(new_attr(), "wxGridCellAttr")
    attr:SetBackgroundColour(rgb(RED[1], RED[2], RED[3]))
    grid:SetRowAttr(5, attr)

    grid:SetCellValue(2, 4, "a wider column")
    grid:SetColSize(4, 3 * grid:GetDefaultColSize() / 2)
    grid:SetColMinimalWidth(4, grid:GetColSize(4))

    grid:SetCellTextColour(5, 8, rgb(GREEN[1], GREEN[2], GREEN[3]))
    grid:SetCellValue(5, 8, "Bg from row attr\nText col from cell attr")
    grid:SetCellValue(5, 5, "Bg from row attr Text col from col attr and this text is so long that it covers over many many empty cells but is broken by one that isn't")

    -- numeric columns with different formatting
    grid:SetColFormatFloat(6, -1, -1)
    grid:SetReadOnly(0, 6, true)
    grid:SetCellValue(0, 6, "Default\nfloat format")
    grid:SetCellValue(1, 6, string.format("%g", 3.1415))
    grid:SetCellValue(2, 6, string.format("%g", 1415.0))
    grid:SetCellValue(3, 6, string.format("%g", 12345.67890))

    grid:SetColFormatFloat(7, 6, 2)
    grid:SetReadOnly(0, 7, true)
    grid:SetCellValue(0, 7, "Width 6\nprecision 2")
    grid:SetCellValue(1, 7, string.format("%g", 3.1415))
    grid:SetCellValue(2, 7, string.format("%g", 1415.0))
    grid:SetCellValue(3, 7, string.format("%g", 12345.67890))

    -- wxGRID_VALUE_FLOAT is "double"; the constant is not exported by kwxFFI.
    grid:SetColFormatCustom(8, "double:-1,4,g")
    grid:SetReadOnly(0, 8, true)
    grid:SetCellValue(0, 8, "Compact\nformat")
    grid:SetCellValue(1, 8, "31415e-4")
    grid:SetCellValue(2, 8, "1415")
    grid:SetCellValue(3, 8, "123456789e-4")

    grid:SetColFormatNumber(9)
    grid:SetReadOnly(0, 9, true)
    grid:SetCellValue(0, 9, "Integer\ncolumn")
    grid:SetCellValue(1, 9, "17")
    grid:SetCellValue(2, 9, "0")
    grid:SetCellEditor(2, 9, must(new_editor(GridCellNumberEdit, 0, 100), "number editor"))
    grid:SetCellValue(2, 10, "<- This cell uses [0, 100] range")
    grid:SetCellValue(3, 9, "-666")
    grid:SetCellAlignment(3, 9, wx.ALIGN_CENTRE, wx.ALIGN_TOP)
    grid:SetCellValue(3, 10, "<- This numeric cell should be centred")

    grid:SetReadOnly(0, 13, true)
    grid:SetCellValue(0, 13, "Localized date\ncolumn")
    grid:SetColFormatDate(13, "")          -- localized by default
    grid:SetCellValue(1, 13, "Today")
    grid:SetReadOnly(0, 14, true)
    grid:SetCellValue(0, 14, "ISO 8601 date\ncolumn")
    grid:SetColFormatDate(14, "%Y-%m-%d")
    grid:SetCellValue(1, 14, "Tomorrow")

    grid:SetCellValue(13, 0, "Date cell:")
    grid:SetCellValue(13, 1, "Today")
    grid:SetCellRenderer(13, 1, must(GridCellDateRend.Create(""), "date renderer"))
    grid:SetCellEditor(13, 1, must(new_editor(GridCellDateEdit, ""), "date editor"))
    grid:SetCellValue(14, 0, "ISO date cell:")
    grid:SetCellValue(14, 1, "Tomorrow")
    grid:SetCellRenderer(14, 1, must(GridCellDateRend.Create("%Y-%m-%d"), "date renderer"))
    grid:SetCellEditor(14, 1, must(new_editor(GridCellDateEdit, ""), "date editor"))

    grid:SetCellValue(13, 3, "String using default ellipsization")
    grid:SetCellFitMode(13, 3, must(GridFitMode.CreateEllipsize(wx.ELLIPSIZE_END), "fit mode"))

    grid:SetCellValue(13, 4, "String ellipsized in the middle")
    grid:SetCellFitMode(13, 4, must(GridFitMode.CreateEllipsize(wx.ELLIPSIZE_MIDDLE), "fit mode"))

    local choices = { "Please select a choice", "This takes two cells", "Another choice" }
    -- wxGridCellChoiceEditor_Ctor takes a char* array (see kwxFFI wx_grid.cpp).
    local choice_ptrs = ffi.new("const char*[256]")
    local choice_keep = {}
    for i, text in ipairs(choices) do
        choice_keep[i] = ffi.cast("const char*", text)
        choice_ptrs[i - 1] = choice_keep[i]
    end
    grid:SetCellEditor(4, 2, must(new_editor(GridCellChoiceEdit, #choices, choice_ptrs, 0),
                                  "choice editor"))
    grid:SetCellSize(4, 2, 1, 2)
    grid:SetCellValue(4, 2, choices[1])
    grid:SetCellOverflow(4, 2, false)

    grid:SetCellSize(7, 1, 3, 4)
    grid:SetCellAlignment(7, 1, wx.ALIGN_CENTRE, wx.ALIGN_CENTRE)
    grid:SetCellValue(7, 1, "Big box!")

    -- separator-like row: grey and non-resizable
    grid:DisableRowResize(10)
    grid:SetRowSize(10, 3 * grid:GetDefaultRowSize() / 2)
    attr = must(new_attr(), "wxGridCellAttr")
    attr:SetBackgroundColour(rgb(LIGHT_GREY[1], LIGHT_GREY[2], LIGHT_GREY[3]))
    attr:SetAlignment(wx.ALIGN_INVALID, wx.ALIGN_CENTRE)
    grid:SetRowAttr(10, attr)
    grid:SetCellValue(10, 0, "You can't resize this row interactively -- try it")

    -- reference-count test
    grid:SetAttr(11, 11, nil)
    grid:SetAttr(11, 11, must(new_attr(), "wxGridCellAttr"))
    grid:SetAttr(11, 11, nil)

    -- ------------------------------------------------------------ sizers

    local top_sizer = BoxSizer(wx.VERTICAL)
    top_sizer:Add(grid, 2, wx.EXPAND)
    top_sizer:Add(log_win, 1, wx.EXPAND)
    frame:SetSizerAndFit(top_sizer)
    frame:Centre(wx.BOTH)

    -- ------------------------------------------------------------ handlers

    local function checked(id) return menu_bar:IsChecked(id) end

    local function menu(id, fn)
        frame:Connect(wx.EVT_MENU, function(evt)
            if not evt then return end
            fn(CommandEvent.FromPtr(evt, false))
        end, id)
    end

    local function on_toggle_row_labels()
        if checked(ID.TOGGLEROWLABELS) then
            grid:SetRowLabelSize(grid:GetDefaultRowLabelSize())
        else
            grid:SetRowLabelSize(0)
        end
    end

    local function on_toggle_col_labels()
        if checked(ID.TOGGLECOLLABELS) then
            grid:SetColLabelSize(grid:GetDefaultColLabelSize())
        else
            grid:SetColLabelSize(0)
        end
    end

    local function on_toggle_editing()
        grid:EnableEditing(checked(ID.TOGGLEEDIT) and 1 or 0)
    end

    local function on_toggle_row_sizing()
        grid:EnableDragRowSize(checked(ID.TOGGLEROWSIZING))
    end

    local function on_toggle_col_sizing()
        grid:EnableDragColSize(checked(ID.TOGGLECOLSIZING))
    end

    local function on_toggle_row_label_sizing()
        grid:EnableDragRowLabelSize(checked(ID.TOGGLEROWLABELSIZING))
    end

    local function on_toggle_col_label_sizing()
        grid:EnableDragColLabelSize(checked(ID.TOGGLECOLLABELSIZING))
    end

    local function on_toggle_row_moving()
        grid:EnableDragRowMove(checked(ID.TOGGLEROWMOVING))
    end

    local function on_toggle_col_moving()
        grid:EnableDragColMove(checked(ID.TOGGLECOLMOVING))
    end

    local function on_toggle_col_hiding()
        if not grid:EnableHidingColumns(checked(ID.TOGGLECOLHIDING)) then
            menu_bar:Check(ID.TOGGLECOLHIDING, grid:CanHideColumns())
        end
    end

    local function on_toggle_grid_sizing()
        grid:EnableDragGridSize(checked(ID.TOGGLEGRIDSIZING))
    end

    local function on_toggle_grid_drag_cell()
        grid:EnableDragCell(checked(ID.TOGGLEGRIDDRAGCELL))
    end

    local function on_native_col_header()
        S.use_custom_headers = false
        grid:UseNativeColHeader(true)
    end

    local function on_native_col_labels()
        S.use_custom_headers = false
        grid:UseNativeColHeader(false)
        grid:SetUseNativeColLabels(true)
    end

    local function on_default_col_header()
        S.use_custom_headers = false
        grid:UseNativeColHeader(false)
        grid:SetUseNativeColLabels(false)
    end

    local function on_custom_col_header()
        S.use_custom_headers = true
        grid:UseNativeColHeader(false)
        grid:SetUseNativeColLabels(false)
    end

    local function on_grid_custom_tab(ev)
        if ev:ShiftDown() then
            if grid:GetGridCursorRow() > 0 then
                grid:MoveCursorUp(false)
            end
        else
            if grid:GetGridCursorRow() < grid:GetNumberRows() - 1 then
                grid:MoveCursorDown(false)
            end
        end
    end

    local function on_set_tab_behaviour(ev)
        if S.custom_tab_cb ~= nil then
            grid:Disconnect(S.custom_tab_cb)
            S.custom_tab_cb = nil
        end
        grid:SetTabBehaviour(ev:GetId() - ID.TAB_STOP)
    end

    local function on_set_tab_custom_handler()
        if S.custom_tab_cb == nil then
            S.custom_tab_cb = grid:Connect(wx.EVT_GRID_TABBING, function(evt)
                if not evt then return end
                on_grid_custom_tab(GridEvent.FromPtr(evt, false))
            end)
        end
    end

    local function on_grid_context_menu(evt)
        local ev = ContextMenuEvent.FromPtr(evt, false)
        local obj = ev:GetEventObject()
        if obj ~= grid._ptr then
            log_error("Context menu unexpectedly sent from non-grid window.")
        else
            local ox, oy = ffi.new("int[1]"), ffi.new("int[1]")
            ev:GetPosition(ox, oy)
            log_message(string.format("wxEVT_CONTEXT_MENU in the grid at at (%d, %d)",
                                      ox[0], oy[0]))
        end
        ev:Skip(true)
    end

    local function on_toggle_grid_lines()
        grid:EnableGridLines(checked(ID.TOGGLEGRIDLINES))
    end

    local function choose_pen_width(current, setter)
        local arr = must(ArrayString.Create(), "wxArrayString")
        for n = 0, 10 do arr:Add(tostring(n)) end
        local dlg = must(gwx.wxSingleChoiceDialog.Create(
            frame, "Choose the thickness of the highlight pen:", "Pen Width", arr._ptr, 0),
            "wxSingleChoiceDialog")
        arr:Delete()
        dlg:SetSelection(current)
        if dlg:ShowModal() == wx.ID_OK then
            setter(dlg:GetSelection())
        end
        dlg:Delete()
    end

    local function on_set_highlight_width()
        choose_pen_width(grid:GetCellHighlightPenWidth(), function(v)
            grid:SetCellHighlightPenWidth(v)
        end)
    end

    local function on_set_ro_highlight_width()
        choose_pen_width(grid:GetCellHighlightROPenWidth(), function(v)
            grid:SetCellHighlightROPenWidth(v)
        end)
    end

    local function on_autosize_cols()
        grid:AutoSizeColumns(1)
        grid:Refresh()
    end

    local function on_cell_overflow(ev)
        grid:SetDefaultCellOverflow(ev:IsChecked())
        grid:Refresh()
    end

    local function on_resize_cell(ev)
        if ev:IsChecked() then
            grid:SetCellSize(7, 1, 5, 5)
        else
            grid:SetCellSize(7, 1, 1, 5)
        end
        grid:Refresh()
    end

    local function colour_dialog_get()
        local dlg = must(gwx.wxColourDialog.Create(nil, nil), "wxColourDialog")
        local result = nil
        if dlg:ShowModal() == wx.ID_OK then
            local data = must(gwx.wxColourData.Create(), "wxColourData")
            local col = must(Colour.CreateEmpty(), "wxColour")
            dlg:GetColourData(data)
            data:GetColour(col)
            result = col
            data:Delete()
        end
        dlg:Delete()
        return result
    end

    local function on_set_label_colour()
        local col = colour_dialog_get()
        if col ~= nil then
            grid:SetLabelBackgroundColour(col)
            col:Delete()
        end
    end

    local function on_set_label_text_colour()
        local col = colour_dialog_get()
        if col ~= nil then
            grid:SetLabelTextColour(col)
            col:Delete()
        end
    end

    local function on_set_label_font()
        local font = must(gwx.wxFont.CreateDefault(), "wxFont")
        ff.wxGetFontFromUser(frame, nil, font)
        if font:IsOk() then
            grid:SetLabelFont(font)
        end
        font:Delete()
    end

    local function cycle_horiz(current)
        if current == wx.ALIGN_LEFT then return wx.ALIGN_CENTRE end
        if current == wx.ALIGN_CENTRE then return wx.ALIGN_RIGHT end
        if current == wx.ALIGN_RIGHT then return wx.ALIGN_LEFT end
        return current
    end

    local function cycle_vert(current)
        if current == wx.ALIGN_TOP then return wx.ALIGN_CENTRE end
        if current == wx.ALIGN_CENTRE then return wx.ALIGN_BOTTOM end
        if current == wx.ALIGN_BOTTOM then return wx.ALIGN_TOP end
        return current
    end

    local function on_row_label_horiz()
        local h, v = ffi.new("int[1]"), ffi.new("int[1]")
        grid:GetRowLabelAlignment(h, v)
        grid:SetRowLabelAlignment(cycle_horiz(h[0]), v[0])
    end

    local function on_row_label_vert()
        local h, v = ffi.new("int[1]"), ffi.new("int[1]")
        grid:GetRowLabelAlignment(h, v)
        grid:SetRowLabelAlignment(h[0], cycle_vert(v[0]))
    end

    local function on_col_label_horiz()
        local h, v = ffi.new("int[1]"), ffi.new("int[1]")
        grid:GetColLabelAlignment(h, v)
        grid:SetColLabelAlignment(cycle_horiz(h[0]), v[0])
    end

    local function on_col_label_vert()
        local h, v = ffi.new("int[1]"), ffi.new("int[1]")
        grid:GetColLabelAlignment(h, v)
        grid:SetColLabelAlignment(h[0], cycle_vert(v[0]))
    end

    local function on_corner_label_horiz()
        local h, v = ffi.new("int[1]"), ffi.new("int[1]")
        grid:GetCornerLabelAlignment(h, v)
        grid:SetCornerLabelAlignment(cycle_horiz(h[0]), v[0])
    end

    local function on_corner_label_vert()
        local h, v = ffi.new("int[1]"), ffi.new("int[1]")
        grid:GetCornerLabelAlignment(h, v)
        grid:SetCornerLabelAlignment(h[0], cycle_vert(v[0]))
    end

    local function on_corner_label_orientation()
        local orientation = grid:GetCornerLabelTextOrientation()
        if orientation == wx.HORIZONTAL then
            orientation = wx.VERTICAL
        elseif orientation == wx.VERTICAL then
            orientation = wx.HORIZONTAL
        end
        grid:SetCornerLabelTextOrientation(orientation)
    end

    local function on_grid_line_colour()
        local col = colour_dialog_get()
        if col ~= nil then
            grid:SetGridLineColour(col)
            col:Delete()
        end
    end

    local function selected_blocks()
        local arr = must(GridBlockCoordsArray.Create(), "wxGridBlockCoordsArray")
        grid:GetSelectedBlocks(arr)
        return arr
    end

    -- HandleEdits(): insert/delete rows or columns.
    local function handle_edits(is_row, is_insertion)
        local blocks = selected_blocks()
        local count = blocks:GetCount()

        if is_insertion then
            local pos, cnt
            if count == 1 then
                local r1, c1 = ffi.new("int[1]"), ffi.new("int[1]")
                local r2, c2 = ffi.new("int[1]"), ffi.new("int[1]")
                blocks:ItemTopLeft(0, r1, c1)
                blocks:ItemBottomRight(0, r2, c2)
                pos = is_row and r1[0] or c1[0]
                local last = is_row and r2[0] or c2[0]
                cnt = last - pos + 1
            else
                pos = is_row and grid:GetGridCursorRow() or grid:GetGridCursorCol()
                cnt = 1
            end
            blocks:Delete()
            if is_row then
                grid:InsertRows(pos, cnt, true)
            else
                grid:InsertCols(pos, cnt, true)
            end
            return
        end

        local seen, deletions = {}, {}
        for i = 0, count - 1 do
            local r1, c1 = ffi.new("int[1]"), ffi.new("int[1]")
            local r2, c2 = ffi.new("int[1]"), ffi.new("int[1]")
            blocks:ItemTopLeft(i, r1, c1)
            blocks:ItemBottomRight(i, r2, c2)
            local first = is_row and r1[0] or c1[0]
            local last = is_row and r2[0] or c2[0]
            for n = first, last do
                if not seen[n] then
                    seen[n] = true
                    deletions[#deletions + 1] = n
                end
            end
        end
        blocks:Delete()

        table.sort(deletions)
        if #deletions == 0 then return end

        local seq_end, seq_count = 0, 0
        for i = #deletions, 1, -1 do
            local n = deletions[i]
            if n ~= seq_end - seq_count then
                if i ~= #deletions then
                    local seq_start = seq_end - seq_count + 1
                    if is_row then
                        grid:DeleteRows(seq_start, seq_count, true)
                    else
                        grid:DeleteCols(seq_start, seq_count, true)
                    end
                end
                seq_end = n
                seq_count = 0
            end
            seq_count = seq_count + 1
        end
        local seq_start = seq_end - seq_count + 1
        if is_row then
            grid:DeleteRows(seq_start, seq_count, true)
        else
            grid:DeleteCols(seq_start, seq_count, true)
        end
    end

    local function on_insert_row()  handle_edits(true, true)  end
    local function on_insert_col()  handle_edits(false, true) end
    local function on_delete_row()  handle_edits(true, false) end
    local function on_delete_col()  handle_edits(false, false) end

    local function on_clear_grid()
        grid:ClearGrid()
    end

    local function on_edit_cell()
        grid:EnableCellEditControl(true)
    end

    local function on_set_corner_label()
        local table_wrap = GridTableBase.FromPtr(grid:GetTable(), false)
        local dlg = must(gwx.wxTextEntryDialog.Create(
            frame, "Please enter corner label:", "Please enter a string",
            table_wrap:GetCornerLabelValue(), wx.OK + wx.CANCEL, -1, -1, -1, -1),
            "wxTextEntryDialog")
        if dlg:ShowModal() == wx.ID_OK then
            table_wrap:SetCornerLabelValue(dlg:GetValue())
        end
        dlg:Destroy()
    end

    local function on_show_selection()
        local blocks = selected_blocks()
        local count = blocks:GetCount()
        local desc = ""
        local ncols = grid:GetNumberCols()
        local nrows = grid:GetNumberRows()

        for i = 0, count - 1 do
            local r1, c1 = ffi.new("int[1]"), ffi.new("int[1]")
            local r2, c2 = ffi.new("int[1]"), ffi.new("int[1]")
            blocks:ItemTopLeft(i, r1, c1)
            blocks:ItemBottomRight(i, r2, c2)
            local top, left, bottom, right = r1[0], c1[0], r2[0], c2[0]

            local block_desc
            if left == 0 and right == ncols - 1 then
                if top == bottom then
                    block_desc = string.format("row %d", top + 1)
                else
                    block_desc = string.format("rows %d..%d", top + 1, bottom + 1)
                end
            elseif top == 0 and bottom == nrows - 1 then
                if left == right then
                    block_desc = string.format("column %d", left + 1)
                else
                    block_desc = string.format("columns %d..%d", left + 1, right + 1)
                end
            elseif top == bottom and left == right then
                block_desc = string.format("cell R%dC%d", top + 1, left + 1)
            else
                block_desc = string.format("block R%dC%d - R%dC%d",
                                           top + 1, left + 1, bottom + 1, right + 1)
            end

            if i > 0 then desc = desc .. "\n\t" end
            desc = desc .. block_desc
        end
        blocks:Delete()

        if count == 0 then
            log_message("No selection")
        elseif count == 1 then
            log_message("Selection: " .. desc)
        else
            log_message(string.format("%d selected blocks:\n\t%s", count, desc))
        end
    end

    local function on_freeze_or_thaw(ev)
        if ev:IsChecked() then
            if not grid:FreezeTo(grid:GetGridCursorRow(), grid:GetGridCursorCol()) then
                log_message("Failed to freeze the grid.")
                menu_bar:Check(ID.FREEZE_OR_THAW, false)
                return
            end
            log_message("Grid is now frozen")
        else
            grid:FreezeTo(0, 0)
            log_message("Grid is now thawed")
        end
        menu_bar:EnableItem(ID.TOGGLECOLMOVING, not grid:IsFrozen())
        menu_bar:EnableItem(ID.TOGGLEROWMOVING, not grid:IsFrozen())
    end

    local function pick_colour()
        local col = must(Colour.CreateEmpty(), "wxColour")
        ff.wxGetColourFromUserEx(frame, nil, "", col)
        return col
    end

    local function on_set_cell_fg()
        local col = pick_colour()
        if col:IsOk() then
            grid:SetDefaultCellTextColour(col)
            grid:Refresh()
        end
        col:Delete()
    end

    local function on_set_cell_bg()
        local col = pick_colour()
        if col:IsOk() then
            local w, h = size_parts(grid:GetSize())
            grid:SetDefaultCellBackgroundColour(col)
            grid:RefreshRect(true, 0, 0, w, h)
        end
        col:Delete()
    end

    local function on_set_cell_highlight_colour()
        local col = pick_colour()
        if col:IsOk() then
            grid:SetCellHighlightColour(col)
            grid:Refresh()
        end
        col:Delete()
    end

    local function on_set_selection_bg()
        local col = pick_colour()
        if col:IsOk() then
            grid:SetSelectionBackground(col)
            grid:Refresh()
        end
        col:Delete()
    end

    local function on_set_selection_fg()
        local col = pick_colour()
        if col:IsOk() then
            grid:SetSelectionForeground(col)
            grid:Refresh()
        end
        col:Delete()
    end

    local function on_set_frozen_border()
        local col = pick_colour()
        if col:IsOk() then
            grid:SetGridFrozenBorderColour(col)
            grid:Refresh()
        end
        col:Delete()
    end

    local function on_overlay_selection()
        grid:DisableOverlaySelection()
        grid:ForceRefresh()
        log_message("Overlay selection disabled")
    end

    local function on_add_to_select(ev)
        S.add_to_sel = ev:IsChecked()
    end

    local function autosize_selected(is_row, label_size)
        -- wxGrid_GetSelectedRows/Cols take a raw int out-buffer and return the
        -- count (kwxFFI/src/wx_grid.cpp:1212).
        local max_count = is_row and grid:GetNumberRows() or grid:GetNumberCols()
        if max_count < 1 then max_count = 1 end
        local buffer = ffi.new("int[?]", max_count)
        local count
        if is_row then
            count = grid:GetSelectedRows(buffer)
        else
            count = grid:GetSelectedCols(buffer)
        end
        for i = 0, count - 1 do
            local n = buffer[i]
            if label_size then
                if is_row then
                    grid:AutoSizeRowLabelSize(n)
                else
                    grid:AutoSizeColLabelSize(n)
                end
            else
                if is_row then
                    grid:AutoSizeRow(n, 0)
                else
                    grid:AutoSizeColumn(n, 0)
                end
            end
        end
    end

    local function on_size_row()        autosize_selected(true, false)  end
    local function on_size_col()        autosize_selected(false, false) end
    local function on_size_row_label()  autosize_selected(true, true)   end
    local function on_size_col_label()  autosize_selected(false, true)  end

    local function on_size_labels_col()
        grid:SetColLabelSize(wx.GRID_AUTOSIZE)
    end

    local function on_size_labels_row()
        grid:SetRowLabelSize(wx.GRID_AUTOSIZE)
    end

    local function on_size_grid()
        grid:AutoSize()
        frame:Layout()
    end

    local function on_hide_col() grid:HideCol(0) end
    local function on_show_col() grid:ShowCol(0) end
    local function on_hide_row() grid:HideRow(1) end
    local function on_show_row() grid:ShowRow(1) end

    local function on_about()
        local info = must(AboutDialogInfo.Create(), "wxAboutDialogInfo")
        info:SetName("wxGrid demo")
        info:SetDescription("wxGrid sample program")
        info:AddDeveloper("Michael Bedward")
        info:AddDeveloper("Julian Smart")
        info:AddDeveloper("Vadim Zeitlin")
        info:SetWebSite("http://www.wxwidgets.org", "")
        ff.wxAboutBox(info, frame)
    end

    local function on_clear()
        log_win:Clear()
    end

    local function on_quit()
        frame:Close(true)
    end

    local function on_vtable()
        local n = ff.wxGetNumberFromUser("Size of the table to create", "Size: ",
                                         "wxGridDemo question", S.size_grid,
                                         0, 10000000, frame, -1, -1)
        if n ~= -1 then
            S.size_grid = n
            create_big_grid_frame(n).frame:Show(true)
        end
    end

    local function on_bugs_table()
        create_bugs_frame().frame:Show(true)
    end

    local function on_tabular_table()
        create_tabular_frame().frame:Show(true)
    end

    local function on_toggle_grid_cells(use_checkered)
        if use_checkered then
            S.checkered_on = not S.checkered_on
        else
            S.coloured_on = not S.coloured_on
        end

        local shared_attr = nil
        if use_checkered and S.checkered_on then
            shared_attr = must(new_attr(), "wxGridCellAttr")
            shared_attr:SetBackgroundColour(rgb(LIGHT_GREY[1], LIGHT_GREY[2], LIGHT_GREY[3]))
        end

        local bg = must(Colour.CreateEmpty(), "wxColour")
        grid:GetDefaultCellBackgroundColour(bg)

        local nrows, ncols = grid:GetNumberRows(), grid:GetNumberCols()
        local srow, scol = ffi.new("int[1]"), ffi.new("int[1]")

        for row = 0, nrows - 1 do
            for col = 0, ncols - 1 do
                if not (use_checkered and bit.band(bit.bxor(row, col), 1) ~= 0) then
                    local merged = false
                    if use_checkered then
                        grid:GetCellSize(row, col, srow, scol)
                        merged = (srow[0] > 1 or scol[0] > 1)
                    end
                    if not merged then
                        if use_checkered then
                            grid:SetAttr(row, col, shared_attr)
                            if S.checkered_on and shared_attr ~= nil then
                                shared_attr:IncRef()
                            end
                        else
                            local r, g, b
                            if S.coloured_on then
                                local factor = 256 / 64
                                r = (127 + row * factor + math.floor(col / factor)) % 256
                                g = (col * factor + math.floor(row / (factor * 2))) % 256
                                b = bit.band(bit.bxor(row, col) * factor, 0xff)
                                r = (r < 128) and r * 2 or 255 - r * 2
                                g = (g < 128) and g * 2 or 255 - g * 2
                                b = (b < 128) and b * 2 or 255 - b * 2
                                bg:Set(r, g, b, 255)
                            end
                            grid:SetCellBackgroundColour(row, col, bg)
                        end
                    end
                end
            end
        end

        if shared_attr ~= nil then
            shared_attr:DecRef()   -- release the reference this function held
        end
        bg:Delete()
        grid:Refresh()
    end

    -- ------------------------------------------------------ render to bitmap

    local function on_grid_render(ev)
        local id = ev:GetId()
        local style_render = 0
        local use_lometric, def_size = false, false
        local zoom = 1.0
        local off_x, off_y = 0, 0

        if checked(ID.RENDER_ROW_LABEL) then style_render = bit.bor(style_render, wx.GRID_DRAW_ROWS_HEADER) end
        if checked(ID.RENDER_COL_LABEL) then style_render = bit.bor(style_render, wx.GRID_DRAW_COLS_HEADER) end
        if checked(ID.RENDER_GRID_LINES) then style_render = bit.bor(style_render, wx.GRID_DRAW_CELL_LINES) end
        if checked(ID.RENDER_GRID_BORDER) then style_render = bit.bor(style_render, wx.GRID_DRAW_BOX_RECT) end
        if checked(ID.RENDER_SELECT_HLIGHT) then style_render = bit.bor(style_render, wx.GRID_DRAW_SELECTION) end
        if checked(ID.RENDER_LOMETRIC) then use_lometric = true end
        if checked(ID.RENDER_MARGIN) then off_x, off_y = 50, 50 end
        if checked(ID.RENDER_ZOOM) then zoom = 1.25 end
        if checked(ID.RENDER_DEFAULT_SIZE) then def_size = true end

        local tl_row, tl_col, br_row, br_col = 0, 0, 8, 6
        if id == ID.RENDER_COORDS then
            tl_col, tl_row, br_col, br_row = 6, 4, 15, 29
        elseif grid:IsSelection() then
            local tls = must(GridCellCoordsArray.Create(), "wxGridCellCoordsArray")
            grid:GetSelectionBlockTopLeft(tls)
            if tls:GetCount() > 0 then
                local brs = must(GridCellCoordsArray.Create(), "wxGridCellCoordsArray")
                grid:GetSelectionBlockBottomRight(brs)
                if brs:GetCount() > 0 then
                    local r1, c1 = ffi.new("int[1]"), ffi.new("int[1]")
                    local r2, c2 = ffi.new("int[1]"), ffi.new("int[1]")
                    tls:Item(0, c1, r1)
                    brs:Item(0, c2, r2)
                    tl_row, tl_col = r1[0], c1[0]
                    br_row, br_col = r2[0], c2[0]
                end
                brs:Delete()
            end
            tls:Delete()
        end

        local render_w, render_h = 0, 0
        for c = tl_col, br_col do render_w = render_w + grid:GetColSize(c) end
        for r = tl_row, br_row do render_h = render_h + grid:GetRowSize(r) end
        if bit.band(style_render, wx.GRID_DRAW_ROWS_HEADER) ~= 0 then
            render_w = render_w + grid:GetRowLabelSize()
        end
        if bit.band(style_render, wx.GRID_DRAW_COLS_HEADER) ~= 0 then
            render_h = render_h + grid:GetColLabelSize()
        end
        render_w = math.floor(render_w * zoom)
        render_h = math.floor(render_h * zoom)

        local old = gwx.wxWindow.FindWindowByName("frameRender", frame)
        if old ~= nil then
            gwx.wxWindow.FromPtr(old, false):Destroy()
        end

        local client_w = render_w + 2 * off_x
        local client_h = render_h + 2 * off_y
        if client_w < 1 then client_w = 1 end
        if client_h < 1 then client_h = 1 end

        local render_frame = wx.Frame(frame, "Grid Render",
                                      wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
                                      wx.DEFAULT_SIZE, wx.DEFAULT_SIZE,
                                      wx.DEFAULT_FRAME_STYLE)
        render_frame:SetClientSize(client_w, client_h)
        render_frame:SetName("frameRender")
        local canvas = wx.Panel(render_frame)

        local bmp = must(Bitmap.CreateEmpty(render_w + off_x, render_h + off_y, -1), "wxBitmap")
        local mem_dc = must(MemoryDC.CreateWithBitmap(bmp), "wxMemoryDC")
        mem_dc:SetLayoutDirection(render_frame:GetLayoutDirection())

        local bg = must(Colour.CreateEmpty(), "wxColour")
        canvas:GetBackgroundColour(bg)
        local bg_brush = must(Brush.CreateFromColour(bg, wx.BRUSHSTYLE_SOLID), "wxBrush")
        mem_dc:SetBackground(bg_brush)
        mem_dc:Clear()
        bg_brush:Delete()
        bg:Delete()

        if use_lometric then
            mem_dc:SetMapMode(wx.MM_LOMETRIC)
            render_w = mem_dc:DeviceToLogicalXRel(render_w)
            render_h = mem_dc:DeviceToLogicalYRel(render_h)
        end

        if def_size then
            render_w, render_h = wx.DEFAULT_SIZE, wx.DEFAULT_SIZE
        end

        grid:Render(mem_dc, off_x, off_y, render_w, render_h,
                    tl_row, tl_col, br_row, br_col, style_render)

        mem_dc:Delete()
        if S.render_bitmap ~= nil then
            S.render_bitmap:Delete()
        end
        S.render_bitmap = bmp

        canvas:Connect(wx.EVT_PAINT, function(evt)
            if not evt then return end
            local bitmap = S.render_bitmap
            if bitmap == nil or not bitmap:IsOk() then return end
            local dc = must(PaintDC.Create(canvas), "wxPaintDC")
            canvas:PrepareDC(dc)
            local mdc = must(MemoryDC.CreateWithBitmap(bitmap), "wxMemoryDC")
            mdc:SetLayoutDirection(render_frame:GetLayoutDirection())
            dc:Blit(0, 0, bitmap:GetWidth(), bitmap:GetHeight(),
                    mdc, 0, 0, wx.COPY, false, -1, -1)
            mdc:Delete()
            dc:Delete()
        end)

        render_frame:Show(true)
    end

    -- ------------------------------------------------ grid event handlers

    local function on_label_left_click(ev)
        local text
        if ev:GetRow() ~= -1 then
            text = string.format("Left click on row label %d", ev:GetRow())
        elseif ev:GetCol() ~= -1 then
            text = string.format("Left click on col label %d", ev:GetCol())
        else
            text = "Left click on corner label"
        end
        if ev:ShiftDown() then text = text .. " (shift down)" end
        if ev:ControlDown() then text = text .. " (control down)" end
        log_message(text)
        ev:Skip(true)
    end

    local function on_cell_left_click(ev)
        log_message(string.format("Left click at row %d, col %d", ev:GetRow(), ev:GetCol()))
        ev:Skip(true)
    end

    local function on_row_size(ev)
        local row = ev:GetRowOrCol()
        log_message(string.format("Resized row %d, new height = %d", row, grid:GetRowSize(row)))
        ev:Skip(true)
    end

    local function on_col_size(ev)
        local col = ev:GetRowOrCol()
        log_message(string.format("Resized column %d, new width = %d", col, grid:GetColSize(col)))
        ev:Skip(true)
    end

    local function on_col_auto_size(ev)
        local col = ev:GetRowOrCol()
        if col % 2 ~= 0 then
            log_message(string.format("Auto-sizing column %d to fit its contents", col))
            grid:AutoSizeColumn(col, 0)
        else
            ev:Skip(true)
        end
    end

    local function on_row_label_size(ev)
        log_message(string.format("Resized row label, new width = %d", grid:GetRowLabelSize()))
        ev:Skip(true)
    end

    local function on_col_label_size(ev)
        log_message(string.format("Resized column label, new height = %d", grid:GetColLabelSize()))
        ev:Skip(true)
    end

    local function on_row_move(ev)
        log_message(string.format("Moving row %d to %d", ev:GetRow(), ev:GetNewRow()))
        ev:Skip(true)
    end

    local function on_col_move(ev)
        log_message(string.format("Moving column %d to %d", ev:GetCol(), ev:GetNewCol()))
        ev:Skip(true)
    end

    local function tf(value) return value and "T" or "F" end

    local function on_select_cell(ev)
        local row, col = ev:GetRow(), ev:GetCol()
        local text = (ev:Selecting() and "Selected " or "Deselected ")
            .. string.format("cell at row %d col %d ( ControlDown: %s, ShiftDown: %s, AltDown: %s, MetaDown: %s )",
                             row, col, tf(ev:ControlDown()), tf(ev:ShiftDown()),
                             tf(ev:AltDown()), tf(ev:MetaDown()))
        local row_pos = grid:GetRowPos(row)
        if row_pos ~= row then
            text = text .. string.format(" *** Row moved, current position: %d", row_pos)
        end
        local col_pos = grid:GetColPos(col)
        if col_pos ~= col then
            text = text .. string.format(" *** Column moved, current position: %d", col_pos)
        end
        log_message(text)
        ev:Skip(true)
    end

    local function log_range_select(ev, suffix)
        local text = (ev:Selecting() and "Select" or "Deselect") .. suffix
            .. string.format(" cells from row %d col %d to row %d col %d ( ControlDown: %s, ShiftDown: %s, AltDown: %s, MetaDown: %s )",
                             ev:GetTopRow(), ev:GetLeftCol(), ev:GetBottomRow(), ev:GetRightCol(),
                             tf(ev:ControlDown()), tf(ev:ShiftDown()),
                             tf(ev:AltDown()), tf(ev:MetaDown()))
        log_message(text)
        ev:Skip(true)
    end

    local function on_range_selected(ev)  log_range_select(ev, "ed")  end
    local function on_range_selecting(ev) log_range_select(ev, "ing") end

    local function on_cell_value_changing(ev)
        local row, col = ev:GetRow(), ev:GetCol()
        local new_value = ev:GetString()
        log_message(string.format('Value of cell at (%d, %d): about to change from "%s" to "%s"',
                                  row, col, grid:GetCellValue(row, col), new_value))
        if new_value == "42" then
            log_message("Vetoing the change.")
            ev:Veto()
            return
        end
        ev:Skip(true)
    end

    local function on_cell_value_changed(ev)
        local row, col = ev:GetRow(), ev:GetCol()
        log_message(string.format('Value of cell at (%d, %d) changed and is now "%s" (was "%s")',
                                  row, col, grid:GetCellValue(row, col), ev:GetString()))
        ev:Skip(true)
    end

    local function on_cell_begin_drag(ev)
        log_message(string.format("Got request to drag cell at row %d, col %d",
                                  ev:GetRow(), ev:GetCol()))
        ev:Skip(true)
    end

    local function on_editor_shown(ev)
        if ev:GetCol() == 4 and ev:GetRow() == 0 then
            local answer = wx.MessageBox("Are you sure you wish to edit this cell",
                                         "Checking", wx.YES_NO, frame)
            if answer == wx.NO then
                ev:Veto()
                return
            end
        end
        log_message("Cell editor shown.")
        ev:Skip(true)
    end

    local function on_editor_hidden(ev)
        if ev:GetCol() == 4 and ev:GetRow() == 0 then
            local answer = wx.MessageBox("Are you sure you wish to finish editing this cell",
                                         "Checking", wx.YES_NO, frame)
            if answer == wx.NO then
                ev:Veto()
                return
            end
        end
        log_message("Cell editor hidden.")
        ev:Skip(true)
    end

    -- ------------------------------------------------------------- connect

    menu(ID.VTABLE, on_vtable)
    menu(ID.BUGS_TABLE, on_bugs_table)
    menu(ID.TABULAR_TABLE, on_tabular_table)

    menu(ID.TOGGLEROWLABELS, on_toggle_row_labels)
    menu(ID.TOGGLECOLLABELS, on_toggle_col_labels)
    menu(ID.TOGGLEEDIT, on_toggle_editing)
    menu(ID.TOGGLEROWSIZING, on_toggle_row_sizing)
    menu(ID.TOGGLECOLSIZING, on_toggle_col_sizing)
    menu(ID.TOGGLEROWLABELSIZING, on_toggle_row_label_sizing)
    menu(ID.TOGGLECOLLABELSIZING, on_toggle_col_label_sizing)
    menu(ID.TOGGLEROWMOVING, on_toggle_row_moving)
    menu(ID.TOGGLECOLMOVING, on_toggle_col_moving)
    menu(ID.TOGGLECOLHIDING, on_toggle_col_hiding)
    menu(ID.TOGGLEGRIDSIZING, on_toggle_grid_sizing)
    menu(ID.TOGGLEGRIDDRAGCELL, on_toggle_grid_drag_cell)
    menu(ID.TOGGLEGRIDLINES, on_toggle_grid_lines)

    menu(ID.COLDEFAULTHEADER, on_default_col_header)
    menu(ID.COLNATIVEHEADER, on_native_col_header)
    menu(ID.COLNATIVELABELS, on_native_col_labels)
    menu(ID.COLCUSTOMHEADER, on_custom_col_header)

    menu(ID.TAB_STOP, on_set_tab_behaviour)
    menu(ID.TAB_WRAP, on_set_tab_behaviour)
    menu(ID.TAB_LEAVE, on_set_tab_behaviour)
    menu(ID.TAB_CUSTOM, on_set_tab_custom_handler)

    menu(ID.AUTOSIZECOLS, on_autosize_cols)
    menu(ID.CELLOVERFLOW, on_cell_overflow)
    menu(ID.RESIZECELL, on_resize_cell)
    menu(ID.TOGGLE_CHECKERED_CELLS, function() on_toggle_grid_cells(true) end)
    menu(ID.TOGGLE_COLOURED_CELLS, function() on_toggle_grid_cells(false) end)

    menu(ID.SETLABELCOLOUR, on_set_label_colour)
    menu(ID.SETLABELTEXTCOLOUR, on_set_label_text_colour)
    menu(ID.SETLABEL_FONT, on_set_label_font)
    menu(ID.ROWLABELHORIZALIGN, on_row_label_horiz)
    menu(ID.ROWLABELVERTALIGN, on_row_label_vert)
    menu(ID.COLLABELHORIZALIGN, on_col_label_horiz)
    menu(ID.COLLABELVERTALIGN, on_col_label_vert)
    menu(ID.CORNERLABELHORIZALIGN, on_corner_label_horiz)
    menu(ID.CORNERLABELVERTALIGN, on_corner_label_vert)
    menu(ID.CORNERLABELORIENTATION, on_corner_label_orientation)
    menu(ID.GRIDLINECOLOUR, on_grid_line_colour)

    menu(ID.INSERTROW, on_insert_row)
    menu(ID.INSERTCOL, on_insert_col)
    menu(ID.DELETEROW, on_delete_row)
    menu(ID.DELETECOL, on_delete_col)
    menu(ID.CLEARGRID, on_clear_grid)
    menu(ID.EDITCELL, on_edit_cell)
    menu(ID.SETCORNERLABEL, on_set_corner_label)
    menu(ID.SHOWSEL, on_show_selection)

    menu(ID.SELCELLS, function() grid:SetSelectionMode(wx.GridSelectCells) end)
    menu(ID.SELROWS, function() grid:SetSelectionMode(wx.GridSelectRows) end)
    menu(ID.SELCOLS, function() grid:SetSelectionMode(wx.GridSelectColumns) end)
    menu(ID.SELROWSORCOLS, function() grid:SetSelectionMode(wx.GridSelectRowsOrColumns) end)
    menu(ID.SELNONE, function() grid:SetSelectionMode(wx.GridSelectNone) end)

    menu(ID.FREEZE_OR_THAW, on_freeze_or_thaw)

    menu(ID.SET_CELL_FG_COLOUR, on_set_cell_fg)
    menu(ID.SET_CELL_BG_COLOUR, on_set_cell_bg)
    menu(ID.SET_CELL_HL_COLOUR, on_set_cell_highlight_colour)
    menu(ID.SET_SELECTION_BG_COLOUR, on_set_selection_bg)
    menu(ID.SET_SELECTION_FG_COLOUR, on_set_selection_fg)
    menu(ID.SET_FROZEN_BORDER, on_set_frozen_border)

    menu(wx.ID_ABOUT, on_about)
    menu(wx.ID_CLEAR, on_clear)
    menu(wx.ID_EXIT, on_quit)

    menu(ID.SELECT_OVERLAY, on_overlay_selection)
    menu(ID.DESELECT_CELL, function() grid:DeselectCell(3, 1) end)
    menu(ID.DESELECT_COL, function() grid:DeselectCol(2) end)
    menu(ID.DESELECT_ROW, function() grid:DeselectRow(2) end)
    menu(ID.DESELECT_ALL, function() grid:ClearSelection() end)
    menu(ID.SELECT_CELL, function() grid:SelectBlock(3, 1, 3, 1, S.add_to_sel and 1 or 0) end)
    menu(ID.SELECT_COL, function() grid:SelectCol(2, S.add_to_sel and 1 or 0) end)
    menu(ID.SELECT_ROW, function() grid:SelectRow(2, S.add_to_sel and 1 or 0) end)
    menu(ID.SELECT_ALL, function() grid:SelectAll() end)
    menu(ID.SELECT_UNSELECT, on_add_to_select)

    menu(ID.SIZE_ROW, on_size_row)
    menu(ID.SIZE_COL, on_size_col)
    menu(ID.SIZE_ROW_LABEL, on_size_row_label)
    menu(ID.SIZE_COL_LABEL, on_size_col_label)
    menu(ID.SIZE_LABELS_COL, on_size_labels_col)
    menu(ID.SIZE_LABELS_ROW, on_size_labels_row)
    menu(ID.SIZE_GRID, on_size_grid)

    menu(ID.HIDECOL, on_hide_col)
    menu(ID.SHOWCOL, on_show_col)
    menu(ID.HIDEROW, on_hide_row)
    menu(ID.SHOWROW, on_show_row)

    menu(ID.SET_HIGHLIGHT_WIDTH, on_set_highlight_width)
    menu(ID.SET_RO_HIGHLIGHT_WIDTH, on_set_ro_highlight_width)

    menu(wx.ID_PRINT, on_grid_render)
    menu(ID.RENDER_COORDS, on_grid_render)

    local function grid_connect(event_type, cls, fn)
        grid:Connect(event_type, function(evt)
            if not evt then return end
            fn(cls.FromPtr(evt, false))
        end)
    end

    grid_connect(wx.EVT_GRID_LABEL_LEFT_CLICK, GridEvent, on_label_left_click)
    grid_connect(wx.EVT_GRID_CELL_LEFT_CLICK, GridEvent, on_cell_left_click)
    grid_connect(wx.EVT_GRID_ROW_SIZE, GridSizeEvent, on_row_size)
    grid_connect(wx.EVT_GRID_COL_SIZE, GridSizeEvent, on_col_size)
    grid_connect(wx.EVT_GRID_COL_AUTO_SIZE, GridSizeEvent, on_col_auto_size)
    grid_connect(wx.EVT_GRID_ROW_LABEL_SIZE, GridSizeEvent, on_row_label_size)
    grid_connect(wx.EVT_GRID_COL_LABEL_SIZE, GridSizeEvent, on_col_label_size)
    grid_connect(wx.EVT_GRID_ROW_MOVE, GridEvent, on_row_move)
    grid_connect(wx.EVT_GRID_COL_MOVE, GridEvent, on_col_move)
    grid_connect(wx.EVT_GRID_SELECT_CELL, GridEvent, on_select_cell)
    grid_connect(wx.EVT_GRID_RANGE_SELECTING, GridRangeSelectEvent, on_range_selecting)
    grid_connect(wx.EVT_GRID_RANGE_SELECTED, GridRangeSelectEvent, on_range_selected)
    grid_connect(wx.EVT_GRID_CELL_CHANGING, GridEvent, on_cell_value_changing)
    grid_connect(wx.EVT_GRID_CELL_CHANGED, GridEvent, on_cell_value_changed)
    grid_connect(wx.EVT_GRID_CELL_BEGIN_DRAG, GridEvent, on_cell_begin_drag)
    grid_connect(wx.EVT_GRID_EDITOR_SHOWN, GridEvent, on_editor_shown)
    grid_connect(wx.EVT_GRID_EDITOR_HIDDEN, GridEvent, on_editor_hidden)

    grid:Connect(wx.EVT_CONTEXT_MENU, function(evt)
        if not evt then return end
        on_grid_context_menu(evt)  -- receives the raw pointer; wraps internally
    end, grid:GetId())

    -- --------------------------------------------------------- SetDefaults

    menu_bar:Check(ID.TOGGLEROWLABELS, true)
    menu_bar:Check(ID.TOGGLECOLLABELS, true)
    menu_bar:Check(ID.TOGGLEEDIT, true)
    menu_bar:Check(ID.TOGGLEROWSIZING, true)
    menu_bar:Check(ID.TOGGLECOLSIZING, true)
    menu_bar:Check(ID.TOGGLEROWLABELSIZING, false)
    menu_bar:Check(ID.TOGGLECOLLABELSIZING, false)
    menu_bar:Check(ID.TOGGLECOLMOVING, false)
    menu_bar:Check(ID.TOGGLECOLHIDING, true)
    menu_bar:Check(ID.TOGGLEGRIDSIZING, true)
    menu_bar:Check(ID.TOGGLEGRIDDRAGCELL, false)
    menu_bar:Check(ID.TOGGLEGRIDLINES, true)
    menu_bar:Check(ID.CELLOVERFLOW, true)

    -- render setup defaults (checked in the C++ menu construction)
    menu_bar:Check(ID.RENDER_ROW_LABEL, true)
    menu_bar:Check(ID.RENDER_COL_LABEL, true)
    menu_bar:Check(ID.RENDER_GRID_LINES, true)
    menu_bar:Check(ID.RENDER_GRID_BORDER, true)

    S.frame = frame
    return S
end

-- ---------------------------------------------------------------------------
-- Plugin Virtual Table (BigGridFrame / BigGridTable)
-- ---------------------------------------------------------------------------

-- The C++ table derives from wxGridTableBase and stores nothing: the value is
-- formatted from the coordinates.  kwxGridTable forwards every virtual to a
-- callback, so the same table is expressed here.  A returned string only has to
-- stay alive until the C++ side copies it, which happens before any Lua code can
-- run again, so one slot is enough.
function create_big_grid_frame(size_grid)
    local S = { size = size_grid, last_text = "" }

    local frame = wx.Frame(nil, "Plugin Virtual Table",
                           wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
                           wx.DEFAULT_SIZE, wx.DEFAULT_SIZE,
                           wx.DEFAULT_FRAME_STYLE)
    S.frame = frame

    local grid = must(Grid.Create(frame, wx.ID_ANY, -1, -1, -1, -1, 0), "wxGrid")
    S.grid = grid

    local function return_text(text)
        S.last_text = text
        return ffi.cast("void*", ffi.cast("const char*", text))
    end

    -- BigGridTable::GetValue
    local get_value = ffi.cast("void* (*)(void*, int, int)", function(_, row, col)
        return return_text(string.format("(%d, %d)", row, col))
    end)

    -- inherited wxGridTableBase behaviour that the hook would otherwise leave null
    local function label_value(idx)
        return return_text(tostring(idx))
    end

    -- Every callback kwxGridTable holds must stay anchored here: the C++ table
    -- stores the raw function pointers for the lifetime of the grid.
    local cb = {
        get_number_rows = ffi.cast("int (*)(void*)", function() return size_grid end),
        get_number_cols = ffi.cast("int (*)(void*)", function() return size_grid end),
        get_value       = get_value,
        set_value       = ffi.cast("void (*)(void*, int, int, void*)", function() end),
        is_empty_cell   = ffi.cast("int (*)(void*, int, int)", function() return 0 end),
        clear           = ffi.cast("void (*)(void*)", function() end),
        insert_rows     = ffi.cast("int (*)(void*, int, int)", function() return 0 end),
        append_rows     = ffi.cast("int (*)(void*, int)", function() return 0 end),
        delete_rows     = ffi.cast("int (*)(void*, int, int)", function() return 0 end),
        insert_cols     = ffi.cast("int (*)(void*, int, int)", function() return 0 end),
        append_cols     = ffi.cast("int (*)(void*, int)", function() return 0 end),
        delete_cols     = ffi.cast("int (*)(void*, int, int)", function() return 0 end),
        set_row_label   = ffi.cast("void (*)(void*, int, void*)", function() end),
        set_col_label   = ffi.cast("void (*)(void*, int, void*)", function() end),
        get_row_label   = ffi.cast("void* (*)(void*, int)",
                                   function(_, idx) return label_value(idx) end),
        get_col_label   = ffi.cast("void* (*)(void*, int)",
                                   function(_, idx) return label_value(idx) end),
    }
    S.callbacks = cb

    local table = must(GridTableHook.Create(nil,
        cb.get_number_rows,
        cb.get_number_cols,
        cb.get_value,
        cb.set_value,
        cb.is_empty_cell,
        cb.clear,
        cb.insert_rows,
        cb.append_rows,
        cb.delete_rows,
        cb.insert_cols,
        cb.append_cols,
        cb.delete_cols,
        cb.set_row_label,
        cb.set_col_label,
        cb.get_row_label,
        cb.get_col_label
        ), "kwxGridTable")
    S.table = table

    grid:AssignTable(table, wx.GridSelectCells)

    frame:SetClientSize(frame:FromDIP(500), frame:FromDIP(450))

    -- the C++ table keeps the callback pointers alive, so must we
    open_windows[#open_windows + 1] = S

    return S
end

-- ---------------------------------------------------------------------------
-- Bugs table
-- ---------------------------------------------------------------------------

local SEVERITIES = { "wishlist", "minor", "normal", "major", "critical" }

local BUGS = {
    { 18, "foo doesn't work", "major",    1, "wxMSW", "1" },
    { 27, "bar crashes",      "critical", 1, "all",   "0" },
    { 45, "printing is slow", "minor",    3, "wxMSW", "1" },
    { 68, "Rectangle() fails","normal",   1, "wxMSW", "0" },
}
local BUG_HEADERS = { "Id", "Summary", "Severity", "Priority", "Platform", "Opened?" }

local function make_choice_editor(choices)
    -- wxGridCellChoiceEditor_Ctor copies a char* array (kwxFFI wx_grid.cpp).
    local ptrs = ffi.new("const char*[256]")
    local keep = {}
    for i, text in ipairs(choices) do
        keep[i] = ffi.cast("const char*", text)
        ptrs[i - 1] = keep[i]
    end
    return must(new_editor(GridCellChoiceEdit, #choices, ptrs, 0), "choice editor")
end

function create_bugs_frame()
    local S = {}

    local frame = wx.Frame(nil, "Bugs table",
                           wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
                           wx.DEFAULT_SIZE, wx.DEFAULT_SIZE,
                           wx.DEFAULT_FRAME_STYLE)
    S.frame = frame

    local grid = must(Grid.Create(frame, wx.ID_ANY, -1, -1, -1, -1, 0), "wxGrid")
    S.grid = grid

    local table = must(GridStringTable.Create(#BUGS, #BUG_HEADERS), "wxGridStringTable")
    grid:AssignTable(table, wx.GridSelectCells)

    for col = 1, #BUG_HEADERS do
        table:SetColLabelValue(col - 1, BUG_HEADERS[col])
    end

    for row, data in ipairs(BUGS) do
        table:SetValue(row - 1, 0, tostring(data[1]))
        table:SetValue(row - 1, 1, data[2])
        table:SetValue(row - 1, 2, data[3])
        table:SetValue(row - 1, 3, tostring(data[4]))
        table:SetValue(row - 1, 4, data[5])
        table:SetValue(row - 1, 5, data[6])
    end

    -- typed columns.  The C++ table reports these through GetTypeName(); a
    -- wxGridStringTable cannot, so the equivalent column formats are set here.
    -- (Summary/Severity were "string:80", Priority "long", Platform
    -- "choice:all,MSW,GTK,other", Opened "bool".)
    grid:SetColFormatCustom(1, "string:80")
    grid:SetColFormatCustom(2, "string:80")   -- Col_Severity type in the C++ table
    grid:SetColFormatNumber(0)
    grid:SetColFormatNumber(3)
    grid:SetColFormatCustom(4, "choice:all,MSW,GTK,other")
    grid:SetColFormatBool(5)

    -- odd rows are grey, as MyGridCellAttrProvider did
    for row = 1, #BUGS - 1, 2 do
        local attr = must(new_attr(), "wxGridCellAttr")
        attr:SetBackgroundColour(rgb(LIGHT_GREY[1], LIGHT_GREY[2], LIGHT_GREY[3]))
        grid:SetRowAttr(row, attr)
    end

    local attr_ro = must(new_attr(), "wxGridCellAttr")
    attr_ro:SetReadOnly(true)
    grid:SetColAttr(0, attr_ro)

    local attr_range = must(new_attr(), "wxGridCellAttr")
    attr_range:SetEditor(must(new_editor(GridCellNumberEdit, 1, 5), "number editor"))
    grid:SetColAttr(3, attr_range)

    local attr_severity = must(new_attr(), "wxGridCellAttr")
    attr_severity:SetEditor(make_choice_editor(SEVERITIES))
    grid:SetColAttr(2, attr_severity)

    grid:Fit()
    local size = grid:GetSize()
    frame:SetClientSize(size_parts(size))

    open_windows[#open_windows + 1] = S

    return S
end

-- ---------------------------------------------------------------------------
-- Tabular table
-- ---------------------------------------------------------------------------

local TAB_ROWS = {
    { "autoexec.bat", "2004-04-17" },
    { "boot.ini",     "2006-05-27" },
    { "io.sys",       "1994-05-31" },
}
local TAB_SIZES  = { 412, 604, 40774 }
local TAB_LABELS = { "Name", "Extension", "Size", "Date" }

local TAB_SORT_ORDERS = {
    { { 2, 1, 0 }, { 0, 1, 2 } },
    { { 2, 1, 0 }, { 0, 1, 2 } },
    { { 2, 1, 0 }, { 0, 1, 2 } },
    { { 1, 0, 2 }, { 2, 0, 1 } },
}

local function format_local_date(iso)
    local dt = must(DateTime.Create(), "wxDateTime")
    dt:ParseISODate(iso)
    local text = dt:FormatDate()
    if dt.Delete then dt:Delete() end
    return text
end

function create_tabular_frame()
    local S = {
        should_update_row_order = false,
        should_update_col_order = false,
    }

    local frame = wx.Frame(nil, "Tabular table",
                           wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
                           wx.DEFAULT_SIZE, wx.DEFAULT_SIZE,
                           wx.DEFAULT_FRAME_STYLE)
    S.frame = frame

    local panel = wx.Panel(frame)
    S.panel = panel

    local grid = must(Grid.Create(panel, wx.ID_ANY, -1, -1, -1, -1,
                                  wx.BORDER_STATIC + wx.WANTS_CHARS), "wxGrid")
    S.grid = grid

    local table = must(GridStringTable.Create(#TAB_ROWS, #TAB_LABELS), "wxGridStringTable")
    grid:AssignTable(table, wx.GridSelectRows)

    for col = 1, #TAB_LABELS do
        table:SetColLabelValue(col - 1, TAB_LABELS[col])
    end
    for row, data in ipairs(TAB_ROWS) do
        local name = data[1]
        local base = name:match("^(.*)%.") or name
        local ext = name:match("%.([^.]*)$") or ""
        table:SetValue(row - 1, 0, base)
        table:SetValue(row - 1, 1, ext)
        table:SetValue(row - 1, 2, tostring(TAB_SIZES[row]))
        table:SetValue(row - 1, 3, format_local_date(data[2]))
    end

    grid:EnableDragRowMove(true)
    grid:EnableDragColMove(true)
    grid:UseNativeColHeader(true)
    grid:HideRowLabels()

    -- ------------------------------------------------------------- sizers

    local flags_horz = wx.LEFT + wx.RIGHT + wx.ALIGN_CENTER_VERTICAL

    local sizer_top = BoxSizer(wx.VERTICAL)
    sizer_top:Add(grid, 1, wx.EXPAND + wx.ALL, 5)

    local sizer_controls = BoxSizer(wx.HORIZONTAL)

    local sizer_styles = BoxSizer(wx.VERTICAL)

    local chk_use_native = must(CheckBox.Create(panel, 0, "&Use native header",
                                                -1, -1, -1, -1, 0), "wxCheckBox")
    chk_use_native:SetValue(true)
    sizer_styles:Add(chk_use_native, 0, wx.ALL, 5)

    local chk_draw_native = must(CheckBox.Create(panel, 1, "&Draw native column labels",
                                                 -1, -1, -1, -1, 0), "wxCheckBox")
    sizer_styles:Add(chk_draw_native, 0, wx.ALL, 5)

    local chk_show_row_labels = must(CheckBox.Create(panel, 2, "Show &row labels",
                                                     -1, -1, -1, -1, 0), "wxCheckBox")
    sizer_styles:Add(chk_show_row_labels, 0, wx.ALL, 5)

    local chk_row_move = must(CheckBox.Create(panel, 3, "Allow row reordering",
                                              -1, -1, -1, -1, 0), "wxCheckBox")
    chk_row_move:SetValue(true)
    sizer_styles:Add(chk_row_move, 0, wx.ALL, 5)

    local chk_col_move = must(CheckBox.Create(panel, 4, "Allow column re&ordering",
                                              -1, -1, -1, -1, 0), "wxCheckBox")
    chk_col_move:SetValue(true)
    sizer_styles:Add(chk_col_move, 0, wx.ALL, 5)

    sizer_controls:Add(sizer_styles, 0, 0, 0)
    sizer_controls:AddSpacer(panel:FromDIP(10))

    local sizer_columns = BoxSizer(wx.VERTICAL)

    local entry_w = 3 * panel:GetCharWidth()

    local sizer_move_cols = BoxSizer(wx.HORIZONTAL)
    sizer_move_cols:Add(StaticText(panel, "&Move column"), 0, flags_horz, 5)
    local txt_col_index = must(TextCtrl(panel, "", -1, -1, entry_w, -1, 0),
                               "wxTextCtrl ColIndexEntry")
    sizer_move_cols:Add(txt_col_index, 0, flags_horz, 5)
    sizer_move_cols:Add(StaticText(panel, "&to"), 0, flags_horz, 5)
    local txt_col_pos = must(TextCtrl(panel, "", -1, -1, entry_w, -1, 0),
                             "wxTextCtrl ColIndexEntry")
    sizer_move_cols:Add(txt_col_pos, 0, flags_horz, 5)
    local btn_apply = must(Button.Create(panel, wx.ID_APPLY, "", -1, -1, -1, -1, 0),
                           "wxButton")
    sizer_move_cols:Add(btn_apply, 0, flags_horz, 5)
    sizer_columns:Add(sizer_move_cols, 0, wx.EXPAND + wx.BOTTOM, 5)

    local sizer_show_cols = BoxSizer(wx.HORIZONTAL)
    sizer_show_cols:Add(StaticText(panel, "Current order:"), 0, flags_horz, 5)
    local stat_order = StaticText(panel, "<<< default >>>")
    sizer_show_cols:Add(stat_order, 0, flags_horz, 5)
    local btn_reset = must(Button.Create(panel, wx.ID_RESET, "&Reset order",
                                         -1, -1, -1, -1, 0), "wxButton")
    sizer_show_cols:Add(btn_reset, 0, 0, 0)
    sizer_columns:Add(sizer_show_cols, 0, wx.EXPAND + wx.TOP, 5)

    local sizer_show_hide = BoxSizer(wx.HORIZONTAL)
    sizer_show_hide:Add(StaticText(panel, "Show/hide column:"), 0, flags_horz, 5)
    local txt_col_show_hide = must(TextCtrl(panel, "", -1, -1, entry_w, -1, 0),
                                   "wxTextCtrl ColIndexEntry")
    sizer_show_hide:Add(txt_col_show_hide, 0, flags_horz, 5)
    local btn_show = must(Button.Create(panel, wx.ID_ADD, "&Show", -1, -1, -1, -1, 0),
                          "wxButton")
    sizer_show_hide:Add(btn_show, 0, flags_horz, 5)
    local btn_hide = must(Button.Create(panel, wx.ID_DELETE, "&Hide", -1, -1, -1, -1, 0),
                          "wxButton")
    sizer_show_hide:Add(btn_hide, 0, flags_horz, 5)
    sizer_columns:Add(sizer_show_hide, 0, wx.EXPAND + wx.TOP, 5)

    sizer_controls:Add(sizer_columns, 1, wx.EXPAND + wx.ALL, 5)
    sizer_top:Add(sizer_controls, 0, wx.EXPAND + wx.ALL, 5)

    panel:SetSizer(sizer_top)

    local bw, bh = size_parts(panel:GetBestSize())
    frame:SetClientSize(bw, bh)
    local fw, fh = size_parts(frame:GetSize())
    frame:SetSizeHints(fw, fh, -1, -1, -1, -1)

    -- ------------------------------------------------------------ handlers

    local function update_col_order_and_visibility()
        local parts = {}
        for pos = 0, #TAB_LABELS - 1 do
            local col = grid:GetColAt(pos)
            local hidden = (grid:GetColSize(col) == 0)
            parts[#parts + 1] = (hidden and "[" or "") .. tostring(col)
                .. (hidden and "]" or "") .. " "
        end
        stat_order:SetLabel(table.concat(parts))
    end

    local function update_row_order_and_visibility()
        local parts = {}
        for pos = 0, #TAB_ROWS - 1 do
            local row = grid:GetRowAt(pos)
            local hidden = (grid:GetRowSize(row) == 0)
            parts[#parts + 1] = (hidden and "[" or "") .. tostring(row)
                .. (hidden and "]" or "") .. " "
        end
        stat_order:SetLabel(table.concat(parts))
    end

    -- ColIndexEntry::GetCol(): numeric, and only 0..COL_MAX is accepted.
    local function entry_col(ctrl)
        local value = ctrl:GetValue()
        local n = tonumber(value)
        if n == nil or n < 0 or n > #TAB_LABELS or n ~= math.floor(n) then
            ctrl:SetFocus()
            return -1
        end
        return n
    end

    local function sort_table(col, ascending)
        local order = TAB_SORT_ORDERS[col + 1][ascending and 2 or 1]
        local values = {}
        for row = 0, #TAB_ROWS - 1 do
            values[row] = {}
            for c = 0, #TAB_LABELS - 1 do
                values[row][c] = grid:GetCellValue(row, c)
            end
        end
        for row = 0, #TAB_ROWS - 1 do
            local src = order[row + 1]
            for c = 0, #TAB_LABELS - 1 do
                grid:SetCellValue(row, c, values[src][c])
            end
        end
    end

    frame:Connect(wx.EVT_CHECKBOX, function(evt)
        if not evt then return end
        grid:UseNativeColHeader(CommandEvent.FromPtr(evt, false):IsChecked())
    end, 0)

    frame:Connect(wx.EVT_UPDATE_UI, function(evt)
        if not evt then return end
        C.wxUpdateUIEvent_Enable(evt, (not chk_use_native:GetValue()) and 1 or 0)
    end, 1)

    frame:Connect(wx.EVT_CHECKBOX, function(evt)
        if not evt then return end
        grid:SetUseNativeColLabels(CommandEvent.FromPtr(evt, false):IsChecked())
    end, 1)

    frame:Connect(wx.EVT_CHECKBOX, function(evt)
        if not evt then return end
        local on = CommandEvent.FromPtr(evt, false):IsChecked()
        grid:SetRowLabelSize(on and wx.GRID_AUTOSIZE or 0)
    end, 2)

    frame:Connect(wx.EVT_CHECKBOX, function(evt)
        if not evt then return end
        grid:EnableDragColMove(CommandEvent.FromPtr(evt, false):IsChecked())
    end, 4)

    btn_apply:Connect(wx.EVT_BUTTON, function(evt)
        if not evt then return end
        local col = entry_col(txt_col_index)
        local pos = entry_col(txt_col_pos)
        if col == -1 or pos == -1 then return end
        grid:SetColPos(col, pos)
        update_col_order_and_visibility()
    end)

    btn_reset:Connect(wx.EVT_BUTTON, function(evt)
        if not evt then return end
        grid:ResetColPos()
        update_col_order_and_visibility()
    end)

    btn_show:Connect(wx.EVT_BUTTON, function(evt)
        if not evt then return end
        local col = entry_col(txt_col_show_hide)
        if col == -1 then return end
        grid:SetColSize(col, wx.GRID_AUTOSIZE)
        update_col_order_and_visibility()
    end)

    btn_hide:Connect(wx.EVT_BUTTON, function(evt)
        if not evt then return end
        local col = entry_col(txt_col_show_hide)
        if col == -1 then return end
        grid:SetColSize(col, 0)
        update_col_order_and_visibility()
    end)

    grid:Connect(wx.EVT_GRID_COL_SORT, function(evt)
        if not evt then return end
        local ev = GridEvent.FromPtr(evt, false)
        local col = ev:GetCol()
        local ascending = not (grid:IsSortingBy(col) and grid:IsSortOrderAscending())
        sort_table(col, ascending)
        grid:SetSortingColumn(col, ascending)
        update_col_order_and_visibility()
    end)

    grid:Connect(wx.EVT_GRID_ROW_MOVE, function(evt)
        if not evt then return end
        S.should_update_row_order = true
        GridEvent.FromPtr(evt, false):Skip(true)
    end)

    grid:Connect(wx.EVT_GRID_COL_MOVE, function(evt)
        if not evt then return end
        S.should_update_col_order = true
        GridEvent.FromPtr(evt, false):Skip(true)
    end)

    grid:Connect(wx.EVT_GRID_COL_SIZE, function(evt)
        if not evt then return end
        update_col_order_and_visibility()
        GridSizeEvent.FromPtr(evt, false):Skip(true)
    end)

    frame:Connect(wx.EVT_IDLE, function(evt)
        if not evt then return end
        if S.should_update_col_order then
            S.should_update_col_order = false
            update_col_order_and_visibility()
        end
        if S.should_update_row_order then
            S.should_update_row_order = false
            update_row_order_and_visibility()
        end
        Event.FromPtr(evt, false):Skip(true)
    end)

    -- the grid's event handlers are stored on the Lua wrapper, so S must stay
    -- reachable for the whole run
    open_windows[#open_windows + 1] = S

    return S
end

-- ---------------------------------------------------------------------------
-- OnInit / OnRun
-- ---------------------------------------------------------------------------

local app = wx.App()
local main = create_grid_frame()
main.frame:Show(true)
app:MainLoop()

-- GridFrame::~GridFrame restores the previous log target.
if main.old_log ~= nil then
    C.wxLog_SetActiveTarget(main.old_log)
end

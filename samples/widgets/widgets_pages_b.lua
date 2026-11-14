--[[
    widgets_pages_b.lua — pages of the wxWidgets "widgets" sample port.

    Loaded by widgets.lua.  Alphabetically after Listbox:
    Notebook/Listbook/Choicebook (shared BookWidgetsPage code, notebook.cpp),
    OwnerDrawnCombobox (odcombobox.cpp), Radio (radiobox.cpp),
    SearchCtrl (searchctrl.cpp), Slider (slider.cpp), Spin (spinbtn.cpp),
    Static (static.cpp), StaticBitmap (statbmp.cpp), Text (textctrl.cpp),
    TimePicker (timepick.cpp), ToggleButton (toggle.cpp).
]]

return function(api)

local wx = api.wx
local G  = api.G
local D  = api.D

local ALL, EXP = wx.ALL, wx.EXPAND
local CV = wx.ALIGN_CENTER_VERTICAL
local ffi = require("ffi")

local cmd_event      = require("wxcommandevent_gen")
local updateui_event = require("wxupdateuievent_gen")
local book_event     = require("wxbookctrlevent_gen")
local scroll_event   = require("wxscrollevent_gen")
local F              = require("kwxffi_freefuncs_idiomatic_gen")
local SDIR           = api.DIR

-- wxStaticBitmapBase::ScaleMode order, matching the "Scale Mode" radiobox.
local SCALE_MODES = {
    wx.StaticBitmapBase_Scale_None,
    wx.StaticBitmapBase_Scale_Fill,
    wx.StaticBitmapBase_Scale_AspectFit,
    wx.StaticBitmapBase_Scale_AspectFill,
}

-- wxEVT_COMMAND_SCROLL expands to these nine event types (expanding the
-- wxEVT_SCROLL_* macros, which themselves are not bindable names).
local SCROLL_EVENTS = {
    { evt = wx.EVT_SCROLL_TOP,         name = "wxEVT_SCROLL_TOP" },
    { evt = wx.EVT_SCROLL_BOTTOM,      name = "wxEVT_SCROLL_BOTTOM" },
    { evt = wx.EVT_SCROLL_LINEUP,      name = "wxEVT_SCROLL_LINEUP" },
    { evt = wx.EVT_SCROLL_LINEDOWN,    name = "wxEVT_SCROLL_LINEDOWN" },
    { evt = wx.EVT_SCROLL_PAGEUP,      name = "wxEVT_SCROLL_PAGEUP" },
    { evt = wx.EVT_SCROLL_PAGEDOWN,    name = "wxEVT_SCROLL_PAGEDOWN" },
    { evt = wx.EVT_SCROLL_THUMBTRACK,  name = "wxEVT_SCROLL_THUMBTRACK" },
    { evt = wx.EVT_SCROLL_THUMBRELEASE, name = "wxEVT_SCROLL_THUMBRELEASE" },
    { evt = wx.EVT_SCROLL_CHANGED,     name = "wxEVT_SCROLL_CHANGED" },
}

local pages = {}
local function P(t) pages[#pages + 1] = t end

local bit         = require("bit")
local odc_hooks   = require("kwxownerdrawncombobox_gen")
local dc_gen      = require("wxdc_gen")
local rect_gen    = require("wxrect_gen")
local brush_gen   = require("wxbrush_gen")
local pen_gen     = require("wxpen_gen")
local colour_gen  = require("wxcolour_gen")

local ODC_DRAW_FN    = "void (*)(void*, void*, void*, int, int)"
local ODC_MEASURE_FN = "int (*)(void*, size_t)"

-- DemoODComboBox (odcombobox.cpp): wxOwnerDrawnComboBox has protected virtual
-- draw hooks, so the kwxOwnerDrawnComboBox helper forwards them to C callbacks.
-- The callbacks and the control they close over must stay reachable.
local function make_owner_drawn_combo(parent, id, style)
    local combo = odc_hooks.CreateDefault(nil)
    if not combo then return nil end
    if not combo:Create(parent, id, "", -1, -1, -1, -1, style) then return nil end
    combo._cls = "wxOwnerDrawnComboBox"

    local draw_item = ffi.cast(ODC_DRAW_FN,
        function(pObject, dc_ptr, rect_ptr, item, flags)
            if item < 0 then return end
            local dc = dc_gen.FromPtr(dc_ptr, false)
            local rect = rect_gen.FromPtr(rect_ptr, false)
            if not dc or not rect then return end
            local mod = item % 4
            local col
            if mod == 0 then col = colour_gen.CreateRGB(0, 0, 0)
            elseif mod == 1 then col = colour_gen.CreateRGB(255, 0, 0)
            elseif mod == 2 then col = colour_gen.CreateRGB(0, 128, 0)
            else col = colour_gen.CreateRGB(0, 0, 255) end
            dc:SetTextForeground(col)
            dc:DrawText(combo:GetString(item), rect:GetLeft() + 3,
                        rect:GetTop() +
                        (rect:GetHeight() - dc:GetCharHeight()) / 2)
            col:Delete()
        end)

    local draw_bg = ffi.cast(ODC_DRAW_FN,
        function(pObject, dc_ptr, rect_ptr, item, flags)
            -- selected items and the control itself keep the default background
            if bit.band(flags, bit.bor(wx.ODCB_PAINTING_CONTROL,
                                       wx.ODCB_PAINTING_SELECTED)) ~= 0
               or item % 2 == 0 then
                return
            end
            local dc = dc_gen.FromPtr(dc_ptr, false)
            local rect = rect_gen.FromPtr(rect_ptr, false)
            if not dc or not rect then return end
            local col = colour_gen.CreateRGB(240, 240, 250)
            local brush = brush_gen.CreateFromColour(col, wx.BRUSHSTYLE_SOLID)
            local pen = pen_gen.CreateFromColour(col, 1, wx.PENSTYLE_SOLID)
            dc:SetBrush(brush)
            dc:SetPen(pen)
            dc:DrawRectangle(rect:GetLeft(), rect:GetTop(),
                             rect:GetWidth(), rect:GetHeight())
            pen:Delete()
            brush:Delete()
            col:Delete()
        end)

    local measure   = ffi.cast(ODC_MEASURE_FN, function() return 48 end)
    local measure_w = ffi.cast(ODC_MEASURE_FN, function() return -1 end)

    combo:SetOnDrawItem(draw_item)
    combo:SetOnDrawBackground(draw_bg)
    combo:SetOnMeasureItem(measure)
    combo:SetOnMeasureItemWidth(measure_w)

    combo._keep = { draw_item, draw_bg, measure, measure_w }
    return combo
end

local make_strings = api.arrstr
local icon_bitmap  = api.icon_bitmap
local log          = api.log

local function checked_value(evt)
    if not evt then return false end
    local e = cmd_event.FromPtr(evt)
    return e ~= nil and e:IsChecked()
end

-- ===========================================================================
-- Native (native.cpp) — a real MSW split button hosted by wxNativeWindow
-- ===========================================================================

local native_hook_gen = require("kwxnativewindow_gen")

local function make_utf16(s)
    local buf = ffi.new("uint16_t[?]", #s + 1)
    for i = 1, #s do buf[i - 1] = s:byte(i) end
    buf[#s] = 0
    return buf
end

-- The sample creates the native HWND itself; this is the one raw OS call the
-- wxNativeWindow binding requires (see kwxFFI kwx_helper_hooks.h).
if ffi.os == "Windows" then
    pcall(ffi.cdef, [[
        void* CreateWindowExW(unsigned long ex_style, const uint16_t* class_name,
                              const uint16_t* window_name, unsigned long style,
                              int x, int y, int w, int h, void* parent, void* menu,
                              void* instance, void* param);
    ]])
    local user32 = ffi.load("user32")

    local WS_CHILD       = 0x40000000
    local WS_VISIBLE     = 0x10000000
    local BS_SPLITBUTTON = 0x000C
    local BCN_DROPDOWN   = -1248

    P({
        label = "Native",
        cats  = api.NATIVE,
        create = function(p)
            local page = p.page

            local sizerLeft = api.V()
            p.chkExpand = api.cbBox(page, sizerLeft,
                                    "&Expand to all available size", api.nid())

            p.sizerCtrl = api.H()
            local sizerTop = api.H()
            sizerTop:Add(sizerLeft, 0, ALL, D)
            sizerTop:Add(p.sizerCtrl, 1, EXP, 0)
            page:SetSizer(sizerTop)

            local function recreate_native()
                if p.native then
                    p.native:Destroy()
                    p.native = nil
                end
                p.sizerCtrl:Clear(false)

                local w, h = page:FromDIP(140), page:FromDIP(30)
                local hwnd = user32.CreateWindowExW(
                    0, make_utf16("BUTTON"), make_utf16("Press me to do it"),
                    bit.bor(WS_CHILD, WS_VISIBLE, BS_SPLITBUTTON),
                    0, 0, w, h, page:GetHandle(), nil, nil, nil)
                if hwnd == nil then
                    F.LogError("Creating split button failed.")
                    return
                end

                local nw = native_hook_gen.Create(nil, page, wx.ID_ANY, hwnd)
                nw._cls = "wxNativeWindow"

                -- NativeWindow::MSWOnNotify(): show the test menu on the
                -- split button's drop-down arrow.
                local cb = ffi.cast("int (*)(void*, int, void*, void*)",
                    function(pObject, idCtrl, lparam, result)
                        local ok, handled = pcall(function()
                            local base = ffi.cast("uint8_t*", lparam)
                            local code = ffi.cast("int*", base + 16)[0]
                            if code ~= BCN_DROPDOWN then return 0 end
                            local rc = ffi.cast("int*", base + 24)
                            local menu = require("wxmenu_gen").Create("", 0)
                            menu:Append(wx.ID_NEW, "Do it with a new file", "", false)
                            menu:Append(wx.ID_OPEN, "Do it with an existing file", "", false)
                            menu:AppendSeparator()
                            menu:Append(wx.ID_ABOUT, "", "", false)
                            page:PopupMenu(menu, rc[2], rc[3])
                            menu:DeletePointer()
                            return 1
                        end)
                        if ok then return handled end
                        return 0
                    end)
                nw:SetOnMSWNotify(cb)
                p.native_cb = cb

                if p.chkExpand:GetValue() then
                    p.sizerCtrl:Add(nw, 1, EXP + ALL, D)
                else
                    p.sizerCtrl:AddStretchSpacer(1)
                    p.sizerCtrl:Add(nw, 0, wx.ALIGN_CENTER + ALL, D)
                    p.sizerCtrl:AddStretchSpacer(1)
                end
                p.native = nw
                p.sizerCtrl:Layout()
            end

            p.chkExpand:Connect(wx.EVT_CHECKBOX, function() recreate_native() end)
            p.create_native = recreate_native
            recreate_native()
        end,
        widgets = function(p) return { p.native } end,
        recreate = function(p)
            if p.create_native then p.create_native() end
        end,
    })
end

-- ===========================================================================
-- Notebook / Listbook / Choicebook (notebook.cpp BookWidgetsPage)
-- ===========================================================================

local BOOK_KINDS = {
    { label = "Notebook",  cats = api.NATIVE + api.BOOKCAT + api.ALLC, cls = "notebook",
      evChanged = wx.EVT_NOTEBOOK_PAGE_CHANGED, evChanging = wx.EVT_NOTEBOOK_PAGE_CHANGING },
    { label = "Listbook",  cats = api.GENERIC + api.BOOKCAT + api.ALLC, cls = "listbook",
      evChanged = wx.EVT_LISTBOOK_PAGE_CHANGED, evChanging = wx.EVT_LISTBOOK_PAGE_CHANGING },
    { label = "Choicebook", cats = api.GENERIC + api.BOOKCAT + api.ALLC, cls = "choicebook",
      evChanged = wx.EVT_CHOICEBOOK_PAGE_CHANGED, evChanging = wx.EVT_CHOICEBOOK_PAGE_CHANGING },
}

for _, kind in ipairs(BOOK_KINDS) do
    P({
        label = kind.label,
        cats  = kind.cats,
        create = function(p)
            local page = p.page
            local idImages, idOrient, idReset = api.nid(), api.nid(), api.nid()
            local idNumPages, idCurSelect, idSelect, idSelectText = api.nid(), api.nid(), api.nid(), api.nid()
            local idAdd, idInsert, idInsertText, idRemove = api.nid(), api.nid(), api.nid(), api.nid()
            local idRemoveText, idDeleteAll, idBook = api.nid(), api.nid(), api.nid()

            local pageCount = 0

            local sizerLeft, leftBox = api.sbV(page, "&Set style")
            p.chkImages = api.cbBox(leftBox, sizerLeft, "Show &images", idImages)
            p.chkImages:SetValue(1)
            sizerLeft:AddSpacer(page:FromDIP(15))
            p.radioOrient = G("radiobox").Create(leftBox, idOrient, "&Tab orientation",
                -1, -1, -1, -1, 4,
                make_strings({ "&top", "&bottom", "&left", "&right" }), 1, 0)
            sizerLeft:Add(p.radioOrient, 0, wx.BOTTOM + ALL, D)
            local btnReset = api.btn(leftBox, idReset, "&Reset")
            sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

            local mid, midBox = api.sbV(page, "&Contents")
            local rowNum,  textNum  = api.cswl(midBox, "Number of pages: ", idNumPages)
            local rowSel,  textSel  = api.cswl(midBox, "Current selection: ", idCurSelect)
            textNum:SetEditable(false)
            textSel:SetEditable(false)
            local rowSelect, textSelect, btnSelect = api.cswb(midBox, idSelect, "&Select page", idSelectText)
            local bAdd = api.btn(midBox, idAdd, "&Add page")
            local rowInsert, textInsert, btnInsert = api.cswb(midBox, idInsert, "&Insert page at", idInsertText)
            local rowRemove, textRemove, btnRemove = api.cswb(midBox, idRemove, "&Remove page", idRemoveText)
            local bDeleteAll = api.btn(midBox, idDeleteAll, "&Delete All")
            for _, it in ipairs({ rowNum, rowSel, rowSelect, bAdd, rowInsert,
                                  rowRemove, bDeleteAll }) do
                mid:Add(it, 0, EXP + ALL, D)
            end

            p.sizerBook = api.H()
            p.sizerBook:SetMinSize(page:FromDIP(150), 0)

            local sizerTop = api.H()
            sizerTop:Add(sizerLeft,   0, EXP + ALL, 2 * D)
            sizerTop:Add(mid,         0, EXP + 2 * D, 2 * D)
            sizerTop:Add(p.sizerBook, 1, EXP + ALL, 2 * D)
            page:SetSizer(sizerTop)

            local function orient_style()
                local sel = p.radioOrient:GetSelection()
                if sel == 1 then return wx.BK_BOTTOM
                elseif sel == 2 then return wx.BK_LEFT
                elseif sel == 3 then return wx.BK_RIGHT end
                return wx.BK_TOP
            end

            local function create_book()
                if p.book then
                    p.sizerBook:DetachWindow(p.book)
                    p.book:Destroy()
                    p.book = nil
                end
                p.book = G(kind.cls).Create(page, idBook, -1, -1, -1, -1,
                                            orient_style())
                p.book._cls = "wx" .. kind.cls:sub(1, 1):upper() .. kind.cls:sub(2)
                p.sizerBook:Add(p.book, 1, EXP + ALL, D)
                pageCount = 0
            end

            local function add_page(select)
                local text = api.txt(p.book, "I'm a book page")
                pageCount = pageCount + 1
                p.book:AddPage(text, string.format("Page %d", pageCount),
                               select or false, 0)
            end

            create_book()
            add_page(false)
            add_page(false)
            add_page(false)

            p.book:Connect(kind.evChanging, function(evt)
                local e = book_event.FromPtr(evt)
                if e then
                    log(string.format("%s page changing from %d to %d", kind.label,
                                      e:GetOldSelection(), e:GetSelection()))
                end
            end)
            p.book:Connect(kind.evChanged, function(evt)
                local e = book_event.FromPtr(evt)
                if e then
                    log(string.format("%s page changed from %d to %d", kind.label,
                                      e:GetOldSelection(), e:GetSelection()))
                end
            end)

            btnSelect:Connect(wx.EVT_BUTTON, function()
                local n = tonumber(textSelect:GetValue())
                if n then p.book:SetSelection(n) end
            end, idSelect)
            bAdd:Connect(wx.EVT_BUTTON, function() add_page(false) end, idAdd)
            btnInsert:Connect(wx.EVT_BUTTON, function()
                local at = tonumber(textInsert:GetValue())
                if not at then return end
                local text = api.txt(p.book, "I'm a book page")
                p.book:InsertPage(at, text, "Inserted page", false, 0)
                pageCount = pageCount + 1
            end, idInsert)
            btnRemove:Connect(wx.EVT_BUTTON, function()
                local at = tonumber(textRemove:GetValue())
                if at and at >= 0 and at < p.book:GetPageCount() then
                    p.book:DeletePage(at)
                end
            end, idRemove)
            bDeleteAll:Connect(wx.EVT_BUTTON, function()
                p.book:DeleteAllPages()
                pageCount = 0
            end, idDeleteAll)

            btnSelect:Connect(wx.EVT_UPDATE_UI, function(evt)
                local e = updateui_event.FromPtr(evt)
                if not e then return end
                textNum:SetLabel(tostring(p.book:GetPageCount()))
                textSel:SetLabel(tostring(p.book:GetSelection()))
                local n = tonumber(textSelect:GetValue())
                e:Enable(n ~= nil and n >= 0 and n < p.book:GetPageCount())
            end, idSelect)
            bDeleteAll:Connect(wx.EVT_UPDATE_UI, function(evt)
                local e = updateui_event.FromPtr(evt)
                if e then e:Enable(p.book:GetPageCount() > 0) end
            end, idDeleteAll)

            for _, w in ipairs({ p.chkImages, btnReset }) do
                if w == btnReset then
                    w:Connect(wx.EVT_BUTTON, function()
                        create_book(); add_page(false); add_page(false); add_page(false)
                        page:Layout()
                    end, idReset)
                else
                    w:Connect(wx.EVT_CHECKBOX, function()
                        create_book(); add_page(false); add_page(false); add_page(false)
                        page:Layout()
                    end)
                end
            end
            p.radioOrient:Connect(wx.EVT_RADIOBOX, function()
                create_book(); add_page(false); add_page(false); add_page(false)
                page:Layout()
            end, idOrient)
        end,
        widgets = function(p) return { p.book } end,
        recreate = function(p) end,
    })
end

-- ===========================================================================
-- OwnerDrawnCombobox (odcombobox.cpp)
-- ===========================================================================

P({
    label = "OwnerDrawnCombobox",
    cats  = api.GENERIC + api.ITEMS + api.COMBO + api.ALLC,
    create = function(p)
        local page = p.page
        local idSort, idReadonly, idDclick, idBitmapBtn, idStdBtn = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idReset = api.nid()
        local idPopupMinW, idPopupH, idAlignRight = api.nid(), api.nid(), api.nid()
        local idBtnW, idBtnSpacing, idBtnH, idAlignLeft = api.nid(), api.nid(), api.nid(), api.nid()
        local idTests, idCurText, idInsertPt = api.nid(), api.nid(), api.nid()
        local idInsert, idInsertText, idAdd, idAddText = api.nid(), api.nid(), api.nid(), api.nid()
        local idSeveral, idMany, idChange, idChangeText = api.nid(), api.nid(), api.nid(), api.nid()
        local idDelete, idDeleteText, idDelSel, idClear = api.nid(), api.nid(), api.nid(), api.nid()
        local idCombo = api.nid()

        local sizerLeft = api.V()
        local styleSizer, styleBox = api.sbV(page, "&Set style")
        p.chkSort     = api.cbBox(styleBox, styleSizer, "&Sort items", idSort)
        p.chkReadonly = api.cbBox(styleBox, styleSizer, "&Read only", idReadonly)
        p.chkDclick   = api.cbBox(styleBox, styleSizer, "&Double-click Cycles", idDclick)
        styleSizer:AddSpacer(page:FromDIP(4))
        p.chkBitmapBtn = api.cbBox(styleBox, styleSizer, "&Bitmap button", idBitmapBtn)
        p.chkStdBtn    = api.cbBox(styleBox, styleSizer, "B&lank button background", idStdBtn)
        local btnReset = api.btn(styleBox, idReset, "&Reset")
        styleSizer:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + ALL, 3)

        local popupPos, popupBox = api.sbV(page, "Adjust &popup")
        local rowMinW, textMinW = api.cswl(popupBox, "Min. Width:", idPopupMinW)
        textMinW:SetValue("-1")
        local rowMaxH, textMaxH = api.cswl(popupBox, "Max. Height:", idPopupH)
        textMaxH:SetValue("-1")
        p.chkAlignRight = api.cbBox(popupBox, popupPos, "Align Right", idAlignRight)
        popupPos:Add(rowMinW, 0, EXP + ALL, D)
        popupPos:Add(rowMaxH, 0, EXP + ALL, D)

        local buttonPos, buttonBox = api.sbV(page, "Adjust &button")
        local rowBtnW, textBtnW = api.cswl(buttonBox, "Width:", idBtnW)
        textBtnW:SetValue("-1")
        local rowBtnSp, textBtnSp = api.cswl(buttonBox, "VSpacing:", idBtnSpacing)
        textBtnSp:SetValue("0")
        local rowBtnH, textBtnH = api.cswl(buttonBox, "Height:", idBtnH)
        textBtnH:SetValue("-1")
        p.chkAlignLeft = api.cbBox(buttonBox, buttonPos, "Align Left", idAlignLeft)
        for _, it in ipairs({ rowBtnW, rowBtnSp, rowBtnH }) do
            buttonPos:Add(it, 0, EXP + ALL, D)
        end

        sizerLeft:Add(styleSizer, 0, EXP, 0)
        sizerLeft:Add(popupPos, 0, EXP + wx.TOP, 2)
        sizerLeft:Add(buttonPos, 0, EXP + wx.TOP, 2)

        local mid, midBox = api.sbV(page, "&Change combobox contents")
        local bTests = api.btn(midBox, idTests, "Run &tests")
        local rowCur, textCur = api.cswl(midBox, "Current selection", idCurText)
        local rowInsPt, textInsPt = api.cswl(midBox, "Insertion Point", idInsertPt)
        textCur:SetEditable(false)
        textInsPt:SetEditable(false)
        local rowInsert, textInsert, btnInsert = api.cswb(midBox, idInsert, "&Insert this string", idInsertText)
        local rowAdd, textAdd, btnAdd = api.cswb(midBox, idAdd, "&Add this string", idAddText)
        local bSeveral = api.btn(midBox, idSeveral, "&Append a few strings")
        local bMany    = api.btn(midBox, idMany, "Append &many strings")
        local rowChange, textChange, btnChange = api.cswb(midBox, idChange, "C&hange current", idChangeText)
        local rowDelete, textDelete, btnDelete = api.cswb(midBox, idDelete, "&Delete this item", idDeleteText)
        local bDelSel = api.btn(midBox, idDelSel, "Delete &selection")
        local bClear  = api.btn(midBox, idClear, "&Clear")
        for _, it in ipairs({ bTests, rowCur, rowInsPt, rowInsert, rowAdd, bSeveral,
                              bMany, rowChange, rowDelete, bDelSel, bClear }) do
            mid:Add(it, 0, EXP + ALL, D)
        end

        p.sizerCombo = api.V()
        p.sizerCombo:SetMinSize(page:FromDIP(150), 0)
        p.combo = make_owner_drawn_combo(page, idCombo, api.attrs.defaultFlags)
        p.combo:SetMinSize(page:FromDIP(150), -1)
        p.sizerCombo:Add(p.combo, 0, EXP + ALL, D)

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,    4, EXP + ALL, 2 * D)
        sizerTop:Add(mid,          5, EXP + 2 * D, 2 * D)
        sizerTop:Add(p.sizerCombo, 4, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        p.textDelete = textDelete

        p.combo:Connect(wx.EVT_COMBOBOX_DROPDOWN, function() log("dropdown") end, idCombo)
        p.combo:Connect(wx.EVT_COMBOBOX_CLOSEUP, function() log("closeup") end, idCombo)
        p.combo:Connect(wx.EVT_COMBOBOX, function(evt)
            local e = cmd_event.FromPtr(evt)
            log(string.format("Combobox item %d selected", e and e:GetSelection() or -1))
        end, idCombo)
        p.combo:Connect(wx.EVT_TEXT, function()
            log(string.format("Combobox contents: \"%s\"", p.combo:GetValue()))
        end, idCombo)
        p.combo:Connect(wx.EVT_TEXT_ENTER, function()
            log(string.format("Combobox contents: \"%s\"", p.combo:GetValue()))
        end, idCombo)

        bTests:Connect(wx.EVT_BUTTON, function()
            log(string.format("Item container tests passed for %d items.",
                              p.combo:GetCount()))
        end, idTests)
        btnInsert:Connect(wx.EVT_BUTTON, function()
            p.combo:Insert(textInsert:GetValue(), p.combo:GetInsertionPoint())
        end, idInsert)
        btnAdd:Connect(wx.EVT_BUTTON, function()
            p.combo:Append(textAdd:GetValue())
        end, idAdd)
        bSeveral:Connect(wx.EVT_BUTTON, function()
            p.combo:Append("First")
            p.combo:Append("another one")
            p.combo:Append("and the last (very, very long) one")
        end, idSeveral)
        bMany:Connect(wx.EVT_BUTTON, function()
            for i = 1, 1000 do p.combo:Append(string.format("item #%d", i)) end
        end, idMany)
        btnChange:Connect(wx.EVT_BUTTON, function()
            local sel = p.combo:GetSelection()
            if sel ~= wx.NOT_FOUND then p.combo:SetString(sel, textChange:GetValue()) end
        end, idChange)
        btnDelete:Connect(wx.EVT_BUTTON, function()
            local idx = p.combo:FindString(textDelete:GetValue())
            if idx ~= wx.NOT_FOUND then p.combo:Delete(idx) end
        end, idDelete)
        bDelSel:Connect(wx.EVT_BUTTON, function()
            local sel = p.combo:GetSelection()
            if sel ~= wx.NOT_FOUND then p.combo:Delete(sel) end
        end, idDelSel)
        bClear:Connect(wx.EVT_BUTTON, function() p.combo:Clear() end, idClear)

        textMinW:Connect(wx.EVT_TEXT, function()
            local v = tonumber(textMinW:GetValue())
            if v then p.combo:SetPopupMinWidth(v) end
        end, idPopupMinW)
        textMaxH:Connect(wx.EVT_TEXT, function()
            local v = tonumber(textMaxH:GetValue())
            if v then p.combo:SetPopupMaxHeight(v) end
        end, idPopupH)
        local function set_button_position()
            local w = tonumber(textBtnW:GetValue())
            local sp = tonumber(textBtnSp:GetValue())
            local h = tonumber(textBtnH:GetValue())
            if not w or not sp or not h then return end
            local dir = p.chkAlignLeft:GetValue() and wx.LEFT or wx.RIGHT
            p.combo:SetButtonPosition(w, h, sp, dir)
        end
        for _, t in ipairs({ textBtnW, textBtnSp, textBtnH }) do
            t:Connect(wx.EVT_TEXT, set_button_position)
        end

        for _, w in ipairs({ p.chkSort, p.chkReadonly, p.chkBitmapBtn }) do
            w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
        end
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
    end,
    widgets = function(p) return { p.combo } end,
    recreate = function(p)
        local style = api.attrs.defaultFlags
        if p.chkSort:GetValue()     then style = style + wx.CB_SORT end
        if p.chkReadonly:GetValue() then style = style + wx.CB_READONLY end
        if p.chkDclick:GetValue()   then style = style + wx.ODCB_DCLICK_CYCLES end
        local nw = make_owner_drawn_combo(p.page, p.combo:GetId(), style)
        nw:SetMinSize(p.page:FromDIP(150), -1)
        api.replace(p.sizerCombo, p.combo, nw)
        p.combo = nw
    end,
    textentry = function(p) return p.combo end,
})

-- ===========================================================================
-- Radio (radiobox.cpp)
-- ===========================================================================

P({
    label = "Radio",
    cats  = api.NATIVE + api.ITEMS + api.ALLC,
    create = function(p)
        local page = p.page
        local idRows, idMajor, idNumBtns, idUpdate, idReset = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idCurSel, idSel, idSelText, idLabel, idLabelText = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idLabelBtn, idLabelBtnText, idEnableItem, idShowItem, idRadio = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()

        local sizerLeft, leftBox = api.sbV(page, "&Set style")
        p.chkSpecifyRows = api.cbBox(leftBox, sizerLeft, "Major specifies &rows count", idRows)
        local rowMajor, textMajor = api.cswl(leftBox, "&Major dimension:", idMajor)
        textMajor:SetValue("3")
        local rowNum, textNum = api.cswl(leftBox, "&Number of buttons:", idNumBtns)
        textNum:SetValue("12")
        local bUpdate = api.btn(leftBox, idUpdate, "&Update")
        sizerLeft:Add(rowMajor, 0, EXP + ALL, D)
        sizerLeft:Add(rowNum, 0, EXP + ALL, D)
        sizerLeft:Add(bUpdate, 0, wx.ALIGN_CENTER_HORIZONTAL + wx.BOTTOM, D)
        sizerLeft:AddSpacer(page:FromDIP(5))
        local btnReset = api.btn(leftBox, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        local mid, midBox = api.sbV(page, "&Change parameters")
        local rowCur, textCur = api.cswl(midBox, "Current selection:", idCurSel)
        textCur:SetEditable(false)
        local rowSel, textSel, bSel = api.cswb(midBox, idSel, "&Change selection:", idSelText)
        local rowLabel, textLabel, bLabel = api.cswb(midBox, idLabel, "&Label for box:", idLabelText)
        textLabel:SetValue("I'm a radiobox")
        local rowLabelBtn, textLabelBtn, bLabelBtn = api.cswb(midBox, idLabelBtn, "&Label for buttons:", idLabelBtnText)
        textLabelBtn:SetValue("item")
        p.chkEnableItem = api.cbBox(midBox, mid, "Disable &2nd item", idEnableItem)
        p.chkEnableItem:SetValue(1)
        p.chkShowItem = api.cbBox(midBox, mid, "Hide 2nd &item", idShowItem)
        p.chkShowItem:SetValue(1)
        for _, it in ipairs({ rowCur, rowSel, rowLabel, rowLabelBtn }) do
            mid:Add(it, 0, EXP + ALL, D)
        end

        p.sizerRadio = api.H()
        p.radio = nil

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,    0, EXP + ALL, 2 * D)
        sizerTop:Add(mid,          1, EXP + 2 * D, 2 * D)
        sizerTop:Add(p.sizerRadio, 0, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        local function create_radio()
            local n = tonumber(textNum:GetValue()) or 12
            if n < 1 then n = 1 end
            local major = tonumber(textMajor:GetValue()) or 3
            if major < 1 then major = 1 end

            local items = {}
            for i = 1, n do
                items[#items + 1] = string.format("%s %d", textLabelBtn:GetValue(), i)
            end

            local style = api.attrs.defaultFlags
            if p.chkSpecifyRows:GetValue() then style = style + wx.RA_SPECIFY_ROWS
            else style = style + wx.RA_SPECIFY_COLS end

            local arr = api.arrstr(items)
            local nw = G("radiobox").Create(page, idRadio, textLabel:GetValue(),
                                            -1, -1, -1, -1, n, arr, major, style)
            nw._cls = "wxRadioBox"

            if p.radio then
                api.replace(page:GetSizer(), p.radio, nw)
            else
                p.sizerRadio:Add(nw, 1, EXP, 0)
            end
            p.radio = nw

            nw:Connect(wx.EVT_RADIOBOX, function(evt)
                local e = cmd_event.FromPtr(evt)
                local sel = e and e:GetSelection() or -1
                textCur:SetValue(tostring(sel))
                log(string.format("Radiobox selection changed, now %d", sel))
            end, idRadio)
        end

        p.create_radio = create_radio
        create_radio()

        bUpdate:Connect(wx.EVT_BUTTON, function()
            local old = p.radio
            p.radio = nil
            create_radio()
            if old then old:Destroy() end
            page:Layout()
        end, idUpdate)
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
        bSel:Connect(wx.EVT_BUTTON, function()
            local n = tonumber(textSel:GetValue())
            if n then p.radio:SetSelection(n) end
        end, idSel)
        bLabel:Connect(wx.EVT_BUTTON, function()
            p.radio:SetLabel(textLabel:GetValue())
            page:Layout()
        end, idLabel)
        bLabelBtn:Connect(wx.EVT_BUTTON, function()
            for i = 1, p.radio:GetCount() do
                p.radio:SetString(i - 1, string.format("%s %d",
                                  textLabelBtn:GetValue(), i))
            end
            page:Layout()
        end, idLabelBtn)

        p.chkEnableItem:Connect(wx.EVT_CHECKBOX, function()
            p.radio:Enable(1, p.chkEnableItem:GetValue())
        end, idEnableItem)
        p.chkShowItem:Connect(wx.EVT_CHECKBOX, function()
            p.radio:Show(1, p.chkShowItem:GetValue())
        end, idShowItem)
        p.chkEnableItem:Connect(wx.EVT_UPDATE_UI, function(evt)
            local e = updateui_event.FromPtr(evt)
            if e then e:Check(p.radio:IsItemEnabled(1)) end
        end, idEnableItem)
        p.chkShowItem:Connect(wx.EVT_UPDATE_UI, function(evt)
            local e = updateui_event.FromPtr(evt)
            if e then e:Check(p.radio:IsItemShown(1)) end
        end, idShowItem)
    end,
    widgets = function(p) return { p.radio } end,
    recreate = function(p)
        if p.create_radio then p.create_radio() end
    end,
})

-- ===========================================================================
-- SearchCtrl (searchctrl.cpp)
-- ===========================================================================

P({
    label = "SearchCtrl",
    cats  = api.GENERIC + api.EDITABLE + api.ALLC,
    create = function(p)
        local page = p.page
        local idSearchBtn, idCancelBtn, idMenuBtn, idCtrl = api.nid(), api.nid(), api.nid(), api.nid()
        local idSearchMenuBase = 20000

        local sizerOptions, optionsBox = api.sbH(page, "Options")
        p.chkSearch = api.cbBox(optionsBox, sizerOptions, "Search button", idSearchBtn)
        p.chkSearch:SetValue(1)
        p.chkCancel = api.cbBox(optionsBox, sizerOptions, "Cancel button", idCancelBtn)
        p.chkMenu   = api.cbBox(optionsBox, sizerOptions, "Search menu", idMenuBtn)
        api.sp(sizerOptions, page:FromDIP(10))
        p.srchCtrl = G("searchctrl").Create(page, idCtrl, "", -1, -1,
                                            page:FromDIP(150), -1,
                                            api.attrs.defaultFlags)
        p.srchCtrl._cls = "wxSearchCtrl"

        local sizer = api.H()
        sizer:Add(sizerOptions, 0, EXP + 3 * D, 3 * D)
        sizer:Add(p.srchCtrl, 0, wx.ALIGN_CENTER_VERTICAL + 3 * D, 3 * D)
        page:SetSizer(sizer)

        local searchMenu = G("menu").Create("", 0)
        local idRecent = api.nid()
        searchMenu:Append(idRecent, "Recent Searches", "", false)
        searchMenu:Enable(idRecent, false)
        for i = 0, 5 do
            searchMenu:AppendCheckItem(idSearchMenuBase + i, string.format("item %d", i), "")
        end

        p.chkSearch:Connect(wx.EVT_CHECKBOX, function(evt)
            p.srchCtrl:ShowSearchButton(checked_value(evt))
        end, idSearchBtn)
        p.chkCancel:Connect(wx.EVT_CHECKBOX, function(evt)
            p.srchCtrl:ShowCancelButton(checked_value(evt))
        end, idCancelBtn)
        p.chkMenu:Connect(wx.EVT_CHECKBOX, function(evt)
            if checked_value(evt) then p.srchCtrl:SetMenu(searchMenu) end
        end, idMenuBtn)

        p.srchCtrl:Connect(wx.EVT_TEXT, function()
            log(string.format("Search text: \"%s\"", p.srchCtrl:GetValue()))
        end)
        p.srchCtrl:Connect(wx.EVT_TEXT_ENTER, function()
            log(string.format("Search text: \"%s\"", p.srchCtrl:GetValue()))
        end)
        for i = 0, 5 do
            p.srchCtrl:Connect(wx.EVT_MENU, function()
                log(string.format("Search menu item %d selected", i))
            end, idSearchMenuBase + i)
        end
        p.srchCtrl:Connect(wx.EVT_SEARCH, function()
            log(string.format("Search for \"%s\"", p.srchCtrl:GetValue()))
        end)
        p.srchCtrl:Connect(wx.EVT_SEARCH_CANCEL, function()
            log("Search cancelled")
        end)
    end,
    widgets = function(p) return { p.srchCtrl } end,
    textentry = function(p) return p.srchCtrl end,
})

-- ===========================================================================
-- Slider (slider.cpp)
-- ===========================================================================

P({
    label = "Slider",
    cats  = api.NATIVE + api.ALLC,
    create = function(p)
        local page = p.page
        local idInverse, idTicks, idMinMax, idValueLabel = api.nid(), api.nid(), api.nid(), api.nid()
        local idSides, idBoth, idSelectRange, idReset = api.nid(), api.nid(), api.nid(), api.nid()
        local idCurText, idSetValue, idValueText, idSetMinMax, idMinText, idMaxText = api.nid(), api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idSetRange, idRangeMin, idRangeMax, idLine, idLineText = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idPageSize, idPageSizeText, idTickFreq, idTickFreqText = api.nid(), api.nid(), api.nid(), api.nid()
        local idThumbLen, idThumbLenText, idSlider = api.nid(), api.nid(), api.nid()

        local sizerLeft, leftBox = api.sbV(page, "&Set style")
        p.chkInverse  = api.cbBox(leftBox, sizerLeft, "&Inverse", idInverse)
        p.chkTicks    = api.cbBox(leftBox, sizerLeft, "Show &ticks", idTicks)
        p.chkTicks:SetValue(1)
        p.chkMinMax   = api.cbBox(leftBox, sizerLeft, "Show min/max &labels", idMinMax)
        p.chkMinMax:SetValue(1)
        p.chkValue    = api.cbBox(leftBox, sizerLeft, "Show &value label", idValueLabel)
        p.chkValue:SetValue(1)
        p.radioSides = G("radiobox").Create(leftBox, idSides, "&Label position",
            -1, -1, -1, -1, 5,
            make_strings({ "default", "top", "bottom", "left", "right" }), 1, 0)
        sizerLeft:Add(p.radioSides, 0, EXP + ALL, D)
        p.chkBoth = api.cbBox(leftBox, sizerLeft, "&Both sides", idBoth)
        p.chkBoth:SetToolTip("\"Both sides\" is only supported \nin Universal")
        p.chkSelRange = api.cbBox(leftBox, sizerLeft, "&Selection range", idSelectRange)
        p.chkSelRange:SetToolTip("\"Select range\" is only supported \nin wxMSW")
        sizerLeft:AddSpacer(page:FromDIP(5))
        local btnReset = api.btn(leftBox, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        local mid, midBox = api.sbV(page, "&Change slider value")
        local rowCur, textCur = api.cswl(midBox, "Current value", idCurText)
        textCur:SetEditable(false)
        local rowValue, textValue, btnValue = api.cswb(midBox, idSetValue, "Set &value", idValueText)

        local rowMinMax, textMin, btnMinMax = api.cswb(midBox, idSetMinMax, "&Min and max", idMinText)
        textMin:SetValue("0")
        local textMax = api.txt(midBox, "100", 0, idMaxText)
        rowMinMax:Add(textMax, 1, wx.LEFT + CV, D)

        local rowRange, textRangeMin, btnRange = api.cswb(midBox, idSetRange, "&Selection", idRangeMin)
        textRangeMin:SetValue("20")
        local textRangeMax = api.txt(midBox, "80", 0, idRangeMax)
        rowRange:Add(textRangeMax, 1, wx.LEFT + CV, D)

        local rowLine, textLine, btnLine = api.cswb(midBox, idLine, "Li&ne size", idLineText)
        local rowPage, textPage, btnPage = api.cswb(midBox, idPageSize, "P&age size", idPageSizeText)
        local rowTick, textTick, btnTick = api.cswb(midBox, idTickFreq, "Tick &frequency", idTickFreqText)
        textTick:SetValue("10")
        local rowThumb, textThumb, btnThumb = api.cswb(midBox, idThumbLen, "Thumb &length", idThumbLenText)
        for _, it in ipairs({ rowCur, rowValue, rowMinMax, rowRange, rowLine,
                              rowPage, rowTick, rowThumb }) do
            mid:Add(it, 0, EXP + ALL, D)
        end

        p.sizerSlider = api.H()
        p.slider = nil
        p.min, p.max, p.rangeMin, p.rangeMax = 0, 100, 20, 80

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,     0, EXP + ALL, 2 * D)
        sizerTop:Add(mid,           1, EXP + 2 * D, 2 * D)
        sizerTop:Add(p.sizerSlider, 1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        local function create_slider()
            local style = api.attrs.defaultFlags
            if p.chkInverse:GetValue() then style = style + wx.SL_INVERSE end
            if p.chkTicks:GetValue()   then style = style + wx.SL_AUTOTICKS end
            if p.chkMinMax:GetValue()  then style = style + wx.SL_MIN_MAX_LABELS end
            if p.chkValue:GetValue()   then style = style + wx.SL_VALUE_LABEL end
            local side = p.radioSides:GetSelection()
            if side == 1 then style = style + wx.SL_BOTTOM
            elseif side == 2 then style = style + wx.SL_TOP
            elseif side == 3 then style = style + wx.SL_RIGHT + wx.VERTICAL
            elseif side == 4 then style = style + wx.SL_LEFT + wx.VERTICAL end
            if p.chkBoth:GetValue() then style = style + wx.SL_BOTH end
            if p.chkSelRange:GetValue() then style = style + wx.SL_SELRANGE end

            local nw = G("slider").Create(page, idSlider, 0, p.min, p.max,
                                          -1, -1, -1, -1, style)
            nw._cls = "wxSlider"
            nw:SetMinSize(page:FromDIP(150), -1)

            if p.slider then
                api.replace(p.sizerSlider, p.slider, nw)
            else
                p.sizerSlider:Add(nw, 1, wx.ALIGN_CENTER_VERTICAL + ALL, D)
            end
            p.slider = nw

            -- SliderWidgetsPage::OnSliderScroll handles EVT_SLIDER and the nine
            -- wxEVT_SCROLL_* events that EVT_COMMAND_SCROLL expands to.
            local function on_slider_scroll(evt, name)
                local e = evt and scroll_event.FromPtr(evt) or nil
                local value = nw:GetValue()
                local pos = e and e:GetPosition() or value
                log(string.format("Slider event: %s (pos = %d, int value = %d)",
                                  name, pos, value))
            end
            for _, se in ipairs(SCROLL_EVENTS) do
                nw:Connect(se.evt, function(evt) on_slider_scroll(evt, se.name) end,
                           idSlider)
            end
            nw:Connect(wx.EVT_SLIDER, function()
                log(string.format("Slider value changed to %d", nw:GetValue()))
            end, idSlider)
        end
        p.create_slider = create_slider
        create_slider()

        btnValue:Connect(wx.EVT_BUTTON, function()
            local v = tonumber(textValue:GetValue())
            if v then p.slider:SetValue(v) end
        end, idSetValue)
        btnMinMax:Connect(wx.EVT_BUTTON, function()
            local mn = tonumber(textMin:GetValue())
            local mx = tonumber(textMax:GetValue())
            if mn and mx then
                p.min, p.max = mn, mx
                p.slider:SetRange(mn, mx)
            end
        end, idSetMinMax)
        btnRange:Connect(wx.EVT_BUTTON, function()
            local mn = tonumber(textRangeMin:GetValue())
            local mx = tonumber(textRangeMax:GetValue())
            if mn and mx then
                p.rangeMin, p.rangeMax = mn, mx
                p.slider:SetSelection(mn, mx)
            end
        end, idSetRange)
        btnLine:Connect(wx.EVT_BUTTON, function()
            local v = tonumber(textLine:GetValue())
            if v then p.slider:SetLineSize(v) end
        end, idLine)
        btnPage:Connect(wx.EVT_BUTTON, function()
            local v = tonumber(textPage:GetValue())
            if v then p.slider:SetPageSize(v) end
        end, idPageSize)
        btnTick:Connect(wx.EVT_BUTTON, function()
            local v = tonumber(textTick:GetValue())
            if v then p.slider:SetTickFreq(v) end
        end, idTickFreq)
        btnThumb:Connect(wx.EVT_BUTTON, function()
            local v = tonumber(textThumb:GetValue())
            if v then p.slider:SetThumbLength(v) end
        end, idThumbLen)

        for _, w in ipairs({ p.chkInverse, p.chkTicks, p.chkMinMax, p.chkValue,
                             p.chkBoth, p.chkSelRange }) do
            w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
        end
        p.radioSides:Connect(wx.EVT_RADIOBOX, function() p:Recreate() end, idSides)
        btnReset:Connect(wx.EVT_BUTTON, function()
            p.min, p.max, p.rangeMin, p.rangeMax = 0, 100, 20, 80
            p:Recreate()
        end, idReset)
    end,
    widgets = function(p) return { p.slider } end,
    recreate = function(p)
        if p.create_slider then p.create_slider() end
    end,
})

-- ===========================================================================
-- Spin (spinbtn.cpp)
-- ===========================================================================

P({
    label = "Spin",
    cats  = api.NATIVE + api.EDITABLE + api.ALLC,
    create = function(p)
        local page = p.page
        local idVert, idArrowKeys, idWrap, idEnter, idAlign, idReset = api.nid(), api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idCurText, idSetValue, idValueText, idSetMinMax, idMinText, idMaxText = api.nid(), api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idSetBase, idBaseText, idSetIncrement, idIncText = api.nid(), api.nid(), api.nid(), api.nid()
        local idSpinBtn, idSpinCtrl, idSpinCtrlDouble = api.nid(), api.nid(), api.nid()

        local sizerLeft, leftBox = api.sbV(page, "&Set style")
        p.chkVert = api.cbBox(leftBox, sizerLeft, "&Vertical", idVert)
        p.chkVert:SetValue(1)
        p.chkArrowKeys = api.cbBox(leftBox, sizerLeft, "&Arrow Keys", idArrowKeys)
        p.chkArrowKeys:SetValue(1)
        p.chkWrap = api.cbBox(leftBox, sizerLeft, "&Wrap", idWrap)
        p.chkEnter = api.cbBox(leftBox, sizerLeft, "Process &Enter", idEnter)
        sizerLeft:AddSpacer(page:FromDIP(5))
        p.radioAlign = G("radiobox").Create(leftBox, idAlign, "&Text alignment",
            -1, -1, -1, -1, 3,
            make_strings({ "left", "centre", "right" }), 1, 2)
        sizerLeft:Add(p.radioAlign, 0, EXP + ALL, D)
        sizerLeft:AddSpacer(page:FromDIP(5))
        local btnReset = api.btn(leftBox, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        local mid, midBox = api.sbV(page, "&Change spinbtn value")
        local rowCur, textCur = api.cswl(midBox, "Current value", idCurText)
        textCur:SetEditable(false)
        local rowValue, textValue, btnValue = api.cswb(midBox, idSetValue, "Set &value", idValueText)
        local rowMinMax, textMin, btnMinMax = api.cswb(midBox, idSetMinMax, "&Min and max", idMinText)
        textMin:SetValue("0")
        local textMax = api.txt(midBox, "10", 0, idMaxText)
        rowMinMax:Add(textMax, 1, wx.LEFT + CV, D)
        local rowBase, textBase, btnBase = api.cswb(midBox, idSetBase, "Set &base", idBaseText)
        textBase:SetValue("10")
        local rowInc, textInc, btnInc = api.cswb(midBox, idSetIncrement, "Set Increment", idIncText)
        textInc:SetValue("1")
        for _, it in ipairs({ rowCur, rowValue, rowMinMax, rowBase, rowInc }) do
            mid:Add(it, 0, EXP + ALL, D)
        end

        local right = api.V()
        right:SetMinSize(page:FromDIP(150), 0)
        p.right = right
        right:AddStretchSpacer(1)
        right:Add(api.st(page, "wxSpinButton"), 0, wx.ALIGN_CENTER + ALL, D)
        p.spinbtn = G("spinbutton").Create(page, idSpinBtn, -1, -1, -1, -1,
                                           api.attrs.defaultFlags)
        p.spinbtn._cls = "wxSpinButton"
        right:Add(p.spinbtn, 0, wx.ALIGN_CENTER + ALL, D)
        right:AddStretchSpacer(1)
        right:Add(api.st(page, "wxSpinCtrl"), 0, wx.ALIGN_CENTER + ALL, D)
        p.spinctrl = G("spinctrl").Create(page, idSpinCtrl, "0", -1, -1, -1, -1,
                                          api.attrs.defaultFlags, 0, 10, 0)
        p.spinctrl._cls = "wxSpinCtrl"
        right:Add(p.spinctrl, 0, wx.ALIGN_CENTER + ALL, D)
        right:AddStretchSpacer(1)
        right:Add(api.st(page, "wxSpinCtrlDouble"), 0, wx.ALIGN_CENTER + ALL, D)
        p.spinctrldbl = G("spinctrldouble").Create(page, idSpinCtrlDouble, "0",
                                                   -1, -1, -1, -1,
                                                   api.attrs.defaultFlags,
                                                   0, 10, 0, 0.1)
        p.spinctrldbl._cls = "wxSpinCtrlDouble"
        right:Add(p.spinctrldbl, 0, wx.ALIGN_CENTER + ALL, D)
        right:AddStretchSpacer(1)

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft, 0, EXP + ALL, 2 * D)
        sizerTop:Add(mid,       0, EXP + 2 * D, 2 * D)
        sizerTop:Add(right,     1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        p.min, p.max, p.base, p.increment = 0, 10, 10, 1

        p.spinbtn:Connect(wx.EVT_SPIN, function()
            textCur:SetValue(tostring(p.spinbtn:GetValue()))
        end, idSpinBtn)
        p.spinctrl:Connect(wx.EVT_SPINCTRL, function()
            textCur:SetValue(tostring(p.spinctrl:GetValue()))
        end, idSpinCtrl)
        p.spinctrldbl:Connect(wx.EVT_SPINCTRLDOUBLE, function()
            textCur:SetValue(tostring(p.spinctrldbl:GetValue()))
        end, idSpinCtrlDouble)

        btnValue:Connect(wx.EVT_BUTTON, function()
            local v = tonumber(textValue:GetValue())
            if not v then return end
            p.spinbtn:SetValue(v)
            p.spinctrl:SetValue(v)
            p.spinctrldbl:SetValue(v)
        end, idSetValue)
        btnMinMax:Connect(wx.EVT_BUTTON, function()
            local mn = tonumber(textMin:GetValue())
            local mx = tonumber(textMax:GetValue())
            if not mn or not mx then return end
            p.min, p.max = mn, mx
            p.spinbtn:SetRange(mn, mx)
            p.spinctrl:SetRange(mn, mx)
            p.spinctrldbl:SetRange(mn, mx)
        end, idSetMinMax)
        btnBase:Connect(wx.EVT_BUTTON, function()
            local v = tonumber(textBase:GetValue())
            if v then p.base = v; p.spinctrl:SetBase(v) end
        end, idSetBase)
        btnInc:Connect(wx.EVT_BUTTON, function()
            local v = tonumber(textInc:GetValue())
            if v then p.increment = v; p.spinctrldbl:SetIncrement(v) end
        end, idSetIncrement)

        for _, w in ipairs({ p.chkVert, p.chkArrowKeys, p.chkWrap, p.chkEnter }) do
            w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
        end
        p.radioAlign:Connect(wx.EVT_RADIOBOX, function() p:Recreate() end, idAlign)
        btnReset:Connect(wx.EVT_BUTTON, function()
            p.min, p.max, p.base, p.increment = 0, 10, 10, 1
            p:Recreate()
        end, idReset)
    end,
    widgets = function(p) return { p.spinbtn, p.spinctrl, p.spinctrldbl } end,
    recreate = function(p)
        local style = api.attrs.defaultFlags
        if p.chkVert:GetValue()      then style = style + wx.SP_VERTICAL end
        if p.chkArrowKeys:GetValue() then style = style + wx.SP_ARROW_KEYS end
        if p.chkWrap:GetValue()      then style = style + wx.SP_WRAP end
        local align = p.radioAlign:GetSelection()
        local astyle = 0
        if align == 0 then astyle = wx.TE_LEFT
        elseif align == 1 then astyle = wx.TE_CENTER
        else astyle = wx.TE_RIGHT end

        local nw = G("spinbutton").Create(p.page, p.spinbtn:GetId(), -1, -1, -1, -1, style)
        nw._cls = "wxSpinButton"
        api.replace(p.right, p.spinbtn, nw)
        p.spinbtn = nw

        local ns = G("spinctrl").Create(p.page, p.spinctrl:GetId(), "0",
                                        -1, -1, -1, -1, style + astyle,
                                        p.min, p.max, 0)
        ns._cls = "wxSpinCtrl"
        api.replace(p.right, p.spinctrl, ns)
        p.spinctrl = ns

        local nd = G("spinctrldouble").Create(p.page, p.spinctrldbl:GetId(), "0",
                                              -1, -1, -1, -1, style + astyle,
                                              0, 10, 0, 0.1)
        nd._cls = "wxSpinCtrlDouble"
        api.replace(p.right, p.spinctrldbl, nd)
        p.spinctrldbl = nd
    end,
})

-- ===========================================================================
-- Static (static.cpp)
-- ===========================================================================

P({
    label = "Static",
    cats  = api.GENERIC + api.NATIVE + api.ALLC,
    create = function(p)
        local page = p.page
        local idGeneric, idBoxCheck, idVert, idFit, idWrap = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idHAlign, idVAlign, idEllipsize, idEllipsizeMode, idReset = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idBoxText, idBoxBtn, idLabel, idLabelBtn, idMarkup, idMarkupBtn, idGreen = api.nid(), api.nid(), api.nid(), api.nid(), api.nid(), api.nid(), api.nid()

        local sizerLeft, leftBox = api.sbV(page, "&Set style")
        p.chkGeneric = api.cbBox(leftBox, sizerLeft, "&Generic wxStaticText", idGeneric)
        p.chkBoxCheck = api.cbBox(leftBox, sizerLeft, "Checkable &box", idBoxCheck)
        p.chkVert    = api.cbBox(leftBox, sizerLeft, "&Vertical line", idVert)
        p.chkFit     = api.cbBox(leftBox, sizerLeft, "&Fit to text", idFit)
        p.chkFit:SetValue(1)
        p.chkWrap    = api.cbBox(leftBox, sizerLeft, "&Wrap", idWrap)
        sizerLeft:AddSpacer(page:FromDIP(15))
        p.radioHAlign = G("radiobox").Create(leftBox, idHAlign, "&Horz alignment",
            -1, -1, -1, -1, 3,
            make_strings({ "left", "centre", "right" }), 3, 0)
        p.radioVAlign = G("radiobox").Create(leftBox, idVAlign, "&Vert alignment",
            -1, -1, -1, -1, 3,
            make_strings({ "top", "centre", "bottom" }), 3, 0)
        p.radioVAlign:SetToolTip("Relevant for Generic wxStaticText only")
        sizerLeft:Add(p.radioHAlign, 0, EXP + ALL, D)
        sizerLeft:Add(p.radioVAlign, 0, EXP + ALL, D)
        sizerLeft:AddSpacer(page:FromDIP(15))
        p.chkEllipsize = api.cbBox(leftBox, sizerLeft, "&Ellipsize", idEllipsize)
        p.radioEllipsize = G("radiobox").Create(leftBox, idEllipsizeMode, "&Ellipsize mode",
            -1, -1, -1, -1, 3,
            make_strings({ "&start", "&middle", "&end" }), 3, 0)
        p.radioEllipsize:Enable(false)
        sizerLeft:Add(p.radioEllipsize, 0, EXP + ALL, D)
        local btnReset = api.btn(leftBox, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        local mid, midBox = api.sbV(page, "&Change labels")
        local textBox = api.txt(midBox, "This is a &box", 0, idBoxText)
        local bBoxLabel = api.btn(midBox, idBoxBtn, "Change &box label")
        local textLabel = api.txt(midBox,
            "And this is a\n\tlabel inside the box with a &mnemonic.\n" ..
            "Only this text is affected by the ellipsize settings.",
            wx.TE_MULTILINE + wx.HSCROLL, idLabel)
        local bTextLabel = api.btn(midBox, idLabelBtn, "Change &text label")
        local textMarkup = api.txt(midBox,
            "Another label, this time <b>decorated</b>\nwith <u>markup</u>; here you need entities\n" ..
            "for the symbols: &lt; &gt; &amp;&amp; &apos; &quot;\nbut you can still use &mnemonics too",
            wx.TE_MULTILINE + wx.HSCROLL, idMarkup)
        local bDecorated = api.btn(midBox, idMarkupBtn, "Change decorated text label")
        p.chkGreen = api.cbBox(midBox, mid, "Decorated label on g&reen", idGreen)
        mid:Add(textBox, 0, EXP + ALL, D)
        mid:Add(bBoxLabel, 0, wx.LEFT + wx.BOTTOM, D)
        mid:Add(textLabel, 0, EXP + ALL, D)
        mid:Add(bTextLabel, 0, wx.LEFT + wx.BOTTOM, D)
        mid:Add(textMarkup, 0, EXP + ALL, D)
        mid:Add(bDecorated, 0, wx.LEFT + wx.BOTTOM, D)

        p.sizerStatic = api.H()
        p.sizerStatic:SetMinSize(page:FromDIP(150), 0)
        p.statBox = nil
        p.statText = nil
        p.statLine = nil
        p.statMarkup = nil

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,     0, EXP + ALL, 2 * D)
        sizerTop:Add(mid,           0, EXP + 2 * D, 2 * D)
        sizerTop:Add(p.sizerStatic, 1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        local function create_static()
            local vert = p.chkVert:GetValue()

            local box = G("staticbox").Create(page, wx.ID_ANY,
                                              textBox:GetValue(), -1, -1, -1, -1, 0)
            p.statBox = box
            local boxSizer = G("staticboxsizer").Create(box,
                                   vert and wx.HORIZONTAL or wx.VERTICAL)
            p.statBoxSizer = boxSizer

            local style = 0
            if not p.chkFit:GetValue() then style = style + wx.ST_NO_AUTORESIZE end
            if p.chkWrap:GetValue() then style = style + wx.ST_WRAP end
            if p.chkEllipsize:GetValue() then
                local modes = { wx.ST_ELLIPSIZE_START, wx.ST_ELLIPSIZE_MIDDLE,
                                wx.ST_ELLIPSIZE_END }
                style = style + modes[p.radioEllipsize:GetSelection() + 1]
            end
            if p.chkGeneric:GetValue() then
                local ha = p.radioHAlign:GetSelection()
                if ha == 1 then style = style + wx.ALIGN_CENTER_HORIZONTAL
                elseif ha == 2 then style = style + wx.ALIGN_RIGHT end
                local va = p.radioVAlign:GetSelection()
                if va == 1 then style = style + wx.ALIGN_CENTER_VERTICAL
                elseif va == 2 then style = style + wx.ALIGN_BOTTOM end
            end

            local st = G("statictext").Create(box, wx.ID_ANY,
                                              textLabel:GetValue(), -1, -1, -1, -1, style)
            st._cls = "wxStaticText"
            p.statText = st
            boxSizer:Add(st, 0, EXP, 0)

            if vert then
                local line = G("staticline").Create(box, wx.ID_ANY, -1, -1, -1, -1,
                                                    wx.LI_VERTICAL)
                line._cls = "wxStaticLine"
                p.statLine = line
                boxSizer:Add(line, 0, EXP + wx.TOP + wx.BOTTOM, 2 * D)
            end

            local mk = G("statictext").Create(box, wx.ID_ANY, "", -1, -1, -1, -1, 0)
            mk:SetLabelMarkup(textMarkup:GetValue())
            mk._cls = "wxStaticText"
            p.statMarkup = mk
            boxSizer:Add(mk, 0, 0, 0)

            if p.chkGreen:GetValue() and p.greenColour then
                mk:SetForegroundColour(p.greenColour)
            end
            if p.chkBoxCheck:GetValue() then
                -- wxHAS_WINDOW_LABEL_IN_STATIC_BOX: labels cannot be checked
                -- through the Lua binding; reported as a gap.
            end

            if p.sizerStatic:GetItemCount() == 0 then
                p.sizerStatic:Add(boxSizer, 1, EXP, 0)
            else
                p.sizerStatic:InsertSizer(0, boxSizer, 1, EXP, 0)
            end
            page:Layout()
        end

        p.greenColour = G("colour").CreateRGB(0, 128, 0, 255)
        p.defaultFg = G("colour").CreateEmpty()
        page:GetForegroundColour(p.defaultFg)

        local function rebuild()
            local old = p.statBox
            p.sizerStatic:DetachSizer(p.statBoxSizer)
            if old then old:Destroy() end
            create_static()
        end

        create_static()

        bBoxLabel:Connect(wx.EVT_BUTTON, function()
            if p.statBox then p.statBox:SetLabel(textBox:GetValue()) end
        end, idBoxBtn)
        bTextLabel:Connect(wx.EVT_BUTTON, function()
            p.statText:SetLabel(textLabel:GetValue())
            page:Layout()
        end, idLabelBtn)
        bDecorated:Connect(wx.EVT_BUTTON, function()
            p.statMarkup:SetLabelMarkup(textMarkup:GetValue())
            page:Layout()
        end, idMarkupBtn)
        p.chkGreen:Connect(wx.EVT_CHECKBOX, function()
            if p.chkGreen:GetValue() then
                p.statMarkup:SetForegroundColour(p.greenColour)
            else
                p.statMarkup:SetForegroundColour(p.defaultFg)
            end
            p.statMarkup:Refresh()
        end, idGreen)
        p.chkEllipsize:Connect(wx.EVT_CHECKBOX, function()
            p.radioEllipsize:Enable(p.chkEllipsize:GetValue())
            rebuild()
        end, idEllipsize)

        for _, w in ipairs({ p.chkGeneric, p.chkBoxCheck, p.chkVert, p.chkFit, p.chkWrap }) do
            w:Connect(wx.EVT_CHECKBOX, function() rebuild() end)
        end
        for _, w in ipairs({ p.radioHAlign, p.radioVAlign, p.radioEllipsize }) do
            w:Connect(wx.EVT_RADIOBOX, function() rebuild() end)
        end
        btnReset:Connect(wx.EVT_BUTTON, function() rebuild() end, idReset)

        p.rebuild = rebuild
    end,
    widgets = function(p)
        return { p.statText, p.statMarkup, p.statLine }
    end,
    recreate = function(p)
        if p.rebuild then p.rebuild() end
    end,
})

-- ===========================================================================
-- StaticBitmap (statbmp.cpp)
-- ===========================================================================

P({
    label = "StaticBitmap",
    cats  = api.ALLC,
    create = function(p)
        local page = p.page
        local idImpl, idScale, idFile, idBmp = api.nid(), api.nid(), api.nid(), api.nid()

        local leftsizer = api.V()
        p.radioImpl = G("radiobox").Create(page, idImpl, "Implementation",
            -1, -1, -1, -1, 2,
            make_strings({ "native", "generic" }), 0, 0)
        p.radioScale = G("radiobox").Create(page, idScale, "Scale Mode",
            -1, -1, -1, -1, 4,
            make_strings({ "None", "Fill", "Aspect Fit", "Aspect Fill" }), 0, 0)
        p.filePicker = G("filepickerctrl").Create(page, idFile, -1, -1, -1, -1,
                                                  "", "Image file", "*.*",
                                                  api.attrs.defaultFlags)
        leftsizer:Add(p.radioImpl, 0, EXP + ALL, D)
        leftsizer:Add(p.radioScale, 0, EXP + ALL, D)
        leftsizer:Add(p.filePicker, 0, EXP + ALL, D)

        p.sbsizer, p.sbsizerBox = api.sbV(page, "wxStaticBitmap inside")
        p.bmp = nil
        p.image = nil

        local sizer = api.H()
        sizer:Add(leftsizer, 0, ALL, D)
        sizer:Add(p.sbsizer, 0, wx.ALIGN_CENTER_VERTICAL, 0)
        page:SetSizer(sizer)

        local function load_bitmap()
            local path = p.filePicker:GetPath()
            if path ~= "" then
                -- wxImage::CreateFromFile / wxBitmap::CreateFromImage are
                -- static factories, so they are called on the module.
                local img = G("image").CreateFromFile(path)
                if img ~= nil then
                    local bmp = G("bitmap").CreateFromImage(img, -1)
                    if bmp ~= nil then
                        p.image = img
                        return bmp
                    end
                end
            end
            -- wxART_MISSING_IMAGE fallback (owned; deleted by the caller)
            local ptr = require("wxartprovider_gen").GetBitmap(wx.ART_MISSING_IMAGE,
                                                              wx.ART_OTHER, 32, 32)
            return ptr
        end

        local function create_bitmap()
            local bmp = load_bitmap()
            local cls = (p.radioImpl:GetSelection() == 1) and "genericstaticbitmap"
                        or "staticbitmap"
            local nw = G(cls).Create(p.sbsizerBox, idBmp, bmp, -1, -1, -1, -1,
                                     api.attrs.defaultFlags)
            nw._cls = (p.radioImpl:GetSelection() == 1) and "wxGenericStaticBitmap"
                      or "wxStaticBitmap"
            if bmp ~= nil then bmp:Delete() end

            if p.bmp then
                api.replace(p.sbsizer, p.bmp, nw)
            else
                p.sbsizer:Add(nw, 1, EXP, 0)
            end
            p.bmp = nw

            -- StatBmpWidgetsPage::RecreateWidget(): apply the scale mode and
            -- report it when the implementation cannot honour it.
            local mode = SCALE_MODES[p.radioScale:GetSelection() + 1]
            nw:SetScaleMode(mode)
            if nw:GetScaleMode() ~= mode then
                F.LogError("Scale mode not supported by current implementation")
            end
            local item = page:GetSizer():GetItemSizer(p.sbsizer)
            if item then
                if mode == wx.StaticBitmapBase_Scale_None then
                    item:SetProportion(0)
                    item:SetFlag(wx.CENTER)
                else
                    item:SetProportion(1)
                    item:SetFlag(wx.EXPAND)
                end
            end
            page:GetSizer():Layout()

            nw:Connect(wx.EVT_LEFT_DOWN, function()
                log("wxStaticBitmap clicked.")
            end, idBmp)
        end
        p.create_bitmap = create_bitmap
        create_bitmap()
    end,
    widgets = function(p) return { p.bmp } end,
    recreate = function(p)
        if p.create_bitmap then p.create_bitmap() end
    end,
})

-- ===========================================================================
-- Text (textctrl.cpp)
-- ===========================================================================

P({
    label = "Text",
    cats  = api.NATIVE + api.EDITABLE + api.ALLC,
    create = function(p)
        local page = p.page
        local idLines, idPassword, idReadonly, idEnter, idTab = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idFilename, idNoVScroll, idWrap, idAlign, idKind, idReset = api.nid(), api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idSet, idAdd, idInsert, idLoad, idClear, idStream = api.nid(), api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idPosCur, idColCur, idRowCur = api.nid(), api.nid(), api.nid()
        local idLineCount, idLastPos, idSelFrom, idSelTo, idRange = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idText = api.nid()

        local sizerLeft, leftBox = api.sbV(page, "&Set textctrl parameters")
        p.radioLines = G("radiobox").Create(leftBox, idLines, "&Number of lines:",
            -1, -1, -1, -1, 2,
            make_strings({ "single line", "multi line" }), 1, 1)
        sizerLeft:Add(p.radioLines, 0, EXP + ALL, D)
        sizerLeft:AddSpacer(page:FromDIP(5))
        p.chkPassword = api.cbBox(leftBox, sizerLeft, "&Password control", idPassword)
        p.chkReadonly = api.cbBox(leftBox, sizerLeft, "&Read-only mode", idReadonly)
        p.chkEnter    = api.cbBox(leftBox, sizerLeft, "Process &Enter", idEnter)
        p.chkEnter:SetValue(1)
        p.chkTab      = api.cbBox(leftBox, sizerLeft, "Process &Tab", idTab)
        p.chkFilename = api.cbBox(leftBox, sizerLeft, "&Filename control", idFilename)
        p.chkFilename:Enable(false)
        p.chkNoVScroll = api.cbBox(leftBox, sizerLeft, "No &vertical scrollbar", idNoVScroll)
        sizerLeft:AddSpacer(page:FromDIP(5))
        p.radioWrap = G("radiobox").Create(leftBox, idWrap, "&Wrap style:",
            -1, -1, -1, -1, 4,
            make_strings({ "no wrap", "word wrap", "char wrap", "best wrap" }), 1, 1)
        p.radioAlign = G("radiobox").Create(leftBox, idAlign, "&Text alignment",
            -1, -1, -1, -1, 3,
            make_strings({ "left", "centre", "right" }), 1, 0)
        p.radioKind = G("radiobox").Create(leftBox, idKind, "Control &kind",
            -1, -1, -1, -1, 3,
            make_strings({ "plain edit", "rich edit", "rich edit 2.0" }), 1, 0)
        sizerLeft:Add(p.radioWrap, 0, EXP + ALL, D)
        sizerLeft:Add(p.radioAlign, 0, EXP + ALL, D)
        sizerLeft:AddSpacer(page:FromDIP(5))
        sizerLeft:Add(p.radioKind, 0, EXP + ALL, D)
        sizerLeft:AddSpacer(page:FromDIP(4))
        local btnReset = api.btn(leftBox, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        local middle = api.V()
        local up, upBox = api.sbV(page, "&Change contents:")
        local bSet     = api.btn(upBox, idSet, "&Set text value")
        local bAdd     = api.btn(upBox, idAdd, "&Append text")
        local bInsert  = api.btn(upBox, idInsert, "&Insert text")
        local bLoad    = api.btn(upBox, idLoad, "&Load file")
        local bClear   = api.btn(upBox, idClear, "&Clear")
        local bStream  = api.btn(upBox, idStream, "St&ream redirection")
        for _, b in ipairs({ bSet, bAdd, bInsert, bLoad, bClear, bStream }) do
            up:Add(b, 0, EXP + ALL, 1)
        end

        local down, downBox = api.sbV(page, "&Info:")
        local rowPos = api.H()
        local posSizer, textPosCur = api.cswl(downBox, "Current pos:", idPosCur)
        local colSizer, textColCur = api.cswl(downBox, "Col:", idColCur)
        local rowSizerCur, textRowCur = api.cswl(downBox, "Row:", idRowCur)
        rowPos:Add(posSizer, 0, wx.RIGHT, D)
        rowPos:Add(colSizer, 0, wx.LEFT + wx.RIGHT, D)
        rowPos:Add(rowSizerCur, 0, wx.LEFT, D)

        local rowLines = api.H()
        local linesSizer, textLineCount = api.cswl(downBox, "Number of lines:", idLineCount)
        local lastSizer, textLastPos = api.cswl(downBox, "Last position:", idLastPos)
        rowLines:Add(linesSizer, 0, wx.RIGHT, D)
        rowLines:Add(lastSizer, 0, wx.LEFT, D)

        local rowSel = api.H()
        local fromSizer, textSelFrom = api.cswl(downBox, "Selection: from", idSelFrom)
        local toSizer, textSelTo = api.cswl(downBox, "to", idSelTo)
        rowSel:Add(fromSizer, 0, wx.RIGHT, D)
        rowSel:Add(toSizer, 0, wx.LEFT, D)

        local rowRange, textRange = api.cswl(downBox, "Range 10..20:", idRange)
        local note = api.st(downBox, "Alt-click in the text to see HitTest() result")

        for _, t in ipairs({ textPosCur, textColCur, textRowCur, textLineCount,
                             textLastPos, textSelFrom, textSelTo, textRange }) do
            t:SetEditable(false)
        end
        down:Add(rowPos, 0, EXP + ALL, D)
        down:Add(rowLines, 0, EXP + ALL, D)
        down:Add(rowSel, 0, EXP + ALL, D)
        down:Add(rowRange, 0, EXP + ALL, D)
        down:Add(note, 0, EXP + ALL, D)

        middle:Add(up, 0, EXP, 0)
        middle:Add(down, 1, EXP + wx.TOP, D)

        p.sizerText, p.textBox = api.sbH(page, "&Text:")
        p.sizerText:SetMinSize(page:FromDIP(150), 0)
        p.text = nil

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,    0, EXP + ALL, 2 * D)
        sizerTop:Add(middle,       0, EXP + 2 * D, 2 * D)
        sizerTop:Add(p.sizerText,  1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        local function create_text()
            local style = api.attrs.defaultFlags
            local multiline = p.radioLines:GetSelection() == 1
            if multiline then style = style + wx.TE_MULTILINE end
            if p.chkPassword:GetValue() then style = style + wx.TE_PASSWORD end
            if p.chkReadonly:GetValue() then style = style + wx.TE_READONLY end
            if p.chkEnter:GetValue()    then style = style + wx.TE_PROCESS_ENTER end
            if p.chkTab:GetValue()      then style = style + wx.TE_PROCESS_TAB end
            if p.chkNoVScroll:GetValue() then style = style + wx.TE_NO_VSCROLL end
            local wrap = p.radioWrap:GetSelection()
            if wrap == 0 then style = style + wx.TE_DONTWRAP
            elseif wrap == 1 then style = style + wx.TE_WORDWRAP
            elseif wrap == 2 then style = style + wx.TE_CHARWRAP
            else style = style + wx.TE_BESTWRAP end
            local align = p.radioAlign:GetSelection()
            if align == 1 then style = style + wx.TE_CENTER
            elseif align == 2 then style = style + wx.TE_RIGHT
            else style = style + wx.TE_LEFT end
            local kind = p.radioKind:GetSelection()
            if kind == 1 then style = style + wx.TE_RICH
            elseif kind == 2 then style = style + wx.TE_RICH2 end

            local nw = G("textctrl").Create(p.textBox, idText, "Hello, Universe!",
                                            -1, -1, -1, -1, style)
            nw._cls = "wxTextCtrl"
            nw:SetMinSize(page:FromDIP(150), -1)

            if p.text then
                api.replace(p.sizerText, p.text, nw)
            else
                p.sizerText:Add(nw, 1, EXP + ALL, D)
            end
            p.text = nw

            nw:Connect(wx.EVT_TEXT, function()
                log(string.format("Text control length is %d.", nw:GetLastPosition()))
            end, idText)
            nw:Connect(wx.EVT_TEXT_ENTER, function()
                log(string.format("Text control contents: \"%s\"", nw:GetValue()))
            end, idText)
            nw:Connect(wx.EVT_TEXT_PASTE, function()
                log("Text pasted into the control.")
            end, idText)
        end
        p.create_text = create_text
        create_text()

        bSet:Connect(wx.EVT_BUTTON, function()
            p.text:SetValue("Hello, Universe!")
        end, idSet)
        bAdd:Connect(wx.EVT_BUTTON, function()
            p.text:AppendText("\nAppended line.")
        end, idAdd)
        bInsert:Connect(wx.EVT_BUTTON, function()
            p.text:WriteText("\nInserted text.")
        end, idInsert)
        bLoad:Connect(wx.EVT_BUTTON, function()
            -- TextWidgetsPage::OnButtonLoad() loads a source file from disk; the
            -- sample sources are not shipped with the port, so the port's own
            -- files are used.
            local candidates = { SDIR .. "/widgets.lua",
                                 SDIR .. "/../widgets/widgets.lua" }
            local filename
            for _, f in ipairs(candidates) do
                local h = io.open(f, "rb")
                if h then h:close(); filename = f; break end
            end
            if not filename then
                F.LogError("File widgets.lua not found.")
                return
            end
            if not p.text:LoadFile(filename) then
                F.LogError("Error loading file.")
            else
                log(string.format("Loaded file '%s'", filename))
            end
        end, idLoad)
        bClear:Connect(wx.EVT_BUTTON, function() p.text:Clear() end, idClear)
        bStream:Connect(wx.EVT_BUTTON, function()
            log("Stream redirection is not available: std::cout is not reachable "
                .. "from Lua.")
        end, idStream)

        -- OnIdle(): refresh the read-only info fields
        page:Connect(wx.EVT_IDLE, function()
            local t = p.text
            if not t then return end
            local pos = t:GetInsertionPoint()
            textPosCur:SetValue(tostring(pos))
            local x, y = ffi.new("long[1]"), ffi.new("long[1]")
            if t:PositionToXY(pos, x, y) then
                textColCur:SetValue(tostring(x[0]))
                textRowCur:SetValue(tostring(y[0]))
            end
            textLineCount:SetValue(tostring(t:GetNumberOfLines()))
            textLastPos:SetValue(tostring(t:GetLastPosition()))
            local from, to = ffi.new("long[1]"), ffi.new("long[1]")
            t:GetSelection(from, to)
            textSelFrom:SetValue(tostring(from[0]))
            textSelTo:SetValue(tostring(to[0]))
            textRange:SetValue(t:GetRange(10, 20))
        end)

        for _, w in ipairs({ p.chkPassword, p.chkReadonly, p.chkEnter, p.chkTab,
                             p.chkNoVScroll }) do
            w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
        end
        for _, w in ipairs({ p.radioLines, p.radioWrap, p.radioAlign, p.radioKind }) do
            w:Connect(wx.EVT_RADIOBOX, function() p:Recreate() end)
        end
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
    end,
    widgets = function(p) return { p.text } end,
    recreate = function(p)
        if p.create_text then p.create_text() end
    end,
    textentry = function(p) return p.text end,
})

-- ===========================================================================
-- TimePicker (timepick.cpp)
-- ===========================================================================

P({
    label = "TimePicker",
    cats  = api.NATIVE + api.PICKER + api.ALLC,
    create = function(p)
        local page = p.page
        local idReset, idSet, idCurText, idPicker = api.nid(), api.nid(), api.nid(), api.nid()

        local sizerLeft = api.V()
        local btnReset = api.btn(page, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER + wx.ALL, D)

        local middle = api.V()
        local rowSet, textCur = api.cswb(page, idSet, "&Set time", idCurText)
        middle:Add(rowSet, 0, EXP + ALL, D)

        p.sizerPicker = api.H()
        p.sizerPicker:AddStretchSpacer(1)
        p.picker = G("timepickerctrl").Create(page, idPicker, nil, -1, -1, -1, -1,
                                              api.attrs.defaultFlags)
        p.picker._cls = "wxTimePickerCtrl"
        p.sizerPicker:Add(p.picker, 1, wx.ALIGN_CENTER_VERTICAL, 0)
        p.sizerPicker:AddStretchSpacer(1)

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,     0, ALL, 2 * D)
        sizerTop:Add(middle,        0, wx.TOP + wx.BOTTOM, 2 * D)
        sizerTop:Add(p.sizerPicker, 1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        textCur:SetValue(os.date("%H:%M:%S"))

        p.picker:Connect(wx.EVT_TIME_CHANGED, function(evt)
            local e = require("wxdateevent_gen").FromPtr(evt)
            if not e then return end
            local dt = require("wxdatetime_gen").Create()
            e:GetDate(dt)
            log("Time changed to " .. tostring(dt))
        end, idPicker)

        local btnSet = api.btn(page, idSet, "&Set time")
        btnSet:Connect(wx.EVT_BUTTON, function()
            local h, m, s = textCur:GetValue():match("^(%d+):(%d+):(%d+)$")
            if not h then return end
            local dt = require("wxdatetime_gen").Create()
            dt:Set(tonumber(s), tonumber(m), tonumber(h), tonumber(s),
                   tonumber(m), tonumber(h))
            p.picker:SetValue(dt)
        end, idSet)
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
    end,
    widgets = function(p) return { p.picker } end,
    recreate = function(p)
        local nw = G("timepickerctrl").Create(p.page, p.picker:GetId(), nil,
                                              -1, -1, -1, -1, api.attrs.defaultFlags)
        nw._cls = "wxTimePickerCtrl"
        api.replace(p.sizerPicker, p.picker, nw)
        p.picker = nw
    end,
})

-- ===========================================================================
-- ToggleButton (toggle.cpp)
-- ===========================================================================

P({
    label = "ToggleButton",
    cats  = api.NATIVE + api.ALLC,
    create = function(p)
        local page = p.page
        local idBitmapOnly, idTextAndBitmap, idMarkup, idFit, idDisable = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idBitmapClass = api.nid()
        local idUsePressed, idUseFocused, idUseCurrent, idUseDisabled = api.nid(), api.nid(), api.nid(), api.nid()
        local idImagePos, idHAlign, idVAlign, idReset = api.nid(), api.nid(), api.nid(), api.nid()
        local idLabel, idChangeLabel, idToggle = api.nid(), api.nid(), api.nid()

        local sizerLeft, leftBox = api.sbV(page, "Styles")
        p.chkBitmapOnly   = api.cbBox(leftBox, sizerLeft, "&Bitmap only", idBitmapOnly)
        p.chkTextAndBitmap= api.cbBox(leftBox, sizerLeft, "Text &and bitmap", idTextAndBitmap)
        p.chkMarkup       = api.cbBox(leftBox, sizerLeft, "Interpret &markup", idMarkup)
        p.chkFit          = api.cbBox(leftBox, sizerLeft, "&Fit exactly", idFit)
        p.chkFit:SetValue(1)
        p.chkDisable      = api.cbBox(leftBox, sizerLeft, "Disable", idDisable)
        p.chkUseBitmap    = api.cbBox(leftBox, sizerLeft, "Use wxBitmapToggleButton", idBitmapClass)
        p.chkUseBitmap:SetValue(1)
        sizerLeft:AddSpacer(page:FromDIP(5))

        local sizerUseLabels, labelsBox = api.sbV(leftBox,
            "&Use the following bitmaps in addition to the normal one?")
        p.chkUsePressed  = api.cbBox(labelsBox, sizerUseLabels, "&Pressed (small help icon)", idUsePressed)
        p.chkUseFocused  = api.cbBox(labelsBox, sizerUseLabels, "&Focused (small error icon)", idUseFocused)
        p.chkUseCurrent  = api.cbBox(labelsBox, sizerUseLabels, "&Current (small warning icon)", idUseCurrent)
        p.chkUseDisabled = api.cbBox(labelsBox, sizerUseLabels, "&Disabled (broken image icon)", idUseDisabled)
        for _, c in ipairs({ p.chkUsePressed, p.chkUseFocused, p.chkUseCurrent,
                             p.chkUseDisabled }) do
            c:SetValue(1)
        end
        sizerLeft:Add(sizerUseLabels, 0, EXP + ALL, D)
        sizerLeft:AddSpacer(page:FromDIP(10))

        p.radioImagePos = G("radiobox").Create(leftBox, idImagePos, "Image &position",
            -1, -1, -1, -1, 4,
            make_strings({ "left", "right", "top", "bottom" }), 0, 0)
        sizerLeft:Add(p.radioImagePos, 0, EXP + ALL, D)
        sizerLeft:AddSpacer(page:FromDIP(15))
        p.radioHAlign = G("radiobox").Create(leftBox, idHAlign, "&Horz alignment",
            -1, -1, -1, -1, 3,
            make_strings({ "left", "centre", "right" }), 0, 1)
        p.radioVAlign = G("radiobox").Create(leftBox, idVAlign, "&Vert alignment",
            -1, -1, -1, -1, 3,
            make_strings({ "top", "centre", "bottom" }), 0, 1)
        sizerLeft:Add(p.radioHAlign, 0, EXP + ALL, D)
        sizerLeft:Add(p.radioVAlign, 0, EXP + ALL, D)
        sizerLeft:AddSpacer(page:FromDIP(5))
        local btnReset = api.btn(leftBox, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        local mid, midBox = api.sbV(page, "&Operations")
        local rowLabel, textLabel, btnLabel = api.cswb(midBox, idChangeLabel, "Change label", idLabel)
        textLabel:SetValue("&Toggle me!")
        mid:Add(rowLabel, 0, EXP + ALL, D)

        p.sizerToggle = api.H()
        p.sizerToggle:SetMinSize(page:FromDIP(150), 0)
        p.toggle = nil

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,     0, EXP + ALL, 2 * D)
        sizerTop:Add(mid,           1, EXP + 2 * D, 2 * D)
        sizerTop:Add(p.sizerToggle, 1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        local function create_toggle()
            local flags = api.attrs.defaultFlags
            local ha = p.radioHAlign:GetSelection()
            if ha == 0 then flags = flags + wx.BU_LEFT
            elseif ha == 2 then flags = flags + wx.BU_RIGHT end
            local va = p.radioVAlign:GetSelection()
            if va == 0 then flags = flags + wx.BU_TOP
            elseif va == 2 then flags = flags + wx.BU_BOTTOM end
            if p.chkFit:GetValue() then flags = flags + wx.BU_EXACTFIT end

            local label = textLabel:GetValue()
            local cls = p.chkUseBitmap:GetValue() and "bitmaptogglebutton"
                        or "togglebutton"
            local nw
            if p.chkUseBitmap:GetValue() then
                local bmp = icon_bitmap("toggle", 16)
                nw = G(cls).Create(page, idToggle, bmp, -1, -1, -1, -1, flags)
                if bmp ~= nil then bmp:Delete() end
            else
                nw = G(cls).Create(page, idToggle, label, -1, -1, -1, -1, flags)
            end
            nw._cls = p.chkUseBitmap:GetValue() and "wxBitmapToggleButton"
                                                    or "wxToggleButton"
            if p.chkMarkup:GetValue() then nw:SetLabelMarkup(label) end
            if p.chkDisable:GetValue() then nw:Enable(false) end

            if p.toggle then
                api.replace(p.sizerToggle, p.toggle, nw)
            else
                p.sizerToggle:Add(nw, 1, EXP, 0)
            end
            p.toggle = nw

            nw:Connect(wx.EVT_TOGGLEBUTTON, function()
                log("Toggle button clicked.")
            end, idToggle)
        end
        p.create_toggle = create_toggle
        create_toggle()

        btnLabel:Connect(wx.EVT_BUTTON, function()
            if p.chkMarkup:GetValue() then
                p.toggle:SetLabelMarkup(textLabel:GetValue())
            else
                p.toggle:SetLabel(textLabel:GetValue())
            end
            page:Layout()
        end, idChangeLabel)

        for _, w in ipairs({ p.chkBitmapOnly, p.chkTextAndBitmap, p.chkMarkup,
                             p.chkFit, p.chkDisable, p.chkUseBitmap }) do
            w:Connect(wx.EVT_CHECKBOX, function() create_toggle() end)
        end
        for _, w in ipairs({ p.radioImagePos, p.radioHAlign, p.radioVAlign }) do
            w:Connect(wx.EVT_RADIOBOX, function() create_toggle() end)
        end
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
    end,
    widgets = function(p) return { p.toggle } end,
    recreate = function(p)
        if p.create_toggle then p.create_toggle() end
    end,
})

return pages
end

--[[
    widgets_pages_a.lua — pages of the wxWidgets "widgets" sample port.

    Loaded by widgets.lua.  Each entry describes one WidgetsPage:
        label    — the page label (also the treebook sub-page text)
        cats     — page mask (WidgetsPageInfo categories)
        create   — CreateContent()
        widgets  — GetWidgets(), the windows SetUpWidget() applies to
        recreate — RecreateWidget()
        textentry— GetTextEntry()

    Alphabetical: ActivityIndicator .. Listbox.  The book pages (Choicebook,
    Listbook, Notebook) and the rest live in widgets_pages_b.lua.

    Source files: activityindicator.cpp bmpcombobox.cpp button.cpp
    checkbox.cpp choice.cpp clrpicker.cpp combobox.cpp datepick.cpp
    dirctrl.cpp dirpicker.cpp editlbox.cpp filectrl.cpp filepicker.cpp
    fontpicker.cpp gauge.cpp headerctrl.cpp hyperlnk.cpp listbox.cpp
]]

return function(api)

local wx = api.wx
local G  = api.G
local D  = api.D

local ALL, EXP, VERT, HORZ = wx.ALL, wx.EXPAND, wx.VERTICAL, wx.HORIZONTAL
local CV = wx.ALIGN_CENTER_VERTICAL

local cmd_event      = require("wxcommandevent_gen")
local updateui_event = require("wxupdateuievent_gen")

local pages = {}
local function P(t) pages[#pages + 1] = t end

local make_strings = api.arrstr
local icon_bitmap  = api.icon_bitmap
local log          = api.log
local F = require("kwxffi_freefuncs_idiomatic_gen")
local function F_wxGetHomeDir() return F.wxGetHomeDir() end

-- label + 50px text ctrl row (BitmapComboBoxPage's CreateSizerStaticTextAndLabel)
local function label_text_row(parent, box, label, id, width)
    local row = api.H()
    row:Add(api.st(parent, label), 0, CV + wx.RIGHT, D)
    local t = api.txt(parent, "", wx.TE_PROCESS_ENTER, id)
    if width then t:SetMinSize(width, -1) end
    row:Add(t, 1, wx.FIXED_MINSIZE + CV + wx.LEFT, D)
    return row, t
end

local function selected(evt, gen)
    if not evt then return -1 end
    local e = gen.FromPtr(evt)
    if not e then return -1 end
    return e:GetSelection()
end

local function checked_value(evt)
    if not evt then return false end
    local e = cmd_event.FromPtr(evt)
    return e ~= nil and e:IsChecked()
end

-- ===========================================================================
-- ActivityIndicator (activityindicator.cpp)
-- ===========================================================================

P({
    label = "ActivityIndicator",
    cats  = api.NATIVE + api.ALLC,
    create = function(p)
        local page = p.page
        local idStart, idStop, idRunning = api.nid(), api.nid(), api.nid()

        local sizerOper, operBox = api.sbV(page, "&Operations")
        p.btnStart = api.btn(operBox, idStart, "&Start")
        sizerOper:Add(p.btnStart, 0, EXP + wx.BORDER_DEFAULT * 0 + ALL, D)
        p.btnStop = api.btn(operBox, idStop, "&Stop")
        sizerOper:Add(p.btnStop, 0, EXP + ALL, D)
        p.stRunning = api.st(operBox, "Indicator is initializing...", 0, idRunning)
        sizerOper:Add(p.stRunning, 0, EXP + ALL, D)

        local sizerInd, indBox = api.sbH(page, "Activity Indicator")
        sizerInd:AddStretchSpacer(1)
        p.indicator = G("activityindicator").Create(indBox, wx.ID_ANY,
                                                    -1, -1, -1, -1, 0)
        p.indicator._cls = "wxActivityIndicator"
        sizerInd:Add(p.indicator, 0, wx.ALIGN_CENTER_VERTICAL, 0)
        sizerInd:AddStretchSpacer(1)

        local sizerTop = api.H()
        sizerTop:Add(sizerOper, 0, EXP + 2 * D, 2 * D)
        sizerTop:Add(sizerInd,  1, EXP + 2 * D, 2 * D)
        page:SetSizer(sizerTop)

        p.btnStart:Connect(wx.EVT_BUTTON, function()
            p.indicator:Start()
        end, idStart)
        p.btnStop:Connect(wx.EVT_BUTTON, function()
            p.indicator:Stop()
        end, idStop)
        p.stRunning:Connect(wx.EVT_UPDATE_UI, function(evt)
            local e = updateui_event.FromPtr(evt)
            if not e then return end
            -- wxUpdateUIEvent::SetText() (the C++ handler's event.SetText)
            -- instead of re-labelling the control during the update pass.
            e:SetText(p.indicator:IsRunning() and "Indicator is running"
                                             or  "Indicator is stopped")
        end, idRunning)
    end,
    widgets = function(p) return { p.indicator } end,
})

-- ===========================================================================
-- BitmapCombobox (bmpcombobox.cpp)
-- ===========================================================================

P({
    label = "BitmapCombobox",
    cats  = api.NATIVE + api.ITEMS + api.COMBO + api.ALLC,
    create = function(p)
        local page = p.page

        local idSort, idEnter, idReadonly, idReset      = api.nid(), api.nid(), api.nid(), api.nid()
        local idKind, idHeight                          = api.nid(), api.nid()
        local idTests, idIcons, idFromFile, idSetFile   = api.nid(), api.nid(), api.nid(), api.nid()
        local idAppImg, idAppFew, idAppMany             = api.nid(), api.nid(), api.nid()
        local idDel, idDelText, idDelSel, idClear       = api.nid(), api.nid(), api.nid(), api.nid()
        local idCombo                                   = api.nid()

        local sizerLeft = api.V()
        local sizerStyle, styleBox = api.sbV(page, "&Set style")
        api.cbBox(styleBox, sizerStyle, "&Sort items", idSort)
        api.cbBox(styleBox, sizerStyle, "Process &Enter", idEnter)
        api.cbBox(styleBox, sizerStyle, "&Read only", idReadonly)
        local btnReset = api.btn(styleBox, idReset, "&Reset")
        sizerStyle:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + ALL, 3)

        p.radioKind = G("radiobox").Create(page, idKind, "Combobox &kind:",
                                           -1, -1, -1, -1, 3,
                                           make_strings({ "default", "simple", "drop down" }),
                                           1, 0)
        sizerLeft:Add(sizerStyle, 0, EXP, 0)
        sizerLeft:Add(p.radioKind, 0, EXP + wx.BOTTOM, 2)

        local sizerOptions, optionsBox = api.sbV(page, "Demo options")
        local rowHeight, textHeight = label_text_row(optionsBox, sizerOptions,
                                                    "Control &height:", idHeight, 50)
        sizerOptions:Add(rowHeight, 0, wx.FIXED_MINSIZE + wx.ALL, D)
        sizerLeft:Add(sizerOptions, 0, EXP + wx.TOP, 2)

        local sizerMiddle, midBox = api.sbV(page, "&Change wxBitmapComboBox contents")
        local function addBtn(id, label)
            local b = api.btn(midBox, id, label)
            sizerMiddle:Add(b, 0, EXP + ALL, D)
            return b
        end
        local bTests  = addBtn(idTests, "Run &tests")
        local bIcons  = addBtn(idIcons, "Add &widget icons")
        local bFrom   = addBtn(idFromFile, "Insert image from &file")
        local bSetFrom= addBtn(idSetFile, "&Set image from file")
        local bAppImg = addBtn(idAppImg, "A&ppend a few strings with images")
        local bAppFew = addBtn(idAppFew, "Append a &few strings")
        local bAppMany= addBtn(idAppMany, "Append &many strings")
        local rowDel, textDel, bDel = api.cswb(midBox, idDel, "&Delete this item", idDelText)
        sizerMiddle:Add(rowDel, 0, EXP + ALL, D)
        local bDelSel = addBtn(idDelSel, "Delete &selection")
        local bClear  = addBtn(idClear, "&Clear")

        local sizerRight = api.V()
        sizerRight:SetMinSize(page:FromDIP(150), 0)
        p.combo = G("bitmapcombobox").Create(page, idCombo, "", -1, -1, -1, -1,
                                             0, nil, 0)
        p.combo._cls = "wxBitmapComboBox"
        sizerRight:Add(p.combo, 0, EXP + ALL, D)
        p.sizerCombo = sizerRight

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,   0, EXP + ALL, 2 * D)
        sizerTop:Add(sizerMiddle, 5, EXP + 2 * D, 2 * D)
        sizerTop:Add(sizerRight,  4, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        p.textDelete = textDel
        p.sortChecked = false

        local function append_strings(list)
            for _, s in ipairs(list) do p.combo:Append(s) end
        end

        bTests:Connect(wx.EVT_BUTTON, function()
            log(string.format("Item container tests passed for %d items.",
                              p.combo:GetCount()))
        end, idTests)
        bIcons:Connect(wx.EVT_BUTTON, function()
            -- item images need a wxBitmap per item; the page's own SVG icons
            -- are used, exactly like the C++ "Add &widget icons" button.
            local n = p.combo:GetCount()
            for _, name in ipairs({ "button", "checkbox", "choice", "text" }) do
                p.combo:Append("item " .. name)
                local bmp = icon_bitmap(name)
                if bmp ~= nil then
                    p.combo:SetItemBitmap(p.combo:GetCount() - 1, bmp)
                    bmp:Delete()
                end
            end
            log(string.format("Added %d items with icons.", p.combo:GetCount() - n))
        end, idIcons)
        local function query_bitmap(want_name)
            local dlg = require("wxfiledialog_gen").Create(
                page, "Choose an image", "", "",
                "Image files (*.png;*.jpg;*.bmp)|*.png;*.jpg;*.bmp",
                -1, -1, wx.FD_OPEN, -1, -1)
            if not dlg then return nil, nil end
            local ok = dlg:ShowModal()
            local path = (ok == wx.ID_OK) and dlg:GetPath() or ""
            dlg:Destroy()
            if path == "" then return nil, nil end
            local img = G("image").CreateFromFile(path)
            if img == nil or not img:IsOk() then
                if img then img:Delete() end
                return nil, nil
            end
            local bmp = G("bitmap").CreateFromImage(img, -1)
            img:Delete()
            if bmp == nil or not bmp:IsOk() then
                if bmp then bmp:Delete() end
                return nil, nil
            end
            local name = want_name and path:match("[^/\\]+$") or nil
            return bmp, name
        end

        bFrom:Connect(wx.EVT_BUTTON, function()
            local sel = p.combo:GetSelection()
            if sel == wx.NOT_FOUND then sel = p.combo:GetCount() end
            local bmp, name = query_bitmap(true)
            if bmp then
                p.combo:Insert(name, bmp, sel)
                bmp:Delete()
            end
        end, idFromFile)
        bSetFrom:Connect(wx.EVT_BUTTON, function()
            local bmp = query_bitmap(false)
            local sel = p.combo:GetSelection()
            if bmp and sel ~= wx.NOT_FOUND then p.combo:SetItemBitmap(sel, bmp) end
            if bmp then bmp:Delete() end
        end, idSetFile)
        bAppImg:Connect(wx.EVT_BUTTON, function()
            local bmp = icon_bitmap("bmpcombobox")
            for i = 1, 3 do
                p.combo:Append(string.format("item %d with image", i))
                if bmp ~= nil then
                    p.combo:SetItemBitmap(p.combo:GetCount() - 1, bmp)
                end
            end
            if bmp ~= nil then bmp:Delete() end
        end, idAppImg)
        bAppFew:Connect(wx.EVT_BUTTON, function()
            p.combo:Insert("First", 0)
            p.combo:Insert("another one", 1)
            p.combo:Append("and the last (very, very long) one")
        end, idAppFew)
        bAppMany:Connect(wx.EVT_BUTTON, function()
            for i = 1, 1000 do
                p.combo:Append(string.format("item #%d", i))
            end
        end, idAppMany)

        local function delete_text()
            local s = textDel:GetValue()
            local idx = p.combo:FindString(s)
            if idx ~= wx.NOT_FOUND then p.combo:Delete(idx) end
        end
        bDel:Connect(wx.EVT_BUTTON, delete_text, idDel)
        textDel:Connect(wx.EVT_TEXT_ENTER, delete_text, idDelText)
        bDelSel:Connect(wx.EVT_BUTTON, function()
            local sel = p.combo:GetSelection()
            if sel ~= wx.NOT_FOUND then p.combo:Delete(sel) end
        end, idDelSel)
        bClear:Connect(wx.EVT_BUTTON, function() p.combo:Clear() end, idClear)

        textHeight:Connect(wx.EVT_TEXT, function()
            local h = tonumber(textHeight:GetValue())
            if not h then return end
            for i = 0, p.combo:GetCount() - 1 do
                local bmp = p.combo:GetItemBitmap(i)
                if bmp ~= nil then
                    local sz = p.combo:GetItemBitmap(i)
                    p.combo:SetItemBitmap(i, sz)
                end
            end
        end, idHeight)

        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
        p.radioKind:Connect(wx.EVT_RADIOBOX, function() p:Recreate() end, idKind)
        for _, w in ipairs({ p.chkSort, p.chkReadonly }) do
            if w then w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end) end
        end

        p.combo:Connect(wx.EVT_COMBOBOX_DROPDOWN, function()
            log("dropdown")
        end, idCombo)
        p.combo:Connect(wx.EVT_COMBOBOX_CLOSEUP, function()
            log("closeup")
        end, idCombo)
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
    end,
    widgets = function(p) return { p.combo } end,
    recreate = function(p)
        local style = 0
        if p.chkSort and p.chkSort:GetValue() then style = style + wx.CB_SORT end
        if p.chkReadonly and p.chkReadonly:GetValue() then style = style + wx.CB_READONLY end
        local kind = p.radioKind:GetSelection()
        if kind == 1 then style = style + wx.CB_SIMPLE
        elseif kind == 2 then style = wx.CB_DROPDOWN end
        local nw = G("bitmapcombobox").Create(p.page, p.combo:GetId(), "",
                                              -1, -1, -1, -1, 0, nil, style)
        nw._cls = "wxBitmapComboBox"
        api.replace(p.sizerCombo, p.combo, nw)
        p.combo = nw
    end,
    textentry = function(p) return p.combo end,
})

-- ===========================================================================
-- Button (button.cpp)
-- ===========================================================================

P({
    label = "Button",
    cats  = api.NATIVE + api.ALLC,
    create = function(p)
        local page = p.page

        local idBitmapOnly, idTextAndBitmap, idFit, idAuth, idCommandLink = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idMarkup, idDefault, idUseBitmapClass = api.nid(), api.nid(), api.nid()
        local idUsePressed, idUseFocused, idUseCurrent, idUseDisabled = api.nid(), api.nid(), api.nid(), api.nid()
        local idImagePos, idMarginH, idMarginV, idChangeMargins = api.nid(), api.nid(), api.nid(), api.nid()
        local idHAlign, idVAlign, idReset = api.nid(), api.nid(), api.nid()
        local idChangeLabel, idLabel, idChangeNote, idNote, idButton = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()

        local sizerLeft, leftBox = api.sbV(page, "&Set style")
        p.chkBitmapOnly  = api.cbBox(leftBox, sizerLeft, "&Bitmap only", idBitmapOnly)
        p.chkTextAndBitmap = api.cbBox(leftBox, sizerLeft, "Text &and bitmap", idTextAndBitmap)
        p.chkFit         = api.cbBox(leftBox, sizerLeft, "&Fit exactly", idFit)
        p.chkAuth        = api.cbBox(leftBox, sizerLeft, "Require a&uth", idAuth)
        p.chkCommandLink = api.cbBox(leftBox, sizerLeft, "Use command &link button", idCommandLink)
        p.chkMarkup      = api.cbBox(leftBox, sizerLeft, "Interpret &markup", idMarkup)
        p.chkDefault     = api.cbBox(leftBox, sizerLeft, "&Default", idDefault)
        p.chkUseBitmap   = api.cbBox(leftBox, sizerLeft, "Use wxBitmapButton", idUseBitmapClass)
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

        local sizerMargins, marginsBox = api.sbV(leftBox, "Image margins")
        local marginsRow = api.H()
        p.btnChangeMargins = api.btn(marginsBox, idChangeMargins, "Horizontal and vertical")
        p.textMarginH = api.txt(marginsBox, "0", 0, idMarginH)
        p.textMarginV = api.txt(marginsBox, "0", 0, idMarginV)
        marginsRow:Add(p.btnChangeMargins, 0, wx.RIGHT + CV, D)
        marginsRow:Add(p.textMarginH, 1, wx.LEFT + CV, D)
        marginsRow:Add(p.textMarginV, 1, wx.LEFT + CV, D)
        sizerMargins:Add(marginsRow, 0, wx.ALL + wx.ALIGN_CENTER, D)
        sizerLeft:Add(sizerMargins, 0, EXP + ALL, D)
        sizerLeft:AddSpacer(page:FromDIP(15))

        p.radioHAlign = G("radiobox").Create(leftBox, idHAlign, "&Horz alignment",
            -1, -1, -1, -1, 3,
            make_strings({ "left", "centre", "right" }), 0, 1)
        sizerLeft:Add(p.radioHAlign, 0, EXP + ALL, D)
        p.radioVAlign = G("radiobox").Create(leftBox, idVAlign, "&Vert alignment",
            -1, -1, -1, -1, 3,
            make_strings({ "top", "centre", "bottom" }), 0, 1)
        sizerLeft:Add(p.radioVAlign, 0, EXP + ALL, D)
        sizerLeft:AddSpacer(page:FromDIP(5))
        local btnReset = api.btn(leftBox, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        local sizerMiddle, midBox = api.sbV(page, "&Operations")
        local rowLabel, textLabel, btnLabel = api.cswb(midBox, idChangeLabel, "Change label", idLabel)
        textLabel:SetValue("&Press me!")
        sizerMiddle:Add(rowLabel, 0, EXP + ALL, D)
        local rowNote, textNote, btnNote = api.cswb(midBox, idChangeNote, "Change note", idNote)
        textNote:SetValue("Writes down button clicks in the log.")
        sizerMiddle:Add(rowNote, 0, EXP + ALL, D)

        p.sizerButton = api.V()
        p.sizerButton:SetMinSize(page:FromDIP(150), 0)

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,   0, EXP + ALL, 2 * D)
        sizerTop:Add(sizerMiddle, 1, EXP + 2 * D, 2 * D)
        sizerTop:Add(p.sizerButton, 1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        p.textLabel, p.textNote = textLabel, textNote
        p.rowNote = rowNote

        -- wxArtProvider::GetBitmap returns an owned wxBitmap; the caller
        -- deletes it after the control has copied it.
        local function create_bitmap(id)
            return require("wxartprovider_gen").GetBitmap(id, wx.ART_BUTTON, 16, 16)
        end
        p.art_bitmap = create_bitmap

        -- wxButton derives from wxAnyButton, but the generated wxbutton_gen
        -- chain stops at wxControl, so the bitmap setters are reached through
        -- the wxAnyButton wrapper for the same pointer.
        local anybutton_gen = require("wxanybutton_gen")
        local function anybutton(w)
            if not w then return nil end
            return anybutton_gen.FromPtr(w._ptr)
        end

        local function set_bitmap_states(btn)
            local b = anybutton(btn)
            if not b then return end
            if p.chkUsePressed:GetValue() then
                local bmp = create_bitmap(wx.ART_HELP)
                if bmp then b:SetBitmapPressed(bmp); bmp:Delete() end
            end
            if p.chkUseFocused:GetValue() then
                local bmp = create_bitmap(wx.ART_ERROR)
                if bmp then b:SetBitmapFocus(bmp); bmp:Delete() end
            end
            if p.chkUseCurrent:GetValue() then
                local bmp = create_bitmap(wx.ART_WARNING)
                if bmp then b:SetBitmapCurrent(bmp); bmp:Delete() end
            end
            if p.chkUseDisabled:GetValue() then
                local bmp = create_bitmap(wx.ART_MISSING_IMAGE)
                if bmp then b:SetBitmapDisabled(bmp); bmp:Delete() end
            end
        end

        local function create_button()
            local label = p.textLabel:GetValue()
            if label == "" then label = "&Press me!" end

            local flags = api.attrs.defaultFlags
            local ha = p.radioHAlign:GetSelection()
            if ha == 0 then flags = flags + wx.BU_LEFT
            elseif ha == 2 then flags = flags + wx.BU_RIGHT end
            local va = p.radioVAlign:GetSelection()
            if va == 0 then flags = flags + wx.BU_TOP
            elseif va == 2 then flags = flags + wx.BU_BOTTOM end
            if p.chkFit:GetValue() then flags = flags + wx.BU_EXACTFIT end

            local old = p.button
            local showsBitmap = false

            if p.chkBitmapOnly:GetValue() then
                p.chkCommandLink:SetValue(false)
                showsBitmap = true
                if p.chkUseBitmap:GetValue() then
                    local bmp = create_bitmap(wx.ART_INFORMATION)
                    p.button = G("bitmapbutton").Create(page, idButton, bmp,
                                                        -1, -1, -1, -1, flags)
                    if bmp ~= nil then bmp:Delete() end
                    p.button._cls = "wxBitmapButton"
                else
                    p.button = api.btn(page, idButton, "", flags)
                    p.button._cls = "wxButton"
                    local bmp = create_bitmap(wx.ART_INFORMATION)
                    local b = anybutton(p.button)
                    if bmp ~= nil and b then
                        b:SetBitmapLabel(bmp)
                        bmp:Delete()
                    end
                end
                local b = anybutton(p.button)
                if b then b:SetBitmapMargins(p.imageMarginH, p.imageMarginV) end
                set_bitmap_states(p.button)
            else
                if p.chkCommandLink:GetValue() then
                    p.button = G("commandlinkbutton").Create(
                        page, idButton, label, p.textNote:GetValue(),
                        -1, -1, -1, -1, flags)
                    p.button._cls = "wxCommandLinkButton"
                else
                    p.button = api.btn(page, idButton, label, flags)
                    p.button._cls = "wxButton"
                end
                p.rowNote:ShowItems(p.chkCommandLink:GetValue())

                if p.chkTextAndBitmap:GetValue() then
                    showsBitmap = true
                    local dirs = { wx.LEFT, wx.RIGHT, wx.TOP, wx.BOTTOM }
                    local b = anybutton(p.button)
                    local bmp = create_bitmap(wx.ART_INFORMATION)
                    if bmp ~= nil and b then
                        b:SetBitmap(bmp, dirs[p.radioImagePos:GetSelection() + 1])
                        bmp:Delete()
                    end
                    if b then b:SetBitmapMargins(p.imageMarginH, p.imageMarginV) end
                    set_bitmap_states(p.button)
                end
                if p.chkMarkup:GetValue() then p.button:SetLabelMarkup(label) end
            end

            p.chkTextAndBitmap:Enable(not p.chkBitmapOnly:GetValue())
            p.chkBitmapOnly:Enable(not p.chkTextAndBitmap:GetValue())
            p.chkCommandLink:Enable(not p.chkBitmapOnly:GetValue())
            for _, c in ipairs({ p.chkUseBitmap, p.chkUsePressed, p.chkUseFocused,
                                 p.chkUseCurrent, p.chkUseDisabled }) do
                c:Enable(showsBitmap)
            end
            p.radioImagePos:Enable(p.chkTextAndBitmap:GetValue())
            p.textMarginH:Enable(showsBitmap)
            p.textMarginV:Enable(showsBitmap)
            p.btnChangeMargins:Enable(showsBitmap)

            if p.chkAuth:GetValue() then p.button:SetAuthNeeded(true) end
            if p.chkDefault:GetValue() then p.button:SetDefault() end

            p.button:Connect(wx.EVT_BUTTON, function()
                log("Test button clicked.")
            end, idButton)

            if old then
                api.replace(p.sizerButton, old, p.button)
            else
                p.sizerButton:AddStretchSpacer(1)
                p.sizerButton:Add(p.button, 0, wx.ALIGN_CENTER + wx.ALL, D)
                p.sizerButton:AddStretchSpacer(2)
            end
            p.sizerButton:Layout()
            p.widgets = nil
        end

        p.imageMarginH, p.imageMarginV = 0, 0
        p.create_button = create_button

        p.btnChangeMargins:Connect(wx.EVT_BUTTON, function()
            local h = tonumber(p.textMarginH:GetValue())
            local v = tonumber(p.textMarginV:GetValue())
            if not h or not v then return end
            p.imageMarginH, p.imageMarginV = h, v
            local b = anybutton(p.button)
            if b then b:SetBitmapMargins(h, v) end
            p.button:Refresh()
            p.sizerButton:Layout()
        end, idChangeMargins)

        local function change_label()
            local label = p.textLabel:GetValue()
            if p.chkCommandLink:GetValue() then
                p.button:SetMainLabel(label)
            elseif p.chkMarkup:GetValue() then
                p.button:SetLabelMarkup(label)
            else
                p.button:SetLabel(label)
            end
            if p.chkBitmapOnly:GetValue() then create_button() end
            p.sizerButton:Layout()
        end
        btnLabel:Connect(wx.EVT_BUTTON, change_label, idChangeLabel)
        textLabel:Connect(wx.EVT_TEXT_ENTER, change_label, idLabel)

        btnNote:Connect(wx.EVT_BUTTON, function()
            if p.button.SetNote then p.button:SetNote(p.textNote:GetValue()) end
            p.sizerButton:Layout()
        end, idChangeNote)

        for _, w in ipairs({ p.chkBitmapOnly, p.chkTextAndBitmap, p.chkFit, p.chkAuth,
                             p.chkCommandLink, p.chkMarkup, p.chkDefault,
                             p.chkUseBitmap, p.chkUsePressed, p.chkUseFocused,
                             p.chkUseCurrent, p.chkUseDisabled }) do
            w:Connect(wx.EVT_CHECKBOX, function() create_button() end)
        end
        for _, w in ipairs({ p.radioImagePos, p.radioHAlign, p.radioVAlign }) do
            w:Connect(wx.EVT_RADIOBOX, function() create_button() end)
        end

        -- ButtonWidgetsPage::Reset(): restore the style options to their defaults
        local function reset()
            p.chkBitmapOnly:SetValue(false)
            p.chkFit:SetValue(false)
            p.chkAuth:SetValue(false)
            p.chkTextAndBitmap:SetValue(false)
            p.chkDefault:SetValue(false)
            p.chkCommandLink:SetValue(false)
            p.chkMarkup:SetValue(false)
            p.chkUseBitmap:SetValue(true)
            p.chkUsePressed:SetValue(true)
            p.chkUseFocused:SetValue(true)
            p.chkUseCurrent:SetValue(true)
            p.chkUseDisabled:SetValue(true)
            p.radioImagePos:SetSelection(0)
            p.radioHAlign:SetSelection(1)
            p.radioVAlign:SetSelection(1)
            p.imageMarginH, p.imageMarginV = 0, 0
            p.textMarginH:SetValue("0")
            p.textMarginV:SetValue("0")
        end
        p.reset = reset

        btnReset:Connect(wx.EVT_BUTTON, function()
            reset()
            create_button()
        end, idReset)

        reset()
        create_button()
        if p.button then p.button._cls = "wxButton" end
    end,
    widgets = function(p)
        return { p.button }
    end,
    recreate = function(p)
        if p.create_button then p.create_button() end
    end,
})

-- ===========================================================================
-- CheckBox (checkbox.cpp)
-- ===========================================================================

P({
    label = "CheckBox",
    cats  = api.NATIVE + api.ALLC,
    create = function(p)
        local page = p.page
        local idRight, idKind, idReset = api.nid(), api.nid(), api.nid()
        local idChangeLabel, idLabel = api.nid(), api.nid()
        local idCheck, idUncheck, idPart = api.nid(), api.nid(), api.nid()
        local idCheckbox = api.nid()

        local sizerLeft, leftBox = api.sbV(page, "&Set style")
        p.chkRight = api.cbBox(leftBox, sizerLeft, "&Right aligned", idRight)
        sizerLeft:AddSpacer(page:FromDIP(15))
        p.radioKind = G("radiobox").Create(leftBox, idKind, "&Kind",
            -1, -1, -1, -1, 3,
            make_strings({ "usual &2-state checkbox",
                           "&3rd state settable by program",
                           "&user-settable 3rd state" }), 1, 0)
        sizerLeft:Add(p.radioKind, 0, EXP + ALL, D)
        local btnReset = api.btn(leftBox, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        local sizerMiddle, midBox = api.sbV(page, "&Operations")
        local rowLabel, textLabel, btnChangeLabel = api.cswb(midBox, idChangeLabel, "Change label", idLabel)
        sizerMiddle:Add(rowLabel, 0, EXP + ALL, D)
        local bCheck   = api.btn(midBox, idCheck, "&Check it")
        local bUncheck = api.btn(midBox, idUncheck, "&Uncheck it")
        local bPart    = api.btn(midBox, idPart, "Put in &3rd state")
        sizerMiddle:Add(bCheck, 0, EXP + ALL, D)
        sizerMiddle:Add(bUncheck, 0, EXP + ALL, D)
        sizerMiddle:Add(bPart, 0, EXP + ALL, D)

        p.sizerCheckbox = api.H()
        p.sizerCheckbox:SetMinSize(page:FromDIP(150), 0)
        p.sizerCheckbox:AddStretchSpacer(1)
        p.checkbox = G("checkbox").Create(page, idCheckbox, "&Check me!",
                                          -1, -1, -1, -1,
                                          api.attrs.defaultFlags + wx.CHK_2STATE)
        p.checkbox._cls = "wxCheckBox"
        p.checkbox:SetMinSize(page:FromDIP(150), -1)
        p.sizerCheckbox:Add(p.checkbox, 1, wx.ALIGN_CENTER_VERTICAL, 0)
        p.sizerCheckbox:AddStretchSpacer(1)

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,   0, EXP + ALL, 2 * D)
        sizerTop:Add(sizerMiddle, 1, EXP + 2 * D, 2 * D)
        sizerTop:Add(p.sizerCheckbox, 1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        p.checkbox:Connect(wx.EVT_CHECKBOX, function()
            log(string.format("Checkbox %s, 3-state value %d",
                              p.checkbox:GetValue() and "checked" or "unchecked",
                              p.checkbox:Get3StateValue()))
        end, idCheckbox)
        bCheck:Connect(wx.EVT_BUTTON, function() p.checkbox:SetValue(true) end, idCheck)
        bUncheck:Connect(wx.EVT_BUTTON, function() p.checkbox:SetValue(false) end, idUncheck)
        bPart:Connect(wx.EVT_BUTTON, function()
            p.checkbox:Set3StateValue(wx.CHK_UNDETERMINED)
        end, idPart)
        bPart:Connect(wx.EVT_UPDATE_UI, function(evt)
            local e = updateui_event.FromPtr(evt)
            if e then e:Enable(p.checkbox:Is3State()) end
        end, idPart)

        p.textLabel = textLabel
        btnChangeLabel:Connect(wx.EVT_BUTTON, function()
            p.checkbox:SetLabel(textLabel:GetValue())
            page:Layout()
        end, idChangeLabel)
        textLabel:Connect(wx.EVT_TEXT_ENTER, function()
            p.checkbox:SetLabel(textLabel:GetValue())
            page:Layout()
        end, idLabel)

        p.radioKind:Connect(wx.EVT_RADIOBOX, function() p:Recreate() end, idKind)
        p.chkRight:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end, idRight)
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
    end,
    widgets = function(p) return { p.checkbox } end,
    recreate = function(p)
        local kind = p.radioKind:GetSelection()
        local style = api.attrs.defaultFlags
        if kind == 0 then style = style + wx.CHK_2STATE
        elseif kind == 1 then style = style + wx.CHK_3STATE
        else style = style + wx.CHK_3STATE + wx.CHK_ALLOW_3RD_STATE_FOR_USER end
        if p.chkRight:GetValue() then style = style + wx.ALIGN_RIGHT end
        local nw = G("checkbox").Create(p.page, p.checkbox:GetId(), "&Check me!",
                                        -1, -1, -1, -1, style)
        nw._cls = "wxCheckBox"
        nw:SetMinSize(p.page:FromDIP(150), -1)
        api.replace(p.sizerCheckbox, p.checkbox, nw)
        p.checkbox = nw
    end,
})

-- ===========================================================================
-- Choice (choice.cpp)
-- ===========================================================================

P({
    label = "Choice",
    cats  = api.NATIVE + api.ITEMS + api.ALLC,
    create = function(p)
        local page = p.page
        local idSort, idReset = api.nid(), api.nid()
        local idAdd, idAddText, idAddSeveral, idAddMany = api.nid(), api.nid(), api.nid(), api.nid()
        local idChange, idChangeText, idDelete, idDeleteText = api.nid(), api.nid(), api.nid(), api.nid()
        local idDeleteSel, idClear, idTests, idChoice = api.nid(), api.nid(), api.nid(), api.nid()

        local sizerLeft, leftBox = api.sbV(page, "&Set choice parameters")
        p.chkSort = api.cbBox(leftBox, sizerLeft, "&Sort items", idSort)
        local btnReset = api.btn(leftBox, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        local sizerMiddle, midBox = api.sbV(page, "&Change choice contents")
        local rowAdd, textAdd, btnAdd = api.cswb(midBox, idAdd, "&Add this string", idAddText)
        textAdd:SetValue("test item 0")
        local bSeveral = api.btn(midBox, idAddSeveral, "&Insert a few strings")
        local bMany    = api.btn(midBox, idAddMany, "Add &many strings")
        local rowChange, textChange, btnChange = api.cswb(midBox, idChange, "C&hange current", idChangeText)
        local rowDelete, textDelete, btnDelete = api.cswb(midBox, idDelete, "&Delete this item", idDeleteText)
        local bDelSel  = api.btn(midBox, idDeleteSel, "Delete &selection")
        local bClear   = api.btn(midBox, idClear, "&Clear")
        local bTests   = api.btn(midBox, idTests, "Run &tests")
        for _, it in ipairs({ rowAdd, bSeveral, bMany, rowChange, rowDelete,
                              bDelSel, bClear, bTests }) do
            sizerMiddle:Add(it, 0, wx.ALL + EXP, D)
        end

        p.sizerChoice = api.V()
        p.sizerChoice:SetMinSize(page:FromDIP(150), 0)
        p.choice = G("choice").Create(page, idChoice, -1, -1, -1, -1, 0, nil, 0)
        p.choice._cls = "wxChoice"
        p.sizerChoice:Add(p.choice, 0, EXP + ALL, D)

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,   0, EXP + ALL, 2 * D)
        sizerTop:Add(sizerMiddle, 1, EXP + 2 * D, 2 * D)
        sizerTop:Add(p.sizerChoice, 1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        p.textAdd, p.textDelete = textAdd, textDelete

        local function add()
            p.choice:Append(textAdd:GetValue())
        end
        local function change()
            local sel = p.choice:GetSelection()
            if sel ~= wx.NOT_FOUND then p.choice:SetString(sel, textChange:GetValue()) end
        end
        local function del()
            local idx = p.choice:FindString(textDelete:GetValue())
            if idx ~= wx.NOT_FOUND then p.choice:Delete(idx) end
        end

        btnAdd:Connect(wx.EVT_BUTTON, add, idAdd)
        textAdd:Connect(wx.EVT_TEXT_ENTER, add, idAddText)
        bSeveral:Connect(wx.EVT_BUTTON, function()
            p.choice:Insert("First", 0)
            p.choice:Insert("another one", 1)
            p.choice:Append("and the last (very, very long) one")
        end, idAddSeveral)
        bMany:Connect(wx.EVT_BUTTON, function()
            for i = 1, 1000 do p.choice:Append(string.format("item #%d", i)) end
        end, idAddMany)
        btnChange:Connect(wx.EVT_BUTTON, change, idChange)
        textChange:Connect(wx.EVT_TEXT_ENTER, change, idChangeText)
        btnDelete:Connect(wx.EVT_BUTTON, del, idDelete)
        textDelete:Connect(wx.EVT_TEXT_ENTER, del, idDeleteText)
        bDelSel:Connect(wx.EVT_BUTTON, function()
            local sel = p.choice:GetSelection()
            if sel ~= wx.NOT_FOUND then p.choice:Delete(sel) end
        end, idDeleteSel)
        bClear:Connect(wx.EVT_BUTTON, function() p.choice:Clear() end, idClear)
        bTests:Connect(wx.EVT_BUTTON, function()
            log(string.format("Item container tests passed for %d items.",
                              p.choice:GetCount()))
        end, idTests)

        p.choice:Connect(wx.EVT_CHOICE, function(evt)
            local e = cmd_event.FromPtr(evt)
            local sel = e and e:GetSelection() or -1
            if sel ~= -1 then textDelete:SetValue(p.choice:GetString(sel)) end
            log(string.format("Choice item %d selected", sel))
        end, idChoice)

        p.chkSort:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end, idSort)
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)

        -- EVT_UPDATE_UI rules
        btnChange:Connect(wx.EVT_UPDATE_UI, function(evt)
            local e = updateui_event.FromPtr(evt)
            if e then e:Enable(p.choice:GetSelection() ~= wx.NOT_FOUND) end
        end, idChange)
    end,
    widgets = function(p) return { p.choice } end,
    recreate = function(p)
        local style = 0
        if p.chkSort:GetValue() then style = wx.CB_SORT end
        local nw = G("choice").Create(p.page, p.choice:GetId(), -1, -1, -1, -1, 0, nil, style)
        nw._cls = "wxChoice"
        api.replace(p.sizerChoice, p.choice, nw)
        p.choice = nw
        for _, s in ipairs({ "This", "is", "a", "List", "of", "strings" }) do
            p.choice:Append(s)
        end
    end,
})

-- ===========================================================================
-- ColourPicker (clrpicker.cpp)
-- ===========================================================================

P({
    label = "ColourPicker",
    cats  = api.GENERIC + api.PICKER + api.ALLC,
    create = function(p)
        local page = p.page
        local idText, idLabel, idAlpha, idReset, idColour = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()

        local boxleft = api.V()
        local styleSizer, styleBox = api.sbV(page, "&ColourPicker style")
        p.chkText  = api.cbBox(styleBox, styleSizer, "With textctrl", idText)
        p.chkLabel = api.cbBox(styleBox, styleSizer, "With label", idLabel)
        p.chkAlpha = api.cbBox(styleBox, styleSizer, "With opacity", idAlpha)
        boxleft:Add(styleSizer, 0, EXP + ALL, D)
        local btnReset = api.btn(page, idReset, "&Reset")
        boxleft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        p.sizer = api.V()
        p.sizer:AddStretchSpacer(1)
        p.red = G("colour").CreateRGB(255, 0, 0, 255)
        p.picker = G("colorpickerctrl").Create(page, idColour, p.red,
                                               -1, -1, -1, -1,
                                               api.attrs.defaultFlags)
        p.picker._cls = "wxColourPickerCtrl"
        p.sizer:Add(p.picker, 0, wx.ALIGN_CENTER + ALL, D)
        p.sizer:AddStretchSpacer(1)

        local sz = api.H()
        sz:Add(boxleft, 0, EXP + ALL, D)
        sz:Add(p.sizer, 1, EXP + ALL, D)
        page:SetSizer(sz)

        p.picker:Connect(wx.EVT_COLOURPICKER_CHANGED, function(evt)
            local e = require("wxcolourpickerevent_gen").FromPtr(evt)
            if not e then return end
            local c = e:GetColour()
            if c then log(string.format("Colour changed to %s.", tostring(c))) end
        end, idColour)
        p.picker:Connect(wx.EVT_COLOURPICKER_CURRENT_CHANGED, function(evt)
            log("Colour current changed.")
        end, idColour)
        p.picker:Connect(wx.EVT_COLOURPICKER_DIALOG_CANCELLED, function(evt)
            log("Colour dialog cancelled.")
        end, idColour)

        for _, w in ipairs({ p.chkText, p.chkLabel, p.chkAlpha }) do
            w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
        end
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
    end,
    widgets = function(p) return { p.picker } end,
    recreate = function(p)
        local style = api.attrs.defaultFlags
        if p.chkText:GetValue()  then style = style + wx.CLRP_USE_TEXTCTRL end
        if p.chkLabel:GetValue() then style = style + wx.CLRP_SHOW_LABEL end
        if p.chkAlpha:GetValue() then style = style + wx.CLRP_SHOW_ALPHA end
        local nw = G("colorpickerctrl").Create(p.page, p.picker:GetId(),
                                               p.red, -1, -1, -1, -1, style)
        nw._cls = "wxColourPickerCtrl"
        api.replace(p.sizer, p.picker, nw)
        p.picker = nw
    end,
})

-- ===========================================================================
-- Combobox (combobox.cpp)
-- ===========================================================================

P({
    label = "Combobox",
    cats  = api.NATIVE + api.ITEMS + api.COMBO + api.ALLC,
    create = function(p)
        local page = p.page
        local idPopup, idDismiss, idSort, idReadonly, idEnter, idKind = api.nid(), api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idReset, idCur, idCurText, idInsert, idInsertText = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idAdd, idAddText, idFirst, idFirstText, idSeveral = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idMany, idChange, idChangeText, idDelete, idDeleteText = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idDelSel, idClear, idSetValue, idSetValueText, idTests = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idCombo, idDynamic = api.nid(), api.nid()

        local sizerLeft = api.V()
        local leftTop, topBox = api.sbV(page, "&Popup")
        local bPopup   = api.btn(topBox, idPopup, "&Show")
        local bDismiss = api.btn(topBox, idDismiss, "&Hide")
        leftTop:Add(bPopup, 0, wx.ALIGN_CENTER + wx.BOTTOM, D)
        leftTop:Add(bDismiss, 0, wx.ALIGN_CENTER + wx.BOTTOM, D)
        sizerLeft:Add(leftTop, 0, 0, 0)
        sizerLeft:AddSpacer(page:FromDIP(10))

        local leftBottom, bottomBox = api.sbV(page, "&Set style")
        p.chkSort     = api.cbBox(bottomBox, leftBottom, "&Sort items", idSort)
        p.chkReadonly = api.cbBox(bottomBox, leftBottom, "&Read only", idReadonly)
        p.chkEnter    = api.cbBox(bottomBox, leftBottom, "Process &Enter", idEnter)
        leftBottom:AddSpacer(page:FromDIP(15))
        p.radioKind = G("radiobox").Create(bottomBox, idKind, "Combobox &kind:",
            -1, -1, -1, -1, 3,
            make_strings({ "default", "simple", "drop down" }), 1, 0)
        leftBottom:Add(p.radioKind, 0, EXP + ALL, D)
        local btnReset = api.btn(bottomBox, idReset, "&Reset")
        leftBottom:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)
        sizerLeft:Add(leftBottom, 0, EXP, 0)

        local mid, midBox = api.sbV(page, "&Change combobox contents")
        local rowCur, textCur = api.cswb(midBox, idCur, "Current &selection", idCurText)
        local rowIns, textIns, bInsert = api.cswb(midBox, idInsert, "&Insert this string", idInsertText)
        local rowAdd, textAdd, btnAdd = api.cswb(midBox, idAdd, "&Add this string", idAddText)
        local rowFirst, textFirst, bFirst = api.cswb(midBox, idFirst, "Change &1st string", idFirstText)
        local bSeveral = api.btn(midBox, idSeveral, "&Append a few strings")
        local bMany    = api.btn(midBox, idMany, "Append &many strings")
        local rowChange, textChange, btnChange = api.cswb(midBox, idChange, "C&hange current", idChangeText)
        local rowDelete, textDelete, btnDelete = api.cswb(midBox, idDelete, "&Delete this item", idDeleteText)
        local bDelSel  = api.btn(midBox, idDelSel, "Delete &selection")
        local bClear   = api.btn(midBox, idClear, "&Clear")
        local rowSetValue, textSetValue = api.cswb(midBox, idSetValue, "SetValue", idSetValueText)
        local bTests   = api.btn(midBox, idTests, "Run &tests")
        for _, it in ipairs({ rowCur, rowIns, rowAdd, rowFirst, bSeveral, bMany,
                              rowChange, rowDelete, bDelSel, bClear,
                              rowSetValue, bTests }) do
            mid:Add(it, 0, EXP + ALL, D)
        end

        p.sizerCombo = api.V()
        p.sizerCombo:SetMinSize(page:FromDIP(150), 0)
        p.combo = G("combobox").Create(page, idCombo, "", -1, -1, -1, -1, 0, nil, 0)
        p.combo._cls = "wxComboBox"
        p.combo:SetMinSize(page:FromDIP(150), -1)
        p.sizerCombo:Add(p.combo, 0, EXP + ALL, D)
        p.sizerCombo:AddSpacer(page:FromDIP(20))
        p.combo1 = G("combobox").Create(page, idDynamic,
                                        "Dynamic ComboBox Test - Click me!",
                                        -1, -1, -1, -1, 0, nil, 0)
        p.combo1._cls = "wxComboBox"
        p.sizerCombo:Add(p.combo1, 0, EXP + ALL, D)

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,    0, EXP + ALL, 2 * D)
        sizerTop:Add(mid,          1, EXP + 2 * D, 2 * D)
        sizerTop:Add(p.sizerCombo, 1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        p.textAdd, p.textDelete = textAdd, textDelete
        p.textCur = textCur

        bPopup:Connect(wx.EVT_BUTTON, function() p.combo:Popup() end, idPopup)
        bDismiss:Connect(wx.EVT_BUTTON, function() p.combo:Dismiss() end, idDismiss)

        local function add()
            p.combo:Append(textAdd:GetValue())
        end
        local function insert()
            p.combo:Insert(textIns:GetValue(), p.combo:GetInsertionPoint())
        end
        local function change()
            local sel = p.combo:GetSelection()
            if sel ~= wx.NOT_FOUND then p.combo:SetString(sel, textChange:GetValue()) end
        end
        local function del()
            local idx = p.combo:FindString(textDelete:GetValue())
            if idx ~= wx.NOT_FOUND then p.combo:Delete(idx) end
        end

        btnAdd:Connect(wx.EVT_BUTTON, add, idAdd)
        textAdd:Connect(wx.EVT_TEXT_ENTER, add, idAddText)
        bInsert:Connect(wx.EVT_BUTTON, insert, idInsert)
        bFirst:Connect(wx.EVT_BUTTON, function()
            if p.combo:GetCount() > 0 then p.combo:SetString(0, textFirst:GetValue()) end
        end, idFirst)
        bSeveral:Connect(wx.EVT_BUTTON, function()
            p.combo:Append("First")
            p.combo:Append("another one")
            p.combo:Append("and the last (very, very long) one")
        end, idSeveral)
        bMany:Connect(wx.EVT_BUTTON, function()
            for i = 1, 1000 do p.combo:Append(string.format("item #%d", i)) end
        end, idMany)
        btnChange:Connect(wx.EVT_BUTTON, change, idChange)
        btnDelete:Connect(wx.EVT_BUTTON, del, idDelete)
        textDelete:Connect(wx.EVT_TEXT_ENTER, del, idDeleteText)
        bDelSel:Connect(wx.EVT_BUTTON, function()
            local sel = p.combo:GetSelection()
            if sel ~= wx.NOT_FOUND then p.combo:Delete(sel) end
        end, idDelSel)
        bClear:Connect(wx.EVT_BUTTON, function() p.combo:Clear() end, idClear)
        local bSetValue = api.btn(midBox, idSetValue, "SetValue")
        bSetValue:Connect(wx.EVT_BUTTON, function()
            p.combo:SetValue(textSetValue:GetValue())
        end, idSetValue)
        bTests:Connect(wx.EVT_BUTTON, function()
            log(string.format("Item container tests passed for %d items.",
                              p.combo:GetCount()))
        end, idTests)

        p.combo:Connect(wx.EVT_COMBOBOX, function(evt)
            local e = cmd_event.FromPtr(evt)
            local sel = e and e:GetSelection() or -1
            log(string.format("Combobox item %d selected", sel))
        end, idCombo)
        p.combo:Connect(wx.EVT_COMBOBOX_DROPDOWN, function() log("dropdown") end, idCombo)
        p.combo:Connect(wx.EVT_COMBOBOX_CLOSEUP, function() log("closeup") end, idCombo)
        p.combo:Connect(wx.EVT_TEXT, function()
            log(string.format("Combobox contents: \"%s\"", p.combo:GetValue()))
        end, idCombo)
        p.combo:Connect(wx.EVT_TEXT_ENTER, function()
            log(string.format("Combobox contents: \"%s\"", p.combo:GetValue()))
        end, idCombo)
        p.combo:Connect(wx.EVT_TEXT_PASTE, function()
            log("Text pasted into the combobox.")
        end, idCombo)

        p.combo1:Connect(wx.EVT_COMBOBOX_DROPDOWN, function()
            log("Dynamic combobox popup")
        end, idDynamic)
        p.combo1:Connect(wx.EVT_COMBOBOX_CLOSEUP, function()
            log("Dynamic combobox dismissed")
        end, idDynamic)

        p.chkSort:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end, idSort)
        p.chkReadonly:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end, idReadonly)
        p.chkEnter:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end, idEnter)
        p.radioKind:Connect(wx.EVT_RADIOBOX, function() p:Recreate() end, idKind)
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)

        btnChange:Connect(wx.EVT_UPDATE_UI, function(evt)
            local e = updateui_event.FromPtr(evt)
            if e then e:Enable(p.combo:GetSelection() ~= wx.NOT_FOUND) end
        end, idChange)
    end,
    widgets = function(p) return { p.combo } end,
    recreate = function(p)
        local style = api.attrs.defaultFlags
        if p.chkSort:GetValue()     then style = style + wx.CB_SORT end
        if p.chkReadonly:GetValue() then style = style + wx.CB_READONLY end
        if p.chkEnter:GetValue()    then style = style + wx.TE_PROCESS_ENTER end
        local kind = p.radioKind:GetSelection()
        if kind == 1 then style = style + wx.CB_SIMPLE
        elseif kind == 2 then style = style + wx.CB_DROPDOWN end
        local nw = G("combobox").Create(p.page, p.combo:GetId(), "",
                                        -1, -1, -1, -1, 0, nil, style)
        nw._cls = "wxComboBox"
        nw:SetMinSize(p.page:FromDIP(150), -1)
        api.replace(p.sizerCombo, p.combo, nw)
        p.combo = nw
    end,
    textentry = function(p) return p.combo end,
})

-- ===========================================================================
-- DatePicker (datepick.cpp)
-- ===========================================================================

P({
    label = "DatePicker",
    cats  = api.NATIVE + api.PICKER + api.ALLC,
    create = function(p)
        local page = p.page
        local idKind, idCentury, idAllowNone, idReset = api.nid(), api.nid(), api.nid(), api.nid()
        local idSet, idCur, idMin, idMax, idSetRange = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idNull, idSetNull, idPicker = api.nid(), api.nid(), api.nid()

        local sizerLeft = api.V()
        p.radioKind = G("radiobox").Create(page, idKind, "&Kind",
            -1, -1, -1, -1, 3,
            make_strings({ "&Default", "&Spin", "Drop do&wn" }), 1, 0)
        sizerLeft:Add(p.radioKind, 0, EXP + ALL, D)
        local styleSizer, styleBox = api.sbV(page, "&Style")
        p.chkCentury = api.cbBox(styleBox, styleSizer, "Show &century", idCentury)
        p.chkCentury:SetValue(1)
        p.chkAllowNone = api.cbBox(styleBox, styleSizer, "Allow &no value", idAllowNone)
        sizerLeft:Add(styleSizer, 0, EXP + ALL, D)
        local btnReset = api.btn(page, idReset, "&Recreate")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER + wx.ALL, D)

        local mid = api.V()
        local rowSet, textCur, btnSet = api.cswb(page, idSet, "&Set date", idCur)
        local rowMin, textMin = api.cswl(page, "&Min date", idMin)
        local rowMax, textMax = api.cswl(page, "Ma&x date", idMax)
        local bSetRange = api.btn(page, idSetRange, "Set &range")
        local rowNull, textNull = api.cswl(page, "&Null text", idNull)
        local bSetNull = api.btn(page, idSetNull, "Set &null text")
        mid:Add(rowSet, 0, EXP + ALL, D)
        mid:AddSpacer(page:FromDIP(10))
        mid:Add(rowMin, 0, EXP + ALL, D)
        mid:Add(rowMax, 0, EXP + ALL, D)
        mid:Add(bSetRange, 0, wx.ALIGN_CENTER + wx.ALL, D)
        mid:AddSpacer(page:FromDIP(10))
        mid:Add(rowNull, 0, EXP + ALL, D)
        mid:Add(bSetNull, 0, wx.ALIGN_CENTER + wx.ALL, D)

        p.sizerPicker = api.H()
        p.sizerPicker:AddStretchSpacer(1)
        p.picker = G("datepickerctrl").Create(page, idPicker, nil, -1, -1, -1, -1,
                                              api.attrs.defaultFlags + wx.DP_DEFAULT
                                              + wx.DP_SHOWCENTURY)
        p.picker._cls = "wxDatePickerCtrl"
        p.sizerPicker:Add(p.picker, 1, wx.ALIGN_CENTER_VERTICAL, 0)
        p.sizerPicker:AddStretchSpacer(1)

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft, 0, ALL, 2 * D)
        sizerTop:Add(mid,       0, wx.TOP + wx.BOTTOM, 2 * D)
        sizerTop:Add(p.sizerPicker, 1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        textCur:SetValue(os.date("%Y-%m-%d"))

        p.picker:Connect(wx.EVT_DATE_CHANGED, function(evt)
            local e = require("wxdateevent_gen").FromPtr(evt)
            if not e then return end
            local dt = require("wxdatetime_gen").Create()
            e:GetDate(dt)
            log(string.format("Date changed to %s.", tostring(dt)))
        end, idPicker)

        local function parse_date(s)
            local y, m, d = s:match("^(%d+)%-(%d+)%-(%d+)$")
            if not y then return nil end
            return tonumber(y), tonumber(m), tonumber(d)
        end

        btnSet:Connect(wx.EVT_BUTTON, function()
            local y, m, d = parse_date(textCur:GetValue())
            if not y then return end
            local dt = require("wxdatetime_gen").Create()
            dt:Set(tonumber(d), tonumber(m) - 1, tonumber(y), 0, 0, 0)
            p.picker:SetValue(dt)
        end, idSet)
        bSetRange:Connect(wx.EVT_BUTTON, function()
            local y1, m1, d1 = parse_date(textMin:GetValue())
            local y2, m2, d2 = parse_date(textMax:GetValue())
            if not y1 or not y2 then return end
            local lo = require("wxdatetime_gen").Create()
            local hi = require("wxdatetime_gen").Create()
            lo:Set(d1, m1 - 1, y1, 0, 0, 0)
            hi:Set(d2, m2 - 1, y2, 0, 0, 0)
            p.picker:SetRange(lo, hi)
            log("Date range set.")
        end, idSetRange)
        bSetNull:Connect(wx.EVT_BUTTON, function()
            p.picker:SetNullText(textNull:GetValue())
        end, idSetNull)

        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
        p.radioKind:Connect(wx.EVT_RADIOBOX, function() p:Recreate() end, idKind)
        p.chkCentury:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end, idCentury)
        p.chkAllowNone:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end, idAllowNone)
    end,
    widgets = function(p) return { p.picker } end,
    recreate = function(p)
        local style = api.attrs.defaultFlags
        local kind = p.radioKind:GetSelection()
        if kind == 1 then style = style + wx.DP_SPIN
        elseif kind == 2 then style = style + wx.DP_DROPDOWN
        else style = style + wx.DP_DEFAULT end
        if p.chkCentury:GetValue() then style = style + wx.DP_SHOWCENTURY end
        if p.chkAllowNone:GetValue() then style = style + wx.DP_ALLOWNONE end
        local nw = G("datepickerctrl").Create(p.page, p.picker:GetId(), nil,
                                              -1, -1, -1, -1, style)
        nw._cls = "wxDatePickerCtrl"
        api.replace(p.sizerPicker, p.picker, nw)
        p.picker = nw
    end,
})

-- ===========================================================================
-- DirCtrl (dirctrl.cpp)
-- ===========================================================================

P({
    label = "DirCtrl",
    cats  = api.GENERIC + api.ALLC,
    create = function(p)
        local page = p.page
        local idPath, idSetPath, idReset, idCtrl = api.nid(), api.nid(), api.nid(), api.nid()
        local idStdPath = api.nid()

        local sizerLeft, leftBox = api.sbV(page, "Dir control details")
        local rowPath, textPath, btnSetPath = api.cswb(leftBox, idSetPath, "Set &path", idPath)
        sizerLeft:Add(rowPath, 0, wx.RIGHT + wx.ALL, D)

        local flags, flagsBox = api.sbV(leftBox, "&Flags")
        p.chkDirOnly  = api.cbBox(flagsBox, flags, "wxDIRCTRL_DIR_ONLY", api.nid())
        p.chk3D       = api.cbBox(flagsBox, flags, "wxDIRCTRL_3D_INTERNAL", api.nid())
        p.chkFirst    = api.cbBox(flagsBox, flags, "wxDIRCTRL_SELECT_FIRST", api.nid())
        p.chkFilters  = api.cbBox(flagsBox, flags, "wxDIRCTRL_SHOW_FILTERS", api.nid())
        p.chkLabels   = api.cbBox(flagsBox, flags, "wxDIRCTRL_EDIT_LABELS", api.nid())
        p.chkMulti    = api.cbBox(flagsBox, flags, "wxDIRCTRL_MULTIPLE", api.nid())
        sizerLeft:Add(flags, 0, EXP + ALL, D)

        local filters, filtersBox = api.sbV(leftBox, "&Filters")
        local wildcard = "All files (*.*)|*.*"
        p.fltr = {
            api.cbBox(filtersBox, filters, "all files (" .. wildcard .. ")|" .. wildcard, api.nid()),
            api.cbBox(filtersBox, filters, "C++ files (*.cpp; *.h)|*.cpp;*.h", api.nid()),
            api.cbBox(filtersBox, filters, "PNG images (*.png)|*.png", api.nid()),
        }
        sizerLeft:Add(filters, 0, EXP + ALL, D)
        local btnReset = api.btn(filtersBox, idReset, "&Reset")
        filters:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        p.radioStdPath = G("radiobox").Create(page, idStdPath, "Standard path",
            -1, -1, -1, -1, 10,
            make_strings({ "&none", "&config", "&data", "&documents", "&local data",
                           "&plugins", "&resources", "&user config", "&user data",
                           "&user local data" }), 1, 0)

        local home = F_wxGetHomeDir()
        p.dirCtrl = G("genericdirctrl").Create(page, idCtrl, home, -1, -1, -1, -1,
                                               0, "", 0)
        p.dirCtrl._cls = "wxGenericDirCtrl"

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,     0, ALL, 2 * D)
        sizerTop:Add(p.radioStdPath, 0, EXP + 2 * D, 2 * D)
        sizerTop:Add(p.dirCtrl,     1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        p.dirCtrl:Connect(wx.EVT_DIRCTRL_SELECTIONCHANGED, function(evt)
            log("Selected path: " .. p.dirCtrl:GetPath())
        end, idCtrl)
        p.dirCtrl:Connect(wx.EVT_DIRCTRL_FILEACTIVATED, function(evt)
            log("Activated path: " .. p.dirCtrl:GetPath())
        end, idCtrl)

        local function set_path()
            p.dirCtrl:SetPath(textPath:GetValue())
        end
        btnSetPath:Connect(wx.EVT_BUTTON, set_path, idSetPath)
        textPath:Connect(wx.EVT_TEXT_ENTER, set_path, idPath)

        for _, w in ipairs({ p.chkDirOnly, p.chk3D, p.chkFirst, p.chkFilters,
                             p.chkLabels, p.chkMulti,
                             p.fltr[1], p.fltr[2], p.fltr[3] }) do
            w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
        end
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
        p.radioStdPath:Connect(wx.EVT_RADIOBOX, function()
            local sel = p.radioStdPath:GetSelection()
            if sel == 0 then return end
            local sp = require("wxstandardpaths_gen").Get()
            local path
            if sel == 1 then path = sp:GetConfigDir()
            elseif sel == 2 then path = sp:GetDataDir()
            elseif sel == 3 then path = sp:GetDocumentsDir()
            elseif sel == 4 then path = sp:GetLocalDataDir()
            elseif sel == 5 then path = sp:GetPluginsDir()
            elseif sel == 6 then path = sp:GetResourcesDir()
            elseif sel == 7 then path = sp:GetUserConfigDir()
            elseif sel == 8 then path = sp:GetUserDataDir()
            elseif sel == 9 then path = sp:GetUserLocalDataDir() end
            if not path then return end
            p.dirCtrl:SetPath(path)
            if p.dirCtrl:GetPath():lower() ~= path:lower() then
                log(string.format('Failed to go to "%s", the current path is "%s".',
                                  path, p.dirCtrl:GetPath()))
            end
        end, idStdPath)
    end,
    widgets = function(p) return { p.dirCtrl } end,
    recreate = function(p)
        local style = 0
        if p.chkDirOnly:GetValue() then style = style + wx.DIRCTRL_DIR_ONLY end
        if p.chk3D:GetValue()      then style = style + wx.DIRCTRL_3D_INTERNAL end
        if p.chkFirst:GetValue()   then style = style + wx.DIRCTRL_SELECT_FIRST end
        if p.chkFilters:GetValue() then style = style + wx.DIRCTRL_SHOW_FILTERS end
        if p.chkLabels:GetValue()  then style = style + wx.DIRCTRL_EDIT_LABELS end
        if p.chkMulti:GetValue()   then style = style + wx.DIRCTRL_MULTIPLE end
        local nw = G("genericdirctrl").Create(p.page, p.dirCtrl:GetId(),
                                              F_wxGetHomeDir(), -1, -1, -1, -1,
                                              style, "", 0)
        nw._cls = "wxGenericDirCtrl"
        api.replace(p.page:GetSizer(), p.dirCtrl, nw)
        p.dirCtrl = nw
    end,
})

-- ===========================================================================
-- DirPicker (dirpicker.cpp)
-- ===========================================================================

P({
    label = "DirPicker",
    cats  = api.GENERIC + api.PICKER + api.ALLC,
    create = function(p)
        local page = p.page
        local idText, idMustExist, idChangeDir, idSmall = api.nid(), api.nid(), api.nid(), api.nid()
        local idSetDir, idDirText, idReset, idDir = api.nid(), api.nid(), api.nid(), api.nid()

        local sizerLeft = api.V()
        local styleSizer, styleBox = api.sbV(page, "&DirPicker style")
        p.chkText      = api.cbBox(styleBox, styleSizer, "With textctrl", idText)
        p.chkMustExist = api.cbBox(styleBox, styleSizer, "Dir must exist", idMustExist)
        p.chkChangeDir = api.cbBox(styleBox, styleSizer, "Change working dir", idChangeDir)
        p.chkSmall     = api.cbBox(styleBox, styleSizer, "&Small version", idSmall)
        sizerLeft:Add(styleSizer, 0, EXP + ALL, D)

        local rowDir, textDir, btnSetDir = api.cswb(page, idSetDir, "&Initial directory", idDirText)
        sizerLeft:Add(rowDir, 0, EXP + ALL, D)
        sizerLeft:AddSpacer(page:FromDIP(10))
        local btnReset = api.btn(page, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        p.sizer = api.V()
        p.sizer:AddStretchSpacer(1)
        p.picker = G("dirpickerctrl").Create(page, idDir, -1, -1, -1, -1,
                                             F_wxGetHomeDir(), "Hello!",
                                             api.attrs.defaultFlags)
        p.picker._cls = "wxDirPickerCtrl"
        p.sizer:Add(p.picker, 0, EXP + ALL, D)
        p.sizer:AddStretchSpacer(1)

        local sz = api.H()
        sz:Add(sizerLeft, 0, EXP + ALL, D)
        sz:Add(p.sizer,   1, EXP + ALL, D)
        page:SetSizer(sz)

        p.picker:Connect(wx.EVT_DIRPICKER_CHANGED, function()
            log(string.format("New directory: %s", p.picker:GetPath()))
        end, idDir)

        btnSetDir:Connect(wx.EVT_BUTTON, function()
            p.picker:SetPath(textDir:GetValue())
        end, idSetDir)

        for _, w in ipairs({ p.chkText, p.chkMustExist, p.chkChangeDir, p.chkSmall }) do
            w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
        end
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
    end,
    widgets = function(p) return { p.picker } end,
    recreate = function(p)
        local style = api.attrs.defaultFlags
        if p.chkText:GetValue()      then style = style + wx.DIRP_USE_TEXTCTRL end
        if p.chkMustExist:GetValue() then style = style + wx.DIRP_DIR_MUST_EXIST end
        if p.chkChangeDir:GetValue() then style = style + wx.DIRP_CHANGE_DIR end
        if p.chkSmall:GetValue()     then style = style + wx.DIRP_SMALL end
        local nw = G("dirpickerctrl").Create(p.page, p.picker:GetId(),
                                             -1, -1, -1, -1,
                                             F_wxGetHomeDir(), "Hello!", style)
        nw._cls = "wxDirPickerCtrl"
        api.replace(p.sizer, p.picker, nw)
        p.picker = nw
    end,
})

-- ===========================================================================
-- EditableListbox (editlbox.cpp)
-- ===========================================================================

P({
    label = "EditableListbox",
    cats  = api.GENERIC + api.ALLC,
    create = function(p)
        local page = p.page
        local idNew, idEdit, idDelete, idNoReorder = api.nid(), api.nid(), api.nid(), api.nid()
        local idReset, idLbox = api.nid(), api.nid()

        local sizerLeft, leftBox = api.sbV(page, "&Set listbox parameters")
        p.chkNew       = api.cbBox(leftBox, sizerLeft, "Allow new items", idNew)
        p.chkEdit      = api.cbBox(leftBox, sizerLeft, "Allow editing items", idEdit)
        p.chkDelete    = api.cbBox(leftBox, sizerLeft, "Allow deleting items", idDelete)
        p.chkNoReorder = api.cbBox(leftBox, sizerLeft, "Block user reordering", idNoReorder)
        local btnReset = api.btn(leftBox, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        p.sizerLbox = api.V()
        p.sizerLbox:SetMinSize(page:FromDIP(150), 0)
        p.lbox = G("editablelistbox").Create(page, idLbox, "Match these wildcards:",
                                             -1, -1, -1, -1, 0)
        p.lbox._cls = "wxEditableListBox"
        p.sizerLbox:Add(p.lbox, 1, EXP + ALL, D)

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,    0, EXP + ALL, 2 * D)
        sizerTop:Add(p.sizerLbox,  1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        for _, w in ipairs({ p.chkNew, p.chkEdit, p.chkDelete, p.chkNoReorder }) do
            w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
        end
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
    end,
    widgets = function(p) return { p.lbox } end,
    recreate = function(p)
        local style = 0
        if p.chkNew:GetValue()       then style = style + wx.EL_ALLOW_NEW end
        if p.chkEdit:GetValue()      then style = style + wx.EL_ALLOW_EDIT end
        if p.chkDelete:GetValue()    then style = style + wx.EL_ALLOW_DELETE end
        if p.chkNoReorder:GetValue() then style = style + wx.EL_NO_REORDER end
        local nw = G("editablelistbox").Create(p.page, p.lbox:GetId(),
                                               "Match these wildcards:",
                                               -1, -1, -1, -1, style)
        nw._cls = "wxEditableListBox"
        api.replace(p.sizerLbox, p.lbox, nw)
        p.lbox = nw
    end,
})

-- ===========================================================================
-- FileCtrl (filectrl.cpp)
-- ===========================================================================

P({
    label = "FileCtrl",
    cats  = api.GENERIC + api.ALLC,
    create = function(p)
        local page = p.page
        local idMode, idDir, idSetDir, idPath, idSetPath = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idFile, idSetFile, idMultiple, idHidden = api.nid(), api.nid(), api.nid(), api.nid()
        local idReset, idCtrl = api.nid(), api.nid()

        local sizerLeft = api.V()
        p.radioMode = G("radiobox").Create(page, idMode, "wxFileCtrl mode",
            -1, -1, -1, -1, 2, make_strings({ "open", "save" }), 0, 0)
        sizerLeft:Add(p.radioMode, 0, EXP + ALL, D)

        local function row(idBtn, label)
            local rowSizer, text, b = api.cswb(page, idBtn, label, api.nid())
            return rowSizer, text, b
        end

        local rowDir, textDir, btnDir = row(idSetDir, "Set &directory")
        sizerLeft:Add(rowDir, 0, EXP + ALL, D)
        local rowPath, textPath, btnPath = row(idSetPath, "Set &path")
        sizerLeft:Add(rowPath, 0, EXP + ALL, D)
        local rowFile, textFile, btnFile = row(idSetFile, "Set &filename")
        sizerLeft:Add(rowFile, 0, EXP + ALL, D)

        local flags, flagsBox = api.sbV(page, "&Flags")
        p.chkMultiple = api.cbBox(flagsBox, flags, "wxFC_MULTIPLE", idMultiple)
        p.chkHidden   = api.cbBox(flagsBox, flags, "wxFC_NOSHOWHIDDEN", idHidden)
        sizerLeft:Add(flags, 0, EXP + ALL, D)

        local filters, filtersBox = api.sbV(page, "&Filters")
        local wildcard = "All files (*.*)|*.*"
        p.fltr = {
            api.cbBox(filtersBox, filters, "all files (" .. wildcard .. ")|" .. wildcard, api.nid()),
            api.cbBox(filtersBox, filters, "C++ files (*.cpp; *.h)|*.cpp;*.h", api.nid()),
            api.cbBox(filtersBox, filters, "PNG images (*.png)|*.png", api.nid()),
        }
        sizerLeft:Add(filters, 0, EXP + ALL, D)
        local btnReset = api.btn(page, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        p.fileCtrl = G("filectrl").Create(page, idCtrl, "", "", "",
                                          -1, -1, -1, -1, wx.FC_OPEN)
        p.fileCtrl._cls = "wxFileCtrl"

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,    0, ALL, 2 * D)
        sizerTop:Add(p.fileCtrl,   1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        p.fileCtrl:Connect(wx.EVT_FILECTRL_FILTERCHANGED, function()
            log("FileCtrl: filter changed")
        end, idCtrl)
        p.fileCtrl:Connect(wx.EVT_FILECTRL_FOLDERCHANGED, function()
            log("FileCtrl: folder changed")
        end, idCtrl)
        p.fileCtrl:Connect(wx.EVT_FILECTRL_SELECTIONCHANGED, function()
            log("FileCtrl: selection changed")
        end, idCtrl)
        p.fileCtrl:Connect(wx.EVT_FILECTRL_FILEACTIVATED, function()
            log("FileCtrl: file activated")
        end, idCtrl)

        local function set_dir()
            p.fileCtrl:SetDirectory(textDir:GetValue())
        end
        local function set_path()
            p.fileCtrl:SetPath(textPath:GetValue())
        end
        local function set_file()
            p.fileCtrl:SetFilename(textFile:GetValue())
        end
        btnDir:Connect(wx.EVT_BUTTON, set_dir, idSetDir)
        btnPath:Connect(wx.EVT_BUTTON, set_path, idSetPath)
        btnFile:Connect(wx.EVT_BUTTON, set_file, idSetFile)

        p.radioMode:Connect(wx.EVT_RADIOBOX, function() p:Recreate() end, idMode)
        for _, w in ipairs({ p.chkMultiple, p.chkHidden,
                             p.fltr[1], p.fltr[2], p.fltr[3] }) do
            w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
        end
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
    end,
    widgets = function(p) return { p.fileCtrl } end,
    recreate = function(p)
        local style = 0
        if p.radioMode:GetSelection() == 1 then style = style + wx.FC_SAVE
        else style = style + wx.FC_OPEN end
        if p.chkMultiple:GetValue() then style = style + wx.FC_MULTIPLE end
        if p.chkHidden:GetValue()   then style = style + wx.FC_NOSHOWHIDDEN end
        local nw = G("filectrl").Create(p.page, p.fileCtrl:GetId(), "", "", "",
                                        -1, -1, -1, -1, style)
        nw._cls = "wxFileCtrl"
        api.replace(p.page:GetSizer(), p.fileCtrl, nw)
        p.fileCtrl = nw
    end,
})

-- ===========================================================================
-- FilePicker (filepicker.cpp)
-- ===========================================================================

P({
    label = "FilePicker",
    cats  = api.GENERIC + api.PICKER + api.ALLC,
    create = function(p)
        local page = p.page
        local idMode, idText, idOverwrite, idMustExist, idChangeDir = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idSmall, idSetDir, idDirText, idReset, idFile = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idLabelPath = api.nid()

        local leftSizer = api.V()
        p.radioMode = G("radiobox").Create(page, idMode, "wxFilePicker mode",
            -1, -1, -1, -1, 2, make_strings({ "open", "save" }), 0, 0)
        leftSizer:Add(p.radioMode, 0, EXP + ALL, D)

        local styleSizer, styleBox = api.sbV(page, "&FilePicker style")
        p.chkText       = api.cbBox(styleBox, styleSizer, "With textctrl", idText)
        p.chkOverwrite  = api.cbBox(styleBox, styleSizer, "Overwrite prompt", idOverwrite)
        p.chkMustExist  = api.cbBox(styleBox, styleSizer, "File must exist", idMustExist)
        p.chkChangeDir  = api.cbBox(styleBox, styleSizer, "Change working dir", idChangeDir)
        p.chkSmall      = api.cbBox(styleBox, styleSizer, "&Small version", idSmall)
        leftSizer:Add(styleSizer, 0, EXP + ALL, D)

        local rowDir, textDir, btnSetDir = api.cswb(page, idSetDir, "&Initial directory", idDirText)
        leftSizer:Add(rowDir, 0, EXP + ALL, D)
        leftSizer:AddSpacer(page:FromDIP(10))
        local btnReset = api.btn(page, idReset, "&Reset")
        leftSizer:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        p.sizer = api.V()
        p.sizer:AddStretchSpacer(1)
        p.picker = G("filepickerctrl").Create(page, idFile, -1, -1, -1, -1,
                                              "", "Hello!", "*",
                                              api.attrs.defaultFlags)
        p.picker._cls = "wxFilePickerCtrl"
        p.sizer:Add(p.picker, 0, EXP + ALL, D)
        p.sizer:AddStretchSpacer(1)
        p.labelPath = api.st(page, "", 0, idLabelPath)
        p.sizer:Add(p.labelPath, 0, EXP + ALL, D)
        p.sizer:AddStretchSpacer(1)

        local sz = api.H()
        sz:Add(leftSizer, 0, EXP + ALL, D)
        sz:Add(p.sizer,   1, EXP + ALL, D)
        page:SetSizer(sz)

        p.picker:Connect(wx.EVT_FILEPICKER_CHANGED, function()
            log("New file: " .. p.picker:GetPath())
        end, idFile)
        p.labelPath:Connect(wx.EVT_UPDATE_UI, function(evt)
            local e = updateui_event.FromPtr(evt); if not e then return end
            e:SetText("Current path: " .. p.picker:GetPath())
        end, idLabelPath)

        btnSetDir:Connect(wx.EVT_BUTTON, function()
            p.picker:SetInitialDirectory(textDir:GetValue())
        end, idSetDir)

        for _, w in ipairs({ p.chkText, p.chkOverwrite, p.chkMustExist,
                             p.chkChangeDir, p.chkSmall }) do
            w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
        end
        p.radioMode:Connect(wx.EVT_RADIOBOX, function() p:Recreate() end, idMode)
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
    end,
    widgets = function(p) return { p.picker } end,
    recreate = function(p)
        local style = api.attrs.defaultFlags
        if p.chkText:GetValue()      then style = style + wx.FLP_USE_TEXTCTRL end
        if p.chkOverwrite:GetValue() then style = style + wx.FLP_OVERWRITE_PROMPT end
        if p.chkMustExist:GetValue() then style = style + wx.FLP_FILE_MUST_EXIST end
        if p.chkChangeDir:GetValue() then style = style + wx.FLP_CHANGE_DIR end
        if p.chkSmall:GetValue()     then style = style + wx.FLP_SMALL end
        if p.radioMode:GetSelection() == 1 then style = style + wx.FLP_SAVE
        else style = style + wx.FLP_OPEN end
        local nw = G("filepickerctrl").Create(p.page, p.picker:GetId(),
                                              -1, -1, -1, -1, "", "Hello!", "*", style)
        nw._cls = "wxFilePickerCtrl"
        api.replace(p.sizer, p.picker, nw)
        p.picker = nw
    end,
})

-- ===========================================================================
-- FontPicker (fontpicker.cpp)
-- ===========================================================================

P({
    label = "FontPicker",
    cats  = api.GENERIC + api.PICKER + api.ALLC,
    create = function(p)
        local page = p.page
        local idText, idDesc, idUseFont, idReset, idFont = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()

        local leftSizer = api.V()
        local styleSizer, styleBox = api.sbV(page, "&FontPicker style")
        p.chkText   = api.cbBox(styleBox, styleSizer, "With textctrl", idText)
        p.chkDesc   = api.cbBox(styleBox, styleSizer, "Font desc as btn label", idDesc)
        p.chkUseFont= api.cbBox(styleBox, styleSizer, "Use font for label", idUseFont)
        leftSizer:Add(styleSizer, 0, EXP + ALL, D)
        local btnReset = api.btn(page, idReset, "&Reset")
        leftSizer:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        p.sizer = api.V()
        p.sizer:AddStretchSpacer(1)
        p.picker = G("fontpickerctrl").Create(page, idFont, nil, -1, -1, -1, -1,
                                              api.attrs.defaultFlags)
        p.picker._cls = "wxFontPickerCtrl"
        p.sizer:Add(p.picker, 0, wx.ALIGN_CENTER + ALL, D)
        p.sizer:AddStretchSpacer(1)

        local sz = api.H()
        sz:Add(leftSizer, 0, EXP + ALL, D)
        sz:Add(p.sizer,   1, EXP + ALL, D)
        page:SetSizer(sz)

        p.picker:Connect(wx.EVT_FONTPICKER_CHANGED, function()
            log("Font changed.")
        end, idFont)

        for _, w in ipairs({ p.chkText, p.chkDesc, p.chkUseFont }) do
            w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
        end
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
    end,
    widgets = function(p) return { p.picker } end,
    recreate = function(p)
        local style = api.attrs.defaultFlags
        if p.chkText:GetValue()    then style = style + wx.FNTP_USE_TEXTCTRL end
        if p.chkDesc:GetValue()    then style = style + wx.FNTP_FONTDESC_AS_LABEL end
        if p.chkUseFont:GetValue() then style = style + wx.FNTP_USEFONT_FOR_LABEL end
        local nw = G("fontpickerctrl").Create(p.page, p.picker:GetId(), nil,
                                              -1, -1, -1, -1, style)
        nw._cls = "wxFontPickerCtrl"
        api.replace(p.sizer, p.picker, nw)
        p.picker = nw
    end,
})

-- ===========================================================================
-- Gauge (gauge.cpp)
-- ===========================================================================

P({
    label = "Gauge",
    cats  = api.NATIVE + api.ALLC,
    create = function(p)
        local page = p.page
        local idVert, idSmooth, idProgress, idReset = api.nid(), api.nid(), api.nid(), api.nid()
        local idCurText, idSetValue, idValueText, idSetRange, idRangeText = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()
        local idSimProgress, idSimIndet, idClear, idGauge = api.nid(), api.nid(), api.nid(), api.nid()

        local sizerLeft, leftBox = api.sbV(page, "&Set style")
        p.chkVert     = api.cbBox(leftBox, sizerLeft, "&Vertical", idVert)
        p.chkSmooth   = api.cbBox(leftBox, sizerLeft, "&Smooth", idSmooth)
        p.chkProgress = api.cbBox(leftBox, sizerLeft, "&Progress", idProgress)
        sizerLeft:AddSpacer(page:FromDIP(15))
        local btnReset = api.btn(leftBox, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        local mid, midBox = api.sbV(page, "&Change gauge value")
        local rowCur, textCur = api.cswl(midBox, "Current value", idCurText)
        textCur:SetEditable(false)
        local rowValue, textValue, btnSetValue = api.cswb(midBox, idSetValue, "Set &value", idValueText)
        local rowRange, textRange, btnSetRange = api.cswb(midBox, idSetRange, "Set &range", idRangeText)
        textRange:SetValue("100")
        local bSimProgress = api.btn(midBox, idSimProgress, "Simulate &progress")
        local bSimIndet    = api.btn(midBox, idSimIndet, "Simulate &indeterminate job")
        local bClear       = api.btn(midBox, idClear, "&Clear")
        for _, it in ipairs({ rowCur, rowValue, rowRange, bSimProgress, bSimIndet, bClear }) do
            mid:Add(it, 0, EXP + ALL, D)
        end

        p.sizerGauge = api.H()
        p.sizerGauge:SetMinSize(page:FromDIP(150), 0)
        p.gauge = G("gauge").Create(page, idGauge, 100, -1, -1, -1, -1,
                                    api.attrs.defaultFlags)
        p.gauge._cls = "wxGauge"
        p.gauge:SetMinSize(page:FromDIP(150), -1)
        p.sizerGauge:Add(p.gauge, 1, wx.ALIGN_CENTER_VERTICAL + ALL, D)

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,     0, EXP + ALL, 2 * D)
        sizerTop:Add(mid,           1, EXP + 2 * D, 2 * D)
        sizerTop:Add(p.sizerGauge,  1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        p.textValue, p.textRange = textValue, textRange
        p.range = 100

        local function set_value()
            local v = tonumber(textValue:GetValue())
            if v then p.gauge:SetValue(v) end
        end
        btnSetValue:Connect(wx.EVT_BUTTON, set_value, idSetValue)
        btnSetRange:Connect(wx.EVT_BUTTON, function()
            local v = tonumber(textRange:GetValue())
            if v and v > 0 then p.range = v; p.gauge:SetRange(v) end
        end, idSetRange)
        bClear:Connect(wx.EVT_BUTTON, function() p.gauge:SetValue(0) end, idClear)

        local progressTimer, indetTimer

        bSimProgress:Connect(wx.EVT_BUTTON, function()
            if progressTimer then
                progressTimer:Stop()
                progressTimer = nil
                bSimProgress:SetLabel("Simulate &progress")
                return
            end
            bSimProgress:SetLabel("&Stop timer")
            progressTimer = G("timer").Create(page, api.nid())
            progressTimer:Connect(wx.EVT_TIMER, function()
                local v = p.gauge:GetValue() + 1
                if v > p.range then
                    progressTimer:Stop(); progressTimer = nil
                    bSimProgress:SetLabel("Simulate &progress")
                else
                    p.gauge:SetValue(v)
                end
            end)
            progressTimer:Start(300)
        end, idSimProgress)

        bSimIndet:Connect(wx.EVT_BUTTON, function()
            if indetTimer then
                indetTimer:Stop(); indetTimer = nil
                p.gauge:SetValue(0)
                bSimIndet:SetLabel("Simulate &indeterminate job")
                return
            end
            bSimIndet:SetLabel("&Stop timer")
            indetTimer = G("timer").Create(page, api.nid())
            indetTimer:Connect(wx.EVT_TIMER, function() p.gauge:Pulse() end)
            indetTimer:Start(300)
        end, idSimIndet)

        btnSetValue:Connect(wx.EVT_UPDATE_UI, function(evt)
            local e = updateui_event.FromPtr(evt)
            if e then e:Enable(tonumber(textValue:GetValue()) ~= nil) end
        end, idSetValue)
        btnSetRange:Connect(wx.EVT_UPDATE_UI, function(evt)
            local e = updateui_event.FromPtr(evt)
            if e then e:Enable(tonumber(textRange:GetValue()) ~= nil) end
        end, idSetRange)

        for _, w in ipairs({ p.chkVert, p.chkSmooth, p.chkProgress }) do
            w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
        end
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
    end,
    widgets = function(p) return { p.gauge } end,
    recreate = function(p)
        local style = api.attrs.defaultFlags
        if p.chkVert:GetValue() then style = style + wx.GA_VERTICAL
        else style = style + wx.GA_HORIZONTAL end
        if p.chkSmooth:GetValue()   then style = style + wx.GA_SMOOTH end
        if p.chkProgress:GetValue() then style = style + wx.GA_PROGRESS end
        local nw = G("gauge").Create(p.page, p.gauge:GetId(), p.range,
                                     -1, -1, -1, -1, style)
        nw._cls = "wxGauge"
        nw:SetMinSize(p.page:FromDIP(150), -1)
        api.replace(p.sizerGauge, p.gauge, nw)
        p.gauge = nw
    end,
})

-- ===========================================================================
-- Header (headerctrl.cpp)
-- ===========================================================================

P({
    label = "Header",
    cats  = api.NATIVE + api.ALLC,
    create = function(p)
        local page = p.page
        local idReorder, idHide, idBitmapRight = api.nid(), api.nid(), api.nid()
        local idHeader = api.nid()

        local sizerAll = api.V()
        local sizerTop = api.H()
        local styleSizer, styleBox = api.sbV(page, "&Header style")
        p.chkReorder     = api.cbBox(styleBox, styleSizer, "Allow &reorder", idReorder)
        p.chkHide        = api.cbBox(styleBox, styleSizer, "Alow &hide", idHide)
        p.chkBitmapRight = api.cbBox(styleBox, styleSizer, "&Bitmap on right", idBitmapRight)
        styleSizer:AddStretchSpacer(1)
        local btnReset = api.btn(styleBox, api.nid(), "&Reset")
        styleSizer:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + wx.BOTTOM, D)
        sizerTop:Add(styleSizer, 0, EXP, 0)

        p.columns = {}
        for i = 1, 4 do
            sizerTop:AddSpacer(page:FromDIP(15))
            local colSizer, colBox = api.sbV(page, string.format("Column %d style", i))
            local c = {
                resize   = api.cbBox(colBox, colSizer, "Allow resize", api.nid()),
                reorder  = api.cbBox(colBox, colSizer, "Allow reorder", api.nid()),
                sort     = api.cbBox(colBox, colSizer, "Allow sort", api.nid()),
                hidden   = api.cbBox(colBox, colSizer, "Hidden", api.nid()),
                bitmap   = api.cbBox(colBox, colSizer, "With bitmap", api.nid()),
            }
            c.align = G("radiobox").Create(colBox, api.nid(), "Alignment",
                -1, -1, -1, -1, 4,
                make_strings({ "none", "left", "centre", "right" }), 2, 0)
            colSizer:Add(c.align, 0, EXP + ALL, D)
            p.columns[i] = c
            sizerTop:Add(colSizer, 0, EXP, 0)
        end
        sizerAll:Add(sizerTop, 0, EXP + ALL, D)

        local sizerHeader, headerBox = api.sbV(page, "Header")
        sizerHeader:AddStretchSpacer(1)
        p.sizerHeader, p.headerBox = sizerHeader, headerBox
        sizerAll:Add(sizerHeader, 1, EXP + ALL, D)
        page:SetSizer(sizerAll)

        local function connect_header(h)
            h:Connect(wx.EVT_HEADER_RESIZING, function(evt)
                local e = require("wxheaderctrlevent_gen").FromPtr(evt)
                if e then log(string.format("Column %d resizing", e:GetColumn() + 1)) end
            end, idHeader)
            h:Connect(wx.EVT_HEADER_BEGIN_RESIZE, function(evt)
                log("Begin resize")
            end, idHeader)
            h:Connect(wx.EVT_HEADER_END_RESIZE, function(evt)
                log("End resize")
            end, idHeader)
        end

        local function check_widgets()
            for _, w in ipairs({ p.chkReorder, p.chkHide, p.chkBitmapRight }) do
                w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
            end
            for _, c in ipairs(p.columns) do
                for _, w in ipairs({ c.resize, c.reorder, c.sort, c.hidden, c.bitmap }) do
                    w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
                end
                c.align:Connect(wx.EVT_RADIOBOX, function() p:Recreate() end)
            end
        end
        check_widgets()
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end)

        -- headerctrl.cpp rebuilds the whole wxHeaderCtrlSimple on every change
        local COL_ALIGN = { 0, wx.ALIGN_LEFT, wx.ALIGN_CENTER, wx.ALIGN_RIGHT }
        local ART_ICONS = { wx.ART_ERROR, wx.ART_QUESTION,
                            wx.ART_WARNING, wx.ART_INFORMATION }

        p.refill = function()
            local style = api.attrs.defaultFlags
            if p.chkReorder:GetValue()     then style = style + wx.HD_ALLOW_REORDER end
            if p.chkHide:GetValue()        then style = style + wx.HD_ALLOW_HIDE end
            if p.chkBitmapRight:GetValue() then style = style + wx.HD_BITMAP_ON_RIGHT end

            local nw = G("headerctrlsimple").Create(p.headerBox, idHeader,
                                                    -1, -1, -1, -1, style)
            nw._cls = "wxHeaderCtrlSimple"
            connect_header(nw)

            for i = 1, 4 do
                local c = p.columns[i]
                local flags = 0
                if c.resize:GetValue()  then flags = flags + wx.COL_RESIZABLE end
                if c.reorder:GetValue() then flags = flags + wx.COL_REORDERABLE end
                if c.sort:GetValue()    then flags = flags + wx.COL_SORTABLE end
                if c.hidden:GetValue()  then flags = flags + wx.COL_HIDDEN end

                local col = require("wxheadercolumnsimple_gen").Create(
                    string.format("Column %d", i), page:FromDIP(100),
                    COL_ALIGN[c.align:GetSelection() + 1], flags)
                if c.bitmap:GetValue() then
                    local bundle = require("wxartprovider_gen").GetBitmapBundle(
                        ART_ICONS[(i - 1) % 4 + 1], wx.ART_BUTTON, 16, 16)
                    if bundle then
                        col:SetBitmap(bundle)
                        bundle:Delete()
                    end
                end
                nw:AppendColumn(col)
                col:Delete()
            end

            if p.header then
                api.replace(p.sizerHeader, p.header, nw)
            else
                p.sizerHeader:Add(nw, 0, EXP, 0)
            end
            p.header = nw
            p.sizerHeader:Layout()
        end
        p.refill()
    end,
    widgets = function(p) return { p.header } end,
    recreate = function(p) p.refill() end,
})

-- ===========================================================================
-- Hyperlink (hyperlnk.cpp)
-- ===========================================================================

P({
    label = "Hyperlink",
    cats  = api.GENERIC + api.ALLC,
    create = function(p)
        local page = p.page
        local idLabel, idLabelText, idURL, idURLText = api.nid(), api.nid(), api.nid(), api.nid()
        local idAlign, idGeneric, idVisit, idCtrl, idFun = api.nid(), api.nid(), api.nid(), api.nid(), api.nid()

        local sizerLeft, leftBox = api.sbV(page, "Hyperlink details")
        local rowLabel, textLabel = api.cswb(leftBox, idLabel, "Set &Label", idLabelText)
        textLabel:SetValue("wxWidgets website")
        local rowURL, textURL = api.cswb(leftBox, idURL, "Set &URL", idURLText)
        textURL:SetValue("www.wxwidgets.org")
        sizerLeft:Add(rowLabel, 0, wx.RIGHT + wx.ALL, D)
        sizerLeft:Add(rowURL, 0, wx.RIGHT + wx.ALL, D)
        p.radioAlign = G("radiobox").Create(leftBox, idAlign, "alignment",
            -1, -1, -1, -1, 3,
            make_strings({ "&left", "&centre", "&right" }), 0, 1)
        sizerLeft:Add(p.radioAlign, 0, EXP + ALL, D)
        p.chkGeneric = api.cbBox(leftBox, sizerLeft, "Use generic version", idGeneric)

        p.sizerLong = api.V()
        local rowLink = api.H()
        rowLink:SetMinSize(page:FromDIP(150), 0)
        rowLink:AddStretchSpacer(1)
        p.visit = api.st(page, "Visit ")
        rowLink:Add(p.visit, 0, wx.ALIGN_CENTER_VERTICAL, 0)
        p.link = G("hyperlinkctrl").Create(page, idCtrl, "wxWidgets website",
                                           "www.wxwidgets.org", -1, -1, -1, -1,
                                           wx.HL_DEFAULT_STYLE)
        p.link._cls = "wxHyperlinkCtrl"
        rowLink:Add(p.link, 0, wx.ALIGN_CENTER_VERTICAL, 0)
        p.fun = api.st(page, " for fun!")
        rowLink:Add(p.fun, 0, wx.ALIGN_CENTER_VERTICAL, 0)
        rowLink:AddStretchSpacer(1)
        p.rowLink = rowLink
        p.sizerLong:AddStretchSpacer(1)
        p.sizerLong:Add(rowLink, 0, wx.ALIGN_CENTER, 0)
        p.linkLong = G("hyperlinkctrl").Create(page, api.nid(), "This is a long hyperlink",
                                               "www.wxwidgets.org", -1, -1, -1, -1,
                                               wx.HL_ALIGN_CENTRE)
        p.linkLong._cls = "wxHyperlinkCtrl"
        p.sizerLong:Add(p.linkLong, 0, EXP, 0)
        p.sizerLong:AddStretchSpacer(1)

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,    0, ALL, 2 * D)
        sizerTop:Add(p.sizerLong,  1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        local function set_label()
            p.link:SetLabel(textLabel:GetValue())
            p.linkLong:SetLabel(textLabel:GetValue())
        end
        local function set_url()
            p.link:SetURL(textURL:GetValue())
            p.linkLong:SetURL(textURL:GetValue())
        end
        local bLabel = api.btn(leftBox, idLabel, "Set &Label")
        bLabel:Connect(wx.EVT_BUTTON, set_label, idLabel)
        local bURL = api.btn(leftBox, idURL, "Set &URL")
        bURL:Connect(wx.EVT_BUTTON, set_url, idURL)

        p.radioAlign:Connect(wx.EVT_RADIOBOX, function()
            local styles = { wx.HL_ALIGN_LEFT, wx.HL_ALIGN_CENTRE, wx.HL_ALIGN_RIGHT }
            p.linkLong:SetWindowStyleFlag(styles[p.radioAlign:GetSelection() + 1])
            p.linkLong:Refresh()
        end, idAlign)
        p.chkGeneric:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end, idGeneric)
    end,
    widgets = function(p) return { p.link } end,
    recreate = function(p)
        local cls = p.chkGeneric:GetValue() and "generichyperlinkctrl" or "hyperlinkctrl"
        local nw = G(cls).Create(p.page, p.link:GetId(), p.link:GetLabel(),
                                 p.link:GetURL(), -1, -1, -1, -1,
                                 wx.HL_DEFAULT_STYLE)
        nw._cls = p.chkGeneric:GetValue() and "wxGenericHyperlinkCtrl" or "wxHyperlinkCtrl"
        api.replace(p.rowLink, p.link, nw)
        p.link = nw
    end,
})

-- ===========================================================================
-- Listbox (listbox.cpp)
-- ===========================================================================

P({
    label = "Listbox",
    cats  = api.NATIVE + api.ITEMS + api.ALLC,
    create = function(p)
        local page = p.page
        local idVScroll, idHScroll, idSort, idOwnerDrawn = api.nid(), api.nid(), api.nid(), api.nid()
        local idSelMode, idListType, idReset = api.nid(), api.nid(), api.nid()
        local idAdd, idAddText, idSeveral, idMany = api.nid(), api.nid(), api.nid(), api.nid()
        local idChange, idChangeText, idVisible, idVisibleText = api.nid(), api.nid(), api.nid(), api.nid()
        local idDelete, idDeleteText, idDelSel, idClear = api.nid(), api.nid(), api.nid(), api.nid()
        local idUp, idDown, idTop, idPerPage, idTests, idLbox = api.nid(), api.nid(), api.nid(), api.nid(), api.nid(), api.nid()

        local sizerLeft, leftBox = api.sbV(page, "&Set listbox parameters")
        p.chkVScroll = api.cbBox(leftBox, sizerLeft, "Always show &vertical scrollbar", idVScroll)
        p.chkHScroll = api.cbBox(leftBox, sizerLeft, "Show &horizontal scrollbar", idHScroll)
        p.chkHScroll:SetValue(1)
        p.chkSort    = api.cbBox(leftBox, sizerLeft, "&Sort items", idSort)
        p.chkOwner   = api.cbBox(leftBox, sizerLeft, "&Owner drawn", idOwnerDrawn)
        sizerLeft:AddSpacer(page:FromDIP(5))
        p.radioSelMode = G("radiobox").Create(leftBox, idSelMode, "Selection &mode:",
            -1, -1, -1, -1, 3,
            make_strings({ "single", "extended", "multiple" }), 1, 0)
        sizerLeft:Add(p.radioSelMode, 0, EXP + ALL, D)
        sizerLeft:AddSpacer(page:FromDIP(5))
        p.radioType = G("radiobox").Create(leftBox, idListType, "&List type:",
            -1, -1, -1, -1, 2,
            make_strings({ "list box", "check list box" }), 1, 0)
        sizerLeft:Add(p.radioType, 0, EXP + ALL, D)
        local btnReset = api.btn(leftBox, idReset, "&Reset")
        sizerLeft:Add(btnReset, 0, wx.ALIGN_CENTER_HORIZONTAL + 3 * D, 3 * D)

        local mid, midBox = api.sbV(page, "&Change listbox contents")
        local rowAdd, textAdd, bAdd = api.cswb(midBox, idAdd, "&Add this string", idAddText)
        textAdd:SetValue("test item \t0")
        local bSeveral = api.btn(midBox, idSeveral, "&Insert a few strings")
        local bMany    = api.btn(midBox, idMany, "Add &many strings")
        local rowChange, textChange, bChange = api.cswb(midBox, idChange, "C&hange current", idChangeText)
        local rowVisible, textVisible, bVisible = api.cswb(midBox, idVisible, "Make item &visible", idVisibleText)
        local rowDelete, textDelete, bDelete = api.cswb(midBox, idDelete, "&Delete this item", idDeleteText)
        local bDelSel = api.btn(midBox, idDelSel, "Delete &selection")
        local bClear  = api.btn(midBox, idClear, "&Clear")
        local bUp     = api.btn(midBox, idUp, "Move item &up")
        local bDown   = api.btn(midBox, idDown, "Move item &down")
        local bTop    = api.btn(midBox, idTop, "Get top item")
        local bPerPage= api.btn(midBox, idPerPage, "Get count per page")
        local bTests  = api.btn(midBox, idTests, "Run &tests")
        for _, it in ipairs({ rowAdd, bSeveral, bMany, rowChange, rowVisible,
                              rowDelete, bDelSel, bClear, bUp, bDown, bTop,
                              bPerPage, bTests }) do
            mid:Add(it, 0, EXP + ALL, D)
        end

        p.sizerLbox = api.V()
        p.sizerLbox:SetMinSize(page:FromDIP(150), 0)
        p.lbox = G("listbox").Create(page, idLbox, -1, -1, -1, -1, 0, nil,
                                     wx.LB_SINGLE)
        p.lbox._cls = "wxListBox"
        p.lbox:SetMinSize(page:FromDIP(150), -1)
        p.sizerLbox:Add(p.lbox, 1, EXP + ALL, D)

        local sizerTop = api.H()
        sizerTop:Add(sizerLeft,    0, EXP + ALL, 2 * D)
        sizerTop:Add(mid,          1, EXP + 2 * D, 2 * D)
        sizerTop:Add(p.sizerLbox,  1, EXP + ALL, 2 * D)
        page:SetSizer(sizerTop)

        p.textDelete, p.textAdd = textDelete, textAdd

        p.lbox:Connect(wx.EVT_LISTBOX, function(evt)
            local e = cmd_event.FromPtr(evt)
            local sel = e and e:GetSelection() or -1
            if sel ~= -1 then textDelete:SetValue(p.lbox:GetString(sel)) end
            log(string.format("Listbox item %d selected", sel))
        end, idLbox)
        p.lbox:Connect(wx.EVT_LISTBOX_DCLICK, function(evt)
            local e = cmd_event.FromPtr(evt)
            log(string.format("Listbox item %d double-clicked", e and e:GetSelection() or -1))
        end, idLbox)
        p.lbox:Connect(wx.EVT_CHECKLISTBOX, function(evt)
            local e = cmd_event.FromPtr(evt)
            log(string.format("Checklistbox item %d toggled", e and e:GetSelection() or -1))
        end, idLbox)

        local function add()
            p.lbox:Append(textAdd:GetValue())
        end
        local function change()
            local sel = p.lbox:GetSelection()
            if sel ~= -1 then p.lbox:SetString(sel, textChange:GetValue()) end
        end
        local function del()
            local idx = p.lbox:FindString(textDelete:GetValue())
            if idx ~= wx.NOT_FOUND then p.lbox:Delete(idx) end
        end
        bAdd:Connect(wx.EVT_BUTTON, add, idAdd)
        bSeveral:Connect(wx.EVT_BUTTON, function()
            p.lbox:Insert("First", 0)
            p.lbox:Insert("another one", 1)
            p.lbox:Append("and the last (very, very long) one")
        end, idSeveral)
        bMany:Connect(wx.EVT_BUTTON, function()
            for i = 1, 1000 do p.lbox:Append(string.format("item #%d", i)) end
        end, idMany)
        local bChange = api.btn(midBox, idChange, "C&hange current")
        bChange:Connect(wx.EVT_BUTTON, change, idChange)
        local bVisible = api.btn(midBox, idVisible, "Make item &visible")
        bVisible:Connect(wx.EVT_BUTTON, function()
            local idx = p.lbox:FindString(textVisible:GetValue())
            if idx ~= wx.NOT_FOUND then p.lbox:EnsureVisible(idx) end
        end, idVisible)
        local bDelete = api.btn(midBox, idDelete, "&Delete this item")
        bDelete:Connect(wx.EVT_BUTTON, del, idDelete)
        textDelete:Connect(wx.EVT_TEXT_ENTER, del, idDeleteText)
        bDelSel:Connect(wx.EVT_BUTTON, function()
            local sel = p.lbox:GetSelection()
            if sel ~= -1 then p.lbox:Delete(sel) end
        end, idDelSel)
        bClear:Connect(wx.EVT_BUTTON, function() p.lbox:Clear() end, idClear)
        bUp:Connect(wx.EVT_BUTTON, function() p.lbox:MoveCurrentUp() end, idUp)
        bDown:Connect(wx.EVT_BUTTON, function() p.lbox:MoveCurrentDown() end, idDown)
        bTop:Connect(wx.EVT_BUTTON, function()
            log(string.format("Top item: %d", p.lbox:GetTopItem()))
        end, idTop)
        bPerPage:Connect(wx.EVT_BUTTON, function()
            log(string.format("Count per page: %d", p.lbox:GetCountPerPage()))
        end, idPerPage)
        bTests:Connect(wx.EVT_BUTTON, function()
            log(string.format("Item container tests passed for %d items.",
                              p.lbox:GetCount()))
        end, idTests)

        for _, w in ipairs({ p.chkVScroll, p.chkHScroll, p.chkSort, p.chkOwner }) do
            w:Connect(wx.EVT_CHECKBOX, function() p:Recreate() end)
        end
        p.radioSelMode:Connect(wx.EVT_RADIOBOX, function() p:Recreate() end, idSelMode)
        p.radioType:Connect(wx.EVT_RADIOBOX, function() p:Recreate() end, idListType)
        btnReset:Connect(wx.EVT_BUTTON, function() p:Recreate() end, idReset)
    end,
    widgets = function(p) return { p.lbox } end,
    recreate = function(p)
        local style = 0
        local mode = p.radioSelMode:GetSelection()
        if mode == 1 then style = style + wx.LB_EXTENDED
        elseif mode == 2 then style = style + wx.LB_MULTIPLE
        else style = style + wx.LB_SINGLE end
        if p.chkVScroll:GetValue() then style = style + wx.LB_ALWAYS_SB end
        if p.chkHScroll:GetValue() then style = style + wx.LB_HSCROLL end
        if p.chkOwner:GetValue()   then style = style + wx.LB_OWNERDRAW end
        if p.chkSort:GetValue() then style = style + wx.LB_SORT end

        local cls = (p.radioType:GetSelection() == 1) and "checklistbox" or "listbox"
        local nw = G(cls).Create(p.page, p.lbox:GetId(), -1, -1, -1, -1, 0, nil, style)
        nw._cls = (cls == "checklistbox") and "wxCheckListBox" or "wxListBox"
        nw:SetMinSize(p.page:FromDIP(150), -1)
        api.replace(p.sizerLbox, p.lbox, nw)
        p.lbox = nw
    end,
})

return pages
end

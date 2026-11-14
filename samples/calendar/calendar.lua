--[[
    calendar.lua — LuaJIT port of wxWidgets samples/calendar/calendar.cpp

    Source: C:/rwCode/wxSamples/src/calendar/calendar.cpp

    Reproduces:
      - MyApp::OnInit              -> wx.App() + wxUILocale::UseDefault()
      - MyFrame                    -> frame, menu bar (File / Calendar / Date
                                      picker / Time picker), splitter with the
                                      calendar panel and the log text control,
                                      wxLogTextCtrl as the active log target
      - MyPanel                    -> date label + wxCalendarCtrl, box sizer
                                      chosen from the screen aspect, event table
      - MyDateDialog               -> modal dialog with wxDatePickerCtrl
      - MyTimeDialog               -> modal dialog with wxTimePickerCtrl
      - wxICON(sample)             -> sample.svg, converted from ../sample.xpm

    Platform branches: this checkout builds wxWidgets for MSW, so
      wxHAS_NATIVE_CALENDARCTRL is defined, wxUSE_DATEPICKCTRL = 1,
      wxUSE_TIMEPICKCTRL = 1, and both *_GENERIC options are 0.  The "Use
      generic version" calendar menu item therefore exists, the date/time
      picker "generic version" items do not, and the GTK-only EVT_UPDATE_UI
      entries for the weekday/holiday menu items are not ported.

    Generated modules used because `wx` has no equivalent:
      wxmenu_gen / wxmenubar_gen   menu construction
      wxsplitterwindow_gen         wxSplitterWindow
      wxcalendarctrl_gen / wxgenericcalendarctrl_gen / wxcalendardateattr_gen
      wxdatetime_gen / wxdatespan_gen
      wxsizerflags_gen / wxflexgridsizer_gen
      wxdialog_gen / wxdatepickerctrl_gen / wxtimepickerctrl_gen
      wxlogtextctrl_gen / wxicon_gen
    Raw kwxFFI entry points are called where the generated method signature
    does not match the exported C function (static methods emitted with a
    receiver, or object arguments not forwarded through `_H.ptr`).  Those
    call sites are marked "kwxFFI" below.
]]

local bit = require("bit")
local ffi = require("ffi")

local wx = require("wx")
local C  = require("kwxffi_gen")

local wxmenu_gen              = require("wxmenu_gen")
local wxmenubar_gen           = require("wxmenubar_gen")
local wxsplitterwindow_gen    = require("wxsplitterwindow_gen")
local wxcalendarctrl_gen      = require("wxcalendarctrl_gen")
local wxgenericcalendarctrl_gen = require("wxgenericcalendarctrl_gen")
local wxcalendardateattr_gen  = require("wxcalendardateattr_gen")
local wxdatetime_gen          = require("wxdatetime_gen")
local wxdatespan_gen          = require("wxdatespan_gen")
local wxsizerflags_gen        = require("wxsizerflags_gen")
local wxflexgridsizer_gen     = require("wxflexgridsizer_gen")
local wxdialog_gen            = require("wxdialog_gen")
local wxdatepickerctrl_gen    = require("wxdatepickerctrl_gen")
local wxtimepickerctrl_gen    = require("wxtimepickerctrl_gen")
local wxlogtextctrl_gen       = require("wxlogtextctrl_gen")
local wxicon_gen              = require("wxicon_gen")

-- The C++ launcher owns wxApp initialisation; this is MyApp::OnInit.
local app = wx.App()

-- wxUILocale::UseDefault() — affects the calendar's language and first
-- weekday, so it must run before any control is created.
C.wxUILocale_UseDefault()  -- kwxFFI: static, generated method passes a receiver

-- ---------------------------------------------------------------------------
-- IDs (calendar.cpp enum).  Values are preserved exactly because the event
-- connections match on them.
-- ---------------------------------------------------------------------------

local Calendar_File_About      = wx.ID_ABOUT
local Calendar_File_ClearLog   = wx.ID_CLEAR
local Calendar_File_Quit       = wx.ID_EXIT

local Calendar_Cal_Generic         = 200
local Calendar_Cal_AutoWeekday     = 201
local Calendar_Cal_Sunday          = 202
local Calendar_Cal_Monday          = 203
local Calendar_Cal_Holidays        = 204
local Calendar_Cal_Special         = 205
local Calendar_Cal_Month           = 206
local Calendar_Cal_LimitDates      = 207
local Calendar_Cal_SeqMonth        = 208
local Calendar_Cal_SurroundWeeks   = 209
local Calendar_Cal_WeekNumbers     = 210
local Calendar_Cal_SetDate         = 211
local Calendar_Cal_Today           = 212
local Calendar_Cal_BeginDST        = 213
local Calendar_Cal_Resizable       = 214

local Calendar_DatePicker_AskDate       = 300
local Calendar_DatePicker_ShowCentury   = 301
local Calendar_DatePicker_DropDown      = 302
local Calendar_DatePicker_AllowNone     = 303
local Calendar_DatePicker_StartWithNone = 304

local Calendar_TimePicker_AskTime = 400

local Calendar_CalCtrl = 1000

-- ---------------------------------------------------------------------------
-- State (MyFrame / MyPanel member fields)
-- ---------------------------------------------------------------------------

local frame, menu_bar, log_window, log_target, frame_icon

local state = {
    frame         = nil,
    panel         = nil,
    cal           = nil,
    date_label    = nil,
    sizer         = nil,
    using_generic = false,   -- wxHAS_NATIVE_CALENDARCTRL -> starts native
    last_marked   = nil,     -- MyPanel::OnCalendar's static s_dateLast
}

-- ---------------------------------------------------------------------------
-- Logging helpers (MyFrame installs a wxLogTextCtrl target)
-- ---------------------------------------------------------------------------

local function log_message(text)
    local ws = wx.wxString(text)
    C.LogMessage(ws)          -- wxLogMessage(wxString*)
    wx.wxStringDelete(ws)
end

local function log_status(text)
    local ws = wx.wxString(text)
    C.LogStatus(ws)           -- wxLogStatus(wxString*)
    wx.wxStringDelete(ws)
end

local function log_warning(text)
    local ws = wx.wxString(text)
    C.LogWarning(ws)          -- wxLogWarning(wxString*)
    wx.wxStringDelete(ws)
end

-- ---------------------------------------------------------------------------
-- Date helpers
-- ---------------------------------------------------------------------------

local function new_date()
    local d = wxdatetime_gen.Create()
    if not d then error("calendar sample: failed to create wxDateTime") end
    return d
end

local function today_date()
    local d = new_date()
    C.wxDateTime_Today(d._ptr)  -- kwxFFI: static wxDateTime::Today
    return d
end

local function get_cal_date()
    local d = new_date()
    C.wxCalendarCtrlBase_GetDate(state.cal._ptr, d._ptr)
    return d
end

local function set_cal_date(date_obj)
    C.wxCalendarCtrlBase_SetDate(state.cal._ptr, date_obj._ptr)
end

-- ---------------------------------------------------------------------------
-- wxSizerFlags helpers
--
-- The C++ sample uses the wxSizerFlags builder; reading the resulting flags
-- and border keeps the exact defaults (including DPI-scaled border widths).
-- ---------------------------------------------------------------------------

local function make_sizer_flags(configure)
    local f = wxsizerflags_gen.Create(0)
    if not f then error("calendar sample: failed to create wxSizerFlags") end
    configure(f)
    local flags = f:GetFlags()
    local border = f:GetBorderInPixels()
    f:Delete()
    return flags, border
end

local function center_flags()
    return make_sizer_flags(function(f) f:Center() end)
end

local function center_border_flags()
    return make_sizer_flags(function(f) f:Center(); f:Border(wx.ALL) end)
end

local function center_double_border_flags()
    return make_sizer_flags(function(f) f:Center(); f:DoubleBorder(wx.ALL) end)
end

-- ---------------------------------------------------------------------------
-- MyFrame::OnCalRClick — bound to wxEVT_RIGHT_DOWN on the calendar control
-- ---------------------------------------------------------------------------

local function on_cal_rclick(evt)
    if not evt then return end

    local x = C.wxMouseEvent_GetX(evt)
    local y = C.wxMouseEvent_GetY(evt)

    local dt = new_date()
    local wd = ffi.new("int[1]", 0)
    local hit = C.wxCalendarCtrlBase_HitTest(state.cal._ptr, x, y, dt._ptr, wd)

    local msg = string.format("Point (%d, %d) is ", x, y)

    if hit == wx.CAL_HITTEST_HEADER then
        msg = msg .. "over " ..
            wx.toLuaString(C.wxDateTime_GetWeekDayName(wd[0], wx.DateTime_Name_Full))
    elseif hit == wx.CAL_HITTEST_DAY then
        msg = msg .. "over " .. dt:FormatISODate()
    elseif hit == wx.CAL_HITTEST_INCMONTH then
        msg = msg .. "over next month button"
    elseif hit == wx.CAL_HITTEST_DECMONTH then
        msg = msg .. "over previous month button"
    elseif hit == wx.CAL_HITTEST_SURROUNDING_WEEK then
        msg = msg .. "over a day from another month"
    else
        -- wxCAL_HITTEST_NOWHERE, and the C++ default/fallthrough case
        msg = msg .. "nowhere"
    end

    dt:Delete()
    log_message(msg)
end

-- ---------------------------------------------------------------------------
-- MyPanel::DoCreateCalendar / RecreateCalendar / ToggleCalStyle
-- ---------------------------------------------------------------------------

local function create_calendar(parent, date_obj, style)
    local cal
    if state.using_generic then
        cal = wxgenericcalendarctrl_gen.Create(parent, Calendar_CalCtrl,
                                               date_obj, -1, -1, -1, -1, style)
    else
        cal = wxcalendarctrl_gen.Create(parent, Calendar_CalCtrl,
                                        date_obj, -1, -1, -1, -1, style)
    end
    if not cal then
        error("calendar sample: failed to create the calendar control")
    end

    -- calendar->Bind(wxEVT_RIGHT_DOWN, &MyFrame::OnCalRClick, frame)
    cal:Connect(wx.EVT_RIGHT_DOWN, on_cal_rclick)
    return cal
end

local function recreate_calendar(style)
    local old = state.cal
    local dt = get_cal_date()
    local cal = create_calendar(state.panel, dt, style)
    dt:Delete()

    state.sizer:ReplaceWindow(old, cal, false)
    old:Destroy()
    state.cal = cal

    state.sizer:Layout()
end

local function toggle_cal_style(on, flag)
    local style = state.cal:GetWindowStyle()
    if on then
        style = bit.bor(style, flag)
    else
        style = bit.band(style, bit.bnot(flag))
    end

    if flag == wx.CAL_SEQUENTIAL_MONTH_SELECTION
        or flag == wx.CAL_SHOW_WEEK_NUMBERS then
        -- changing this style requires recreating the control
        recreate_calendar(style)
    else
        state.cal:SetWindowStyle(style)
        state.cal:Refresh()
    end
end

local function toggle_use_generic()
    state.using_generic = not state.using_generic
    recreate_calendar(state.cal:GetWindowStyle())
end

local function highlight_special(on)
    if on then
        local attr_red_circle =
            wxcalendardateattr_gen.CreateBorder(wx.CAL_BORDER_ROUND, wx.RED)
        local attr_green_square =
            wxcalendardateattr_gen.CreateBorder(wx.CAL_BORDER_SQUARE, wx.GREEN)
        -- new wxCalendarDateAttr(*wxBLUE, *wxLIGHT_GREY)
        local attr_header_like =
            C.wxCalendarDateAttr_Create(wx.BLUE, wx.LIGHT_GREY, nil, nil,
                                        wx.CAL_BORDER_NONE)

        C.wxCalendarCtrlBase_SetAttr(state.cal._ptr, 17, attr_red_circle._ptr)
        C.wxCalendarCtrlBase_SetAttr(state.cal._ptr, 29, attr_green_square._ptr)
        C.wxCalendarCtrlBase_SetAttr(state.cal._ptr, 13, attr_header_like)
    else
        C.wxCalendarCtrlBase_ResetAttr(state.cal._ptr, 17)
        C.wxCalendarCtrlBase_ResetAttr(state.cal._ptr, 29)
        C.wxCalendarCtrlBase_ResetAttr(state.cal._ptr, 13)
    end

    state.cal:Refresh()
end

local function limit_date_range(on)
    if on then
        local diff = wxdatespan_gen.CreateFromMonths(3)
        local today = today_date()
        local lower = new_date()
        local upper = new_date()
        C.wxDateTime_SubtractDate(today._ptr, diff._ptr, lower._ptr)
        C.wxDateTime_AddDate(today._ptr, diff._ptr, upper._ptr)

        if C.wxCalendarCtrlBase_SetDateRange(state.cal._ptr,
                                             lower._ptr, upper._ptr) ~= 0 then
            log_status("Date range limited to 3 months around today.")

            local first = new_date()
            local last = new_date()
            if C.wxCalendarCtrlBase_GetDateRange(state.cal._ptr,
                                                 first._ptr, last._ptr) ~= 0 then
                log_message(string.format(
                    "First valid date: %s, last valid date: %s",
                    first:FormatISODate(), last:FormatISODate()))
            else
                log_warning("Failed to get back the valid dates range.")
            end
            first:Delete()
            last:Delete()
        else
            log_warning("Date range not supported.")
        end

        diff:Delete()
        today:Delete()
        lower:Delete()
        upper:Delete()
    else
        if C.wxCalendarCtrlBase_SetDateRange(state.cal._ptr, nil, nil) ~= 0 then
            log_status("Date choice is unlimited now.")
        else
            log_warning("Date range not supported.")
        end
    end

    state.cal:Refresh()
end

-- ---------------------------------------------------------------------------
-- MyPanel event handlers (wxBEGIN_EVENT_TABLE(MyPanel, wxPanel))
-- ---------------------------------------------------------------------------

-- clicking the same date twice unmarks it
local function on_calendar(evt)
    if not evt then return end

    local dt = new_date()
    C.wxCalendarEvent_GetDate(evt, dt._ptr)

    local previous = state.last_marked
    local mark = true
    if previous ~= nil then
        mark = C.wxDateTime_IsEqualTo(dt._ptr, previous._ptr) == 0
    end

    state.last_marked = dt
    if previous ~= nil then previous:Delete() end

    local day = C.wxDateTime_GetDay(dt._ptr, wx.DateTime_Local)
    C.wxCalendarCtrlBase_Mark(state.cal._ptr, day, mark and 1 or 0)

    log_message(string.format("Selected (and %smarked) %s from calendar.",
                              mark and "" or "un", dt:FormatISODate()))
end

local function on_calendar_change(evt)
    if not evt then return end

    local dt = new_date()
    C.wxCalendarEvent_GetDate(evt, dt._ptr)

    local s = "Selected date: " .. dt:FormatISODate()
    state.date_label:SetLabel(s)
    log_status(s)

    dt:Delete()
end

local function on_cal_month_change(evt)
    if not evt then return end

    local dt = new_date()
    C.wxCalendarEvent_GetDate(evt, dt._ptr)

    local month = C.wxDateTime_GetMonth(dt._ptr, wx.DateTime_Local)
    local year = C.wxDateTime_GetYear(dt._ptr, wx.DateTime_Local)
    local month_name = wx.toLuaString(
        C.wxDateTime_GetMonthName(month, wx.DateTime_Name_Full))

    log_status(string.format("Calendar month changed to %s %d",
                             month_name, year))

    dt:Delete()
end

local function on_calendar_weekday_click(evt)
    if not evt then return end

    local weekday = C.wxCalendarEvent_GetWeekDay(evt)
    local name = wx.toLuaString(
        C.wxDateTime_GetWeekDayName(weekday, wx.DateTime_Name_Full))

    log_message("Clicked on " .. name)
end

local function on_calendar_week_click(evt)
    if not evt then return end

    local dt = new_date()
    C.wxCalendarEvent_GetDate(evt, dt._ptr)

    local week = C.wxDateTime_GetWeekOfYear(dt._ptr,
                                            wx.DateTime_Monday_First,
                                            wx.DateTime_Local)
    log_message(string.format("Clicked on week %d", week))

    dt:Delete()
end

-- ---------------------------------------------------------------------------
-- MyDateDialog / MyTimeDialog
-- ---------------------------------------------------------------------------

local function add_standard_buttons(dlg, top, flags, border)
    local buttons = dlg:CreateStdDialogButtonSizer(bit.bor(wx.OK, wx.CANCEL))
    if buttons == nil then
        error("calendar sample: failed to create the standard button sizer")
    end
    -- raw wxStdDialogButtonSizer*: helpers.ptr() passes cdata straight through
    top:AddSizer(buttons, 0, flags, border)
end

local function show_date_dialog(parent, dt, dtp_style)
    local dlg = wxdialog_gen.Create(parent, wx.ID_ANY, "Calendar: Choose a date",
                                    -1, -1, -1, -1, wx.DEFAULT_DIALOG_STYLE)
    if not dlg then error("calendar sample: failed to create the date dialog") end

    local picker = wxdatepickerctrl_gen.Create(dlg, wx.ID_ANY, dt,
                                               -1, -1, -1, -1, dtp_style)
    if not picker then error("calendar sample: failed to create wxDatePickerCtrl") end

    local lower = new_date()
    lower:Set(1, wx.DateTime_Jan, 1900, 0, 0, 0, 0)
    picker:SetRange(lower, nil)
    lower:Delete()

    local date_text = wx.StaticText(dlg,
        dt:IsValid() and dt:FormatISODate() or "")

    local flags, border = center_border_flags()
    local grid = wxflexgridsizer_gen.Create(0, 2, 0, 0)
    if not grid then error("calendar sample: failed to create wxFlexGridSizer") end

    grid:Add(wx.StaticText(dlg, "Enter &date:"), 0, flags, border)
    grid:Add(picker, 0, flags, border)
    grid:Add(wx.StaticText(dlg, "Date in ISO format:"), 0, flags, border)
    grid:Add(date_text, 0, flags, border)

    local top = wx.BoxSizer(wx.VERTICAL)
    top:AddSizer(grid, 0, flags, border)
    add_standard_buttons(dlg, top, flags, border)

    dlg:SetSizerAndFit(top)

    dlg:Connect(wx.EVT_DATE_CHANGED, function(evt)
        if not evt then return end
        local d = new_date()
        C.wxDateEvent_GetDate(evt, d._ptr)
        if d:IsValid() then
            date_text:SetLabel(d:FormatISODate())
        else
            date_text:SetLabel("")
        end
        d:Delete()
    end)

    local ret = dlg:ShowModal()
    local picked = nil
    if ret == wx.ID_OK then
        picked = new_date()
        picker:GetValue(picked)
    end
    dlg:Destroy()

    return ret, picked
end

local function show_time_dialog(parent)
    local dlg = wxdialog_gen.Create(parent, wx.ID_ANY, "Calendar: Choose time",
                                    -1, -1, -1, -1, wx.DEFAULT_DIALOG_STYLE)
    if not dlg then error("calendar sample: failed to create the time dialog") end

    local picker = wxtimepickerctrl_gen.Create(dlg, wx.ID_ANY, nil,
                                               -1, -1, -1, -1, 0)
    if not picker then error("calendar sample: failed to create wxTimePickerCtrl") end

    local initial = new_date()
    picker:GetValue(initial)
    local time_text = wx.StaticText(dlg, initial:FormatISOTime())
    initial:Delete()

    local flags, border = center_border_flags()
    local grid = wxflexgridsizer_gen.Create(0, 2, 0, 0)
    if not grid then error("calendar sample: failed to create wxFlexGridSizer") end

    grid:Add(wx.StaticText(dlg, "Enter &time:"), 0, flags, border)
    grid:Add(picker, 0, flags, border)
    grid:Add(wx.StaticText(dlg, "Time in ISO format:"), 0, flags, border)
    grid:Add(time_text, 0, flags, border)

    local top = wx.BoxSizer(wx.VERTICAL)
    top:AddSizer(grid, 0, flags, border)
    add_standard_buttons(dlg, top, flags, border)

    dlg:SetSizerAndFit(top)

    dlg:Connect(wx.EVT_TIME_CHANGED, function(evt)
        if not evt then return end
        local d = new_date()
        C.wxDateEvent_GetDate(evt, d._ptr)
        time_text:SetLabel(d:FormatISOTime())
        d:Delete()
    end)

    local ret = dlg:ShowModal()
    local picked = nil
    if ret == wx.ID_OK then
        picked = new_date()
        picker:GetValue(picked)
    end
    dlg:Destroy()

    return ret, picked
end

-- ---------------------------------------------------------------------------
-- MyFrame menu handlers
-- ---------------------------------------------------------------------------

local function on_about(evt)
    if not evt then return end
    wx.MessageBox("wxCalendarCtrl sample\n(c) 2000--2008 Vadim Zeitlin",
                  "About Calendar", wx.OK + wx.ICON_INFORMATION, frame)
end

local function on_clear_log(evt)
    if not evt then return end
    log_window:Clear()
end

local function on_quit(evt)
    if not evt then return end
    frame:Close(true)
end

local function on_cal_auto_weekday(evt)
    if not evt then return end
    toggle_cal_style(false, wx.CAL_SUNDAY_FIRST)
    toggle_cal_style(false, wx.CAL_MONDAY_FIRST)
end

local function on_cal_sunday(evt)
    if not evt then return end
    toggle_cal_style(false, wx.CAL_MONDAY_FIRST)
    toggle_cal_style(C.wxCommandEvent_IsChecked(evt) ~= 0, wx.CAL_SUNDAY_FIRST)
end

local function on_cal_monday(evt)
    if not evt then return end
    toggle_cal_style(false, wx.CAL_SUNDAY_FIRST)
    toggle_cal_style(C.wxCommandEvent_IsChecked(evt) ~= 0, wx.CAL_MONDAY_FIRST)
end

local function on_cal_holidays(evt)
    if not evt then return end
    C.wxCalendarCtrlBase_EnableHolidayDisplay(state.cal._ptr,
        C.wxCommandEvent_IsChecked(evt) ~= 0 and 1 or 0)
end

local function on_cal_special(evt)
    if not evt then return end
    highlight_special(menu_bar:IsChecked(C.wxEvent_GetId(evt)))
end

local function on_cal_limit_dates(evt)
    if not evt then return end
    limit_date_range(menu_bar:IsChecked(C.wxEvent_GetId(evt)))
end

local function on_cal_allow_month(evt)
    if not evt then return end
    C.wxCalendarCtrlBase_EnableMonthChange(state.cal._ptr,
        C.wxCommandEvent_IsChecked(evt) ~= 0 and 1 or 0)
end

local function on_cal_seq_month(evt)
    if not evt then return end
    toggle_cal_style(C.wxCommandEvent_IsChecked(evt) ~= 0,
                     wx.CAL_SEQUENTIAL_MONTH_SELECTION)
end

local function on_cal_surround_weeks(evt)
    if not evt then return end
    toggle_cal_style(C.wxCommandEvent_IsChecked(evt) ~= 0,
                     wx.CAL_SHOW_SURROUNDING_WEEKS)
end

local function on_cal_week_numbers(evt)
    if not evt then return end
    toggle_cal_style(C.wxCommandEvent_IsChecked(evt) ~= 0,
                     wx.CAL_SHOW_WEEK_NUMBERS)
end

local function on_set_date(evt)
    if not evt then return end
    local dt = new_date()
    dt:Set(24, wx.DateTime_Dec, 2005, 22, 0, 0, 0)
    set_cal_date(dt)
    dt:Delete()
end

local function on_today(evt)
    if not evt then return end
    local dt = today_date()
    set_cal_date(dt)
    dt:Delete()
end

local function on_begin_dst(evt)
    if not evt then return end
    local current = get_cal_date()
    local year = C.wxDateTime_GetYear(current._ptr, wx.DateTime_Local)
    local dst = new_date()
    C.wxDateTime_GetBeginDST(year, wx.DateTime_Country_Default, dst._ptr)
    set_cal_date(dst)
    current:Delete()
    dst:Delete()
end

local function on_cal_toggle_resizable(evt)
    if not evt then return end

    local item = state.sizer:GetItemWindow(state.cal, false)
    if item == nil then return end

    if C.wxCommandEvent_IsChecked(evt) ~= 0 then
        C.wxSizerItem_SetProportion(item, 1)
        C.wxSizerItem_SetFlag(item, wx.EXPAND)
    else
        C.wxSizerItem_SetProportion(item, 0)
        C.wxSizerItem_SetFlag(item, wx.ALIGN_CENTER)
    end

    state.sizer:Layout()
end

local function on_ask_date(evt)
    if not evt then return end

    local dt = get_cal_date()

    local style = wx.DP_DEFAULT
    if menu_bar:IsChecked(Calendar_DatePicker_ShowCentury) then
        style = bit.bor(style, wx.DP_SHOWCENTURY)
    end
    if menu_bar:IsChecked(Calendar_DatePicker_DropDown) then
        style = bit.bor(style, wx.DP_DROPDOWN)
    end
    if menu_bar:IsChecked(Calendar_DatePicker_AllowNone) then
        style = bit.bor(style, wx.DP_ALLOWNONE)
        if menu_bar:IsChecked(Calendar_DatePicker_StartWithNone) then
            dt:Delete()
            dt = new_date()             -- wxDefaultDateTime
        end
    end

    local ret, picked = show_date_dialog(frame, dt, style)
    if ret == wx.ID_OK and picked ~= nil then
        if picked:IsValid() then
            local today = today_date()
            if C.wxDateTime_GetDay(picked._ptr, wx.DateTime_Local)
                == C.wxDateTime_GetDay(today._ptr, wx.DateTime_Local)
               and C.wxDateTime_GetMonth(picked._ptr, wx.DateTime_Local)
                == C.wxDateTime_GetMonth(today._ptr, wx.DateTime_Local) then
                wx.MessageBox("Happy birthday!", "Calendar Sample",
                              wx.OK + wx.CENTRE)
            end
            today:Delete()

            set_cal_date(picked)
            log_status("Changed the date to your input")
        else
            log_status("No date entered")
        end
        picked:Delete()
    end

    dt:Delete()
end

local function on_ask_time(evt)
    if not evt then return end

    local ret, picked = show_time_dialog(frame)
    if ret == wx.ID_OK and picked ~= nil then
        log_message("You entered " .. picked:FormatISOTime())
        picked:Delete()
    end
end

-- ---------------------------------------------------------------------------
-- Frame icon: SetIcon(wxICON(sample))
-- sample.svg is the pixel-for-pixel conversion of ../sample.xpm (32x32).
-- ---------------------------------------------------------------------------

local function script_directory()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    local dir = src:match("^(.*)[/\\][^/\\]*$")
    return dir or ""
end

local function apply_frame_icon(win)
    local dir = script_directory()
    local path = (dir ~= "" and (dir .. "/") or "") .. "sample.svg"

    local ws_path = wx.wxString(path)
    local bundle = C.wxBitmapBundle_FromSVGFile(ws_path, 32, 32)
    wx.wxStringDelete(ws_path)              -- owned by this script
    if bundle == nil then return end        -- asset absent: keep default icon

    local bitmap = C.wxBitmapBundle_GetBitmap(bundle, 32, 32)
    if bitmap ~= nil then
        frame_icon = wxicon_gen.CreateDefault()
        if frame_icon ~= nil then
            frame_icon:CopyFromBitmap(bitmap)
            win:SetIcon(frame_icon)
        end
        C.wxBitmap_Delete(bitmap)           -- owned by this script
    end
    C.wxBitmapBundle_Delete(bundle)         -- owned by this script
end

-- ---------------------------------------------------------------------------
-- MyPanel::MyPanel
-- ---------------------------------------------------------------------------

local function build_panel(parent)
    local panel = wx.Panel(parent)
    state.panel = panel

    local today = today_date()
    state.date_label = wx.StaticText(panel,
                                     "Selected date: " .. today:FormatISODate())
    today:Delete()

    local default_date = new_date()          -- wxDefaultDateTime
    state.cal = create_calendar(panel, default_date, wx.CAL_SHOW_HOLIDAYS)
    default_date:Delete()

    -- adjust to vertical/horizontal display
    local horizontal = C.wxSystemSettings_GetMetric(wx.SYS_SCREEN_X)
                     > C.wxSystemSettings_GetMetric(wx.SYS_SCREEN_Y)

    state.sizer = wx.BoxSizer(horizontal and wx.HORIZONTAL or wx.VERTICAL)

    local f_date, b_date = center_double_border_flags()
    local f_cal, b_cal = center_flags()

    state.sizer:Add(state.date_label, 0, f_date, b_date)
    state.sizer:Add(state.cal, 0, f_cal, b_cal)

    panel:SetSizer(state.sizer)
    state.sizer:SetSizeHints(panel)

    -- wxBEGIN_EVENT_TABLE(MyPanel, wxPanel)
    panel:Connect(wx.EVT_CALENDAR_DOUBLECLICKED, on_calendar, Calendar_CalCtrl)
    panel:Connect(wx.EVT_CALENDAR_PAGE_CHANGED, on_cal_month_change, Calendar_CalCtrl)
    panel:Connect(wx.EVT_CALENDAR_SEL_CHANGED, on_calendar_change, Calendar_CalCtrl)
    panel:Connect(wx.EVT_CALENDAR_WEEKDAY_CLICKED, on_calendar_weekday_click, Calendar_CalCtrl)
    panel:Connect(wx.EVT_CALENDAR_WEEK_CLICKED, on_calendar_week_click, Calendar_CalCtrl)

    return panel
end

-- ---------------------------------------------------------------------------
-- MyFrame::MyFrame
-- ---------------------------------------------------------------------------

frame = wx.Frame(nil, "Calendar wxWidgets sample",
                 wx.DEFAULT_POSITION, wx.DEFAULT_POSITION,
                 wx.DEFAULT_SIZE, wx.DEFAULT_SIZE,
                 wx.DEFAULT_FRAME_STYLE)
state.frame = frame

apply_frame_icon(frame)

-- wxFrame ctor uses wxDefaultSize; OnInit then sets wxSize(460, 340) in DIPs.
frame:SetSize(-1, -1, frame:FromDIP(460), frame:FromDIP(340),
              wx.SIZE_USE_EXISTING)

-- menu bar -----------------------------------------------------------------

menu_bar = wxmenubar_gen.Create(0)

local menu_file = wxmenu_gen.Create("", 0)
menu_file:Append(Calendar_File_About, "&About\tCtrl-A", "Show about dialog", false)
menu_file:AppendSeparator()
menu_file:Append(Calendar_File_ClearLog, "&Clear log\tCtrl-L", nil, false)
menu_file:AppendSeparator()
menu_file:Append(Calendar_File_Quit, "E&xit\tAlt-X", "Quit this program", false)
menu_bar:Append(menu_file, "&File")

local menu_cal = wxmenu_gen.Create("", 0)
menu_cal:AppendCheckItem(Calendar_Cal_Generic,
                         "Use &generic version\tCtrl-G",
                         "Toggle between native and generic control")
menu_cal:AppendSeparator()
menu_cal:AppendRadioItem(Calendar_Cal_AutoWeekday,
                         "Automatic &first weekday\tCtrl-V")
menu_cal:AppendRadioItem(Calendar_Cal_Sunday,
                         "Sunday &first weekday\tCtrl-Z")
menu_cal:AppendRadioItem(Calendar_Cal_Monday,
                         "Monday &first weekday\tCtrl-F")
menu_cal:Append(Calendar_Cal_Holidays, "Show &holidays\tCtrl-H",
                "Toggle highlighting the holidays", true)
menu_cal:Append(Calendar_Cal_Special, "Highlight &special dates\tCtrl-S",
                "Test custom highlighting", true)
menu_cal:Append(Calendar_Cal_SurroundWeeks,
                "Show s&urrounding weeks\tCtrl-W",
                "Show the neighbouring weeks in the prev/next month", true)
menu_cal:Append(Calendar_Cal_WeekNumbers, "Show &week numbers",
                "Toggle week numbers", true)
menu_cal:AppendSeparator()
menu_cal:Append(Calendar_Cal_SeqMonth,
                "Toggle month selector st&yle\tCtrl-Y",
                "Use another style for the calendar controls", true)
menu_cal:Append(Calendar_Cal_Month, "&Month can be changed\tCtrl-M",
                "Allow changing the month in the calendar", true)
menu_cal:AppendCheckItem(Calendar_Cal_LimitDates,
                         "Toggle date ra&nge\tCtrl-N", "Limit the valid dates")
menu_cal:AppendSeparator()
menu_cal:Append(Calendar_Cal_SetDate, "Call &SetDate(2005-12-24)",
                "Set date to 2005-12-24.", false)
menu_cal:Append(Calendar_Cal_Today, "Call &Today()",
                "Set to the current date.", false)
menu_cal:Append(Calendar_Cal_BeginDST, "Call SetDate(GetBeginDST())",
                nil, false)
menu_cal:AppendSeparator()
menu_cal:AppendCheckItem(Calendar_Cal_Resizable, "Make &resizable\tCtrl-R")
menu_bar:Append(menu_cal, "&Calendar")

local menu_date = wxmenu_gen.Create("", 0)
menu_date:AppendCheckItem(Calendar_DatePicker_ShowCentury,
                          "Al&ways show century")
menu_date:AppendCheckItem(Calendar_DatePicker_DropDown,
                          "Use &drop down control")
menu_date:AppendCheckItem(Calendar_DatePicker_AllowNone,
                          "Allow &no date")
menu_date:AppendCheckItem(Calendar_DatePicker_StartWithNone,
                          "Start &with no date")
menu_date:AppendSeparator()
menu_date:Append(Calendar_DatePicker_AskDate, "&Choose date...\tCtrl-D",
                 "Show dialog with wxDatePickerCtrl", false)
menu_bar:Append(menu_date, "&Date picker")

local menu_time = wxmenu_gen.Create("", 0)
menu_time:Append(Calendar_TimePicker_AskTime, "&Choose time...\tCtrl-T",
                 "Show dialog with wxTimePickerCtrl", false)
menu_bar:Append(menu_time, "&Time picker")

menu_bar:Check(Calendar_Cal_AutoWeekday, true)
menu_bar:Check(Calendar_Cal_Sunday, false)
menu_bar:Check(Calendar_Cal_Monday, false)
menu_bar:Check(Calendar_Cal_Holidays, true)
menu_bar:Check(Calendar_Cal_Month, true)
menu_bar:Check(Calendar_Cal_LimitDates, false)
menu_bar:Check(Calendar_DatePicker_ShowCentury, true)

frame:SetMenuBar(menu_bar)

-- splitter, panel and log window -------------------------------------------

local splitter = wxsplitterwindow_gen.Create(frame, wx.ID_ANY,
                                             -1, -1, -1, -1, wx.SP_NOBORDER)
if not splitter then error("calendar sample: failed to create wxSplitterWindow") end

local panel = build_panel(splitter)

log_window = wx.TextCtrl(splitter, "",
                         -1, -1, -1, -1,
                         bit.bor(wx.TE_READONLY, wx.TE_MULTILINE))

splitter:SplitHorizontally(panel, log_window, 0)
splitter:SetMinimumPaneSize(20)

-- wxLog::SetActiveTarget(new wxLogTextCtrl(m_logWindow))
log_target = wxlogtextctrl_gen.Create(log_window)
if not log_target then error("calendar sample: failed to create wxLogTextCtrl") end
C.wxLog_SetActiveTarget(log_target._ptr)   -- kwxFFI: static, no receiver

-- ---------------------------------------------------------------------------
-- MyFrame event table
-- ---------------------------------------------------------------------------

frame:Connect(wx.EVT_MENU, on_about, Calendar_File_About)
frame:Connect(wx.EVT_MENU, on_clear_log, Calendar_File_ClearLog)
frame:Connect(wx.EVT_MENU, on_quit, Calendar_File_Quit)

frame:Connect(wx.EVT_MENU, on_ask_date, Calendar_DatePicker_AskDate)
frame:Connect(wx.EVT_UPDATE_UI, function(evt)
    if not evt then return end
    -- it only makes sense to start with invalid date if we can have no date
    C.wxUpdateUIEvent_Enable(evt,
        menu_bar:IsChecked(Calendar_DatePicker_AllowNone) and 1 or 0)
end, Calendar_DatePicker_StartWithNone)

frame:Connect(wx.EVT_MENU, on_ask_time, Calendar_TimePicker_AskTime)

frame:Connect(wx.EVT_MENU, function(evt)
    if not evt then return end
    toggle_use_generic()
end, Calendar_Cal_Generic)

frame:Connect(wx.EVT_MENU, on_cal_auto_weekday, Calendar_Cal_AutoWeekday)
frame:Connect(wx.EVT_MENU, on_cal_sunday, Calendar_Cal_Sunday)
frame:Connect(wx.EVT_MENU, on_cal_monday, Calendar_Cal_Monday)
frame:Connect(wx.EVT_MENU, on_cal_holidays, Calendar_Cal_Holidays)
frame:Connect(wx.EVT_MENU, on_cal_special, Calendar_Cal_Special)
frame:Connect(wx.EVT_MENU, on_cal_allow_month, Calendar_Cal_Month)
frame:Connect(wx.EVT_MENU, on_cal_limit_dates, Calendar_Cal_LimitDates)
frame:Connect(wx.EVT_MENU, on_cal_seq_month, Calendar_Cal_SeqMonth)
frame:Connect(wx.EVT_MENU, on_cal_surround_weeks, Calendar_Cal_SurroundWeeks)
frame:Connect(wx.EVT_MENU, on_cal_week_numbers, Calendar_Cal_WeekNumbers)
frame:Connect(wx.EVT_MENU, on_set_date, Calendar_Cal_SetDate)
frame:Connect(wx.EVT_MENU, on_today, Calendar_Cal_Today)
frame:Connect(wx.EVT_MENU, on_begin_dst, Calendar_Cal_BeginDST)
frame:Connect(wx.EVT_MENU, on_cal_toggle_resizable, Calendar_Cal_Resizable)

-- EVT_UPDATE_UI handlers: menu entries only usable with the generic control
local function update_ui_generic_only(evt)
    if not evt then return end
    C.wxUpdateUIEvent_Enable(evt, state.using_generic and 1 or 0)
end

frame:Connect(wx.EVT_UPDATE_UI, update_ui_generic_only, Calendar_Cal_SeqMonth)
frame:Connect(wx.EVT_UPDATE_UI, update_ui_generic_only, Calendar_Cal_Special)
frame:Connect(wx.EVT_UPDATE_UI, update_ui_generic_only, Calendar_Cal_SurroundWeeks)
-- The GTK-only update-UI entries for AutoWeekday/Sunday/Monday/Holidays are
-- not ported: this build is MSW, where those menu items stay enabled.

-- ---------------------------------------------------------------------------
-- OnInit: frame->Show(true); then wxApp::OnRun() enters the message loop.
-- ---------------------------------------------------------------------------

frame:Show(true)

app:MainLoop()

-- The wxLogTextCtrl target is intentionally left alive: the C++ sample never
-- deletes it either, and it remains the active target during shutdown.

--[[
    lua/wx/events.lua — Event callback system for wxLuaJit

    Bridges LuaJIT FFI callbacks to wxWidgets events via the kwxFFI
    wxClosure/wxCallback mechanism.

    Architecture:
        Lua handler → FFI callback → wxClosure → wxCallback → wxEvtHandler_Connect
        wxWidgets event → wxCallback::Invoke → wxClosure::Invoke → FFI callback → pcall(Lua handler)

    Usage (called internally by wxEvtHandler:Connect / :Bind):
        local events = require("wx.events")
        events.connect(window_ptr, wx.EVT_BUTTON, function(evt) ... end)

    LuaJIT FFI callback notes:
        - LuaJIT has a hard limit on concurrent FFI callbacks (~1000)
        - Callbacks MUST be prevented from garbage collection via registry
        - The ClosureFun signature is: void(void* fun, void* data, void* evt)
        - When evt is NULL, the closure is being destroyed (cleanup opportunity)
]]

local ffi = require("ffi")
local C = ffi.C

-- ============================================================================
-- Callback Registry
-- ============================================================================
-- FFI callbacks are garbage-collectable cdata.  If collected, calling them
-- from C crashes.  We anchor every callback here until explicitly freed.

local _M = {}

-- callback_id → { cb = ffi_callback, closure = wxClosure*, handlers = { handler_func, ... } }
local registry = {}
local next_id = 1

-- Map: (evthandler_ptr_as_number, event_type) → callback_id
-- Allows reuse of a single FFI callback for all handlers of the same
-- (object, event_type) pair, and allows Disconnect to find the right entry.
local handler_map = {}

-- Weak table mapping object pointers to their connection lists for cleanup
local object_connections = {}

-- Error handler for pcall — returns traceback
local function error_handler(err)
    return debug.traceback(tostring(err), 2)
end

-- ============================================================================
-- ClosureFun callback type
-- ============================================================================

-- The FFI callback type matching ClosureFun: void(void*, void*, void*)
local ClosureFun_ct = ffi.typeof("void(*)(void*, void*, void*)")

-- ============================================================================
-- connect()
-- ============================================================================
-- Connect a Lua function to a wxWidgets event on a given object.
--
-- Parameters:
--   obj_ptr    — void* (the wxEvtHandler, e.g., window._ptr)
--   event_type — integer event type (e.g., expEVT_COMMAND_BUTTON_CLICKED())
--   handler    — Lua function, called as handler(evt_ptr) where evt_ptr is void*
--   id         — optional: window id for the event source (default -1 = wxID_ANY)
--
-- Returns: callback_id for later disconnection

function _M.connect(obj_ptr, event_type, handler, id)
    id = id or -1

    -- Allocate a new callback entry
    local cb_id = next_id
    next_id = next_id + 1

    -- Create the FFI callback.  This function is called FROM C on every event.
    local cb = ffi.cast(ClosureFun_ct, function(fun, data, evt)
        -- evt == NULL means the closure is being destroyed by wxWidgets.
        -- Mark the registry entry dead so shutdown() won't call Disconnect
        -- on the already-freed wxEvtHandler.
        if evt == nil then
            local entry = registry[cb_id]
            if entry then entry.dead = true end
            return
        end

        -- Dispatch to the Lua handler inside a protected call
        local ok, err = xpcall(handler, error_handler, evt)
        if not ok then
            io.stderr:write("wxLuaJit event handler error:\n")
            io.stderr:write(tostring(err) .. "\n")
        end
    end)

    -- Anchor the callback so it is not garbage-collected
    registry[cb_id] = {
        cb = cb,
        handler = handler,
        obj_ptr = obj_ptr,
        event_type = event_type,
        id = id,
    }

    -- Create kwxFFI closure wrapping our FFI callback
    local closure = C.wxClosure_Create(cb, nil)

    -- Store the closure pointer for later disconnect
    registry[cb_id].closure = closure

    -- Connect via kwxFFI: wxEvtHandler_Connect(obj, first, last, type, closure)
    -- first = id, last = id  (single ID range; -1 means wxID_ANY)
    C.wxEvtHandler_Connect(obj_ptr, id, id, event_type, closure)

    -- Track in handler_map for lookup
    local key = tostring(tonumber(ffi.cast("uintptr_t", obj_ptr))) .. ":" .. event_type .. ":" .. id
    if not handler_map[key] then
        handler_map[key] = {}
    end
    table.insert(handler_map[key], cb_id)

    return cb_id
end

-- ============================================================================
-- disconnect()
-- ============================================================================
-- Disconnect a previously connected handler by callback_id.
--
-- Parameters:
--   cb_id — the id returned by connect()
--
-- Returns: true if disconnected, false if not found

function _M.disconnect(cb_id)
    local entry = registry[cb_id]
    if not entry then
        return false
    end

    -- Disconnect from wxWidgets only if wxWidgets hasn't already destroyed
    -- the handler (entry.dead is set by the evt==nil closure callback).
    if not entry.dead then
        C.wxEvtHandler_Disconnect(entry.obj_ptr, entry.id, entry.id, entry.event_type, 0)
    end

    -- Free the FFI callback (releases the LuaJIT callback slot)
    if entry.cb then
        entry.cb:free()
    end

    -- Remove from handler_map
    local key = tostring(tonumber(ffi.cast("uintptr_t", entry.obj_ptr))) .. ":" .. entry.event_type .. ":" .. entry.id
    local ids = handler_map[key]
    if ids then
        for i, v in ipairs(ids) do
            if v == cb_id then
                table.remove(ids, i)
                break
            end
        end
        if #ids == 0 then
            handler_map[key] = nil
        end
    end

    registry[cb_id] = nil
    return true
end

-- ============================================================================
-- disconnect_all()
-- ============================================================================
-- Disconnect ALL handlers for a given object pointer.
-- Call this when a window is being destroyed.

function _M.disconnect_all(obj_ptr)
    local prefix = tostring(tonumber(ffi.cast("uintptr_t", obj_ptr))) .. ":"
    local to_remove = {}

    for key, ids in pairs(handler_map) do
        if key:sub(1, #prefix) == prefix then
            for _, cb_id in ipairs(ids) do
                table.insert(to_remove, cb_id)
            end
        end
    end

    for _, cb_id in ipairs(to_remove) do
        _M.disconnect(cb_id)
    end
end

-- ============================================================================
-- shutdown()
-- ============================================================================
-- Disconnect ALL handlers for ALL objects and free all FFI callbacks.
-- MUST be called before lua_close() to prevent wxClosure destructors from
-- calling freed FFI callbacks.  See wrapper.cpp ~wxClosure() which calls
-- m_fun(fun, data, nullptr) on destruction.

function _M.shutdown()
    -- Collect all cb_ids first (disconnect modifies registry)
    local all_ids = {}
    for cb_id in pairs(registry) do
        table.insert(all_ids, cb_id)
    end

    for _, cb_id in ipairs(all_ids) do
        _M.disconnect(cb_id)
    end

    -- Clear maps
    handler_map = {}
end

-- ============================================================================
-- stats() — for debugging
-- ============================================================================

function _M.stats()
    local count = 0
    for _ in pairs(registry) do
        count = count + 1
    end
    return {
        active_callbacks = count,
        next_id = next_id,
    }
end

return _M

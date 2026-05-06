--[[
    lua/wx/debug_agent.lua — Debug hook agent for kwxLuaJit

    TCP server that listens for a debug adapter connection and provides:
    - Breakpoint management (set, clear, hit detection)
    - Stepping (next, stepIn, stepOut, continue)
    - Stack trace inspection
    - Variable inspection (locals, upvalues, globals)
    - Expression evaluation in breakpoint context

    Wire protocol: newline-delimited JSON messages over TCP.
    Each message has a "command" field for requests and a "type" field
    ("response" or "event") for outgoing messages. Request/response
    correlation uses a "seq" field.

    Architecture:
        DAP Adapter <-TCP-> debug_agent (this module) <-debug hooks-> LuaJIT VM

    Usage (from C++ main.cpp):
        -- loaded before user script
        local agent = require("wx.debug_agent")
        agent.start(port)
        -- user script runs with hooks active
]]

local ffi = require("ffi")
local debug = debug
local jit = jit

-- ============================================================================
-- Platform-specific Socket FFI
-- ============================================================================

local is_windows = (ffi.os == "Windows")

if is_windows then
    ffi.cdef[[
        // Winsock types
        typedef unsigned int SOCKET;
        typedef unsigned short WORD;
        typedef unsigned long DWORD;
        typedef int socklen_t;

        typedef struct {
            WORD wVersion;
            WORD wHighVersion;
            unsigned short iMaxSockets;
            unsigned short iMaxUdpDg;
            char* lpVendorInfo;
            char szDescription[257];
            char szSystemStatus[129];
        } WSADATA;

        typedef struct sockaddr_in {
            short sin_family;
            unsigned short sin_port;
            struct { unsigned long s_addr; } sin_addr;
            char sin_zero[8];
        } sockaddr_in;

        typedef struct sockaddr {
            unsigned short sa_family;
            char sa_data[14];
        } sockaddr;

        int WSAStartup(WORD wVersionRequested, WSADATA* lpWSAData);
        int WSACleanup(void);
        int WSAGetLastError(void);

        SOCKET socket(int af, int type, int protocol);
        int bind(SOCKET s, const struct sockaddr* name, int namelen);
        int listen(SOCKET s, int backlog);
        SOCKET accept(SOCKET s, struct sockaddr* addr, int* addrlen);
        int closesocket(SOCKET s);
        int send(SOCKET s, const char* buf, int len, int flags);
        int recv(SOCKET s, char* buf, int len, int flags);
        int setsockopt(SOCKET s, int level, int optname,
                       const char* optval, int optlen);
        unsigned short htons(unsigned short hostshort);
        unsigned long htonl(unsigned long hostlong);
    ]]
else
    ffi.cdef[[
        typedef int socklen_t;

        typedef struct sockaddr_in {
            short sin_family;
            unsigned short sin_port;
            struct { unsigned long s_addr; } sin_addr;
            char sin_zero[8];
        } sockaddr_in;

        typedef struct sockaddr {
            unsigned short sa_family;
            char sa_data[14];
        } sockaddr;

        int socket(int domain, int type, int protocol);
        int bind(int sockfd, const struct sockaddr* addr, socklen_t addrlen);
        int listen(int sockfd, int backlog);
        int accept(int sockfd, struct sockaddr* addr, socklen_t* addrlen);
        int close(int fd);
        long send(int sockfd, const void* buf, size_t len, int flags);
        long recv(int sockfd, void* buf, size_t len, int flags);
        int setsockopt(int sockfd, int level, int optname,
                       const void* optval, socklen_t optlen);
        unsigned short htons(unsigned short hostshort);
        unsigned long htonl(unsigned long hostlong);
    ]]
end

-- Socket constants
local AF_INET      = 2
local SOCK_STREAM  = 1
local IPPROTO_TCP  = 6
local SOL_SOCKET   = is_windows and 0xFFFF or 1
local SO_REUSEADDR = is_windows and 4 or 2
local INADDR_LOOPBACK = 0x0100007F  -- 127.0.0.1 in network byte order

-- Load winsock library on Windows
local sock_lib
if is_windows then
    sock_lib = ffi.load("ws2_32")
    -- Initialize Winsock
    local wsadata = ffi.new("WSADATA")
    local rc = sock_lib.WSAStartup(0x0202, wsadata)
    if rc ~= 0 then
        io.stderr:write("debug_agent: WSAStartup failed: " .. rc .. "\n")
    end
else
    sock_lib = ffi.C
end

-- ============================================================================
-- Socket Helpers
-- ============================================================================

local INVALID_SOCKET = is_windows and 0xFFFFFFFF or -1

local function sock_close(fd)
    if fd == INVALID_SOCKET then return end
    if is_windows then
        sock_lib.closesocket(fd)
    else
        sock_lib.close(fd)
    end
end

local function sock_send(fd, data)
    local sent = 0
    local len = #data
    while sent < len do
        local n = sock_lib.send(fd, data:sub(sent + 1), len - sent, 0)
        if n <= 0 then return false end
        sent = sent + tonumber(n)
    end
    return true
end

-- Receive until newline (for newline-delimited JSON)
local function sock_recv_line(fd)
    local buf = ffi.new("char[1]")
    local line = {}
    while true do
        local n = sock_lib.recv(fd, buf, 1, 0)
        if n <= 0 then return nil end
        local ch = string.char(buf[0])
        if ch == "\n" then
            return table.concat(line)
        end
        if ch ~= "\r" then
            line[#line + 1] = ch
        end
    end
end

-- ============================================================================
-- Minimal JSON Encoder/Decoder
-- ============================================================================
-- Self-contained to avoid external dependencies. Handles the subset needed
-- for the debug wire protocol: objects, arrays, strings, numbers, booleans,
-- null.

local json = {}

-- Encode ---------------------------------------------------------------

local function json_encode_value(val, buf)
    local t = type(val)
    if val == nil then
        buf[#buf + 1] = "null"
    elseif t == "boolean" then
        buf[#buf + 1] = val and "true" or "false"
    elseif t == "number" then
        if val ~= val then
            buf[#buf + 1] = "null"  -- NaN
        elseif val == 1/0 then
            buf[#buf + 1] = "1e999"
        elseif val == -1/0 then
            buf[#buf + 1] = "-1e999"
        elseif val == math.floor(val) and val >= -2^53 and val <= 2^53 then
            buf[#buf + 1] = string.format("%.0f", val)
        else
            buf[#buf + 1] = tostring(val)
        end
    elseif t == "string" then
        buf[#buf + 1] = '"'
        for i = 1, #val do
            local c = val:byte(i)
            if c == 0x22 then buf[#buf + 1] = '\\"'
            elseif c == 0x5C then buf[#buf + 1] = '\\\\'
            elseif c == 0x08 then buf[#buf + 1] = '\\b'
            elseif c == 0x0C then buf[#buf + 1] = '\\f'
            elseif c == 0x0A then buf[#buf + 1] = '\\n'
            elseif c == 0x0D then buf[#buf + 1] = '\\r'
            elseif c == 0x09 then buf[#buf + 1] = '\\t'
            elseif c < 0x20 then
                buf[#buf + 1] = string.format("\\u%04x", c)
            else
                buf[#buf + 1] = string.char(c)
            end
        end
        buf[#buf + 1] = '"'
    elseif t == "table" then
        -- Detect array vs object: array if sequential integer keys from 1
        local is_array = true
        local max_i = 0
        for k in pairs(val) do
            if type(k) == "number" and k == math.floor(k) and k >= 1 then
                if k > max_i then max_i = k end
            else
                is_array = false
                break
            end
        end
        if is_array and max_i > 0 then
            for i = 1, max_i do
                if val[i] == nil then
                    is_array = false
                    break
                end
            end
        end
        if is_array then
            buf[#buf + 1] = "["
            for i = 1, max_i do
                if i > 1 then buf[#buf + 1] = "," end
                json_encode_value(val[i], buf)
            end
            buf[#buf + 1] = "]"
        else
            buf[#buf + 1] = "{"
            local first = true
            for k, v in pairs(val) do
                if not first then buf[#buf + 1] = "," end
                first = false
                json_encode_value(tostring(k), buf)
                buf[#buf + 1] = ":"
                json_encode_value(v, buf)
            end
            buf[#buf + 1] = "}"
        end
    else
        -- cdata, userdata, function -> string representation
        buf[#buf + 1] = '"'
        buf[#buf + 1] = tostring(val):gsub('[\\"]', '\\%0')
        buf[#buf + 1] = '"'
    end
end

function json.encode(val)
    local buf = {}
    json_encode_value(val, buf)
    return table.concat(buf)
end

-- Decode ---------------------------------------------------------------

local function json_decode_error(str, pos, msg)
    error(string.format("JSON decode error at position %d: %s", pos, msg))
end

local function skip_ws(str, pos)
    return str:match("^%s*()", pos)
end

local json_decode_value  -- forward declaration

local function json_decode_string(str, pos)
    pos = pos + 1  -- skip opening '"'
    local parts = {}
    while pos <= #str do
        local c = str:byte(pos)
        if c == 0x22 then  -- closing '"'
            return table.concat(parts), pos + 1
        elseif c == 0x5C then  -- backslash
            pos = pos + 1
            local esc = str:byte(pos)
            if     esc == 0x22 then parts[#parts + 1] = '"'
            elseif esc == 0x5C then parts[#parts + 1] = '\\'
            elseif esc == 0x2F then parts[#parts + 1] = '/'
            elseif esc == 0x62 then parts[#parts + 1] = '\b'
            elseif esc == 0x66 then parts[#parts + 1] = '\f'
            elseif esc == 0x6E then parts[#parts + 1] = '\n'
            elseif esc == 0x72 then parts[#parts + 1] = '\r'
            elseif esc == 0x74 then parts[#parts + 1] = '\t'
            elseif esc == 0x75 then  -- \uXXXX
                local hex = str:sub(pos + 1, pos + 4)
                local code = tonumber(hex, 16)
                if code then
                    if code < 0x80 then
                        parts[#parts + 1] = string.char(code)
                    elseif code < 0x800 then
                        parts[#parts + 1] = string.char(
                            0xC0 + math.floor(code / 64),
                            0x80 + (code % 64))
                    else
                        parts[#parts + 1] = string.char(
                            0xE0 + math.floor(code / 4096),
                            0x80 + math.floor((code % 4096) / 64),
                            0x80 + (code % 64))
                    end
                end
                pos = pos + 4
            end
            pos = pos + 1
        else
            parts[#parts + 1] = string.char(c)
            pos = pos + 1
        end
    end
    json_decode_error(str, pos, "unterminated string")
end

local function json_decode_number(str, pos)
    local num_str = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    if not num_str then
        json_decode_error(str, pos, "invalid number")
    end
    return tonumber(num_str), pos + #num_str
end

local function json_decode_array(str, pos)
    pos = pos + 1  -- skip '['
    local arr = {}
    pos = skip_ws(str, pos)
    if str:byte(pos) == 0x5D then  -- ']'
        return arr, pos + 1
    end
    while true do
        local val
        val, pos = json_decode_value(str, pos)
        arr[#arr + 1] = val
        pos = skip_ws(str, pos)
        local c = str:byte(pos)
        if c == 0x5D then  -- ']'
            return arr, pos + 1
        elseif c == 0x2C then  -- ','
            pos = skip_ws(str, pos + 1)
        else
            json_decode_error(str, pos, "expected ',' or ']'")
        end
    end
end

local function json_decode_object(str, pos)
    pos = pos + 1  -- skip '{'
    local obj = {}
    pos = skip_ws(str, pos)
    if str:byte(pos) == 0x7D then  -- '}'
        return obj, pos + 1
    end
    while true do
        if str:byte(pos) ~= 0x22 then
            json_decode_error(str, pos, "expected string key")
        end
        local key
        key, pos = json_decode_string(str, pos)
        pos = skip_ws(str, pos)
        if str:byte(pos) ~= 0x3A then  -- ':'
            json_decode_error(str, pos, "expected ':'")
        end
        pos = skip_ws(str, pos + 1)
        local val
        val, pos = json_decode_value(str, pos)
        obj[key] = val
        pos = skip_ws(str, pos)
        local c = str:byte(pos)
        if c == 0x7D then  -- '}'
            return obj, pos + 1
        elseif c == 0x2C then  -- ','
            pos = skip_ws(str, pos + 1)
        else
            json_decode_error(str, pos, "expected ',' or '}'")
        end
    end
end

json_decode_value = function(str, pos)
    pos = skip_ws(str, pos)
    local c = str:byte(pos)
    if c == 0x22 then return json_decode_string(str, pos)
    elseif c == 0x7B then return json_decode_object(str, pos)
    elseif c == 0x5B then return json_decode_array(str, pos)
    elseif c == 0x74 then  -- true
        if str:sub(pos, pos + 3) == "true" then return true, pos + 4 end
    elseif c == 0x66 then  -- false
        if str:sub(pos, pos + 4) == "false" then return false, pos + 5 end
    elseif c == 0x6E then  -- null
        -- Represent JSON null as a sentinel (Lua nil disappears from tables)
        if str:sub(pos, pos + 3) == "null" then return nil, pos + 4 end
    elseif c == 0x2D or (c >= 0x30 and c <= 0x39) then  -- '-' or digit
        return json_decode_number(str, pos)
    end
    json_decode_error(str, pos,
        "unexpected character '" .. string.char(c or 0) .. "'")
end

function json.decode(str)
    local val, pos = json_decode_value(str, 1)
    return val
end

-- ============================================================================
-- Agent State
-- ============================================================================

local agent = {
    port       = 19820,
    server_fd  = INVALID_SOCKET,
    client_fd  = INVALID_SOCKET,

    -- Breakpoints: normalized_source -> {[line] = true}
    breakpoints = {},

    -- Stepping mode: nil (running), "next", "stepIn", "stepOut"
    stepping     = nil,
    step_depth   = 0,
    step_line    = 0,
    step_source  = nil,

    -- Current call depth tracked by hook
    call_depth = 0,

    -- Protocol sequence counter
    seq = 0,

    -- Whether agent is active
    active = false,

    -- Whether currently paused in command loop
    paused = false,
}

-- ============================================================================
-- Source Path Normalization
-- ============================================================================

local function normalize_source(source)
    if not source then return "" end
    -- Remove @ prefix that debug.getinfo adds for file sources
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    -- Normalize path separators to forward slash
    source = source:gsub("\\", "/")
    -- Lowercase on Windows for case-insensitive matching
    if is_windows then
        source = source:lower()
    end
    return source
end

-- ============================================================================
-- Protocol Helpers
-- ============================================================================

local function next_seq()
    agent.seq = agent.seq + 1
    return agent.seq
end

local function send_message(msg)
    if agent.client_fd == INVALID_SOCKET then return false end
    msg.seq = msg.seq or next_seq()
    local data = json.encode(msg) .. "\n"
    return sock_send(agent.client_fd, data)
end

local function send_response(request_seq, command, success, body)
    return send_message({
        type        = "response",
        request_seq = request_seq,
        command     = command,
        success     = success,
        body        = body or {},
    })
end

local function send_event(event, body)
    return send_message({
        type  = "event",
        event = event,
        body  = body or {},
    })
end

local function recv_command()
    local line = sock_recv_line(agent.client_fd)
    if not line or line == "" then return nil end
    local ok, msg = pcall(json.decode, line)
    if not ok then
        io.stderr:write("debug_agent: JSON parse error: "
                        .. tostring(msg) .. "\n")
        return nil
    end
    return msg
end

-- ============================================================================
-- Variable Inspection
-- ============================================================================

-- Safely convert a value to a displayable string
local function value_to_string(val)
    local t = type(val)
    if t == "string" then
        if #val > 256 then
            return '"' .. val:sub(1, 253) .. '..."'
        end
        return '"' .. val .. '"'
    elseif t == "nil" then
        return "nil"
    elseif t == "boolean" then
        return tostring(val)
    elseif t == "number" then
        return tostring(val)
    elseif t == "table" then
        local count = 0
        for _ in pairs(val) do
            count = count + 1
            if count > 100 then break end
        end
        local mt = getmetatable(val)
        if mt and mt.__tostring then
            local ok, s = pcall(tostring, val)
            if ok then return s end
        end
        return string.format("table (%d items)", count)
    elseif t == "function" then
        local info = debug.getinfo(val, "S")
        if info and info.short_src then
            return string.format("function <%s:%d>",
                                 info.short_src, info.linedefined or 0)
        end
        return "function"
    elseif t == "cdata" then
        local ok, s = pcall(tostring, val)
        return ok and s or "cdata"
    else
        return tostring(val)
    end
end

-- Determine type name for a value
local function value_type(val)
    local t = type(val)
    if t == "table" then
        local mt = getmetatable(val)
        if mt and mt.__name then
            return mt.__name
        end
        return "table"
    elseif t == "cdata" then
        local ok, ct = pcall(ffi.typeof, val)
        if ok then return tostring(ct) end
        return "cdata"
    end
    return t
end

-- Get locals at a given stack level
local function get_locals(level)
    local vars = {}
    local idx = 1
    while true do
        local name, val = debug.getlocal(level, idx)
        if not name then break end
        -- Skip internal variables (names starting with '(')
        if name:sub(1, 1) ~= "(" then
            vars[#vars + 1] = {
                name  = name,
                value = value_to_string(val),
                type  = value_type(val),
                variablesReference = (type(val) == "table") and idx or 0,
            }
        end
        idx = idx + 1
    end
    return vars
end

-- Get upvalues for the function at a given stack level
local function get_upvalues(level)
    local info = debug.getinfo(level, "f")
    if not info or not info.func then return {} end
    local vars = {}
    local idx = 1
    while true do
        local name, val = debug.getupvalue(info.func, idx)
        if not name then break end
        vars[#vars + 1] = {
            name  = name,
            value = value_to_string(val),
            type  = value_type(val),
            variablesReference = (type(val) == "table") and (1000 + idx) or 0,
        }
        idx = idx + 1
    end
    return vars
end

-- Get a subset of globals (capped for performance)
local function get_globals()
    local vars = {}
    local count = 0
    for k, v in pairs(_G) do
        count = count + 1
        if count > 200 then break end
        vars[#vars + 1] = {
            name  = tostring(k),
            value = value_to_string(v),
            type  = value_type(v),
            variablesReference = (type(v) == "table") and (2000 + count) or 0,
        }
    end
    table.sort(vars, function(a, b) return a.name < b.name end)
    return vars
end

-- ============================================================================
-- Stack Trace
-- ============================================================================

local function get_stack_trace(start_level)
    local frames = {}
    local level = start_level or 2
    while true do
        local info = debug.getinfo(level, "Snl")
        if not info then break end
        -- Skip C functions and internal debug agent frames
        if info.source and info.source ~= "=[C]" then
            local source = info.source
            if source:sub(1, 1) == "@" then
                source = source:sub(2)
            end
            frames[#frames + 1] = {
                id     = level,
                name   = info.name or info.what or "<unknown>",
                source = source,
                line   = info.currentline or 0,
                column = 0,
            }
        end
        level = level + 1
        if level > 100 then break end  -- safety limit
    end
    return frames
end

-- ============================================================================
-- Expression Evaluation
-- ============================================================================

local function evaluate_expression(expr, level)
    -- Build an environment with locals, upvalues, and globals
    local env = setmetatable({}, {__index = _G})

    -- Inject locals
    local idx = 1
    while true do
        local name, val = debug.getlocal(level, idx)
        if not name then break end
        if name:sub(1, 1) ~= "(" then
            env[name] = val
        end
        idx = idx + 1
    end

    -- Inject upvalues
    local info = debug.getinfo(level, "f")
    if info and info.func then
        idx = 1
        while true do
            local name, val = debug.getupvalue(info.func, idx)
            if not name then break end
            env[name] = val
            idx = idx + 1
        end
    end

    -- Try as expression first (return value), then as statement
    local chunk, err = loadstring("return " .. expr)
    if not chunk then
        chunk, err = loadstring(expr)
    end
    if not chunk then
        return false, "compile error: " .. tostring(err)
    end

    setfenv(chunk, env)
    local ok, result = pcall(chunk)
    if not ok then
        return false, "runtime error: " .. tostring(result)
    end
    return true, value_to_string(result), value_type(result)
end

-- ============================================================================
-- Command Handlers
-- ============================================================================

-- Stack level of the debug hook function, used as offset for getlocal/getinfo.
-- When paused in command_loop called from debug_hook:
--   command_loop -> debug_hook -> [user code]
-- User code is at (hook_level).
local hook_level = 0

local function handle_set_breakpoints(msg)
    local file  = msg.file or ""
    local lines = msg.lines or {}
    local norm  = normalize_source(file)

    local bp_table = {}
    for _, line in ipairs(lines) do
        bp_table[line] = true
    end
    agent.breakpoints[norm] = bp_table

    local verified = {}
    for _, line in ipairs(lines) do
        verified[#verified + 1] = { line = line, verified = true }
    end
    return send_response(msg.seq, "setBreakpoints", true,
                         { breakpoints = verified })
end

local function handle_stack_trace(msg)
    local frames = get_stack_trace(hook_level + 1)
    return send_response(msg.seq, "stackTrace", true, {
        stackFrames = frames,
        totalFrames = #frames,
    })
end

local function handle_scopes(msg)
    local frame_id = msg.frameId or (hook_level + 1)
    local scopes = {
        { name = "Locals",   variablesReference = frame_id * 10 + 1,
          expensive = false },
        { name = "Upvalues", variablesReference = frame_id * 10 + 2,
          expensive = false },
        { name = "Globals",  variablesReference = frame_id * 10 + 3,
          expensive = true },
    }
    return send_response(msg.seq, "scopes", true, { scopes = scopes })
end

local function handle_variables(msg)
    local ref = msg.variablesReference or 0
    local scope_type = ref % 10
    local frame_id   = math.floor(ref / 10)

    local vars
    if scope_type == 1 then
        vars = get_locals(frame_id)
    elseif scope_type == 2 then
        vars = get_upvalues(frame_id)
    elseif scope_type == 3 then
        vars = get_globals()
    else
        vars = {}
    end
    return send_response(msg.seq, "variables", true, { variables = vars })
end

local function handle_evaluate(msg)
    local expr     = msg.expression or ""
    local frame_id = msg.frameId or (hook_level + 1)
    local ok, result, result_type = evaluate_expression(expr, frame_id)
    if ok then
        return send_response(msg.seq, "evaluate", true, {
            result = result,
            type   = result_type,
        })
    else
        return send_response(msg.seq, "evaluate", false, {
            error = result,
        })
    end
end

-- ============================================================================
-- Command Loop (runs while paused at breakpoint/step)
-- ============================================================================

local function command_loop(reason, source, line)
    agent.paused = true

    -- Notify adapter we have stopped
    send_event("stopped", {
        reason = reason or "breakpoint",
        source = source or "",
        line   = line or 0,
    })

    while agent.paused do
        local msg = recv_command()
        if not msg then
            -- Connection lost — resume execution silently
            agent.paused   = false
            agent.active   = false
            agent.stepping = nil
            debug.sethook()
            return
        end

        local cmd = msg.command

        if cmd == "continue" then
            agent.stepping = nil
            agent.paused   = false
            send_response(msg.seq, "continue", true)

        elseif cmd == "next" then
            agent.stepping    = "next"
            agent.step_depth  = agent.call_depth
            agent.step_line   = line
            agent.step_source = source
            agent.paused      = false
            send_response(msg.seq, "next", true)

        elseif cmd == "stepIn" then
            agent.stepping = "stepIn"
            agent.paused   = false
            send_response(msg.seq, "stepIn", true)

        elseif cmd == "stepOut" then
            agent.stepping   = "stepOut"
            agent.step_depth = agent.call_depth
            agent.paused     = false
            send_response(msg.seq, "stepOut", true)

        elseif cmd == "setBreakpoints" then
            handle_set_breakpoints(msg)

        elseif cmd == "stackTrace" then
            handle_stack_trace(msg)

        elseif cmd == "scopes" then
            handle_scopes(msg)

        elseif cmd == "variables" then
            handle_variables(msg)

        elseif cmd == "evaluate" then
            handle_evaluate(msg)

        elseif cmd == "disconnect" then
            agent.paused   = false
            agent.active   = false
            agent.stepping = nil
            debug.sethook()
            send_response(msg.seq, "disconnect", true)
            return

        else
            send_response(msg.seq, cmd, false, {
                error = "unknown command: " .. tostring(cmd),
            })
        end
    end
end

-- ============================================================================
-- Debug Hook
-- ============================================================================

local function debug_hook(event, line)
    if not agent.active then return end

    if event == "call" or event == "tail call" then
        agent.call_depth = agent.call_depth + 1
        return
    end

    if event == "return" or event == "tail return" then
        agent.call_depth = agent.call_depth - 1

        -- stepOut: when depth drops below step_depth, convert to stepIn
        -- so we stop on the very next line event at the caller's level.
        if agent.stepping == "stepOut"
           and agent.call_depth < agent.step_depth then
            agent.stepping = "stepIn"
        end
        return
    end

    -- event == "line"
    local info = debug.getinfo(2, "S")
    if not info then return end
    local source = normalize_source(info.source)

    -- Skip internal debug agent frames
    if source:find("debug_agent", 1, true) then return end

    -- Record stack level for inspection commands.
    -- Level 0 = debug_hook, level 1 = [C] hook dispatch, level 2 = user code
    hook_level = 2

    -- Check breakpoints
    local bp_lines = agent.breakpoints[source]
    if bp_lines and bp_lines[line] then
        command_loop("breakpoint", source, line)
        return
    end

    -- Check stepping
    if agent.stepping == "stepIn" then
        command_loop("step", source, line)
        return
    end

    if agent.stepping == "next" then
        if agent.call_depth <= agent.step_depth then
            if line ~= agent.step_line or source ~= agent.step_source then
                command_loop("step", source, line)
                return
            end
        end
        return
    end
end

-- ============================================================================
-- Server Lifecycle
-- ============================================================================

local function create_server(port)
    local fd = sock_lib.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if fd == INVALID_SOCKET then
        return INVALID_SOCKET, "socket() failed"
    end

    -- Set SO_REUSEADDR
    local optval = ffi.new("int[1]", 1)
    sock_lib.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR,
        ffi.cast("const char*", optval), ffi.sizeof("int"))

    -- Bind to localhost only
    local addr = ffi.new("struct sockaddr_in")
    addr.sin_family     = AF_INET
    addr.sin_port       = sock_lib.htons(port)
    addr.sin_addr.s_addr = sock_lib.htonl(INADDR_LOOPBACK)

    if sock_lib.bind(fd, ffi.cast("const struct sockaddr*", addr),
                     ffi.sizeof("struct sockaddr_in")) ~= 0 then
        sock_close(fd)
        return INVALID_SOCKET, "bind() failed on port " .. port
    end

    if sock_lib.listen(fd, 1) ~= 0 then
        sock_close(fd)
        return INVALID_SOCKET, "listen() failed"
    end

    return fd, nil
end

local function accept_client(server_fd)
    local addr    = ffi.new("struct sockaddr_in")
    local addrlen = ffi.new("int[1]", ffi.sizeof("struct sockaddr_in"))
    local client_fd = sock_lib.accept(server_fd,
        ffi.cast("struct sockaddr*", addr), addrlen)
    if client_fd == INVALID_SOCKET then
        return INVALID_SOCKET, "accept() failed"
    end
    return client_fd, nil
end

-- ============================================================================
-- Public API
-- ============================================================================

local _M = {}

--- Start the debug agent.  Blocks until a client connects and sends
--- configurationDone, then enables debug hooks and returns.
-- @param port number  TCP port to listen on (default 19820)
-- @return boolean  true if hooks are active, false on error
function _M.start(port)
    port = port or 19820
    agent.port = port

    -- Disable JIT — debug hooks don't fire for JIT-compiled traces
    if jit then
        jit.off()
    end

    -- Create TCP server
    local fd, err = create_server(port)
    if fd == INVALID_SOCKET then
        io.stderr:write("debug_agent: " .. (err or "unknown error") .. "\n")
        return false
    end
    agent.server_fd = fd

    io.stderr:write(string.format(
        "debug_agent: listening on 127.0.0.1:%d\n", port))

    -- Wait for client connection (blocking)
    local client_fd, cerr = accept_client(fd)
    if client_fd == INVALID_SOCKET then
        io.stderr:write("debug_agent: " .. (cerr or "accept failed") .. "\n")
        sock_close(fd)
        agent.server_fd = INVALID_SOCKET
        return false
    end
    agent.client_fd = client_fd

    io.stderr:write("debug_agent: client connected\n")

    -- Close server socket — only one debug client supported
    sock_close(agent.server_fd)
    agent.server_fd = INVALID_SOCKET

    -- Send initialization event
    send_event("initialized", {
        agent   = "kwxlua-debug-agent",
        version = "0.1.0",
    })

    -- Process initial configuration (breakpoints, etc.) before script starts.
    -- The adapter sends "configurationDone" when ready.
    while true do
        local msg = recv_command()
        if not msg then
            io.stderr:write(
                "debug_agent: client disconnected during configuration\n")
            agent.client_fd = INVALID_SOCKET
            return false
        end

        local cmd = msg.command
        if cmd == "setBreakpoints" then
            handle_set_breakpoints(msg)
        elseif cmd == "configurationDone" then
            send_response(msg.seq, "configurationDone", true)
            break
        elseif cmd == "disconnect" then
            send_response(msg.seq, "disconnect", true)
            sock_close(agent.client_fd)
            agent.client_fd = INVALID_SOCKET
            return false
        else
            send_response(msg.seq, cmd, true, {})
        end
    end

    -- Enable debug hooks
    agent.active     = true
    agent.call_depth = 0
    debug.sethook(debug_hook, "lcr")

    io.stderr:write("debug_agent: hooks active, script executing\n")
    return true
end

--- Stop the debug agent and clean up all resources.
function _M.stop()
    agent.active = false
    agent.paused = false
    debug.sethook()

    if agent.client_fd ~= INVALID_SOCKET then
        send_event("terminated")
        sock_close(agent.client_fd)
        agent.client_fd = INVALID_SOCKET
    end

    if agent.server_fd ~= INVALID_SOCKET then
        sock_close(agent.server_fd)
        agent.server_fd = INVALID_SOCKET
    end

    if is_windows and sock_lib then
        sock_lib.WSACleanup()
    end

    io.stderr:write("debug_agent: stopped\n")
end

--- Check if the agent is active.
-- @return boolean
function _M.is_active()
    return agent.active
end

return _M

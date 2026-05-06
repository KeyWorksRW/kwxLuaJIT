# kwxLuaJit Examples

This directory contains example scripts demonstrating kwxLuaJit functionality.

## Running Examples

```powershell
# From the project root directory
.\build\Debug\wxluajit.exe examples\hello.lua
```

## Examples

### hello.lua — Hello World Demo

**Features demonstrated:**
- Application creation and lifecycle
- Frame and panel creation
- BoxSizer layout management
- StaticText label
- Button control
- Event handling (button click)
- Message box dialog

**Code highlights:**
```lua
local wx = require("wx")

local app = wx.App()
local frame = wx.Frame(nil, "kwxLuaJit Demo")
local panel = wx.Panel(frame)
local sizer = wx.BoxSizer(wx.VERTICAL)

local label = wx.StaticText(panel, "Welcome to kwxLuaJit!")
local button = wx.Button(panel, "Click Me")

button:Connect(wx.EVT_BUTTON, function()
    wx.MessageBox("Hello from Lua!", "kwxLuaJit")
end)

sizer:Add(label, 0, wx.ALL, 10)
sizer:Add(button, 0, wx.ALL + wx.ALIGN_CENTER, 10)
panel:SetSizer(sizer)

frame:Show(true)
frame:Center()
app:MainLoop()
```

## API Patterns

### Creating Windows

All window constructors follow this pattern:
```lua
local widget = wx.WidgetType(parent, ..., x, y, w, h, style)
```

Simplified forms are available:
```lua
local frame = wx.Frame(nil, "Title")  -- Uses defaults
local button = wx.Button(panel, "Label")  -- Minimal args
```

### Layout Management

1. Create a sizer:
   ```lua
   local sizer = wx.BoxSizer(wx.VERTICAL)
   ```

2. Add controls with flags:
   ```lua
   sizer:Add(control, proportion, flags, border)
   ```

3. Set sizer on container:
   ```lua
   panel:SetSizer(sizer)
   ```

### Event Handling

Connect events using the `:Connect()` method:
```lua
control:Connect(wx.EVT_TYPE, function(evt)
    -- Handle event
end)
```

Common event types:
- `wx.EVT_BUTTON` — Button click
- `wx.EVT_TEXT` — Text control changed
- `wx.EVT_CLOSE` — Window closing

### Sizer Flags

Flags can be combined with `+`:
```lua
wx.ALL + wx.EXPAND
wx.TOP + wx.BOTTOM + wx.ALIGN_CENTER
```

Common flags:
- **Direction**: `wx.ALL`, `wx.TOP`, `wx.BOTTOM`, `wx.LEFT`, `wx.RIGHT`
- **Sizing**: `wx.EXPAND`, `wx.SHAPED`, `wx.FIXED_MINSIZE`
- **Alignment**: `wx.ALIGN_CENTER`, `wx.ALIGN_LEFT`, `wx.ALIGN_RIGHT`, `wx.ALIGN_TOP`, `wx.ALIGN_BOTTOM`

## Tips

- **Always** set a sizer on panels/frames that contain controls
- Use `proportion=0` for fixed-size controls, `proportion=1` for expanding controls
- `wx.ALL` adds border on all four sides — more efficient than individual flags
- Call `frame:Center()` after `frame:Show()` for proper centering
- The app object must call `MainLoop()` to start event processing
- Event handlers can be anonymous functions (lambdas) or named functions

## Error Handling

If a widget fails to create, an error is thrown:
```lua
local frame = wx.Frame(nil, "Test")  -- If this fails, script terminates
```

For production code, use `pcall` for error handling:
```lua
local ok, frame = pcall(function()
    return wx.Frame(nil, "Test")
end)

if not ok then
    print("Failed to create frame:", frame)
end
```

## Next Steps

- Study `test_wx.lua` in the project root for more advanced examples
- Read `lua/wx/init.lua` for complete API documentation
- Explore kwxFFI documentation for underlying C API

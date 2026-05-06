// wxLuaJit - LuaJIT-based wxWidgets scripting
// Entry point using kwxApp pure C interface for wxWidgets lifecycle
//
// Uses kwxFFI's kwxApp interface (examples/CApp/kwxApp.h) instead of
// subclassing wxApp in C++. This eliminates linker conflicts and
// simplifies the application architecture.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>

#ifdef _WIN32
#include <windows.h>
#endif

#include "kwxApp.h"

extern "C"
{
#include "lauxlib.h"
#include "lua.h"
#include "luajit.h"
#include "lualib.h"
}

// Command line state
static struct
{
  int argc;
  char **argv;
  const char *execute_chunk; // -e chunk
  const char *script_file;   // script.lua
  int script_arg_index;      // index of script in argv
  bool show_version;
  bool show_help;
  int debug_port; // --debug [port], 0 = disabled
} g_cmdline = {};

// ============================================================================
// Helper functions
// ============================================================================

static void print_usage(const char *progname)
{
  std::fprintf(stderr,
               "wxLuaJit - LuaJIT-based wxWidgets scripting\n"
               "Usage: %s [options] [script [args]]\n"
               "\n"
               "Options:\n"
               "  -e chunk          Execute string 'chunk'\n"
               "  -v                Show version information\n"
               "  --debug [port]    Enable debug agent (default port: 19820)\n"
               "  --                Stop handling options\n"
               "\n",
               progname);
}

static void print_version()
{
  std::printf("%s\n", LUAJIT_VERSION);
  std::printf("%s\n", LUAJIT_COPYRIGHT);
}

static int report_error(lua_State *L, int status)
{
  if (status != LUA_OK)
  {
    const char *msg = lua_tostring(L, -1);
    std::fprintf(stderr, "Error: %s\n", msg ? msg : "(unknown error)");
    lua_pop(L, 1);
  }
  return status;
}

static int run_chunk(lua_State *L, const char *chunk, const char *name)
{
  int status = luaL_loadbuffer(L, chunk, std::strlen(chunk), name);
  if (status == LUA_OK)
  {
    status = lua_pcall(L, 0, LUA_MULTRET, 0);
  }
  return report_error(L, status);
}

static int run_file(lua_State *L, const char *filename)
{
  int status = luaL_loadfile(L, filename);
  if (status == LUA_OK)
  {
    status = lua_pcall(L, 0, LUA_MULTRET, 0);
  }
  return report_error(L, status);
}

// Set up Lua package path to find wx module
// Adds paths relative to the executable and current working directory
static void setup_lua_paths(lua_State *L)
{
  // Get executable directory
  std::filesystem::path exe_path;
#ifdef _WIN32
  wchar_t exe_buf[MAX_PATH];
  GetModuleFileNameW(nullptr, exe_buf, MAX_PATH);
  exe_path = std::filesystem::path(exe_buf).parent_path();
#else
  char exe_buf[PATH_MAX];
  ssize_t len = readlink("/proc/self/exe", exe_buf, sizeof(exe_buf) - 1);
  if (len != -1)
  {
    exe_buf[len] = '\0';
    exe_path = std::filesystem::path(exe_buf).parent_path();
  }
#endif

  // Build path string with multiple search locations
  std::string lua_path;

  // 1. Paths relative to executable (for installed/release builds)
  std::string exe_dir = exe_path.string();
  lua_path += exe_dir + "/lua/?.lua;";
  lua_path += exe_dir + "/lua/?/init.lua;";
  lua_path += exe_dir + "/../lua/?.lua;";
  lua_path += exe_dir + "/../lua/?/init.lua;";
  lua_path += exe_dir + "/../../lua/?.lua;";
  lua_path += exe_dir + "/../../lua/?/init.lua;";

  // Generated wx modules (kwxgen output lives in wx/ directory)
  lua_path += exe_dir + "/wx/?.lua;";
  lua_path += exe_dir + "/../wx/?.lua;";
  lua_path += exe_dir + "/../../wx/?.lua;";

  // 2. Current working directory
  lua_path += "./lua/?.lua;";
  lua_path += "./lua/?/init.lua;";
  lua_path += "./?.lua;";
  lua_path += "./?/init.lua;";
  lua_path += "./wx/?.lua;";

  // Append to existing package.path
  lua_getglobal(L, "package");
  lua_getfield(L, -1, "path");
  const char *old_path = lua_tostring(L, -1);
  lua_pop(L, 1);

  std::string full_path = lua_path + (old_path ? old_path : "");
  lua_pushstring(L, full_path.c_str());
  lua_setfield(L, -2, "path");
  lua_pop(L, 1);
}

// Parse command line arguments (before wxWidgets init)
static bool parse_cmdline(int argc, char *argv[])
{
  g_cmdline.argc = argc;
  g_cmdline.argv = argv;
  g_cmdline.execute_chunk = nullptr;
  g_cmdline.script_file = nullptr;
  g_cmdline.script_arg_index = 0;
  g_cmdline.show_version = false;
  g_cmdline.show_help = false;
  g_cmdline.debug_port = 0;

  for (int i = 1; i < argc; ++i)
  {
    const char *arg = argv[i];

    if (arg[0] != '-')
    {
      g_cmdline.script_file = arg;
      g_cmdline.script_arg_index = i;
      break;
    }

    if (std::strcmp(arg, "--") == 0)
    {
      if (i + 1 < argc)
      {
        g_cmdline.script_file = argv[i + 1];
        g_cmdline.script_arg_index = i + 1;
      }
      break;
    }

    if (std::strcmp(arg, "-v") == 0)
    {
      g_cmdline.show_version = true;
      return true;
    }

    if (std::strcmp(arg, "-h") == 0 || std::strcmp(arg, "--help") == 0)
    {
      g_cmdline.show_help = true;
      return true;
    }

    if (std::strcmp(arg, "-e") == 0)
    {
      if (++i >= argc)
      {
        std::fprintf(stderr, "Error: -e requires an argument\n");
        return false;
      }
      g_cmdline.execute_chunk = argv[i];
      continue;
    }

    if (std::strcmp(arg, "--debug") == 0)
    {
      // Optional port argument: --debug [port]
      if (i + 1 < argc && argv[i + 1][0] != '-')
      {
        ++i;
        char *endptr = nullptr;
        long port = std::strtol(argv[i], &endptr, 10);
        if (*endptr != '\0' || port <= 0 || port > 65535)
        {
          std::fprintf(stderr, "Error: Invalid debug port: %s\n", argv[i]);
          return false;
        }
        g_cmdline.debug_port = static_cast<int>(port);
      }
      else
      {
        g_cmdline.debug_port = 19820; // default port
      }
      continue;
    }

    std::fprintf(stderr, "Error: Unknown option: %s\n", arg);
    return false;
  }

  return true;
}

// ============================================================================
// Main entry point
// ============================================================================

int main(int argc, char *argv[])
{
  // Parse command line first (before wxWidgets init)
  if (!parse_cmdline(argc, argv))
  {
    print_usage(argv[0]);
    return EXIT_FAILURE;
  }

  // Handle -v and -h without starting wxWidgets
  if (g_cmdline.show_version)
  {
    print_version();
    return EXIT_SUCCESS;
  }

  if (g_cmdline.show_help)
  {
    print_usage(argv[0]);
    return EXIT_SUCCESS;
  }

  // If no script or chunk, show usage
  if (!g_cmdline.execute_chunk && !g_cmdline.script_file)
  {
    print_usage(argv[0]);
    return EXIT_SUCCESS;
  }

  // Initialize wxWidgets via kwxApp C interface
  if (!kwxApp_Initialize(argc, argv))
  {
    std::fprintf(stderr, "Error: Failed to initialize wxWidgets\n");
    return EXIT_FAILURE;
  }

  kwxApp_SetAppName("wxLuaJit");
  kwxApp_InitAllImageHandlers();

  // Create Lua state
  lua_State *L = luaL_newstate();
  if (!L)
  {
    std::fprintf(stderr, "Error: Failed to create Lua state\n");
    kwxApp_Shutdown();
    return EXIT_FAILURE;
  }

  luaL_openlibs(L);
  setup_lua_paths(L);

  // Start debug agent if --debug flag was provided.
  // Must be loaded BEFORE require("wx") so hooks see all code.
  if (g_cmdline.debug_port > 0)
  {
    std::string debug_chunk =
        "local agent = require('wx.debug_agent')\n"
        "agent.start(" +
        std::to_string(g_cmdline.debug_port) + ")\n";
    int dbg_status = luaL_loadbuffer(L, debug_chunk.c_str(),
                                     debug_chunk.size(), "=debug_init");
    if (dbg_status == LUA_OK)
    {
      dbg_status = lua_pcall(L, 0, 0, 0);
    }
    if (dbg_status != LUA_OK)
    {
      const char *msg = lua_tostring(L, -1);
      std::fprintf(stderr, "Warning: Debug agent failed to start: %s\n",
                   msg ? msg : "(unknown error)");
      lua_pop(L, 1);
      // Continue without debugger -- don't abort the script
    }
  }

  // Set up arg table for Lua scripts
  if (g_cmdline.script_file && g_cmdline.script_arg_index > 0)
  {
    lua_createtable(L, g_cmdline.argc - g_cmdline.script_arg_index,
                    g_cmdline.script_arg_index);
    for (int i = 0; i < g_cmdline.argc; ++i)
    {
      lua_pushstring(L, g_cmdline.argv[i]);
      lua_rawseti(L, -2, i - g_cmdline.script_arg_index);
    }
    lua_setglobal(L, "arg");
  }

  int status = LUA_OK;

  // Execute -e chunk if provided
  if (g_cmdline.execute_chunk)
  {
    status = run_chunk(L, g_cmdline.execute_chunk, "=(command line)");
  }

  // Run script file if provided
  if (status == LUA_OK && g_cmdline.script_file)
  {
    status = run_file(L, g_cmdline.script_file);
  }

  int result = (status != LUA_OK) ? EXIT_FAILURE : EXIT_SUCCESS;

  // Run the event loop only if the script created windows
  if (status == LUA_OK && kwxApp_GetTopWindow() != nullptr)
  {
    result = kwxApp_MainLoop();
  }

  // Cleanup order matters:
  // 1. Stop debug agent (closes TCP socket, removes hooks).
  // 2. Disconnect all event callbacks while Lua state and FFI callbacks
  //    are still alive.  wxClosure::~wxClosure() calls m_fun(nullptr),
  //    so the FFI callback must still exist when wxWidgets cleans up.
  // 3. Shut down wxWidgets (destroys windows and remaining event data).
  // 4. Close Lua state last (frees FFI callback slots).

  // Step 1: stop debug agent if it was started
  if (g_cmdline.debug_port > 0)
  {
    lua_getglobal(L, "require");
    lua_pushstring(L, "wx.debug_agent");
    if (lua_pcall(L, 1, 1, 0) == LUA_OK && lua_istable(L, -1))
    {
      lua_getfield(L, -1, "stop");
      if (lua_isfunction(L, -1))
      {
        lua_pcall(L, 0, 0, 0);
      }
      else
      {
        lua_pop(L, 1);
      }
    }
    lua_settop(L, 0);
  }

  // Step 2: disconnect all Lua event handlers
  lua_getglobal(L, "require");
  lua_pushstring(L, "wx.events");
  if (lua_pcall(L, 1, 1, 0) == LUA_OK && lua_istable(L, -1))
  {
    lua_getfield(L, -1, "shutdown");
    if (lua_isfunction(L, -1))
    {
      lua_pcall(L, 0, 0, 0);
    }
    else
    {
      lua_pop(L, 1);
    }
  }
  lua_settop(L, 0);

  // Step 3: destroy wxWidgets state (windows, event tables, etc.)
  kwxApp_Shutdown();

  // Step 4: close Lua state (frees FFI callback slots)
  lua_close(L);
  return result;
}

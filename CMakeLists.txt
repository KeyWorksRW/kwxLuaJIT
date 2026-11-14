# CMake 3.30 required for FetchContent performance improvements (CMP0168)
cmake_minimum_required(VERSION 3.30)

string(TIMESTAMP YEAR "%y")
string(TIMESTAMP DOY "%j")
string(TIMESTAMP PROJECT_YEAR "%Y")
math(EXPR BUILD_NUM "${YEAR}%100 * 1000 + ${DOY}")

set(PROJECT_VERSION_MAJOR 0)
set(PROJECT_VERSION_MINOR 1)
set(PROJECT_VERSION_PATCH 0)
set(PROJECT_VERSION_BUILD ${BUILD_NUM})
set(PROJECT_VERSION_YEAR ${PROJECT_YEAR})

# Even though the repository is called kwxLuaJIT, we want the executable to be just kwxlua to save typing.
project(kwxlua
    LANGUAGES C CXX
    VERSION ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}.${PROJECT_VERSION_BUILD}
    DESCRIPTION "LuaJIT-based wxWidgets scripting"
    HOMEPAGE_URL "https://github.com/Randalphwa/wxLuaJit-dev"
)

# ###################### General Settings #######################
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(CMAKE_CXX_EXTENSIONS OFF)

# ###################### sccache #######################
find_program(SCCACHE_PROGRAM sccache)
if(SCCACHE_PROGRAM)
    message(STATUS "sccache found: ${SCCACHE_PROGRAM}")
    set(CMAKE_C_COMPILER_LAUNCHER "${SCCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${SCCACHE_PROGRAM}")
else()
    message(STATUS "sccache not found; building without a compiler cache")
endif()

# ###################### Options #######################

# Only generate compile_commands.json for local development
if(NOT DEFINED ENV{CI})
    # creates a compile_commands.json file in the build directory, suitable for clangd
    set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
endif()

# ###################### sccache support #######################
find_program(SCCACHE_PROGRAM sccache)

if(SCCACHE_PROGRAM)
    message(STATUS "Using sccache: ${SCCACHE_PROGRAM}")
    set(CMAKE_C_COMPILER_LAUNCHER "${SCCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${SCCACHE_PROGRAM}")
endif()

# ###################### LuaJIT #######################
add_subdirectory(external)

# ###################### kwxFFI/wxWidgets via FetchContent #######################
include(FetchContent)

# Suppress verbose FetchContent git output (CMake 3.30+)
set(FETCHCONTENT_QUIET ON)

# kwxFFI must be built as a STATIC library for the WHOLE_ARCHIVE approach.
# Force OFF to prevent stale cache from overriding.
set(KWXFFI_BUILD_SHARED OFF CACHE BOOL "Build kwxFFI as shared library" FORCE)

message(STATUS "Fetching kwxFFI and wxWidgets (this may take awhile) ...")

FetchContent_Declare(
    kwxFFI
    # TEMPORARY: use the local sibling checkout so source changes show up immediately.
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../kwxFFI
    GIT_TAG origin/main
    GIT_SHALLOW TRUE
    UPDATE_DISCONNECTED FALSE
)

message(NOTICE "Configuring kwxFFI...")

FetchContent_MakeAvailable(kwxFFI)

message(NOTICE "kwxFFI has been fetched and configured.")
message(STATUS "kwxFFI sources: ${kwxFFI_SOURCE_DIR}")

# ###################### kwxgen — lua wrapper generator #######################

# disabled until the new kwxgen repository is ready
# include (cmake/kwxgen.cmake)

# Define wxWidgets paths (kwxFFI fetches wxWidgets as a subdependency)
set(WX_SRC_DIR ${CMAKE_BINARY_DIR}/_deps/wxwidgets-src)
set(WX_BUILD_DIR ${CMAKE_BINARY_DIR}/_deps/wxwidgets-build)
message(STATUS "wxWidgets sources: ${WX_SRC_DIR}")
message(STATUS "wxWidgets build: ${WX_BUILD_DIR}")

# ###################### wxLuaJit Executable #######################
set(KWXLUA_SOURCES
    src/main.cpp
    src/kwxApp.cpp
)

# Add Windows resource file for manifest and version info
if(WIN32)
    list(APPEND KWXLUA_SOURCES src/kwxlua.rc)
endif()

add_executable(kwxlua ${KWXLUA_SOURCES})

# ###################### Embed Lua Modules as Bytecode #######################
# Compiles all Lua source (generated wx/*_gen.lua + manual lua/wx/*.lua) into
# LuaJIT bytecode embedded in a single C file. Each module defines a
# luaJIT_BC_<modname> symbol with __declspec(dllexport), so LuaJIT's require()
# finds them via GetProcAddress/dlsym at runtime. No external .lua files or
# DLLs are needed — everything is baked into the executable.

set(LUA_BC_DIR "${CMAKE_BINARY_DIR}/lua_bytecode")
set(LUA_EMBEDDED_C "${LUA_BC_DIR}/embedded_modules.c")

# Glob all .lua files so ANY change (generated or manual) triggers bytecode rebuild.
# CMAKE_CONFIGURE_DEPENDS on the directories ensures CMake reconfigures when
# files are added or removed (e.g. kwxgen emits a new *_gen.lua).
file(GLOB WX_GEN_LUA_FILES "${CMAKE_SOURCE_DIR}/wx/*.lua")
file(GLOB MANUAL_LUA_FILES "${CMAKE_SOURCE_DIR}/lua/wx/*.lua")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/wx"
    "${CMAKE_SOURCE_DIR}/lua/wx"
)

# add_custom_target (with ALL) always runs on every build, unlike
# add_custom_command(OUTPUT) which only runs when file timestamps are stale.
# BYPRODUCTS tells Ninja that ${LUA_EMBEDDED_C} is produced here so it can
# satisfy target_sources() below without a separate add_custom_command.
# When kwxgen is re-enabled, replace this target with the real kwxgen target
# and restore add_custom_command(OUTPUT ...) with kwxgen as a DEPENDS entry.
add_custom_target(compile_lua_bytecode ALL
    COMMAND ${CMAKE_COMMAND}
    -DLUAJIT_EXE=$<TARGET_FILE:luajit_exe>
    -DLUAJIT_JIT_DIR=${CMAKE_SOURCE_DIR}/external/luaJIT/src
    -DWX_SRC_DIR=${CMAKE_SOURCE_DIR}/wx
    -DLUA_SRC_DIR=${CMAKE_SOURCE_DIR}/lua
    -DOUT_DIR=${LUA_BC_DIR}
    -DCOMBINED_OUTPUT=${LUA_EMBEDDED_C}
    -P ${CMAKE_SOURCE_DIR}/cmake/compile_lua_bytecode.cmake
    BYPRODUCTS ${LUA_EMBEDDED_C}
    DEPENDS luajit_exe
    COMMENT "Compiling Lua modules to embedded bytecode"
    VERBATIM
)
add_dependencies(kwxlua compile_lua_bytecode)

target_sources(kwxlua PRIVATE ${LUA_EMBEDDED_C})

# Platform-specific symbol export files — expose kwxFFI symbols in the exe's
# dynamic export table so LuaJIT ffi.C can find them at runtime.
# Files are generated by: kwxgen generate --exports
if(WIN32)
    if(MSVC)
        target_link_options(kwxlua PRIVATE "/DEF:${CMAKE_SOURCE_DIR}/wx/kwxffi_exports.def")
    else()
        # MinGW lld: pass .def file as a direct linker input (recognized by extension).
        # Neither --def nor --input-def are supported; the file must be a raw argument.
        target_link_options(kwxlua PRIVATE "${CMAKE_SOURCE_DIR}/wx/kwxffi_exports.def")
    endif()
elseif(APPLE)
    target_link_options(kwxlua PRIVATE
        -Wl,-exported_symbols_list,${CMAKE_SOURCE_DIR}/wx/kwxffi_exports.exp)
elseif(UNIX)
    target_link_options(kwxlua PRIVATE
        -Wl,--version-script=${CMAKE_SOURCE_DIR}/wx/kwxffi_exports.map)
endif()

target_compile_definitions(kwxlua PRIVATE KWXAPP_EXPORTS)

target_include_directories(kwxlua PRIVATE
    ${LUAJIT_INCLUDE_DIR}
    ${LUAJIT_BUILD_INCLUDE_DIR}
    ${CMAKE_SOURCE_DIR}/src
    ${kwxFFI_SOURCE_DIR}/include
    ${WX_SRC_DIR}/include
)

# Platform-specific wxWidgets setup.h include
if(WIN32)
    target_include_directories(kwxlua PRIVATE
        ${WX_BUILD_DIR}/lib/vc_x64_lib/mswu
    )
elseif(APPLE)
    target_include_directories(kwxlua PRIVATE
        ${WX_BUILD_DIR}/lib/osx_cocoa-unicode-static
    )
elseif(UNIX)
    target_include_directories(kwxlua PRIVATE
        ${WX_BUILD_DIR}/lib/gtk3_unixu-3.3/include
    )
else()
    message(FATAL_ERROR "Unsupported platform: Only WIN32, APPLE, or UNIX are supported.")
endif()

# Link against LuaJIT and kwxFFI. All wxWidgets libraries are pulled in
# transitively via kwxFFI's INTERFACE_LINK_LIBRARIES — no need to list them
# explicitly (mirrors the kwxGO pattern in cmake/functions.cmake).
# WHOLE_ARCHIVE is required so ALL kwxFFI symbols land in the exe for
# LuaJIT ffi.C to resolve via GetProcAddress/dlsym at runtime.
target_link_libraries(kwxlua PRIVATE
    luajit
    $<LINK_LIBRARY:WHOLE_ARCHIVE,kwxFFI>
)

# ENABLE_EXPORTS: causes CMake to generate an import lib alongside the exe
# (Windows) and ensures the dynamic export table is populated — required for
# LuaJIT ffi.C to resolve symbols via GetProcAddress/dlsym at runtime.
set_target_properties(kwxlua PROPERTIES
    ENABLE_EXPORTS TRUE
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_SOURCE_DIR}/bin/Debug"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/bin/Release"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_SOURCE_DIR}/bin/RelWithDebInfo"
)

# CMakeLists.txt for building LuaJIT as a static library
# This wraps LuaJIT's build system for CMake integration

cmake_minimum_required(VERSION 3.20)

set(LUAJIT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/luaJIT)
set(LUAJIT_SRC_DIR ${LUAJIT_DIR}/src)
set(LUAJIT_BUILD_DIR ${CMAKE_CURRENT_BINARY_DIR})

# Export include directory for parent project
set(LUAJIT_INCLUDE_DIR ${LUAJIT_SRC_DIR} CACHE PATH "LuaJIT include directory" FORCE)
set(LUAJIT_BUILD_INCLUDE_DIR ${LUAJIT_BUILD_DIR} CACHE PATH "LuaJIT build include directory (for luajit.h)" FORCE)

# ###################### Host Tools #######################
# Build minilua - a minimal Lua interpreter for running dynasm
add_executable(minilua ${LUAJIT_SRC_DIR}/host/minilua.c)
target_compile_definitions(minilua PRIVATE _CRT_SECURE_NO_DEPRECATE)
if(MSVC)
    target_compile_options(minilua PRIVATE /W3)
endif()

# Determine target architecture and set DASC flags
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|aarch64")
        set(LUAJIT_ARCH "arm64")
        set(DASC_FILE ${LUAJIT_SRC_DIR}/vm_arm64.dasc)
        set(DASMFLAGS -D WIN -D JIT -D FFI -D ENDIAN_LE -D FPU -D P64)
    else()
        set(LUAJIT_ARCH "x64")
        set(DASC_FILE ${LUAJIT_SRC_DIR}/vm_x64.dasc)
        set(DASMFLAGS -D WIN -D JIT -D FFI -D ENDIAN_LE -D FPU -D P64)
    endif()
else()
    set(LUAJIT_ARCH "x86")
    set(DASC_FILE ${LUAJIT_SRC_DIR}/vm_x86.dasc)
    set(DASMFLAGS -D WIN -D JIT -D FFI -D ENDIAN_LE -D FPU)
endif()

message(STATUS "LuaJIT target architecture: ${LUAJIT_ARCH}")

# Generate buildvm_arch.h via DynASM
set(DASM_DIR ${LUAJIT_DIR}/dynasm)
set(BUILDVM_ARCH_H ${LUAJIT_BUILD_DIR}/buildvm_arch.h)

add_custom_command(
    OUTPUT ${BUILDVM_ARCH_H}
    COMMAND minilua ${DASM_DIR}/dynasm.lua -LN ${DASMFLAGS} -o ${BUILDVM_ARCH_H} ${DASC_FILE}
    DEPENDS minilua ${DASC_FILE} ${DASM_DIR}/dynasm.lua
    WORKING_DIRECTORY ${LUAJIT_SRC_DIR}
    COMMENT "Generating buildvm_arch.h via DynASM"
)

# Generate version info
set(LUAJIT_RELVER_TXT ${LUAJIT_BUILD_DIR}/luajit_relver.txt)
set(LUAJIT_H ${LUAJIT_BUILD_DIR}/luajit.h)

if(EXISTS ${LUAJIT_DIR}/.git)
    add_custom_command(
        OUTPUT ${LUAJIT_RELVER_TXT}
        COMMAND ${CMAKE_COMMAND} -E echo "0" > ${LUAJIT_RELVER_TXT}
        COMMENT "Generating luajit_relver.txt from git"
    )
else()
    add_custom_command(
        OUTPUT ${LUAJIT_RELVER_TXT}
        COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_DIR}/.relver ${LUAJIT_RELVER_TXT}
        DEPENDS ${LUAJIT_DIR}/.relver
        COMMENT "Copying luajit_relver.txt from .relver"
    )
endif()

# Generate luajit.h from luajit_rolling.h using genversion.lua
add_custom_command(
    OUTPUT ${LUAJIT_H}
    COMMAND minilua ${LUAJIT_SRC_DIR}/host/genversion.lua
            ${LUAJIT_SRC_DIR}/luajit_rolling.h
            ${LUAJIT_RELVER_TXT}
            ${LUAJIT_H}
    DEPENDS minilua ${LUAJIT_RELVER_TXT} ${LUAJIT_SRC_DIR}/luajit_rolling.h ${LUAJIT_SRC_DIR}/host/genversion.lua
    WORKING_DIRECTORY ${LUAJIT_BUILD_DIR}
    COMMENT "Generating luajit.h via genversion.lua"
)

# Build buildvm - generates various headers from lib_*.c
add_executable(buildvm
    ${LUAJIT_SRC_DIR}/host/buildvm.c
    ${LUAJIT_SRC_DIR}/host/buildvm_asm.c
    ${LUAJIT_SRC_DIR}/host/buildvm_peobj.c
    ${LUAJIT_SRC_DIR}/host/buildvm_lib.c
    ${LUAJIT_SRC_DIR}/host/buildvm_fold.c
    ${BUILDVM_ARCH_H}
    ${LUAJIT_H}
)

target_include_directories(buildvm PRIVATE
    ${LUAJIT_SRC_DIR}
    ${LUAJIT_BUILD_DIR}
    ${DASM_DIR}
)

target_compile_definitions(buildvm PRIVATE _CRT_SECURE_NO_DEPRECATE)
if(MSVC)
    target_compile_options(buildvm PRIVATE /W3)
endif()

# Library source files that define Lua functions
set(ALL_LIB
    ${LUAJIT_SRC_DIR}/lib_base.c
    ${LUAJIT_SRC_DIR}/lib_math.c
    ${LUAJIT_SRC_DIR}/lib_bit.c
    ${LUAJIT_SRC_DIR}/lib_string.c
    ${LUAJIT_SRC_DIR}/lib_table.c
    ${LUAJIT_SRC_DIR}/lib_io.c
    ${LUAJIT_SRC_DIR}/lib_os.c
    ${LUAJIT_SRC_DIR}/lib_package.c
    ${LUAJIT_SRC_DIR}/lib_debug.c
    ${LUAJIT_SRC_DIR}/lib_jit.c
    ${LUAJIT_SRC_DIR}/lib_ffi.c
    ${LUAJIT_SRC_DIR}/lib_buffer.c
)

# Generate headers using buildvm
set(LJ_VM_OBJ ${LUAJIT_BUILD_DIR}/lj_vm.obj)
set(LJ_BCDEF_H ${LUAJIT_BUILD_DIR}/lj_bcdef.h)
set(LJ_FFDEF_H ${LUAJIT_BUILD_DIR}/lj_ffdef.h)
set(LJ_LIBDEF_H ${LUAJIT_BUILD_DIR}/lj_libdef.h)
set(LJ_RECDEF_H ${LUAJIT_BUILD_DIR}/lj_recdef.h)
set(LJ_FOLDDEF_H ${LUAJIT_BUILD_DIR}/lj_folddef.h)
set(VMDEF_LUA ${LUAJIT_BUILD_DIR}/vmdef.lua)

add_custom_command(
    OUTPUT ${LJ_VM_OBJ}
    COMMAND buildvm -m peobj -o ${LJ_VM_OBJ}
    DEPENDS buildvm
    WORKING_DIRECTORY ${LUAJIT_BUILD_DIR}
    COMMENT "Generating lj_vm.obj"
)

add_custom_command(
    OUTPUT ${LJ_BCDEF_H}
    COMMAND buildvm -m bcdef -o ${LJ_BCDEF_H} ${ALL_LIB}
    DEPENDS buildvm ${ALL_LIB}
    WORKING_DIRECTORY ${LUAJIT_BUILD_DIR}
    COMMENT "Generating lj_bcdef.h"
)

add_custom_command(
    OUTPUT ${LJ_FFDEF_H}
    COMMAND buildvm -m ffdef -o ${LJ_FFDEF_H} ${ALL_LIB}
    DEPENDS buildvm ${ALL_LIB}
    WORKING_DIRECTORY ${LUAJIT_BUILD_DIR}
    COMMENT "Generating lj_ffdef.h"
)

add_custom_command(
    OUTPUT ${LJ_LIBDEF_H}
    COMMAND buildvm -m libdef -o ${LJ_LIBDEF_H} ${ALL_LIB}
    DEPENDS buildvm ${ALL_LIB}
    WORKING_DIRECTORY ${LUAJIT_BUILD_DIR}
    COMMENT "Generating lj_libdef.h"
)

add_custom_command(
    OUTPUT ${LJ_RECDEF_H}
    COMMAND buildvm -m recdef -o ${LJ_RECDEF_H} ${ALL_LIB}
    DEPENDS buildvm ${ALL_LIB}
    WORKING_DIRECTORY ${LUAJIT_BUILD_DIR}
    COMMENT "Generating lj_recdef.h"
)

add_custom_command(
    OUTPUT ${LJ_FOLDDEF_H}
    COMMAND buildvm -m folddef -o ${LJ_FOLDDEF_H} ${LUAJIT_SRC_DIR}/lj_opt_fold.c
    DEPENDS buildvm ${LUAJIT_SRC_DIR}/lj_opt_fold.c
    WORKING_DIRECTORY ${LUAJIT_BUILD_DIR}
    COMMENT "Generating lj_folddef.h"
)

add_custom_command(
    OUTPUT ${VMDEF_LUA}
    COMMAND buildvm -m vmdef -o ${VMDEF_LUA} ${ALL_LIB}
    DEPENDS buildvm ${ALL_LIB}
    WORKING_DIRECTORY ${LUAJIT_BUILD_DIR}
    COMMENT "Generating vmdef.lua"
)

# Custom target for all generated headers
add_custom_target(luajit_generated
    DEPENDS
        ${LJ_BCDEF_H}
        ${LJ_FFDEF_H}
        ${LJ_LIBDEF_H}
        ${LJ_RECDEF_H}
        ${LJ_FOLDDEF_H}
        ${VMDEF_LUA}
        ${LJ_VM_OBJ}
)

# ###################### LuaJIT Static Library #######################
# Core source files
set(LUAJIT_CORE_SRC
    ${LUAJIT_SRC_DIR}/lj_assert.c
    ${LUAJIT_SRC_DIR}/lj_gc.c
    ${LUAJIT_SRC_DIR}/lj_err.c
    ${LUAJIT_SRC_DIR}/lj_char.c
    ${LUAJIT_SRC_DIR}/lj_bc.c
    ${LUAJIT_SRC_DIR}/lj_obj.c
    ${LUAJIT_SRC_DIR}/lj_buf.c
    ${LUAJIT_SRC_DIR}/lj_str.c
    ${LUAJIT_SRC_DIR}/lj_tab.c
    ${LUAJIT_SRC_DIR}/lj_func.c
    ${LUAJIT_SRC_DIR}/lj_udata.c
    ${LUAJIT_SRC_DIR}/lj_meta.c
    ${LUAJIT_SRC_DIR}/lj_debug.c
    ${LUAJIT_SRC_DIR}/lj_prng.c
    ${LUAJIT_SRC_DIR}/lj_state.c
    ${LUAJIT_SRC_DIR}/lj_dispatch.c
    ${LUAJIT_SRC_DIR}/lj_vmevent.c
    ${LUAJIT_SRC_DIR}/lj_vmmath.c
    ${LUAJIT_SRC_DIR}/lj_strscan.c
    ${LUAJIT_SRC_DIR}/lj_strfmt.c
    ${LUAJIT_SRC_DIR}/lj_strfmt_num.c
    ${LUAJIT_SRC_DIR}/lj_serialize.c
    ${LUAJIT_SRC_DIR}/lj_api.c
    ${LUAJIT_SRC_DIR}/lj_profile.c
    ${LUAJIT_SRC_DIR}/lj_lex.c
    ${LUAJIT_SRC_DIR}/lj_parse.c
    ${LUAJIT_SRC_DIR}/lj_bcread.c
    ${LUAJIT_SRC_DIR}/lj_bcwrite.c
    ${LUAJIT_SRC_DIR}/lj_load.c
    ${LUAJIT_SRC_DIR}/lj_ir.c
    ${LUAJIT_SRC_DIR}/lj_opt_mem.c
    ${LUAJIT_SRC_DIR}/lj_opt_fold.c
    ${LUAJIT_SRC_DIR}/lj_opt_narrow.c
    ${LUAJIT_SRC_DIR}/lj_opt_dce.c
    ${LUAJIT_SRC_DIR}/lj_opt_loop.c
    ${LUAJIT_SRC_DIR}/lj_opt_split.c
    ${LUAJIT_SRC_DIR}/lj_opt_sink.c
    ${LUAJIT_SRC_DIR}/lj_mcode.c
    ${LUAJIT_SRC_DIR}/lj_snap.c
    ${LUAJIT_SRC_DIR}/lj_record.c
    ${LUAJIT_SRC_DIR}/lj_crecord.c
    ${LUAJIT_SRC_DIR}/lj_ffrecord.c
    ${LUAJIT_SRC_DIR}/lj_asm.c
    ${LUAJIT_SRC_DIR}/lj_trace.c
    ${LUAJIT_SRC_DIR}/lj_gdbjit.c
    ${LUAJIT_SRC_DIR}/lj_ctype.c
    ${LUAJIT_SRC_DIR}/lj_cdata.c
    ${LUAJIT_SRC_DIR}/lj_cconv.c
    ${LUAJIT_SRC_DIR}/lj_ccall.c
    ${LUAJIT_SRC_DIR}/lj_ccallback.c
    ${LUAJIT_SRC_DIR}/lj_carith.c
    ${LUAJIT_SRC_DIR}/lj_clib.c
    ${LUAJIT_SRC_DIR}/lj_cparse.c
    ${LUAJIT_SRC_DIR}/lj_lib.c
    ${LUAJIT_SRC_DIR}/lj_alloc.c
    ${LUAJIT_SRC_DIR}/lib_aux.c
    ${LUAJIT_SRC_DIR}/lib_init.c
    ${ALL_LIB}
)

add_library(luajit STATIC
    ${LUAJIT_CORE_SRC}
    ${LJ_VM_OBJ}
)

add_dependencies(luajit luajit_generated)

target_include_directories(luajit PUBLIC
    ${LUAJIT_SRC_DIR}
)

target_include_directories(luajit PRIVATE
    ${LUAJIT_BUILD_DIR}
)

target_compile_definitions(luajit PRIVATE
    _CRT_SECURE_NO_DEPRECATE
    _CRT_STDIO_INLINE=__declspec\(dllexport\)__inline
)

if(MSVC)
    target_compile_options(luajit PRIVATE /W3)
    # Use /O2 only in Release to avoid conflict with /RTC1 in Debug
    target_compile_options(luajit PRIVATE $<$<CONFIG:Release>:/O2>)
endif()

set_target_properties(luajit PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    ARCHIVE_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/lib/Debug"
    ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/lib/Release"
)

# ###################### LuaJIT CLI Executable #######################
# Required for `luajit -b` which compiles Lua source to bytecode objects
# that are embedded into the final kwxlua executable.

add_executable(luajit_exe ${LUAJIT_SRC_DIR}/luajit.c)
add_dependencies(luajit_exe luajit)
target_link_libraries(luajit_exe PRIVATE luajit)

target_include_directories(luajit_exe PRIVATE
    ${LUAJIT_SRC_DIR}
    ${LUAJIT_BUILD_DIR}
)

target_compile_definitions(luajit_exe PRIVATE _CRT_SECURE_NO_DEPRECATE)

if(NOT WIN32)
    target_link_libraries(luajit_exe PRIVATE m dl)
    if(NOT APPLE)
        target_link_libraries(luajit_exe PRIVATE pthread)
    endif()
endif()

set_target_properties(luajit_exe PROPERTIES
    OUTPUT_NAME "luajit"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tools"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/tools"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/tools"
)

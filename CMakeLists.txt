cmake_minimum_required(VERSION 3.20)
project(QuireTWM VERSION 1.0.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
    add_compile_options(/permissive- /utf-8 /EHsc /D_CRT_SECURE_NO_WARNINGS /wd5321 /wd4100)
endif()

file(GLOB LUA_RAW_SOURCES "third_party/lua/*.c")
set(LUA_SOURCES "")
foreach(SRC ${LUA_RAW_SOURCES})
    if(NOT SRC MATCHES "(lua|luac)\\.c$")
        list(APPEND LUA_SOURCES ${SRC})
    endif()
endforeach()

add_library(lua_lib STATIC ${LUA_SOURCES})
target_compile_definitions(lua_lib PRIVATE LUA_OPNAMES)
target_include_directories(lua_lib PUBLIC third_party/lua)

if(MSVC)
    target_compile_options(lua_lib PRIVATE /W0)
endif()

add_subdirectory(core)

add_executable(QuireTWM 
    core/src/main.cpp
    core/src/app.rc
)
target_include_directories(QuireTWM PRIVATE third_party third_party/lua)

if(MSVC)
    target_compile_options(QuireTWM PRIVATE /W4)
endif()

target_link_libraries(QuireTWM PRIVATE 
    core_lib 
    lua_lib 
    user32 
    dwmapi 
    dcomp 
    d2d1 
    dwrite 
    shell32
    winmm
)

add_custom_command(TARGET QuireTWM POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
    "${CMAKE_CURRENT_SOURCE_DIR}/scripts"
    "$<TARGET_FILE_DIR:QuireTWM>/scripts"
)
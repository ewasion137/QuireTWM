add_library(core_lib STATIC
    src/renderer.cpp
    src/alttab.cpp
    src/isle.cpp
)

target_include_directories(core_lib PUBLIC 
    include
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/lua
)

target_link_libraries(core_lib PUBLIC d2d1 dwrite dwmapi user32)
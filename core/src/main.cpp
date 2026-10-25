#ifndef NOMINMAX
#define NOMINMAX
#endif

#define SOL_ALL_SAFETIES_ON 1

#include "../include/renderer.hpp"
#include "../include/alttab.hpp"
#include <dwmapi.h>
#include <shellapi.h>
#include <iostream>
#include <string>
#include <windows.h>
#include <filesystem>
#include <fstream>
#include <windowsx.h>
#include <shlobj.h>
#include <thread>
#include <vector>
#include <mutex>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#include <sol/sol.hpp>

sol::state* g_lua = nullptr;
std::mutex g_lua_mutex;
Renderer g_renderer;
HWND g_overlay_hwnd = NULL;
namespace fs = std::filesystem;
std::vector<int> g_registered_hotkeys;

Renderer* g_current_renderer = nullptr;

#define WM_QUIRE_IPC (WM_USER + 500)
#define WM_QUIRE_ALTTAB (WM_USER + 501)

struct IPCMessage {
    const char* request;
    std::string response;
};

LRESULT CALLBACK OverlayWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_QUIRE_ALTTAB: {
        if (!g_lua) return 0;
        std::lock_guard<std::mutex> lock(g_lua_mutex);
        sol::protected_function fn = (*g_lua)["Quire"]["on_alttab_action"];
        if (fn.valid()) {
            const char* act = (wParam == 3) ? "cancel" : ((wParam == 2) ? "commit" : ((wParam == 1) ? "prev" : "next"));
            fn(act);
        }
        return 0;
    }
    case WM_QUIRE_IPC: {
        auto* ipcm = reinterpret_cast<IPCMessage*>(lParam);
        if (ipcm && g_lua) {
            std::lock_guard<std::mutex> lock(g_lua_mutex);
            sol::protected_function fn = (*g_lua)["Quire"]["on_ipc_request"];
            if (fn.valid()) {
                auto res = fn(ipcm->request);
                if (res.valid()) {
                    ipcm->response = res.get<std::string>();
                } else {
                    sol::error err = res;
                    ipcm->response = "LUA ERROR: " + std::string(err.what());
                }
            } else {
                ipcm->response = "ERROR: IPC handler missing";
            }
        }
        return 1;
    }
    default:
        return DefWindowProcA(hwnd, msg, wParam, lParam);
    }
}

void IPCServerThread() {
    while (true) {
        HANDLE hPipe = CreateNamedPipeA(
            "\\\\.\\pipe\\quire",
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
            1,
            2048, 2048, 0, nullptr
        );

        if (hPipe == INVALID_HANDLE_VALUE) {
            Sleep(500);
            continue;
        }

        if (ConnectNamedPipe(hPipe, nullptr) ? TRUE : (GetLastError() == ERROR_PIPE_CONNECTED)) {
            char buffer[2048];
            DWORD bytesRead = 0;
            if (ReadFile(hPipe, buffer, sizeof(buffer) - 1, &bytesRead, nullptr) && bytesRead > 0) {
                buffer[bytesRead] = '\0';
                IPCMessage msg;
                msg.request = buffer;

                if (g_overlay_hwnd) {
                    SendMessageA(g_overlay_hwnd, WM_QUIRE_IPC, 0, reinterpret_cast<LPARAM>(&msg));
                } else {
                    msg.response = "ERROR: Overlay unavailable";
                }

                DWORD bytesWritten = 0;
                WriteFile(hPipe, msg.response.data(), static_cast<DWORD>(msg.response.size()), &bytesWritten, nullptr);
            }
        }
        DisconnectNamedPipe(hPipe);
        CloseHandle(hPipe);
    }
}

bool IsToplevelWindow(HWND hwnd) {
    if (!IsWindow(hwnd)) return false;

    DWORD pid;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == GetCurrentProcessId()) return false;

    if (!IsWindowVisible(hwnd)) return false;

    LONG ex_style = GetWindowLong(hwnd, GWL_EXSTYLE);
    LONG style = GetWindowLong(hwnd, GWL_STYLE);
    HWND owner = GetWindow(hwnd, GW_OWNER);

    if (ex_style & WS_EX_TOPMOST) return false;
    if (ex_style & WS_EX_TOOLWINDOW) return false;

    int cloaked = 0;
    if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) && cloaked != 0) {
        return false;
    }

    if ((style & WS_POPUP) && !(style & WS_CAPTION)) {
        RECT rc;
        GetWindowRect(hwnd, &rc);
        int screen_w = GetSystemMetrics(SM_CXSCREEN);
        int screen_h = GetSystemMetrics(SM_CYSCREEN);
        if (rc.left <= 0 && rc.top <= 0 && rc.right >= screen_w && rc.bottom >= screen_h) {
            return false;
        }
    }

    if (ex_style & WS_EX_APPWINDOW) return true;

    if (owner == NULL && !(style & WS_CHILD)) {
        RECT rc;
        GetWindowRect(hwnd, &rc);
        if ((rc.right - rc.left) > 150 && (rc.bottom - rc.top) > 100) {
            return true;
        }
    }

    return false;
}

// Защита: восстанавливаем окна при выходе или краше
void RestoreAllWindows() {
    static int offset = 0;
    int screen_w = GetSystemMetrics(SM_CXSCREEN);
    int screen_h = GetSystemMetrics(SM_CYSCREEN);

    EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
        if (IsWindowVisible(hwnd) && IsToplevelWindow(hwnd)) {
            // Возвращаем 100% прозрачность
            LONG ex_style = GetWindowLong(hwnd, GWL_EXSTYLE);
            if (ex_style & WS_EX_LAYERED) {
                SetWindowLong(hwnd, GWL_EXSTYLE, ex_style & ~WS_EX_LAYERED);
            }

            RECT rc;
            GetWindowRect(hwnd, &rc);
            // Если окно уехало за экран дальше чем положено — возвращаем каскадом
            if (rc.left < -500 || rc.left > GetSystemMetrics(SM_CXSCREEN) + 500) {
                int* off = (int*)lParam;
                SetWindowPos(hwnd, HWND_NOTOPMOST, 100 + *off, 100 + *off, 1200, 700, 
                             SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED);
                *off = (*off + 30) % 300;
            }
        }
        return TRUE;
    }, (LPARAM)&offset);
}

BOOL WINAPI ConsoleHandler(DWORD ctrlType) {
    RestoreAllWindows();
    return FALSE;
}

void CALLBACK WinEventProc(HWINEVENTHOOK hWinEventHook, DWORD event, HWND hwnd,
                           LONG idObject, LONG idChild, DWORD dwEventThread,
                           DWORD dwmsEventTime) {
    if (idObject != OBJID_WINDOW || idChild != CHILDID_SELF || hwnd == nullptr) return;
    if (event == 0x800B || event == 0x800A) return;

    HWND root = GetAncestor(hwnd, GA_ROOT);
    if (root != hwnd) {
        return;
    }

    bool is_removal = (event == EVENT_OBJECT_DESTROY || event == EVENT_SYSTEM_MINIMIZESTART);

    if (!is_removal) {
        if (!IsWindowVisible(hwnd) || !IsToplevelWindow(hwnd)) return;
    }

    if (g_lua) {
        char title[256] = {0};
        GetWindowTextA(hwnd, title, sizeof(title));

        std::lock_guard<std::mutex> lock(g_lua_mutex);
        sol::protected_function dispatcher = (*g_lua)["Quire"]["dispatch_event"];
        if (dispatcher.valid()) {
            dispatcher(event, reinterpret_cast<size_t>(hwnd), std::string(title));
        }
    }
}

std::string GetConfigPath() {
    char szPath[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathA(NULL, CSIDL_PROFILE, NULL, 0, szPath))) {
        fs::path configDir = fs::path(szPath) / ".quire";
        if (!fs::exists(configDir)) {
            fs::create_directories(configDir);
        }
        return (configDir / "config.lua").string();
    }
    return "config.lua";
}

int main() {
    try {
        SetConsoleCtrlHandler(ConsoleHandler, TRUE);
        atexit(RestoreAllWindows);

        std::cout << "=== QuireTWM: Initializing ===" << std::endl;
        std::string configPath = GetConfigPath();

        sol::state lua;
        g_lua = &lua;

        lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::string,
                           sol::lib::math, sol::lib::table, sol::lib::os, sol::lib::io, sol::lib::debug);

        lua.set_function("log", [](std::string message) {
            std::cout << "[Quire]: " << message << std::endl;
        });

        auto wm = lua.create_named_table("wm");

        wm.set_function("get_class_name", [](size_t hwnd) {
            char class_name[256] = {0};
            GetClassNameA((HWND)hwnd, class_name, sizeof(class_name));
            return std::string(class_name);
        });

        wm.set_function("register_hotkey", [](int id, int modifiers, int vk) {
            UnregisterHotKey(NULL, id);
            if (RegisterHotKey(NULL, id, modifiers, vk)) {
                g_registered_hotkeys.push_back(id);
                return true;
            }
            return false;
        });

        wm.set_function("unregister_all_hotkeys", []() {
            for (int id : g_registered_hotkeys) {
                UnregisterHotKey(NULL, id);
            }
            g_registered_hotkeys.clear();
        });

        wm.set_function("close_window", [](size_t hwnd) {
            PostMessage((HWND)hwnd, WM_CLOSE, 0, 0);
        });

        wm.set_function("get_window_title", [](size_t hwnd) {
            char title[256] = {0};
            GetWindowTextA((HWND)hwnd, title, sizeof(title));
            return std::string(title);
        });

        wm.set_function("is_toplevel", [](size_t hwnd) {
            return IsToplevelWindow(reinterpret_cast<HWND>(hwnd));
        });

        wm.set_function("get_foreground_window", []() {
            return (size_t)GetForegroundWindow();
        });

        wm.set_function("spawn", [](std::string command) {
            ShellExecuteA(NULL, "open", command.c_str(), NULL, NULL, SW_SHOWNORMAL);
        });

        wm.set_function("focus_window", [](size_t hwnd) {
            HWND handle = (HWND)hwnd;
            if (!IsWindow(handle)) return;

            if (IsIconic(handle)) ShowWindow(handle, SW_RESTORE);
            else ShowWindow(handle, SW_SHOW);

            HWND fg = GetForegroundWindow();
            DWORD fgThread = GetWindowThreadProcessId(fg, NULL);
            DWORD currentThread = GetCurrentThreadId();

            SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0, (LPVOID)0, SPIF_SENDCHANGE);

            if (fgThread != currentThread && fgThread != 0) {
                AttachThreadInput(currentThread, fgThread, TRUE);
                SetForegroundWindow(handle);
                BringWindowToTop(handle);
                SetActiveWindow(handle);
                SetFocus(handle);
                AttachThreadInput(currentThread, fgThread, FALSE);
            } else {
                SetForegroundWindow(handle);
                BringWindowToTop(handle);
                SetActiveWindow(handle);
                SetFocus(handle);
            }
        });

        wm.set_function("set_window_opacity", [](size_t hwnd, double opacity) {
            HWND handle = reinterpret_cast<HWND>(hwnd);
            if (!IsWindow(handle)) return;

            LONG ex_style = GetWindowLong(handle, GWL_EXSTYLE);

            if (opacity >= 0.999) {
                if (ex_style & WS_EX_LAYERED) {
                    SetWindowLong(handle, GWL_EXSTYLE, ex_style & ~WS_EX_LAYERED);
                    SetWindowPos(handle, NULL, 0, 0, 0, 0,
                                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
                }
            } else {
                if (!(ex_style & WS_EX_LAYERED)) {
                    SetWindowLong(handle, GWL_EXSTYLE, ex_style | WS_EX_LAYERED);
                    SetWindowPos(handle, NULL, 0, 0, 0, 0,
                                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
                }
                BYTE alpha = static_cast<BYTE>(opacity * 255.0);
                SetLayeredWindowAttributes(handle, 0, alpha, LWA_ALPHA);
            }
        });

        wm.set_function("move_window", [](size_t hwnd, double x, double y, double w, double h) {
            HWND handle = reinterpret_cast<HWND>(hwnd);
            if (IsZoomed(handle)) ShowWindow(handle, SW_RESTORE);

            RECT windowRect, frameRect;
            GetWindowRect(handle, &windowRect);

            if (SUCCEEDED(DwmGetWindowAttribute(handle, DWMWA_EXTENDED_FRAME_BOUNDS, &frameRect, sizeof(RECT)))) {
                int leftMargin = frameRect.left - windowRect.left;
                int topMargin = frameRect.top - windowRect.top;
                int rightMargin = windowRect.right - frameRect.right;
                int bottomMargin = windowRect.bottom - frameRect.bottom;

                SetWindowPos(handle, HWND_NOTOPMOST,
                             static_cast<int>(x) - leftMargin,
                             static_cast<int>(y) - topMargin,
                             static_cast<int>(w) + leftMargin + rightMargin,
                             static_cast<int>(h) + topMargin + bottomMargin,
                             SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOSENDCHANGING);
            } else {
                SetWindowPos(handle, HWND_NOTOPMOST,
                             static_cast<int>(x),
                             static_cast<int>(y),
                             static_cast<int>(w),
                             static_cast<int>(h),
                             SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOSENDCHANGING);
            }
        });

        wm.set_function("get_screen_size", []() {
            return std::make_pair(GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
        });

        wm.set_function("get_window_rect", [](size_t hwnd) {
            RECT rect = {0};
            if (SUCCEEDED(DwmGetWindowAttribute((HWND)hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &rect, sizeof(RECT)))) {
                return std::make_tuple((int)rect.left, (int)rect.top,
                                       (int)(rect.right - rect.left),
                                       (int)(rect.bottom - rect.top));
            }
            GetWindowRect((HWND)hwnd, &rect);
            return std::make_tuple((int)rect.left, (int)rect.top,
                                   (int)(rect.right - rect.left),
                                   (int)(rect.bottom - rect.top));
        });

        wm.set_function("is_window_visible", [](size_t hwnd) {
            if (!IsWindowVisible((HWND)hwnd)) return false;
            int cloaked = 0;
            if (SUCCEEDED(DwmGetWindowAttribute((HWND)hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) && cloaked != 0) {
                return false;
            }
            return true;
        });

        wm.set_function("is_minimized", [](size_t hwnd) {
            return (bool)IsIconic((HWND)hwnd);
        });

        wm.set_function("enumerate_windows", []() {
            std::vector<size_t> hwnds;
            EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
                auto list = (std::vector<size_t>*)lParam;
                if (IsWindowVisible(hwnd) && IsToplevelWindow(hwnd)) {
                    int cloaked = 0;
                    if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) && cloaked != 0) {
                        return TRUE;
                    }
                    list->push_back((size_t)hwnd);
                }
                return TRUE;
            }, (LPARAM)&hwnds);
            return hwnds;
        });

        wm.set_function("get_config_path", [configPath]() {
            return configPath;
        });

        auto ui = lua.create_named_table("ui");
        ui.set_function("draw_rect", [](float x, float y, float w, float h, float r, float g, float b, float a, float th) {
            if (g_current_renderer) g_current_renderer->draw_rect(x, y, w, h, r, g, b, a, th);
        });
        ui.set_function("fill_rect", [](float x, float y, float w, float h, float r, float g, float b, float a) {
            if (g_current_renderer) g_current_renderer->fill_rect(x, y, w, h, r, g, b, a);
        });
        ui.set_function("draw_rounded_rect", [](float x, float y, float w, float h, float rad, float r, float g, float b, float a, float th) {
            if (g_current_renderer) g_current_renderer->draw_rounded_rect(x, y, w, h, rad, r, g, b, a, th);
        });
        ui.set_function("fill_rounded_rect", [](float x, float y, float w, float h, float rad, float r, float g, float b, float a) {
            if (g_current_renderer) g_current_renderer->fill_rounded_rect(x, y, w, h, rad, r, g, b, a);
        });
        ui.set_function("draw_text", [](std::string text, float x, float y, float size, float r, float g, float b, float a, std::string font) {
            if (g_current_renderer) g_current_renderer->draw_text(text, x, y, size, r, g, b, a, font);
        });
        ui.set_function("measure_text", [](std::string text, float size, std::string font) {
            if (g_current_renderer) return g_current_renderer->measure_text_width(text, size, font);
            return 0.0f;
        });

        WNDCLASSEXA wc = {sizeof(WNDCLASSEXA), CS_HREDRAW | CS_VREDRAW, OverlayWndProc, 0, 0,
                          GetModuleHandle(NULL), NULL, NULL, (HBRUSH)GetStockObject(BLACK_BRUSH),
                          NULL, "QuireOverlay", NULL};
        RegisterClassExA(&wc);

        HWND overlay_hwnd = CreateWindowExA(
            WS_EX_TOPMOST | WS_EX_TRANSPARENT | WS_EX_LAYERED, "QuireOverlay",
            "QuireOverlay", WS_POPUP, 0, 0, GetSystemMetrics(SM_CXSCREEN),
            GetSystemMetrics(SM_CYSCREEN), NULL, NULL, wc.hInstance, NULL);

        g_overlay_hwnd = overlay_hwnd;
        SetLayeredWindowAttributes(overlay_hwnd, 0, 255, LWA_ALPHA);

        MARGINS margins = {-1};
        DwmExtendFrameIntoClientArea(overlay_hwnd, &margins);

        if (!g_renderer.init(overlay_hwnd)) {
            std::cerr << "Quire: Failed to initialize Renderer!" << std::endl;
            return -1;
        }

        ShowWindow(overlay_hwnd, SW_SHOW);
        SetWindowPos(overlay_hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);

        char buffer[MAX_PATH];
        GetModuleFileNameA(NULL, buffer, MAX_PATH);
        std::string path(buffer);
        std::string exe_dir = path.substr(0, path.find_last_of("\\/"));
        std::string script_path = exe_dir + "\\scripts\\main.lua";

        std::cout << "Quire: Loading core engine from " << script_path << std::endl;

        sol::protected_function_result result = lua.script_file(script_path);
        if (!result.valid()) {
            sol::error err = result;
            std::cerr << "!!! LUA SCRIPT ERROR: " << err.what() << std::endl;
            return 1;
        }

        HWINEVENTHOOK hook_objects = SetWinEventHook(EVENT_OBJECT_CREATE, EVENT_OBJECT_NAMECHANGE, NULL,
                                                    WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);
        HWINEVENTHOOK hook_focus = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, NULL,
                                                  WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);
        HWINEVENTHOOK hook_minimize = SetWinEventHook(EVENT_SYSTEM_MINIMIZESTART, EVENT_SYSTEM_MINIMIZEEND,
                                                    NULL, WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);

        if (!hook_objects || !hook_focus || !hook_minimize) {
            std::cerr << "Quire: Failed to register WinEventHooks!" << std::endl;
            return 1;
        }

        InitializeAltTabHook();
        std::thread(IPCServerThread).detach();

        MSG msg;
        using clock = std::chrono::steady_clock;
        auto last_frame = clock::now();
        const std::chrono::nanoseconds frame_target(16666666); // ~60 FPS

        bool running = true;
        while (running) {
            while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
                if (msg.message == WM_QUIT) {
                    running = false;
                    break;
                }

                if (msg.message == WM_HOTKEY && g_lua) {
                    std::lock_guard<std::mutex> lock(g_lua_mutex);
                    sol::protected_function on_hotkey = (*g_lua)["Quire"]["on_hotkey"];
                    if (on_hotkey.valid()) on_hotkey(static_cast<int>(msg.wParam));
                }
                TranslateMessage(&msg);
                DispatchMessageA(&msg);
            }
            if (!running) break;

            auto now = clock::now();
            if (now - last_frame < frame_target) {
                Sleep(1);
                continue;
            }
            last_frame = now;

            if (IsWindowVisible(g_overlay_hwnd)) {
                g_current_renderer = &g_renderer;
                g_renderer.begin_draw();
                g_renderer.clear(0, 0, 0, 0);

                if (g_lua) {
                    std::lock_guard<std::mutex> lock(g_lua_mutex);
                    sol::protected_function render = (*g_lua)["Quire"]["on_render_overlay"];
                    if (render.valid()) render();
                }

                g_renderer.end_draw();
            }
        }

        // Cleanup
        UnhookWinEvent(hook_objects);
        UnhookWinEvent(hook_focus);
        UnhookWinEvent(hook_minimize);
        CleanupAltTabHook();
        RestoreAllWindows();

    } catch (const std::exception& e) {
        std::cerr << "FATAL: " << e.what() << std::endl;
        RestoreAllWindows();
        return 1;
    }

    return 0;
}
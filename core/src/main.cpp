#ifndef NOMINMAX
#define NOMINMAX
#endif

#ifdef NDEBUG
#pragma comment(linker, "/SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup")
#endif

#define SOL_ALL_SAFETIES_ON 1
#define WM_QUIRE_IPC (WM_USER + 500)
#define WM_QUIRE_ALTTAB (WM_USER + 501)
#define WM_QUIRE_RELOAD (WM_USER + 504)
#define WM_QUIRE_TRAY (WM_USER + 505)

#define ID_TRAY_EXIT 1001
#define ID_TRAY_OPEN_CONFIG 1002
#define ID_TRAY_RELOAD_CONFIG 1003
#define ID_TRAY_SAVE_SESSION 1005
#define ID_TRAY_RESTORE_SESSION 1006
#define ID_TRAY_APP_BASE 2000

#include "../include/alttab.hpp"
#include "../include/renderer.hpp"
#include <chrono>
#include <dwmapi.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mutex>
#include <shellapi.h>
#include <shlobj.h>
#include <string>
#include <thread>
#include <timeapi.h>
#include <vector>
#include <windows.h>
#include <windowsx.h>
#include <unordered_set>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#include <sol/sol.hpp>

sol::state *g_lua = nullptr;
std::recursive_mutex g_lua_mutex;
Renderer g_renderer;
HWND g_overlay_hwnd = NULL;
namespace fs = std::filesystem;
std::vector<int> g_registered_hotkeys;
NOTIFYICONDATAA g_nid = {};
bool g_running = true;
int g_target_fps = 100;

static std::unordered_set<HWND> g_managed_hwnds;
static std::mutex g_managed_mutex;

Renderer *g_current_renderer = nullptr;

static HHOOK g_mouse_hook = nullptr;
static HHOOK g_input_hook = nullptr;
static bool g_input_capture = false;

struct AppMenuItem {
    std::string name;
    std::string path;
};
std::vector<AppMenuItem> g_tray_apps;

struct IPCMessage {
    const char *request;
    std::string response;
};

void CallLuaExitCleanup();
void RestoreAllWindows();

static std::string GetWindowTextUtf8(HWND hwnd) {
    if (!IsWindow(hwnd))
        return "";
    int len = GetWindowTextLengthW(hwnd);
    if (len <= 0)
        return "";
    std::wstring wbuf(len + 1, L'\0');
    GetWindowTextW(hwnd, wbuf.data(), len + 1);
    wbuf.resize(len);

    int utf8_len = WideCharToMultiByte(CP_UTF8, 0, wbuf.data(), len, nullptr, 0, nullptr, nullptr);
    if (utf8_len <= 0)
        return "";
    std::string utf8_str(utf8_len, '\0');
    WideCharToMultiByte(CP_UTF8, 0, wbuf.data(), len, utf8_str.data(), utf8_len, nullptr, nullptr);
    return utf8_str;
}

static void TrackManagedWindow(HWND hwnd) {
    if (IsWindow(hwnd)) {
        std::lock_guard<std::mutex> lock(g_managed_mutex);
        g_managed_hwnds.insert(hwnd);
    }
}

static void UntrackManagedWindow(HWND hwnd) {
    std::lock_guard<std::mutex> lock(g_managed_mutex);
    g_managed_hwnds.erase(hwnd);
}

int DetectMonitorRefreshRate() {
    DEVMODEA dm = {};
    dm.dmSize = sizeof(dm);
    if (EnumDisplaySettingsA(NULL, ENUM_CURRENT_SETTINGS, &dm) && dm.dmDisplayFrequency > 1) {
        return static_cast<int>(dm.dmDisplayFrequency);
    }
    return 60;
}

void UpdateTargetFps() {
    int rate = DetectMonitorRefreshRate();
    if (g_lua) {
        std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
        sol::object obj = (*g_lua)["Quire"]["config"]["fps_cap"];
        if (obj.is<int>()) {
            int val = obj.as<int>();
            if (val > 0)
                rate = val;
        }
    }
    g_target_fps = rate;
}

void ShowTrayMenu(HWND hwnd) {
    POINT pt;
    GetCursorPos(&pt);
    SetForegroundWindow(hwnd);

    HMENU hMenu = CreatePopupMenu();
    HMENU hSubMenu = CreatePopupMenu();

    g_tray_apps.clear();
    if (g_lua) {
        std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
        sol::table apps = (*g_lua)["Quire"]["apps"];
        if (apps.valid()) {
            for (size_t i = 1; i <= apps.size(); ++i) {
                sol::table app = apps[i];
                if (app.valid()) {
                    std::string name = app["name"].get_or(std::string("Application"));
                    std::string path = app["path"].get_or(std::string(""));
                    g_tray_apps.push_back({name, path});
                    AppendMenuA(hSubMenu, MF_STRING, ID_TRAY_APP_BASE + i - 1, name.c_str());
                }
            }
        }
    }

    if (g_tray_apps.empty()) {
        AppendMenuA(hSubMenu, MF_GRAYED, 0, "No apps configured");
    }

    AppendMenuA(hMenu, MF_POPUP, reinterpret_cast<UINT_PTR>(hSubMenu), "Launcher");
    AppendMenuA(hMenu, MF_SEPARATOR, 0, NULL);
    AppendMenuA(hMenu, MF_STRING, ID_TRAY_OPEN_CONFIG, "Open config.lua");
    AppendMenuA(hMenu, MF_STRING, ID_TRAY_RELOAD_CONFIG, "Reload Config");
    AppendMenuA(hMenu, MF_SEPARATOR, 0, NULL);
    AppendMenuA(hMenu, MF_STRING, ID_TRAY_SAVE_SESSION, "Save Window Positions");
    AppendMenuA(hMenu, MF_STRING, ID_TRAY_RESTORE_SESSION, "Restore Window Positions");
    AppendMenuA(hMenu, MF_SEPARATOR, 0, NULL);
    AppendMenuA(hMenu, MF_STRING, ID_TRAY_EXIT, "Quit QuireTWM (Restore Windows)");

    int cmd = TrackPopupMenu(hMenu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                            pt.x, pt.y, 0, hwnd, NULL);
    PostMessageA(hwnd, WM_NULL, 0, 0);

    DestroyMenu(hSubMenu);
    DestroyMenu(hMenu);

    if (cmd == ID_TRAY_EXIT) {
        CallLuaExitCleanup();
        RestoreAllWindows();
        g_running = false;
        PostQuitMessage(0);
    } else if (cmd == ID_TRAY_OPEN_CONFIG) {
        char szPath[MAX_PATH];
        if (SUCCEEDED(SHGetFolderPathA(NULL, CSIDL_PROFILE, NULL, 0, szPath))) {
            std::string cfg = std::string(szPath) + "\\.quire\\config.lua";
            ShellExecuteA(NULL, "open", cfg.c_str(), NULL, NULL, SW_SHOWNORMAL);
        }
    } else if (cmd == ID_TRAY_RELOAD_CONFIG) {
        PostMessageA(hwnd, WM_QUIRE_RELOAD, 0, 0);
    } else if (cmd >= ID_TRAY_APP_BASE && cmd < ID_TRAY_APP_BASE + static_cast<int>(g_tray_apps.size())) {
        size_t idx = cmd - ID_TRAY_APP_BASE;
        ShellExecuteA(NULL, "open", g_tray_apps[idx].path.c_str(), NULL, NULL, SW_SHOWNORMAL);
    } else if (cmd == ID_TRAY_SAVE_SESSION) {
        if (g_lua) {
            std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
            sol::protected_function fn = (*g_lua)["Quire"]["save_session"];
            if (fn.valid())
                fn();
        }
    } else if (cmd == ID_TRAY_RESTORE_SESSION) {
        if (g_lua) {
            std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
            sol::protected_function fn = (*g_lua)["Quire"]["restore_session"];
            if (fn.valid())
                fn();
        }
    }
}

LRESULT CALLBACK OverlayWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_QUIRE_TRAY: {
        if (lParam == WM_RBUTTONUP || lParam == WM_LBUTTONUP) {
            ShowTrayMenu(hwnd);
        }
        return 0;
    }
    case WM_QUIRE_RELOAD: {
        if (!g_lua)
            return 0;
        std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
        sol::protected_function fn = (*g_lua)["Quire"]["reload_config"];
        if (fn.valid())
            fn();
        UpdateTargetFps();
        return 0;
    }
    case WM_QUIRE_ALTTAB: {
        if (!g_lua)
            return 0;
        std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
        sol::protected_function fn = (*g_lua)["Quire"]["on_alttab_action"];
        if (fn.valid()) {
            const char *act = (wParam == 3) ? "cancel" : ((wParam == 2) ? "commit" : ((wParam == 1) ? "prev" : "next"));
            fn(act);
        }
        return 0;
    }
    case WM_QUIRE_IPC: {
        auto *ipcm = reinterpret_cast<IPCMessage *>(lParam);
        if (ipcm && g_lua) {
            std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
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
    case WM_DISPLAYCHANGE: {
        UpdateTargetFps();
        int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
        int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
        int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
        int vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);
        SetWindowPos(hwnd, HWND_TOPMOST, vx, vy, vw, vh, SWP_NOACTIVATE);
        g_renderer.init(hwnd);
        return 0;
    }
    case WM_DPICHANGED: {
        int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
        int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
        int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
        int vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);
        SetWindowPos(hwnd, HWND_TOPMOST, vx, vy, vw, vh, SWP_NOACTIVATE);
        g_renderer.init(hwnd);
        return 0;
    }
    default:
        return DefWindowProcA(hwnd, msg, wParam, lParam);
    }
}

static LRESULT CALLBACK MouseProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode != HC_ACTION || (wParam != WM_MOUSEWHEEL && wParam != WM_MOUSEHWHEEL) || !g_lua) {
        return CallNextHookEx(g_mouse_hook, nCode, wParam, lParam);
    }

    auto *ms = reinterpret_cast<MSLLHOOKSTRUCT *>(lParam);
    float dx = 0.0f;
    float dy = 0.0f;
    short raw = static_cast<short>(HIWORD(ms->mouseData));

    bool shift = (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
    bool alt = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
    bool ctrl = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;

    if (wParam == WM_MOUSEHWHEEL) {
        dx = static_cast<float>(raw);
    } else if (wParam == WM_MOUSEWHEEL) {
        if (shift) {
            dx = static_cast<float>(raw);
        } else {
            dy = static_cast<float>(raw);
        }
    }

    if (dx != 0.0f || dy != 0.0f) {
        std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
        if (g_lua) {
            sol::protected_function fn = (*g_lua)["Quire"]["on_trackpad_scroll"];
            if (fn.valid()) {
                auto res = fn(dx, dy, ctrl, alt);
                if (res.valid() && res.get<bool>()) {
                    return 1;
                }
            }
        }
    }

    return CallNextHookEx(g_mouse_hook, nCode, wParam, lParam);
}

static LRESULT CALLBACK InputKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode != HC_ACTION || !g_input_capture || !g_lua) {
        return CallNextHookEx(g_input_hook, nCode, wParam, lParam);
    }

    auto *kbd = reinterpret_cast<KBDLLHOOKSTRUCT *>(lParam);
    if (kbd->flags & LLKHF_INJECTED) {
        return CallNextHookEx(g_input_hook, nCode, wParam, lParam);
    }

    if (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) {
        DWORD vk = kbd->vkCode;
        BYTE kbdState[256];
        GetKeyboardState(kbdState);

        WCHAR unicodeChar[4] = {0};
        int res = ToUnicode(vk, kbd->scanCode, kbdState, unicodeChar, 4, 0);

        std::string utf8_char;
        if (res > 0) {
            int ulen = WideCharToMultiByte(CP_UTF8, 0, unicodeChar, res, nullptr, 0, nullptr, nullptr);
            if (ulen > 0) {
                utf8_char.resize(ulen);
                WideCharToMultiByte(CP_UTF8, 0, unicodeChar, res, utf8_char.data(), ulen, nullptr, nullptr);
            }
        }

        std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
        if (g_lua) {
            sol::protected_function fn = (*g_lua)["Quire"]["on_keyboard_input"];
            if (fn.valid()) {
                auto ret = fn(static_cast<int>(vk), utf8_char);
                if (ret.valid() && ret.get<bool>()) {
                    return 1;
                }
            }
        }
    }

    return CallNextHookEx(g_input_hook, nCode, wParam, lParam);
}

bool IsGameFullscreenActive() {
    HWND fg = GetForegroundWindow();
    if (!fg || fg == g_overlay_hwnd)
        return false;

    DWORD pid = 0;
    GetWindowThreadProcessId(fg, &pid);
    if (pid == GetCurrentProcessId())
        return false;

    RECT rc;
    GetWindowRect(fg, &rc);
    int sw = GetSystemMetrics(SM_CXSCREEN);
    int sh = GetSystemMetrics(SM_CYSCREEN);

    if (rc.left <= 0 && rc.top <= 0 && rc.right >= sw && rc.bottom >= sh) {
        if (g_lua) {
            std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
            sol::protected_function is_tiled = (*g_lua)["Quire"]["is_tiled"];
            if (is_tiled.valid()) {
                auto res = is_tiled(reinterpret_cast<size_t>(fg));
                if (res.valid() && res.get<bool>()) {
                    return false;
                }
            }
        }
        return true;
    }
    return false;
}

void ConfigWatcherThread(std::string configDir) {
    HANDLE hDir = CreateFileA(configDir.c_str(), FILE_LIST_DIRECTORY,
                              FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    if (hDir == INVALID_HANDLE_VALUE)
        return;

    char buffer[1024];
    DWORD bytesReturned;
    while (ReadDirectoryChangesW(hDir, buffer, sizeof(buffer), FALSE,
                                 FILE_NOTIFY_CHANGE_LAST_WRITE | FILE_NOTIFY_CHANGE_SIZE,
                                 &bytesReturned, NULL, NULL)) {
        Sleep(150);
        if (g_overlay_hwnd && IsWindow(g_overlay_hwnd)) {
            PostMessageA(g_overlay_hwnd, WM_QUIRE_RELOAD, 0, 0);
        }
    }
    CloseHandle(hDir);
}

void IPCServerThread() {
    while (g_running) {
        HANDLE hPipe = CreateNamedPipeA("\\\\.\\pipe\\quire", PIPE_ACCESS_DUPLEX,
                                        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1,
                                        2048, 2048, 0, nullptr);

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

                if (g_overlay_hwnd && IsWindow(g_overlay_hwnd)) {
                    DWORD_PTR res = 0;
                    if (!SendMessageTimeoutA(g_overlay_hwnd, WM_QUIRE_IPC, 0,
                                            reinterpret_cast<LPARAM>(&msg),
                                            SMTO_BLOCK | SMTO_NOTIMEOUTIFNOTHUNG,
                                            1000, &res)) {
                        msg.response = "ERROR: Main thread response timeout";
                    }
                } else {
                    msg.response = "ERROR: Overlay unavailable";
                }

                DWORD bytesWritten = 0;
                WriteFile(hPipe, msg.response.data(), static_cast<DWORD>(msg.response.size()),
                          &bytesWritten, nullptr);
            }
        }
        DisconnectNamedPipe(hPipe);
        CloseHandle(hPipe);
    }
}

bool IsManagedWindow(HWND hwnd) {
    if (!g_lua)
        return false;
    std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
    sol::protected_function fn = (*g_lua)["Quire"]["is_managed"];
    if (fn.valid()) {
        auto res = fn(reinterpret_cast<size_t>(hwnd));
        if (res.valid() && res.get<bool>())
            return true;
    }
    return false;
}

bool IsToplevelWindow(HWND hwnd) {
    if (!IsWindow(hwnd) || hwnd == g_overlay_hwnd)
        return false;

    DWORD pid;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == GetCurrentProcessId() || !IsWindowVisible(hwnd))
        return false;

    LONG ex_style = GetWindowLong(hwnd, GWL_EXSTYLE);
    LONG style = GetWindowLong(hwnd, GWL_STYLE);
    HWND owner = GetWindow(hwnd, GW_OWNER);

    if (ex_style & WS_EX_TOOLWINDOW)
        return false;

    if (owner != NULL || (style & WS_CHILD))
        return false;

    bool managed = IsManagedWindow(hwnd);
    if ((ex_style & WS_EX_TOPMOST) && !managed)
        return false;

    int cloaked = 0;
    if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) &&
        cloaked != 0 && !managed)
        return false;

    if ((style & WS_POPUP) && !(style & WS_CAPTION)) {
        RECT rc;
        GetWindowRect(hwnd, &rc);
        if (rc.left <= 0 && rc.top <= 0 &&
            rc.right >= GetSystemMetrics(SM_CXSCREEN) &&
            rc.bottom >= GetSystemMetrics(SM_CYSCREEN))
            return false;
    }

    if (ex_style & WS_EX_APPWINDOW)
        return true;

    RECT rc;
    GetWindowRect(hwnd, &rc);
    return (rc.right - rc.left) > 150 && (rc.bottom - rc.top) > 100;
}

void CallLuaExitCleanup() {
    if (g_lua) {
        std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
        sol::protected_function fn = (*g_lua)["Quire"]["cleanup_for_exit"];
        if (fn.valid()) {
            fn();
        }
    }
}

void RestoreAllWindows() {
    CallLuaExitCleanup();

    std::vector<HWND> to_restore;
    {
        std::lock_guard<std::mutex> lock(g_managed_mutex);
        to_restore.assign(g_managed_hwnds.begin(), g_managed_hwnds.end());
        g_managed_hwnds.clear();
    }

    RECT wa = {0};
    int sw = GetSystemMetrics(SM_CXSCREEN);
    int sh = GetSystemMetrics(SM_CYSCREEN);

    if (!SystemParametersInfoA(SPI_GETWORKAREA, 0, &wa, 0)) {
        wa.left = 0;
        wa.top = 0;
        wa.right = sw;
        wa.bottom = sh;
    }

    int offset = 0;

    for (HWND hwnd : to_restore) {
        if (!IsWindow(hwnd))
            continue;

        BOOL false_val = FALSE;
        DwmSetWindowAttribute(hwnd, 13, &false_val, sizeof(false_val));
        int zero = 0;
        DwmSetWindowAttribute(hwnd, DWMWA_CLOAKED, &zero, sizeof(zero));

        LONG ex_style = GetWindowLong(hwnd, GWL_EXSTYLE);
        if (ex_style & WS_EX_LAYERED) {
            SetWindowLong(hwnd, GWL_EXSTYLE, ex_style & ~WS_EX_LAYERED);
        }

        RECT rc = {0};
        GetWindowRect(hwnd, &rc);
        int cur_w = rc.right - rc.left;
        int cur_h = rc.bottom - rc.top;

        bool is_offscreen = (rc.left < wa.left - 50 || rc.top < wa.top - 50 ||
                             rc.left >= wa.right || rc.top >= wa.bottom ||
                             rc.right <= wa.left + 50 || rc.bottom <= wa.top + 50 ||
                             cur_w < 150 || cur_h < 100);

        if (is_offscreen) {
            int target_w = (wa.right - wa.left > 1200) ? 1100 : (wa.right - wa.left - 100);
            int target_h = (wa.bottom - wa.top > 800) ? 700 : (wa.bottom - wa.top - 100);
            int target_x = wa.left + 80 + offset;
            int target_y = wa.top + 60 + offset;
            offset = (offset + 30) % 240;

            SetWindowPos(hwnd, HWND_NOTOPMOST, target_x, target_y, target_w, target_h,
                         SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
        } else {
            SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
        }
    }
}

BOOL WINAPI ConsoleHandler(DWORD ctrlType) {
    RestoreAllWindows();
    return FALSE;
}

void CALLBACK WinEventProc(HWINEVENTHOOK hWinEventHook, DWORD event, HWND hwnd,
                           LONG idObject, LONG idChild, DWORD dwEventThread,
                           DWORD dwmsEventTime) {
    if (idObject != OBJID_WINDOW || idChild != CHILDID_SELF || hwnd == nullptr)
        return;
    if (event == 0x800B || event == 0x800A)
        return;

    HWND root = GetAncestor(hwnd, GA_ROOT);
    if (root != hwnd)
        return;

    if (event == EVENT_SYSTEM_MOVESIZESTART) {
        LONG ex_style = GetWindowLong(hwnd, GWL_EXSTYLE);
        if (ex_style & WS_EX_TOPMOST)
            return;

        if (g_lua) {
            std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
            sol::protected_function is_tiled = (*g_lua)["Quire"]["is_tiled"];
            if (is_tiled.valid()) {
                auto res = is_tiled(reinterpret_cast<size_t>(hwnd));
                if (res.valid() && res.get<bool>()) {
                    PostMessageA(hwnd, WM_CANCELMODE, 0, 0);
                }
            }
        }
        return;
    }

    bool is_removal = (event == EVENT_OBJECT_DESTROY || event == EVENT_SYSTEM_MINIMIZESTART);
    if (!is_removal) {
        if (!IsWindowVisible(hwnd) || !IsToplevelWindow(hwnd))
            return;
    }

    if (g_lua) {
        std::string title = GetWindowTextUtf8(hwnd);
        std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
        sol::protected_function dispatcher = (*g_lua)["Quire"]["dispatch_event"];
        if (dispatcher.valid()) {
            dispatcher(event, reinterpret_cast<size_t>(hwnd), title);
        }
    }
}

std::string GetConfigDirectory() {
    char szPath[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathA(NULL, CSIDL_PROFILE, NULL, 0, szPath))) {
        fs::path configDir = fs::path(szPath) / ".quire";
        if (!fs::exists(configDir)) {
            fs::create_directories(configDir);
        }
        return configDir.string();
    }
    return ".";
}

int main() {
    SystemParametersInfoA(SPI_SETFOREGROUNDLOCKTIMEOUT, 0, NULL, 0);
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    timeBeginPeriod(1);
    try {
        SetConsoleCtrlHandler(ConsoleHandler, TRUE);
        atexit(RestoreAllWindows);

        std::cout << "=== QuireTWM: Initializing ===" << std::endl;
        std::string configDir = GetConfigDirectory();
        std::string configPath = configDir + "\\config.lua";

        sol::state lua;
        g_lua = &lua;

        lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::string,
                           sol::lib::math, sol::lib::table, sol::lib::os,
                           sol::lib::io, sol::lib::debug, sol::lib::utf8);

        lua["os"]["execute"] = sol::nil;
        lua["os"]["remove"] = sol::nil;
        lua["os"]["rename"] = sol::nil;
        lua["os"]["tmpname"] = sol::nil;
        lua["io"]["popen"] = sol::nil;
        lua["package"]["loadlib"] = sol::nil;

        lua.set_function("log", [](std::string message) {
            std::cout << "[Quire]: " << message << std::endl;
        });

        auto wm = lua.create_named_table("wm");

        wm.set_function("get_class_name", [](size_t hwnd) {
            char class_name[256] = {0};
            GetClassNameA(reinterpret_cast<HWND>(hwnd), class_name, sizeof(class_name));
            return std::string(class_name);
        });

        wm.set_function("get_process_name", [](size_t hwnd) {
            DWORD pid = 0;
            GetWindowThreadProcessId(reinterpret_cast<HWND>(hwnd), &pid);
            if (pid == 0)
                return std::string("");

            HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
            if (hProcess) {
                char path[MAX_PATH];
                DWORD size = MAX_PATH;
                if (QueryFullProcessImageNameA(hProcess, 0, path, &size)) {
                    CloseHandle(hProcess);
                    std::string fullPath(path);
                    return fullPath.substr(fullPath.find_last_of("\\/") + 1);
                }
                CloseHandle(hProcess);
            }
            return std::string("");
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

        wm.set_function("set_topmost", [](size_t hwnd, bool topmost) {
            HWND handle = reinterpret_cast<HWND>(hwnd);
            if (!IsWindow(handle))
                return;
            SetWindowPos(handle, topmost ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
        });

        wm.set_function("close_window", [](size_t hwnd) {
            HWND handle = reinterpret_cast<HWND>(hwnd);
            if (!IsWindow(handle))
                return;
            SetWindowPos(handle, HWND_NOTOPMOST, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
            PostMessage(handle, WM_CLOSE, 0, 0);
        });

        wm.set_function("get_window_title", [](size_t hwnd) {
            return GetWindowTextUtf8(reinterpret_cast<HWND>(hwnd));
        });

        wm.set_function("is_toplevel", [](size_t hwnd) {
            return IsToplevelWindow(reinterpret_cast<HWND>(hwnd));
        });

        wm.set_function("get_foreground_window", []() {
            return reinterpret_cast<size_t>(GetForegroundWindow());
        });

        wm.set_function("spawn", [](std::string command) {
            ShellExecuteA(NULL, "open", command.c_str(), NULL, NULL, SW_SHOWNORMAL);
        });

        wm.set_function("create_thumbnail", [](size_t src_hwnd) {
            return CreateDwmThumbnail(g_overlay_hwnd, reinterpret_cast<HWND>(src_hwnd));
        });

        wm.set_function("update_thumbnail", [](size_t thumb_id, int x, int y, int w, int h, int opacity) {
            BYTE alpha = static_cast<BYTE>(opacity < 0 ? 0 : (opacity > 255 ? 255 : opacity));
            UpdateDwmThumbnail(thumb_id, x, y, w, h, alpha);
        });

        wm.set_function("destroy_thumbnail", [](size_t thumb_id) {
            DestroyDwmThumbnail(thumb_id);
        });

        wm.set_function("set_input_capture", [](bool enable) {
            g_input_capture = enable;
        });

        wm.set_function("focus_window", [](size_t hwnd) {
            HWND handle = reinterpret_cast<HWND>(hwnd);
            if (!IsWindow(handle))
                return;

            if (IsIconic(handle))
                ShowWindow(handle, SW_RESTORE);

            HWND fg = GetForegroundWindow();
            if (fg == handle)
                return;

            DWORD fgThread = GetWindowThreadProcessId(fg, NULL);
            DWORD currentThread = GetCurrentThreadId();

            if (fgThread != currentThread && fgThread != 0) {
                AttachThreadInput(currentThread, fgThread, TRUE);
                SetForegroundWindow(handle);
                BringWindowToTop(handle);
                AttachThreadInput(currentThread, fgThread, FALSE);
            } else {
                SetForegroundWindow(handle);
                BringWindowToTop(handle);
            }
        });

        wm.set_function("set_window_opacity", [](size_t hwnd, double opacity) {
            HWND handle = reinterpret_cast<HWND>(hwnd);
            if (!IsWindow(handle))
                return;

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

        wm.set_function("track_window", [](size_t hwnd) {
            TrackManagedWindow(reinterpret_cast<HWND>(hwnd));
        });

        wm.set_function("untrack_window", [](size_t hwnd) {
            UntrackManagedWindow(reinterpret_cast<HWND>(hwnd));
        });

        wm.set_function("move_window", [](size_t hwnd, double x, double y, double w, double h) {
            HWND handle = reinterpret_cast<HWND>(hwnd);
            if (!IsWindow(handle))
                return;

            TrackManagedWindow(handle);

            if (IsZoomed(handle))
                ShowWindow(handle, SW_RESTORE);

            if (x < -10000.0) {
                SetWindowPos(handle, HWND_NOTOPMOST, -20000, -20000, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
                return;
            }

            bool wants_topmost = false;
            if (g_lua) {
                std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
                sol::protected_function is_f = (*g_lua)["Quire"]["is_floating"];
                if (is_f.valid()) {
                    auto res = is_f(hwnd);
                    if (res.valid() && res.get<bool>())
                        wants_topmost = true;
                }
            }

            HWND insertAfter = wants_topmost ? HWND_TOPMOST : HWND_NOTOPMOST;
            bool is_currently_topmost = (GetWindowLong(handle, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;

            RECT windowRect;
            GetWindowRect(handle, &windowRect);

            RECT frameRect = {0};
            int lm = 0, tm = 0, rm = 0, bm = 0;
            if (SUCCEEDED(DwmGetWindowAttribute(handle, DWMWA_EXTENDED_FRAME_BOUNDS, &frameRect, sizeof(RECT)))) {
                lm = frameRect.left - windowRect.left;
                tm = frameRect.top - windowRect.top;
                rm = windowRect.right - frameRect.right;
                bm = windowRect.bottom - frameRect.bottom;
            }

            int cur_x = windowRect.left + lm;
            int cur_y = windowRect.top + tm;
            int cur_w = (windowRect.right - windowRect.left) - lm - rm;
            int cur_h = (windowRect.bottom - windowRect.top) - tm - bm;

            int final_x = static_cast<int>(x) - lm;
            int final_y = static_cast<int>(y) - tm;
            int final_w = static_cast<int>(w) + lm + rm;
            int final_h = static_cast<int>(h) + tm + bm;

            UINT flags = SWP_NOACTIVATE | SWP_NOCOPYBITS | SWP_DEFERERASE;
            bool same_zorder = (wants_topmost == is_currently_topmost);
            if (same_zorder)
                flags |= SWP_NOZORDER;

            bool same_size = (std::abs(cur_w - static_cast<int>(w)) <= 1 &&
                              std::abs(cur_h - static_cast<int>(h)) <= 1);
            if (same_size)
                flags |= SWP_NOSIZE;

            bool same_pos = (std::abs(cur_x - static_cast<int>(x)) <= 1 &&
                             std::abs(cur_y - static_cast<int>(y)) <= 1);
            if (same_pos)
                flags |= SWP_NOMOVE;

            if (same_zorder && same_size && same_pos)
                return;

            SetWindowPos(handle, insertAfter, final_x, final_y, final_w, final_h, flags);
        });

        wm.set_function("move_to_monitor", [](size_t hwnd_val, int dir) {
            HWND hwnd = reinterpret_cast<HWND>(hwnd_val);
            if (!IsWindow(hwnd))
                return;

            struct MonData {
                HMONITOR handle;
                RECT rc;
            };
            std::vector<MonData> mons;

            EnumDisplayMonitors(
                NULL, NULL,
                [](HMONITOR hMon, HDC, LPRECT, LPARAM lp) -> BOOL {
                    auto *list = reinterpret_cast<std::vector<MonData> *>(lp);
                    MONITORINFO mi = {sizeof(MONITORINFO)};
                    if (GetMonitorInfoA(hMon, &mi)) {
                        list->push_back({hMon, mi.rcWork});
                    }
                    return TRUE;
                },
                reinterpret_cast<LPARAM>(&mons));

            if (mons.size() <= 1)
                return;

            HMONITOR currentMon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
            int currentIdx = 0;
            for (size_t i = 0; i < mons.size(); ++i) {
                if (mons[i].handle == currentMon) {
                    currentIdx = static_cast<int>(i);
                    break;
                }
            }

            int targetIdx = (currentIdx + dir + static_cast<int>(mons.size())) % static_cast<int>(mons.size());
            RECT src = mons[currentIdx].rc;
            RECT dst = mons[targetIdx].rc;

            RECT wnd;
            GetWindowRect(hwnd, &wnd);
            int rel_x = wnd.left - src.left;
            int rel_y = wnd.top - src.top;

            SetWindowPos(hwnd, HWND_NOTOPMOST, dst.left + rel_x, dst.top + rel_y, 0, 0,
                         SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER | SWP_FRAMECHANGED);
        });

        wm.set_function("get_screen_size", []() {
            return std::make_pair(GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
        });

        wm.set_function("get_work_area", []() {
            RECT rc;
            if (SystemParametersInfoA(SPI_GETWORKAREA, 0, &rc, 0)) {
                APPBARDATA abd = {sizeof(APPBARDATA)};
                UINT state = static_cast<UINT>(SHAppBarMessage(ABM_GETSTATE, &abd));
                bool isAutoHide = (state & ABS_AUTOHIDE) != 0;

                if (isAutoHide) {
                    HWND hTaskbar = FindWindowA("Shell_TrayWnd", NULL);
                    if (hTaskbar) {
                        RECT rcBar;
                        GetWindowRect(hTaskbar, &rcBar);
                        int screen_h = GetSystemMetrics(SM_CYSCREEN);
                        if (rcBar.top >= screen_h - 100) {
                            rc.bottom = screen_h - 2;
                        }
                    }
                }

                return std::make_tuple(static_cast<int>(rc.left),
                                       static_cast<int>(rc.top),
                                       static_cast<int>(rc.right - rc.left),
                                       static_cast<int>(rc.bottom - rc.top));
            }
            return std::make_tuple(0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
        });

        wm.set_function("get_window_rect", [](size_t hwnd) {
            RECT rect = {0};
            if (SUCCEEDED(DwmGetWindowAttribute(reinterpret_cast<HWND>(hwnd),
                                                DWMWA_EXTENDED_FRAME_BOUNDS,
                                                &rect, sizeof(RECT)))) {
                return std::make_tuple(static_cast<int>(rect.left), static_cast<int>(rect.top),
                                       static_cast<int>(rect.right - rect.left),
                                       static_cast<int>(rect.bottom - rect.top));
            }
            GetWindowRect(reinterpret_cast<HWND>(hwnd), &rect);
            return std::make_tuple(static_cast<int>(rect.left), static_cast<int>(rect.top),
                                   static_cast<int>(rect.right - rect.left),
                                   static_cast<int>(rect.bottom - rect.top));
        });

        wm.set_function("is_window_visible", [](size_t hwnd) {
            if (!IsWindowVisible(reinterpret_cast<HWND>(hwnd)))
                return false;
            int cloaked = 0;
            if (SUCCEEDED(DwmGetWindowAttribute(reinterpret_cast<HWND>(hwnd),
                                                DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) &&
                cloaked != 0) {
                return false;
            }
            return true;
        });

        static auto s_start_time = std::chrono::steady_clock::now();
        wm.set_function("get_time", []() {
            auto now = std::chrono::steady_clock::now();
            return std::chrono::duration<double>(now - s_start_time).count();
        });

        wm.set_function("is_window", [](size_t hwnd) {
            return static_cast<bool>(IsWindow(reinterpret_cast<HWND>(hwnd)));
        });

        wm.set_function("is_minimized", [](size_t hwnd) {
            return static_cast<bool>(IsIconic(reinterpret_cast<HWND>(hwnd)));
        });

        wm.set_function("cloak_window", [](size_t hwnd, bool cloak) {
            HWND handle = reinterpret_cast<HWND>(hwnd);
            if (!IsWindow(handle))
                return;
            BOOL val = cloak ? TRUE : FALSE;
            DwmSetWindowAttribute(handle, 13, &val, sizeof(val));
            int cval = cloak ? 1 : 0;
            DwmSetWindowAttribute(handle, DWMWA_CLOAKED, &cval, sizeof(cval));
            if (!cloak) {
                ShowWindow(handle, SW_SHOWNA);
            }
        });

        wm.set_function("enumerate_windows", []() {
            std::vector<size_t> hwnds;
            EnumWindows(
                [](HWND hwnd, LPARAM lParam) -> BOOL {
                    auto *list = reinterpret_cast<std::vector<size_t> *>(lParam);
                    if (IsWindowVisible(hwnd) && IsToplevelWindow(hwnd)) {
                        int cloaked = 0;
                        if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) &&
                            cloaked != 0) {
                            return TRUE;
                        }
                        list->push_back(reinterpret_cast<size_t>(hwnd));
                    }
                    return TRUE;
                },
                reinterpret_cast<LPARAM>(&hwnds));
            return hwnds;
        });

        wm.set_function("get_config_path", [configPath]() { return configPath; });

        auto ui = lua.create_named_table("ui");
        ui.set_function("draw_rect", [](float x, float y, float w, float h, float r, float g, float b, float a, float th) {
            if (g_current_renderer)
                g_current_renderer->draw_rect(x, y, w, h, r, g, b, a, th);
        });
        ui.set_function("fill_rect", [](float x, float y, float w, float h, float r, float g, float b, float a) {
            if (g_current_renderer)
                g_current_renderer->fill_rect(x, y, w, h, r, g, b, a);
        });
        ui.set_function("draw_rounded_rect", [](float x, float y, float w, float h, float rad, float r, float g, float b, float a, float th) {
            if (g_current_renderer)
                g_current_renderer->draw_rounded_rect(x, y, w, h, rad, r, g, b, a, th);
        });
        ui.set_function("draw_gradient_rounded_rect", [](float x, float y, float w, float h, float rad, float r1, float g1, float b1, float a1, float r2, float g2, float b2, float a2, float angle, float th) {
            if (g_current_renderer)
                g_current_renderer->draw_gradient_rounded_rect(x, y, w, h, rad, r1, g1, b1, a1, r2, g2, b2, a2, angle, th);
        });
        ui.set_function("fill_rounded_rect", [](float x, float y, float w, float h, float rad, float r, float g, float b, float a) {
            if (g_current_renderer)
                g_current_renderer->fill_rounded_rect(x, y, w, h, rad, r, g, b, a);
        });
        ui.set_function("draw_shadow_rounded_rect", [](float x, float y, float w, float h, float rad, float r, float g, float b, float a, float blur, float spread) {
            if (g_current_renderer)
                g_current_renderer->draw_shadow_rounded_rect(x, y, w, h, rad, r, g, b, a, blur, spread);
        });
        ui.set_function("draw_glow_rounded_rect", [](float x, float y, float w, float h, float rad, float r, float g, float b, float a, float intensity, float spread) {
            if (g_current_renderer)
                g_current_renderer->draw_glow_rounded_rect(x, y, w, h, rad, r, g, b, a, intensity, spread);
        });
        ui.set_function("draw_text", [](std::string text, float x, float y, float size, float r, float g, float b, float a, std::string font) {
            if (g_current_renderer)
                g_current_renderer->draw_text(text, x, y, size, r, g, b, a, font);
        });
        ui.set_function("measure_text", [](std::string text, float size, std::string font) {
            if (g_current_renderer)
                return g_current_renderer->measure_text_width(text, size, font);
            return 0.0f;
        });
        ui.set_function("draw_line", [](float x1, float y1, float x2, float y2, float r, float g, float b, float a, float th) {
            if (g_current_renderer)
                g_current_renderer->draw_line(x1, y1, x2, y2, r, g, b, a, th);
        });
        ui.set_function("draw_circle", [](float x, float y, float rad, float r, float g, float b, float a, float th) {
            if (g_current_renderer)
                g_current_renderer->draw_circle(x, y, rad, r, g, b, a, th);
        });
        ui.set_function("fill_circle", [](float x, float y, float rad, float r, float g, float b, float a) {
            if (g_current_renderer)
                g_current_renderer->fill_circle(x, y, rad, r, g, b, a);
        });
        ui.set_function("push_clip", [](float x, float y, float w, float h) {
            if (g_current_renderer)
                g_current_renderer->push_clip(x, y, w, h);
        });
        ui.set_function("pop_clip", []() {
            if (g_current_renderer)
                g_current_renderer->pop_clip();
        });

        WNDCLASSEXA wc = {sizeof(WNDCLASSEXA),
                          CS_HREDRAW | CS_VREDRAW,
                          OverlayWndProc,
                          0,
                          0,
                          GetModuleHandle(NULL),
                          NULL,
                          NULL,
                          reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)),
                          NULL,
                          "QuireOverlay",
                          NULL};
        RegisterClassExA(&wc);

        int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
        int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
        int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
        int vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);

        HWND overlay_hwnd =
            CreateWindowExA(WS_EX_TOPMOST | WS_EX_TRANSPARENT | WS_EX_LAYERED |
                                WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                            "QuireOverlay", "QuireOverlay", WS_POPUP, vx, vy,
                            (vw > 0 ? vw : GetSystemMetrics(SM_CXSCREEN)),
                            (vh > 0 ? vh : GetSystemMetrics(SM_CYSCREEN)), NULL,
                            NULL, wc.hInstance, NULL);

        g_mouse_hook = SetWindowsHookExA(WH_MOUSE_LL, MouseProc, GetModuleHandleA(NULL), 0);
        g_input_hook = SetWindowsHookExA(WH_KEYBOARD_LL, InputKeyboardProc, GetModuleHandleA(NULL), 0);
        g_overlay_hwnd = overlay_hwnd;
        SetLayeredWindowAttributes(overlay_hwnd, 0, 255, LWA_ALPHA);

        MARGINS margins = {-1};
        DwmExtendFrameIntoClientArea(overlay_hwnd, &margins);

        if (!g_renderer.init(overlay_hwnd)) {
            std::cerr << "Quire: Failed to initialize Renderer!" << std::endl;
            return -1;
        }

        ShowWindow(overlay_hwnd, SW_SHOW);
        SetWindowPos(overlay_hwnd, HWND_TOPMOST, vx, vy, vw, vh, SWP_NOACTIVATE | SWP_SHOWWINDOW);

        g_nid.cbSize = sizeof(NOTIFYICONDATAA);
        g_nid.hWnd = overlay_hwnd;
        g_nid.uID = 1;
        g_nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        g_nid.uCallbackMessage = WM_QUIRE_TRAY;
        g_nid.hIcon = reinterpret_cast<HICON>(
            LoadImageA(GetModuleHandle(NULL), MAKEINTRESOURCEA(1), IMAGE_ICON,
                       GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR));
        if (!g_nid.hIcon) {
            g_nid.hIcon = LoadIcon(NULL, IDI_APPLICATION);
        }
        strcpy_s(g_nid.szTip, "QuireTWM");
        Shell_NotifyIconA(NIM_ADD, &g_nid);

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

        UpdateTargetFps();

        HWINEVENTHOOK hook_objects =
            SetWinEventHook(EVENT_OBJECT_CREATE, EVENT_OBJECT_NAMECHANGE, NULL,
                            WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);
        HWINEVENTHOOK hook_focus =
            SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
                            NULL, WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);
        HWINEVENTHOOK hook_minimize = SetWinEventHook(
            EVENT_SYSTEM_MINIMIZESTART, EVENT_SYSTEM_MINIMIZEEND, NULL,
            WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);
        HWINEVENTHOOK hook_movesize = SetWinEventHook(
            EVENT_SYSTEM_MOVESIZESTART, EVENT_SYSTEM_MOVESIZEEND, NULL,
            WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);

        if (!hook_objects || !hook_focus || !hook_minimize || !hook_movesize) {
            std::cerr << "Quire: Failed to register WinEventHooks!" << std::endl;
            return 1;
        }

        InitializeAltTabHook();
        std::thread(IPCServerThread).detach();
        std::thread(ConfigWatcherThread, configDir).detach();

        MSG msg;
        using clock = std::chrono::steady_clock;
        auto next_frame = clock::now();

        while (g_running) {
            while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
                if (msg.message == WM_QUIT) {
                    g_running = false;
                    break;
                }

                if (msg.message == WM_HOTKEY) {
                    std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
                    if (g_lua) {
                        sol::protected_function on_hotkey = (*g_lua)["Quire"]["on_hotkey"];
                        if (on_hotkey.valid()) {
                            auto res = on_hotkey(static_cast<int>(msg.wParam));
                            if (!res.valid()) {
                                sol::error err = res;
                                std::cerr << "[Quire Hotkey Error]: " << err.what() << std::endl;
                            }
                        }
                    }
                }
                TranslateMessage(&msg);
                DispatchMessageA(&msg);
            }
            if (!g_running)
                break;

            bool is_game = IsGameFullscreenActive();

            if (is_game) {
                if (g_mouse_hook) {
                    UnhookWindowsHookEx(g_mouse_hook);
                    g_mouse_hook = nullptr;
                }
                if (IsWindowVisible(g_overlay_hwnd)) {
                    ShowWindow(g_overlay_hwnd, SW_HIDE);
                }
                Sleep(16);
                continue;
            } else {
                if (!g_mouse_hook) {
                    g_mouse_hook = SetWindowsHookExA(WH_MOUSE_LL, MouseProc, GetModuleHandleA(NULL), 0);
                }
                if (!IsWindowVisible(g_overlay_hwnd)) {
                    ShowWindow(g_overlay_hwnd, SW_SHOW);
                    SetWindowPos(g_overlay_hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
                }
            }

            static POINT s_last_mouse_pos = {0, 0};
            POINT cur_pt;
            if (GetCursorPos(&cur_pt)) {
                int dx = std::abs(cur_pt.x - s_last_mouse_pos.x);
                int dy = std::abs(cur_pt.y - s_last_mouse_pos.y);
                if (dx >= 6 || dy >= 6) {
                    s_last_mouse_pos = cur_pt;
                    if (g_lua) {
                        std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
                        if (g_lua) {
                            sol::protected_function fn = (*g_lua)["Quire"]["on_mouse_move"];
                            if (fn.valid())
                                fn(cur_pt.x, cur_pt.y);
                        }
                    }
                }
            }

            int fps = g_target_fps > 0 ? g_target_fps : 100;
            auto frame_duration = std::chrono::nanoseconds(1000000000LL / fps);

            auto now = clock::now();
            if (now < next_frame) {
                auto diff = std::chrono::duration_cast<std::chrono::milliseconds>(next_frame - now);
                if (diff.count() > 1) {
                    Sleep(static_cast<DWORD>(diff.count() - 1));
                }
                while (clock::now() < next_frame) {
                    YieldProcessor();
                }
            }
            next_frame = clock::now() + frame_duration;

            if (IsWindowVisible(g_overlay_hwnd)) {
                g_current_renderer = &g_renderer;
                g_renderer.begin_draw();
                g_renderer.clear(0, 0, 0, 0);

                if (g_lua) {
                    std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
                    if (g_lua) {
                        sol::protected_function render = (*g_lua)["Quire"]["on_render_overlay"];
                        if (render.valid()) {
                            auto res = render();
                            if (!res.valid()) {
                                sol::error err = res;
                                std::cerr << "[Quire Render Error]: " << err.what() << std::endl;
                            }
                        }
                    }
                }

                g_renderer.end_draw();
            }
        }

        {
            std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
            g_lua = nullptr;
        }

        Shell_NotifyIconA(NIM_DELETE, &g_nid);
        UnhookWinEvent(hook_objects);
        UnhookWinEvent(hook_focus);
        UnhookWinEvent(hook_minimize);
        UnhookWinEvent(hook_movesize);
        if (g_mouse_hook)
            UnhookWindowsHookEx(g_mouse_hook);
        if (g_input_hook)
            UnhookWindowsHookEx(g_input_hook);

        CleanupAltTabHook();
        RestoreAllWindows();

        if (g_overlay_hwnd && IsWindow(g_overlay_hwnd)) {
            DestroyWindow(g_overlay_hwnd);
            g_overlay_hwnd = NULL;
        }
        UnregisterClassA("QuireOverlay", wc.hInstance);

        g_renderer.shutdown();
        g_current_renderer = nullptr;

    } catch (const std::exception &e) {
        std::cerr << "FATAL: " << e.what() << std::endl;
        {
            std::lock_guard<std::recursive_mutex> lock(g_lua_mutex);
            g_lua = nullptr;
        }
        Shell_NotifyIconA(NIM_DELETE, &g_nid);
        RestoreAllWindows();
        if (g_overlay_hwnd && IsWindow(g_overlay_hwnd)) {
            DestroyWindow(g_overlay_hwnd);
            g_overlay_hwnd = NULL;
        }
        g_renderer.shutdown();
        g_current_renderer = nullptr;
        timeEndPeriod(1);
        CoUninitialize();
        return 1;
    }
    timeEndPeriod(1);
    CoUninitialize();
    return 0;
}
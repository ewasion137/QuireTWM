#include "../include/alttab.hpp"
#include <dwmapi.h>

#define WM_QUIRE_ALTTAB (WM_USER + 501)

extern HWND g_overlay_hwnd;

static HHOOK g_keyboard_hook = nullptr;
static bool g_alttab_active = false;

static LRESULT CALLBACK KeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode != HC_ACTION) {
        return CallNextHookEx(g_keyboard_hook, nCode, wParam, lParam);
    }

    auto *kbd = reinterpret_cast<KBDLLHOOKSTRUCT *>(lParam);
    if (kbd->flags & LLKHF_INJECTED) {
        return CallNextHookEx(g_keyboard_hook, nCode, wParam, lParam);
    }

    bool alt_down = (kbd->flags & LLKHF_ALTDOWN) || ((GetKeyState(VK_MENU) & 0x8000) != 0);

    if (kbd->vkCode == VK_TAB && alt_down) {
        if (wParam == WM_SYSKEYDOWN || wParam == WM_KEYDOWN) {
            g_alttab_active = true;
            bool shift_down = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
            if (g_overlay_hwnd && IsWindow(g_overlay_hwnd)) {
                PostMessageA(g_overlay_hwnd, WM_QUIRE_ALTTAB, shift_down ? 1 : 0, 0);
            }
            return 1;
        }
    }

    if (g_alttab_active) {
        if (kbd->vkCode == VK_RIGHT && (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN)) {
            PostMessageA(g_overlay_hwnd, WM_QUIRE_ALTTAB, 0, 0);
            return 1;
        }
        if (kbd->vkCode == VK_LEFT && (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN)) {
            PostMessageA(g_overlay_hwnd, WM_QUIRE_ALTTAB, 1, 0);
            return 1;
        }
        if (kbd->vkCode == VK_ESCAPE && (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN)) {
            g_alttab_active = false;
            if (g_overlay_hwnd && IsWindow(g_overlay_hwnd)) {
                PostMessageA(g_overlay_hwnd, WM_QUIRE_ALTTAB, 3, 0);
            }
            return 1;
        }
    }

    if ((kbd->vkCode == VK_MENU || kbd->vkCode == VK_LMENU || kbd->vkCode == VK_RMENU) && g_alttab_active) {
        if (wParam == WM_KEYUP || wParam == WM_SYSKEYUP) {
            g_alttab_active = false;
            if (g_overlay_hwnd && IsWindow(g_overlay_hwnd)) {
                PostMessageA(g_overlay_hwnd, WM_QUIRE_ALTTAB, 2, 0);
            }
        }
    }

    return CallNextHookEx(g_keyboard_hook, nCode, wParam, lParam);
}

bool InitializeAltTabHook() {
    if (g_keyboard_hook)
        return true;
    g_keyboard_hook = SetWindowsHookExW(WH_KEYBOARD_LL, KeyboardProc, GetModuleHandleW(nullptr), 0);
    return g_keyboard_hook != nullptr;
}

void CleanupAltTabHook() {
    if (g_keyboard_hook) {
        UnhookWindowsHookEx(g_keyboard_hook);
        g_keyboard_hook = nullptr;
    }
    g_alttab_active = false;
}

size_t CreateDwmThumbnail(HWND dest, HWND src) {
    if (!dest || !src || !IsWindow(dest) || !IsWindow(src))
        return 0;
    HTHUMBNAIL thumb = nullptr;
    if (SUCCEEDED(DwmRegisterThumbnail(dest, src, &thumb))) {
        return reinterpret_cast<size_t>(thumb);
    }
    return 0;
}

void UpdateDwmThumbnail(size_t thumb_id, int x, int y, int w, int h, BYTE opacity) {
    if (!thumb_id)
        return;
    auto thumb = reinterpret_cast<HTHUMBNAIL>(thumb_id);
    DWM_THUMBNAIL_PROPERTIES props = {};
    props.dwFlags = DWM_TNP_RECTDESTINATION | DWM_TNP_VISIBLE | DWM_TNP_OPACITY;
    props.rcDestination = RECT{ x, y, x + w, y + h };
    props.fVisible = TRUE;
    props.opacity = opacity;
    DwmUpdateThumbnailProperties(thumb, &props);
}

void DestroyDwmThumbnail(size_t thumb_id) {
    if (!thumb_id)
        return;
    auto thumb = reinterpret_cast<HTHUMBNAIL>(thumb_id);
    DwmUnregisterThumbnail(thumb);
}
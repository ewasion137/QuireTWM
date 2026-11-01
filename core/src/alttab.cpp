#include "../include/alttab.hpp"

#define WM_HYPRWIN_ALTTAB (WM_USER + 501)

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

    bool alt_down =
        (kbd->flags & LLKHF_ALTDOWN) || ((GetKeyState(VK_MENU) & 0x8000) != 0);

    if (kbd->vkCode == VK_TAB && alt_down) {
        if (wParam == WM_SYSKEYDOWN || wParam == WM_KEYDOWN) {
            g_alttab_active = true;
            bool shift_down = (GetKeyState(VK_SHIFT) & 0x8000) != 0;

            if (g_overlay_hwnd && IsWindow(g_overlay_hwnd)) {
                PostMessageA(g_overlay_hwnd, WM_HYPRWIN_ALTTAB,
                             shift_down ? 1 : 0, 0);
            }
            return 1;
        }
    }

    if (g_alttab_active && kbd->vkCode == VK_ESCAPE) {
        g_alttab_active = false;
        if (g_overlay_hwnd && IsWindow(g_overlay_hwnd)) {
            PostMessageA(g_overlay_hwnd, WM_HYPRWIN_ALTTAB, 3, 0);
        }
        return 1;
    }

    if ((kbd->vkCode == VK_MENU || kbd->vkCode == VK_LMENU ||
         kbd->vkCode == VK_RMENU) &&
        g_alttab_active) {
        if (wParam == WM_KEYUP || wParam == WM_SYSKEYUP) {
            g_alttab_active = false;
            if (g_overlay_hwnd && IsWindow(g_overlay_hwnd)) {
                PostMessageA(g_overlay_hwnd, WM_HYPRWIN_ALTTAB, 2, 0);
            }
        }
    }

    return CallNextHookEx(g_keyboard_hook, nCode, wParam, lParam);
}

bool InitializeAltTabHook() {
    if (g_keyboard_hook)
        return true;
    g_keyboard_hook = SetWindowsHookEx(WH_KEYBOARD_LL, KeyboardProc,
                                       GetModuleHandle(nullptr), 0);
    return g_keyboard_hook != nullptr;
}

void CleanupAltTabHook() {
    if (g_keyboard_hook) {
        UnhookWindowsHookEx(g_keyboard_hook);
        g_keyboard_hook = nullptr;
    }
    g_alttab_active = false;
}
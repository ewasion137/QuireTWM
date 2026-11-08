#include "../include/isle.hpp"
#include <audioclient.h>
#include <audiopolicy.h>
#include <endpointvolume.h>
#include <mmdeviceapi.h>
#include <sol/sol.hpp>
#include <windows.h>

namespace Isle {

static IAudioEndpointVolume *g_endpointVolume = nullptr;
static IMMDeviceEnumerator *g_deviceEnumerator = nullptr;

static ULONGLONG FileTimeToUint64(const FILETIME &ft) {
    ULARGE_INTEGER u;
    u.LowPart = ft.dwLowDateTime;
    u.HighPart = ft.dwHighDateTime;
    return u.QuadPart;
}

void Initialize() {
    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_INPROC_SERVER,
        __uuidof(IMMDeviceEnumerator), reinterpret_cast<void **>(&g_deviceEnumerator));

    if (SUCCEEDED(hr) && g_deviceEnumerator) {
        IMMDevice *defaultDevice = nullptr;
        hr = g_deviceEnumerator->GetDefaultAudioEndpoint(eRender, eConsole, &defaultDevice);
        if (SUCCEEDED(hr) && defaultDevice) {
            defaultDevice->Activate(
                __uuidof(IAudioEndpointVolume), CLSCTX_INPROC_SERVER, nullptr,
                reinterpret_cast<void **>(&g_endpointVolume));
            defaultDevice->Release();
        }
    }
}

void Shutdown() {
    if (g_endpointVolume) {
        g_endpointVolume->Release();
        g_endpointVolume = nullptr;
    }
    if (g_deviceEnumerator) {
        g_deviceEnumerator->Release();
        g_deviceEnumerator = nullptr;
    }
}

float GetMasterVolume() {
    if (!g_endpointVolume)
        return 0.0f;
    float vol = 0.0f;
    g_endpointVolume->GetMasterVolumeLevelScalar(&vol);
    return vol;
}

void SetMasterVolume(float level) {
    if (!g_endpointVolume)
        return;
    float clamped = (level < 0.0f) ? 0.0f : ((level > 1.0f) ? 1.0f : level);
    g_endpointVolume->SetMasterVolumeLevelScalar(clamped, nullptr);
}

bool IsMasterMuted() {
    if (!g_endpointVolume)
        return false;
    BOOL muted = FALSE;
    g_endpointVolume->GetMute(&muted);
    return muted == TRUE;
}

void SetMasterMuted(bool mute) {
    if (!g_endpointVolume)
        return;
    g_endpointVolume->SetMute(mute ? TRUE : FALSE, nullptr);
}

int GetBatteryPercentage() {
    SYSTEM_POWER_STATUS sps;
    if (GetSystemPowerStatus(&sps) && sps.BatteryLifePercent != 255) {
        return static_cast<int>(sps.BatteryLifePercent);
    }
    return -1;
}

bool IsBatteryCharging() {
    SYSTEM_POWER_STATUS sps;
    if (GetSystemPowerStatus(&sps)) {
        return (sps.ACLineStatus == 1);
    }
    return false;
}

bool HasBattery() {
    SYSTEM_POWER_STATUS sps;
    if (GetSystemPowerStatus(&sps)) {
        return (sps.BatteryFlag != 128 && sps.BatteryLifePercent != 255);
    }
    return false;
}

int GetRamUsage() {
    MEMORYSTATUSEX memInfo;
    memInfo.dwLength = sizeof(MEMORYSTATUSEX);
    if (GlobalMemoryStatusEx(&memInfo)) {
        return static_cast<int>(memInfo.dwMemoryLoad);
    }
    return 0;
}

float GetCpuUsage() {
    static FILETIME prevIdleTime = {0, 0};
    static FILETIME prevKernelTime = {0, 0};
    static FILETIME prevUserTime = {0, 0};
    static float lastCalculatedCpu = 0.0f;
    static ULONGLONG lastTick = 0;

    ULONGLONG now = GetTickCount64();
    if (now - lastTick < 400 && lastTick != 0) {
        return lastCalculatedCpu;
    }

    FILETIME idleTime, kernelTime, userTime;
    if (GetSystemTimes(&idleTime, &kernelTime, &userTime)) {
        if (prevIdleTime.dwLowDateTime != 0 || prevIdleTime.dwHighDateTime != 0) {
            ULONGLONG idle = FileTimeToUint64(idleTime) - FileTimeToUint64(prevIdleTime);
            ULONGLONG kernel = FileTimeToUint64(kernelTime) - FileTimeToUint64(prevKernelTime);
            ULONGLONG user = FileTimeToUint64(userTime) - FileTimeToUint64(prevUserTime);
            ULONGLONG total = kernel + user;

            if (total > 0) {
                float usage = static_cast<float>(total - idle) * 100.0f / static_cast<float>(total);
                lastCalculatedCpu = (usage < 0.0f) ? 0.0f : ((usage > 100.0f) ? 100.0f : usage);
            }
        }
        prevIdleTime = idleTime;
        prevKernelTime = kernelTime;
        prevUserTime = userTime;
        lastTick = now;
    }
    return lastCalculatedCpu;
}

void MediaPlayPause() {
    keybd_event(VK_MEDIA_PLAY_PAUSE, 0, 0, 0);
    keybd_event(VK_MEDIA_PLAY_PAUSE, 0, KEYEVENTF_KEYUP, 0);
}

void MediaNext() {
    keybd_event(VK_MEDIA_NEXT_TRACK, 0, 0, 0);
    keybd_event(VK_MEDIA_NEXT_TRACK, 0, KEYEVENTF_KEYUP, 0);
}

void MediaPrev() {
    keybd_event(VK_MEDIA_PREV_TRACK, 0, 0, 0);
    keybd_event(VK_MEDIA_PREV_TRACK, 0, KEYEVENTF_KEYUP, 0);
}

std::string GetActiveMediaTitle() {
    if (!g_deviceEnumerator)
        return "";

    IMMDevice *pDevice = nullptr;
    if (FAILED(g_deviceEnumerator->GetDefaultAudioEndpoint(eRender, eConsole, &pDevice)) || !pDevice)
        return "";

    IAudioSessionManager2 *pSessionManager = nullptr;
    HRESULT hr = pDevice->Activate(
        __uuidof(IAudioSessionManager2), CLSCTX_INPROC_SERVER, nullptr,
        reinterpret_cast<void **>(&pSessionManager));

    if (FAILED(hr) || !pSessionManager) {
        pDevice->Release();
        return "";
    }

    IAudioSessionEnumerator *pSessionEnum = nullptr;
    std::string result = "";

    if (SUCCEEDED(pSessionManager->GetSessionEnumerator(&pSessionEnum)) && pSessionEnum) {
        int count = 0;
        pSessionEnum->GetCount(&count);

        for (int i = 0; i < count; ++i) {
            IAudioSessionControl *pSession = nullptr;
            if (SUCCEEDED(pSessionEnum->GetSession(i, &pSession)) && pSession) {
                AudioSessionState state;
                pSession->GetState(&state);

                if (state == AudioSessionStateActive) {
                    IAudioSessionControl2 *pSession2 = nullptr;
                    if (SUCCEEDED(pSession->QueryInterface(
                            __uuidof(IAudioSessionControl2),
                            reinterpret_cast<void **>(&pSession2))) && pSession2) {
                        DWORD pid = 0;
                        pSession2->GetProcessId(&pid);

                        if (pid != 0 && pid != GetCurrentProcessId()) {
                            struct WindowSearch {
                                DWORD pid;
                                HWND found_hwnd;
                            };
                            WindowSearch search = {pid, nullptr};

                            EnumWindows([](HWND hwnd, LPARAM lp) -> BOOL {
                                auto *s = reinterpret_cast<WindowSearch *>(lp);
                                DWORD wpid = 0;
                                GetWindowThreadProcessId(hwnd, &wpid);
                                if (wpid == s->pid && IsWindowVisible(hwnd)) {
                                    if (GetWindowTextLengthW(hwnd) > 0) {
                                        s->found_hwnd = hwnd;
                                        return FALSE;
                                    }
                                }
                                return TRUE;
                            }, reinterpret_cast<LPARAM>(&search));

                            if (search.found_hwnd) {
                                wchar_t wbuf[512] = {0};
                                GetWindowTextW(search.found_hwnd, wbuf, 511);
                                char ubuf[1024] = {0};
                                WideCharToMultiByte(CP_UTF8, 0, wbuf, -1, ubuf, sizeof(ubuf) - 1, nullptr, nullptr);
                                result = ubuf;
                            }
                        }
                        pSession2->Release();
                    }
                }
                pSession->Release();
                if (!result.empty())
                    break;
            }
        }
        pSessionEnum->Release();
    }

    pSessionManager->Release();
    pDevice->Release();
    return result;
}

void RegisterLuaBindings(sol::state *lua) {
    if (!lua)
        return;

    auto wm = (*lua)["wm"].get_or_create<sol::table>();

    wm.set_function("get_volume", []() { return GetMasterVolume(); });
    wm.set_function("set_volume", [](float val) { SetMasterVolume(val); });
    wm.set_function("is_muted", []() { return IsMasterMuted(); });
    wm.set_function("set_muted", [](bool mute) { SetMasterMuted(mute); });

    wm.set_function("get_battery", [lua]() {
        sol::table t = lua->create_table();
        t["percentage"] = GetBatteryPercentage();
        t["is_charging"] = IsBatteryCharging();
        t["has_battery"] = HasBattery();
        return t;
    });

    wm.set_function("get_cpu_usage", []() { return GetCpuUsage(); });
    wm.set_function("get_ram_usage", []() { return GetRamUsage(); });

    wm.set_function("media_play_pause", []() { MediaPlayPause(); });
    wm.set_function("media_next", []() { MediaNext(); });
    wm.set_function("media_prev", []() { MediaPrev(); });
    wm.set_function("get_media_title", []() { return GetActiveMediaTitle(); });
}

}
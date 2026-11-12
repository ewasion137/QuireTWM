#include "../include/isle.hpp"
#include <atomic>
#include <audioclient.h>
#include <audiopolicy.h>
#include <endpointvolume.h>
#include <mmdeviceapi.h>
#include <mutex>
#include <sol/sol.hpp>
#include <thread>
#include <tlhelp32.h>
#include <windows.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>

#pragma comment(lib, "windowsapp.lib")

namespace Isle {

static IAudioEndpointVolume *g_endpointVolume = nullptr;
static IMMDeviceEnumerator *g_deviceEnumerator = nullptr;
static FILETIME g_prevIdleTime = {0, 0};
static FILETIME g_prevKernelTime = {0, 0};
static FILETIME g_prevUserTime = {0, 0};
static float g_lastCpu = 0.0f;
static ULONGLONG g_lastTick = 0;

static std::thread g_workerThread;
static std::atomic<bool> g_workerRunning{false};
static std::mutex g_mediaMutex;
static std::string g_cachedMediaTitle = "";

static ULONGLONG FileTimeToUint64(const FILETIME &ft) {
    ULARGE_INTEGER u;
    u.LowPart = ft.dwLowDateTime;
    u.HighPart = ft.dwHighDateTime;
    return u.QuadPart;
}

static DWORD GetParentProcessId(DWORD pid) {
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap == INVALID_HANDLE_VALUE)
        return 0;

    PROCESSENTRY32 pe = {sizeof(pe)};
    DWORD ppid = 0;
    if (Process32First(hSnap, &pe)) {
        do {
            if (pe.th32ProcessID == pid) {
                ppid = pe.th32ParentProcessID;
                break;
            }
        } while (Process32Next(hSnap, &pe));
    }
    CloseHandle(hSnap);
    return ppid;
}

static void EnsureAudioEndpoint() {
    if (g_endpointVolume)
        return;

    if (!g_deviceEnumerator) {
        CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                         CLSCTX_INPROC_SERVER, __uuidof(IMMDeviceEnumerator),
                         reinterpret_cast<void **>(&g_deviceEnumerator));
    }

    if (g_deviceEnumerator) {
        IMMDevice *defaultDevice = nullptr;
        if (SUCCEEDED(g_deviceEnumerator->GetDefaultAudioEndpoint(
                eRender, eMultimedia, &defaultDevice)) &&
            defaultDevice) {
            defaultDevice->Activate(
                __uuidof(IAudioEndpointVolume), CLSCTX_INPROC_SERVER, nullptr,
                reinterpret_cast<void **>(&g_endpointVolume));
            defaultDevice->Release();
        }
    }
}

static std::string QueryWinRTMedia() {
    try {
        using namespace winrt::Windows::Media::Control;
        auto op =
            GlobalSystemMediaTransportControlsSessionManager::RequestAsync();
        auto mgr = op.get();
        if (!mgr)
            return "";
        auto session = mgr.GetCurrentSession();
        if (!session)
            return "";
        auto propOp = session.TryGetMediaPropertiesAsync();
        auto props = propOp.get();
        if (!props)
            return "";

        std::wstring title = props.Title().c_str();
        std::wstring artist = props.Artist().c_str();
        if (title.empty())
            return "";

        std::wstring full = artist.empty() ? title : (artist + L" - " + title);
        int len = WideCharToMultiByte(CP_UTF8, 0, full.data(),
                                      static_cast<int>(full.size()), nullptr, 0,
                                      nullptr, nullptr);
        if (len <= 0)
            return "";
        std::string out(len, '\0');
        WideCharToMultiByte(CP_UTF8, 0, full.data(),
                            static_cast<int>(full.size()), out.data(), len,
                            nullptr, nullptr);
        return out;
    } catch (...) {
        return "";
    }
}

static std::string QueryActiveAudioSessionWindow() {
    EnsureAudioEndpoint();
    if (!g_deviceEnumerator)
        return "";

    IMMDevice *pDevice = nullptr;
    if (FAILED(g_deviceEnumerator->GetDefaultAudioEndpoint(eRender, eMultimedia,
                                                           &pDevice)) ||
        !pDevice)
        return "";

    IAudioSessionManager2 *pSessionManager = nullptr;
    HRESULT hr =
        pDevice->Activate(__uuidof(IAudioSessionManager2), CLSCTX_INPROC_SERVER,
                          nullptr, reinterpret_cast<void **>(&pSessionManager));

    if (FAILED(hr) || !pSessionManager) {
        pDevice->Release();
        return "";
    }

    IAudioSessionEnumerator *pSessionEnum = nullptr;
    std::string result = "";

    if (SUCCEEDED(pSessionManager->GetSessionEnumerator(&pSessionEnum)) &&
        pSessionEnum) {
        int count = 0;
        pSessionEnum->GetCount(&count);

        for (int i = 0; i < count; ++i) {
            IAudioSessionControl *pSession = nullptr;
            if (SUCCEEDED(pSessionEnum->GetSession(i, &pSession)) && pSession) {
                AudioSessionState state;
                pSession->GetState(&state);

                if (state == AudioSessionStateActive) {
                    IAudioMeterInformation *pMeter = nullptr;
                    float peak = 0.0f;
                    if (SUCCEEDED(pSession->QueryInterface(
                            __uuidof(IAudioMeterInformation),
                            reinterpret_cast<void **>(&pMeter))) &&
                        pMeter) {
                        pMeter->GetPeakValue(&peak);
                        pMeter->Release();
                    }

                    if (peak > 0.001f) {
                        IAudioSessionControl2 *pSession2 = nullptr;
                        if (SUCCEEDED(pSession->QueryInterface(
                                __uuidof(IAudioSessionControl2),
                                reinterpret_cast<void **>(&pSession2))) &&
                            pSession2) {
                            DWORD pid = 0;
                            pSession2->GetProcessId(&pid);

                            if (pid != 0 && pid != GetCurrentProcessId()) {
                                DWORD pids[2] = {pid, GetParentProcessId(pid)};

                                for (int p_idx = 0; p_idx < 2 && result.empty();
                                     ++p_idx) {
                                    DWORD target_pid = pids[p_idx];
                                    if (target_pid == 0)
                                        continue;

                                    char procName[MAX_PATH] = {0};
                                    HANDLE hP = OpenProcess(
                                        PROCESS_QUERY_LIMITED_INFORMATION,
                                        FALSE, target_pid);
                                    if (hP) {
                                        DWORD sz = MAX_PATH;
                                        QueryFullProcessImageNameA(
                                            hP, 0, procName, &sz);
                                        CloseHandle(hP);
                                    }
                                    std::string pStr = procName;
                                    if (pStr.find("explorer.exe") !=
                                            std::string::npos ||
                                        pStr.find("ShellExperienceHost.exe") !=
                                            std::string::npos) {
                                        continue;
                                    }

                                    struct WindowSearch {
                                        DWORD pid;
                                        HWND found_hwnd;
                                    } search = {target_pid, nullptr};

                                    EnumWindows(
                                        [](HWND hwnd, LPARAM lp) -> BOOL {
                                            auto *s = reinterpret_cast<
                                                WindowSearch *>(lp);
                                            DWORD wpid = 0;
                                            GetWindowThreadProcessId(hwnd,
                                                                     &wpid);
                                            if (wpid == s->pid &&
                                                IsWindowVisible(hwnd)) {
                                                if (GetWindowTextLengthW(hwnd) >
                                                    0) {
                                                    s->found_hwnd = hwnd;
                                                    return FALSE;
                                                }
                                            }
                                            return TRUE;
                                        },
                                        reinterpret_cast<LPARAM>(&search));

                                    if (search.found_hwnd) {
                                        wchar_t wbuf[512] = {0};
                                        GetWindowTextW(search.found_hwnd, wbuf,
                                                       511);
                                        char ubuf[1024] = {0};
                                        WideCharToMultiByte(
                                            CP_UTF8, 0, wbuf, -1, ubuf,
                                            sizeof(ubuf) - 1, nullptr, nullptr);
                                        result = ubuf;
                                    }
                                }
                            }
                            pSession2->Release();
                        }
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

static void MediaWorkerLoop() {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    while (g_workerRunning) {
        std::string title = QueryWinRTMedia();
        if (title.empty()) {
            title = QueryActiveAudioSessionWindow();
        }

        {
            std::lock_guard<std::mutex> lock(g_mediaMutex);
            g_cachedMediaTitle = title;
        }

        for (int i = 0; i < 8 && g_workerRunning; ++i) {
            Sleep(100);
        }
    }
    CoUninitialize();
}

void Initialize() {
    GetSystemTimes(&g_prevIdleTime, &g_prevKernelTime, &g_prevUserTime);
    g_lastTick = GetTickCount64();
    EnsureAudioEndpoint();

    if (!g_workerRunning) {
        g_workerRunning = true;
        g_workerThread = std::thread(MediaWorkerLoop);
    }
}

void Shutdown() {
    if (g_workerRunning) {
        g_workerRunning = false;
        if (g_workerThread.joinable()) {
            g_workerThread.join();
        }
    }

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
    EnsureAudioEndpoint();
    if (!g_endpointVolume)
        return 0.5f;
    float vol = 0.5f;
    g_endpointVolume->GetMasterVolumeLevelScalar(&vol);
    return vol;
}

void SetMasterVolume(float level) {
    EnsureAudioEndpoint();
    if (!g_endpointVolume)
        return;
    float clamped = (level < 0.0f) ? 0.0f : ((level > 1.0f) ? 1.0f : level);
    g_endpointVolume->SetMasterVolumeLevelScalar(clamped, nullptr);
}

bool IsMasterMuted() {
    EnsureAudioEndpoint();
    if (!g_endpointVolume)
        return false;
    BOOL muted = FALSE;
    g_endpointVolume->GetMute(&muted);
    return muted == TRUE;
}

void SetMasterMuted(bool mute) {
    EnsureAudioEndpoint();
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
    ULONGLONG now = GetTickCount64();
    if (now - g_lastTick < 350 && g_lastTick != 0) {
        return g_lastCpu;
    }

    FILETIME idleTime, kernelTime, userTime;
    if (GetSystemTimes(&idleTime, &kernelTime, &userTime)) {
        ULONGLONG idle =
            FileTimeToUint64(idleTime) - FileTimeToUint64(g_prevIdleTime);
        ULONGLONG kernel =
            FileTimeToUint64(kernelTime) - FileTimeToUint64(g_prevKernelTime);
        ULONGLONG user =
            FileTimeToUint64(userTime) - FileTimeToUint64(g_prevUserTime);
        ULONGLONG total = kernel + user;

        if (total > 0 && total >= idle) {
            float usage = static_cast<float>(total - idle) * 100.0f /
                          static_cast<float>(total);
            g_lastCpu =
                (usage < 0.0f) ? 0.0f : ((usage > 100.0f) ? 100.0f : usage);
        }
        g_prevIdleTime = idleTime;
        g_prevKernelTime = kernelTime;
        g_prevUserTime = userTime;
        g_lastTick = now;
    }
    return g_lastCpu;
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
    std::lock_guard<std::mutex> lock(g_mediaMutex);
    return g_cachedMediaTitle;
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

} // namespace Isle
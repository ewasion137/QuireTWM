#pragma once

#include <string>

namespace sol {
class state;
}

namespace Isle {

struct MediaInfo {
    std::string title;
    bool playing = false;
    double pos = 0.0;
    double dur = 0.0;
};

void Initialize();
void Shutdown();
void RegisterLuaBindings(sol::state *lua);

float GetMasterVolume();
void SetMasterVolume(float level);
bool IsMasterMuted();
void SetMasterMuted(bool mute);

int GetBatteryPercentage();
bool IsBatteryCharging();
bool HasBattery();

float GetCpuUsage();
int GetRamUsage();

void MediaPlayPause();
void MediaNext();
void MediaPrev();
void MediaSeek(double seconds);

std::string GetActiveMediaTitle();
MediaInfo GetMediaInfo();

} // namespace Isle

#pragma once

#include <string>

namespace sol {
class state;
}

namespace Isle {
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

std::string GetActiveMediaTitle();
}
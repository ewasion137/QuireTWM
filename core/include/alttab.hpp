#pragma once
#include <windows.h>

bool InitializeAltTabHook();
void CleanupAltTabHook();

size_t CreateDwmThumbnail(HWND dest, HWND src);
void UpdateDwmThumbnail(size_t thumb_id, int x, int y, int w, int h, BYTE opacity);
void DestroyDwmThumbnail(size_t thumb_id);
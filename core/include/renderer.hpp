#pragma once

#include <d2d1.h>
#include <dwrite.h>
#include <windows.h>
#include <string>
#include <unordered_map>

class Renderer {
public:
    Renderer();
    ~Renderer();

    Renderer(const Renderer&) = delete;
    Renderer& operator=(const Renderer&) = delete;
    Renderer(Renderer&&) = delete;
    Renderer& operator=(Renderer&&) = delete;

    bool init(HWND hwnd);
    void shutdown();
    void begin_draw();
    void end_draw();
    void clear(float r, float g, float b, float a);

    void draw_rect(float x, float y, float w, float h, float r, float g, float b, float a, float thickness);
    void fill_rect(float x, float y, float w, float h, float r, float g, float b, float a);
    void draw_rounded_rect(float x, float y, float w, float h, float radius, float r, float g, float b, float a, float thickness);
    void fill_rounded_rect(float x, float y, float w, float h, float radius, float r, float g, float b, float a);

    void draw_text(const std::string& text, float x, float y, float size, float r, float g, float b, float a, const std::string& fontName);
    float measure_text_width(const std::string& text, float size, const std::string& fontName);

private:
    ID2D1Factory* factory;
    ID2D1HwndRenderTarget* target;
    ID2D1SolidColorBrush* brush;
    IDWriteFactory* writeFactory;
    std::unordered_map<std::wstring, IDWriteTextFormat*> font_cache;

    void set_brush_color(float r, float g, float b, float a);
    IDWriteTextFormat* get_cached_text_format(const std::wstring& font, float size);
};
#pragma once

#include <d2d1.h>
#include <dwrite.h>
#include <string>
#include <unordered_map>
#include <windows.h>

class Renderer {
  public:
    Renderer();
    ~Renderer();

    Renderer(const Renderer &) = delete;
    Renderer &operator=(const Renderer &) = delete;
    Renderer(Renderer &&) = delete;
    Renderer &operator=(Renderer &&) = delete;

    bool init(HWND hwnd);
    void shutdown();
    void begin_draw();
    void end_draw();
    void clear(float r, float g, float b, float a);

    void draw_rect(float x, float y, float w, float h, float r, float g,
                   float b, float a, float thickness);
    void fill_rect(float x, float y, float w, float h, float r, float g,
                   float b, float a);
    void draw_rounded_rect(float x, float y, float w, float h, float radius,
                           float r, float g, float b, float a, float thickness);
    void draw_gradient_rounded_rect(float x, float y, float w, float h,
                                    float radius, float r1, float g1, float b1,
                                    float a1, float r2, float g2, float b2,
                                    float a2, float angle, float thickness);
    void fill_rounded_rect(float x, float y, float w, float h, float radius,
                           float r, float g, float b, float a);

    void draw_shadow_rounded_rect(float x, float y, float w, float h,
                                  float radius, float r, float g, float b,
                                  float a, float blur, float spread);
    void draw_glow_rounded_rect(float x, float y, float w, float h,
                                float radius, float r, float g, float b,
                                float a, float intensity, float spread);

    void draw_text(const std::string &text, float x, float y, float size,
                   float r, float g, float b, float a,
                   const std::string &fontName);
    float measure_text_width(const std::string &text, float size,
                             const std::string &fontName);
    void draw_line(float x1, float y1, float x2, float y2, float r, float g,
                   float b, float a, float thickness);
    void draw_circle(float x, float y, float radius, float r, float g, float b,
                     float a, float thickness);
    void fill_circle(float x, float y, float radius, float r, float g, float b,
                     float a);
    void push_clip(float x, float y, float w, float h);
    void pop_clip();

  private:
    struct GradientKey {
        uint32_t c1;
        uint32_t c2;
        bool operator==(const GradientKey &other) const {
            return c1 == other.c1 && c2 == other.c2;
        }
    };

    struct GradientKeyHash {
        size_t operator()(const GradientKey &k) const {
            return static_cast<size_t>(k.c1) ^
                   (static_cast<size_t>(k.c2) * 2654435761u);
        }
    };

    struct TextLayoutKey {
        std::string text;
        std::wstring font;
        float size;
        bool operator==(const TextLayoutKey &o) const {
            return size == o.size && font == o.font && text == o.text;
        }
    };

    struct TextLayoutKeyHash {
        size_t operator()(const TextLayoutKey &k) const {
            size_t h1 = std::hash<std::string>{}(k.text);
            size_t h2 = std::hash<std::wstring>{}(k.font);
            size_t h3 = std::hash<float>{}(k.size);
            return h1 ^ (h2 << 1) ^ (h3 << 2);
        }
    };

    struct CachedLayout {
        IDWriteTextLayout *layout;
        float width;
        uint32_t last_frame;
    };

    HWND hwnd_target;
    ID2D1Factory *factory;
    ID2D1HwndRenderTarget *target;
    ID2D1SolidColorBrush *brush;
    IDWriteFactory *writeFactory;

    std::unordered_map<std::wstring, IDWriteTextFormat *> font_cache;
    std::unordered_map<GradientKey, ID2D1LinearGradientBrush *, GradientKeyHash>
        gradient_cache;
    std::unordered_map<TextLayoutKey, CachedLayout, TextLayoutKeyHash>
        layout_cache;

    uint32_t frame_index;
    float current_dpi;

    void release_target_resources();
    void set_brush_color(float r, float g, float b, float a);
    IDWriteTextFormat *get_cached_text_format(const std::wstring &font,
                                              float size);
    CachedLayout *get_or_create_layout(const std::string &text, float size,
                                       const std::string &fontName);
    void prune_layout_cache();
};
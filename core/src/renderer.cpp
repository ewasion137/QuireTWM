#include "../include/renderer.hpp"
#include <algorithm>
#include <cmath>

static void utf8_to_wide(const std::string &src, std::wstring &dst) {
    if (src.empty()) {
        dst.clear();
        return;
    }
    wchar_t stack_buf[256];
    int len = MultiByteToWideChar(CP_UTF8, 0, src.data(),
                                  static_cast<int>(src.size()), nullptr, 0);
    if (len <= 0) {
        dst.clear();
        return;
    }
    if (len < 256) {
        MultiByteToWideChar(CP_UTF8, 0, src.data(),
                            static_cast<int>(src.size()), stack_buf, len);
        dst.assign(stack_buf, len);
    } else {
        dst.resize(len);
        MultiByteToWideChar(CP_UTF8, 0, src.data(),
                            static_cast<int>(src.size()), dst.data(), len);
    }
}

static inline uint32_t pack_rgba(float r, float g, float b, float a) {
    auto clamp_val = [](float v) -> uint32_t {
        if (v <= 0.0f)
            return 0;
        if (v >= 1.0f)
            return 255;
        return static_cast<uint32_t>(v * 255.0f + 0.5f);
    };
    return (clamp_val(a) << 24) | (clamp_val(r) << 16) | (clamp_val(g) << 8) |
           clamp_val(b);
}

Renderer::Renderer()
    : hwnd_target(nullptr), factory(nullptr), target(nullptr), brush(nullptr),
      writeFactory(nullptr), frame_index(0), current_dpi(96.0f) {}

Renderer::~Renderer() { shutdown(); }

void Renderer::release_target_resources() {
    for (auto &[_, b] : gradient_cache) {
        if (b)
            b->Release();
    }
    gradient_cache.clear();

    if (brush) {
        brush->Release();
        brush = nullptr;
    }
    if (target) {
        target->Release();
        target = nullptr;
    }
}

void Renderer::shutdown() {
    for (auto &[_, item] : layout_cache) {
        if (item.layout)
            item.layout->Release();
    }
    layout_cache.clear();

    for (auto &[_, fmt] : font_cache) {
        if (fmt)
            fmt->Release();
    }
    font_cache.clear();

    release_target_resources();

    if (writeFactory) {
        writeFactory->Release();
        writeFactory = nullptr;
    }
    if (factory) {
        factory->Release();
        factory = nullptr;
    }
    hwnd_target = nullptr;
}

bool Renderer::init(HWND hwnd) {
    if (!IsWindow(hwnd))
        return false;

    hwnd_target = hwnd;

    if (!factory && FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
                                             &factory))) {
        return false;
    }

    if (!writeFactory &&
        FAILED(DWriteCreateFactory(
            DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
            reinterpret_cast<IUnknown **>(&writeFactory)))) {
        return false;
    }

    UINT dpi = GetDpiForWindow(hwnd);
    current_dpi = 96.0f;

    RECT rc;
    GetClientRect(hwnd, &rc);
    UINT32 width =
        (rc.right - rc.left > 0) ? static_cast<UINT32>(rc.right - rc.left) : 1;
    UINT32 height =
        (rc.bottom - rc.top > 0) ? static_cast<UINT32>(rc.bottom - rc.top) : 1;
    D2D1_SIZE_U size = D2D1::SizeU(width, height);

    release_target_resources();

    HRESULT hr = factory->CreateHwndRenderTarget(
        D2D1::RenderTargetProperties(
            D2D1_RENDER_TARGET_TYPE_DEFAULT,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,
                              D2D1_ALPHA_MODE_PREMULTIPLIED),
            current_dpi, current_dpi),
        D2D1::HwndRenderTargetProperties(hwnd, size,
                                         D2D1_PRESENT_OPTIONS_IMMEDIATELY),
        &target);

    if (SUCCEEDED(hr) && target) {
        target->SetDpi(current_dpi, current_dpi);
        target->SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
        return true;
    }
    return false;
}

void Renderer::begin_draw() {
    if (!target && hwnd_target && IsWindow(hwnd_target)) {
        init(hwnd_target);
    }
    if (target) {
        float vx = static_cast<float>(GetSystemMetrics(SM_XVIRTUALSCREEN));
        float vy = static_cast<float>(GetSystemMetrics(SM_YVIRTUALSCREEN));
        target->SetTransform(D2D1::Matrix3x2F::Translation(-vx, -vy));

        target->BeginDraw();
        frame_index++;
        if ((frame_index % 300) == 0) {
            prune_layout_cache();
        }
    }
}

void Renderer::end_draw() {
    if (!target)
        return;
    HRESULT hr = target->EndDraw();
    if (hr == D2DERR_RECREATE_TARGET || FAILED(hr)) {
        release_target_resources();
    }
}

void Renderer::clear(float r, float g, float b, float a) {
    if (target)
        target->Clear(D2D1::ColorF(r, g, b, a));
}

void Renderer::set_brush_color(float r, float g, float b, float a) {
    if (!target)
        return;
    if (!brush) {
        target->CreateSolidColorBrush(D2D1::ColorF(r, g, b, a), &brush);
    } else {
        brush->SetColor(D2D1::ColorF(r, g, b, a));
    }
}

IDWriteTextFormat *Renderer::get_cached_text_format(const std::wstring &font,
                                                    float size) {
    if (!writeFactory)
        return nullptr;
    float safe_size = (size > 0.0f) ? size : 12.0f;
    const std::wstring &safe_font =
        font.empty() ? L"Segoe UI Variable Display" : font;
    std::wstring key = safe_font + L"#" + std::to_wstring(safe_size);

    auto it = font_cache.find(key);
    if (it != font_cache.end())
        return it->second;

    IDWriteTextFormat *format = nullptr;
    HRESULT hr = writeFactory->CreateTextFormat(
        safe_font.c_str(), nullptr, DWRITE_FONT_WEIGHT_NORMAL,
        DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, safe_size, L"",
        &format);

    if (SUCCEEDED(hr) && format) {
        font_cache.emplace(std::move(key), format);
        return format;
    }
    return nullptr;
}

Renderer::CachedLayout *
Renderer::get_or_create_layout(const std::string &text, float size,
                               const std::string &fontName) {
    if (!writeFactory || text.empty())
        return nullptr;

    std::wstring wfont;
    utf8_to_wide(fontName, wfont);
    TextLayoutKey key = {text, wfont, size};

    auto it = layout_cache.find(key);
    if (it != layout_cache.end()) {
        it->second.last_frame = frame_index;
        return &it->second;
    }

    IDWriteTextFormat *format = get_cached_text_format(wfont, size);
    if (!format)
        return nullptr;

    std::wstring wtext;
    utf8_to_wide(text, wtext);

    IDWriteTextLayout *layout = nullptr;
    HRESULT hr = writeFactory->CreateTextLayout(
        wtext.c_str(), static_cast<UINT32>(wtext.length()), format, 8192.0f,
        2048.0f, &layout);

    if (SUCCEEDED(hr) && layout) {
        float width = 0.0f;
        DWRITE_TEXT_METRICS metrics = {};
        if (SUCCEEDED(layout->GetMetrics(&metrics))) {
            width = metrics.width;
        }
        auto res = layout_cache.emplace(
            std::move(key), CachedLayout{layout, width, frame_index});
        return &res.first->second;
    }
    return nullptr;
}

void Renderer::prune_layout_cache() {
    for (auto it = layout_cache.begin(); it != layout_cache.end();) {
        if (frame_index - it->second.last_frame > 300) {
            if (it->second.layout)
                it->second.layout->Release();
            it = layout_cache.erase(it);
        } else {
            ++it;
        }
    }
}

void Renderer::draw_rect(float x, float y, float w, float h, float r, float g,
                         float b, float a, float thickness) {
    if (!target || thickness <= 0.0f || w <= 0.0f || h <= 0.0f)
        return;
    set_brush_color(r, g, b, a);
    float inset = thickness * 0.5f;
    float rx = x + inset;
    float ry = y + inset;
    float rw = (w > thickness) ? (w - thickness) : 0.0f;
    float rh = (h > thickness) ? (h - thickness) : 0.0f;
    target->DrawRectangle(D2D1::RectF(rx, ry, rx + rw, ry + rh), brush,
                          thickness);
}

void Renderer::fill_rect(float x, float y, float w, float h, float r, float g,
                         float b, float a) {
    if (!target || w <= 0.0f || h <= 0.0f)
        return;
    set_brush_color(r, g, b, a);
    target->FillRectangle(D2D1::RectF(x, y, x + w, y + h), brush);
}

void Renderer::draw_rounded_rect(float x, float y, float w, float h,
                                 float radius, float r, float g, float b,
                                 float a, float thickness) {
    if (!target || thickness <= 0.0f || w <= 0.0f || h <= 0.0f)
        return;
    set_brush_color(r, g, b, a);
    float inset = thickness * 0.5f;
    float rx = x + inset;
    float ry = y + inset;
    float rw = (w > thickness) ? (w - thickness) : 0.0f;
    float rh = (h > thickness) ? (h - thickness) : 0.0f;
    float rad = (radius > inset) ? (radius - inset) : 0.0f;
    D2D1_ROUNDED_RECT rr =
        D2D1::RoundedRect(D2D1::RectF(rx, ry, rx + rw, ry + rh), rad, rad);
    target->DrawRoundedRectangle(rr, brush, thickness);
}

void Renderer::draw_gradient_rounded_rect(float x, float y, float w, float h,
                                          float radius, float r1, float g1,
                                          float b1, float a1, float r2,
                                          float g2, float b2, float a2,
                                          float angle, float thickness) {
    if (!target || thickness <= 0.0f || w <= 0.0f || h <= 0.0f)
        return;

    float rad_angle = angle * 0.0174532925f;
    float cx = x + (w * 0.5f);
    float cy = y + (h * 0.5f);
    float half_diag = 0.5f * std::sqrt(w * w + h * h);

    float dx = std::cos(rad_angle) * half_diag;
    float dy = std::sin(rad_angle) * half_diag;

    D2D1_POINT_2F start = D2D1::Point2F(cx - dx, cy - dy);
    D2D1_POINT_2F end = D2D1::Point2F(cx + dx, cy + dy);

    GradientKey key = {pack_rgba(r1, g1, b1, a1), pack_rgba(r2, g2, b2, a2)};
    auto it = gradient_cache.find(key);
    ID2D1LinearGradientBrush *grad_brush = nullptr;

    if (it != gradient_cache.end()) {
        grad_brush = it->second;
    } else {
        D2D1_GRADIENT_STOP stops[2];
        stops[0].color = D2D1::ColorF(r1, g1, b1, a1);
        stops[0].position = 0.0f;
        stops[1].color = D2D1::ColorF(r2, g2, b2, a2);
        stops[1].position = 1.0f;

        ID2D1GradientStopCollection *coll = nullptr;
        if (SUCCEEDED(target->CreateGradientStopCollection(stops, 2, &coll)) &&
            coll) {
            target->CreateLinearGradientBrush(
                D2D1::LinearGradientBrushProperties(start, end), coll,
                &grad_brush);
            coll->Release();
            if (grad_brush) {
                gradient_cache.emplace(key, grad_brush);
            }
        }
    }

    if (grad_brush) {
        grad_brush->SetStartPoint(start);
        grad_brush->SetEndPoint(end);

        float inset = thickness * 0.5f;
        float rx = x + inset;
        float ry = y + inset;
        float rw = (w > thickness) ? (w - thickness) : 0.0f;
        float rh = (h > thickness) ? (h - thickness) : 0.0f;
        float rad = (radius > inset) ? (radius - inset) : 0.0f;

        D2D1_ROUNDED_RECT rr =
            D2D1::RoundedRect(D2D1::RectF(rx, ry, rx + rw, ry + rh), rad, rad);
        target->DrawRoundedRectangle(rr, grad_brush, thickness);
    }
}

void Renderer::fill_rounded_rect(float x, float y, float w, float h,
                                 float radius, float r, float g, float b,
                                 float a) {
    if (!target || w <= 0.0f || h <= 0.0f)
        return;
    set_brush_color(r, g, b, a);
    D2D1_ROUNDED_RECT rr =
        D2D1::RoundedRect(D2D1::RectF(x, y, x + w, y + h), radius, radius);
    target->FillRoundedRectangle(rr, brush);
}

void Renderer::draw_shadow_rounded_rect(float x, float y, float w, float h,
                                        float radius, float r, float g, float b,
                                        float a, float blur, float spread) {
    if (!target || a <= 0.001f || blur <= 0.0f)
        return;

    const int steps = 5;
    float base_alpha = a / static_cast<float>(steps);
    float step_spread = (blur + spread) / static_cast<float>(steps);

    for (int i = steps; i >= 1; --i) {
        float exp_dist = step_spread * static_cast<float>(i);
        float step_alpha = base_alpha * (1.0f - static_cast<float>(i - 1) /
                                                    static_cast<float>(steps));
        set_brush_color(r, g, b, step_alpha);
        D2D1_ROUNDED_RECT rr =
            D2D1::RoundedRect(D2D1::RectF(x - exp_dist, y - exp_dist,
                                          x + w + exp_dist, y + h + exp_dist),
                              radius + exp_dist, radius + exp_dist);
        target->DrawRoundedRectangle(rr, brush, step_spread);
    }
}

void Renderer::draw_glow_rounded_rect(float x, float y, float w, float h,
                                      float radius, float r, float g, float b,
                                      float a, float intensity, float spread) {
    if (!target || a <= 0.001f || intensity <= 0.0f)
        return;

    const int steps = 4;
    float step_spread = (spread + intensity * 2.0f) / static_cast<float>(steps);
    float base_alpha = (a * intensity * 0.45f) / static_cast<float>(steps);

    for (int i = steps; i >= 1; --i) {
        float exp_dist = step_spread * static_cast<float>(i);
        float step_alpha = base_alpha * (1.0f - static_cast<float>(i - 1) /
                                                    static_cast<float>(steps));
        set_brush_color(r, g, b, step_alpha);
        D2D1_ROUNDED_RECT rr =
            D2D1::RoundedRect(D2D1::RectF(x - exp_dist, y - exp_dist,
                                          x + w + exp_dist, y + h + exp_dist),
                              radius + exp_dist, radius + exp_dist);
        target->DrawRoundedRectangle(rr, brush, step_spread);
    }
}

void Renderer::draw_text(const std::string &text, float x, float y, float size,
                         float r, float g, float b, float a,
                         const std::string &fontName) {
    if (!target || text.empty())
        return;

    CachedLayout *cached = get_or_create_layout(text, size, fontName);
    if (cached && cached->layout) {
        set_brush_color(r, g, b, a);
        target->DrawTextLayout(D2D1::Point2F(x, y), cached->layout, brush);
    }
}

float Renderer::measure_text_width(const std::string &text, float size,
                                   const std::string &fontName) {
    if (text.empty())
        return 0.0f;

    CachedLayout *cached = get_or_create_layout(text, size, fontName);
    return cached ? cached->width : 0.0f;
}

void Renderer::draw_line(float x1, float y1, float x2, float y2, float r,
                         float g, float b, float a, float thickness) {
    if (!target || thickness <= 0.0f)
        return;
    set_brush_color(r, g, b, a);
    target->DrawLine(D2D1::Point2F(x1, y1), D2D1::Point2F(x2, y2), brush,
                     thickness);
}

void Renderer::draw_circle(float x, float y, float radius, float r, float g,
                           float b, float a, float thickness) {
    if (!target || thickness <= 0.0f || radius <= 0.0f)
        return;
    set_brush_color(r, g, b, a);
    D2D1_ELLIPSE el = D2D1::Ellipse(D2D1::Point2F(x, y), radius, radius);
    target->DrawEllipse(el, brush, thickness);
}

void Renderer::fill_circle(float x, float y, float radius, float r, float g,
                           float b, float a) {
    if (!target || radius <= 0.0f)
        return;
    set_brush_color(r, g, b, a);
    D2D1_ELLIPSE el = D2D1::Ellipse(D2D1::Point2F(x, y), radius, radius);
    target->FillEllipse(el, brush);
}

void Renderer::push_clip(float x, float y, float w, float h) {
    if (!target)
        return;
    target->PushAxisAlignedClip(D2D1::RectF(x, y, x + w, y + h),
                                D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
}

void Renderer::pop_clip() {
    if (!target)
        return;
    target->PopAxisAlignedClip();
}

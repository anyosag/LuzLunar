// [fork] The night sky's aurora, per pixel (design canvas Main.dc.html startAurora(), 446-565): the
// "main" layer M, the sum of the canvas's two curtains of 3 px columns drawn 2 px apart with the
// 'lighter' (additive) operator. Rendered into a layer of 1 px per logical px, as the canvas's bitmap.
// Each pixel finds the (at most two) columns of each curtain that cover its centre, evaluates the
// canvas's column math for them and adds their gradient colour: the 2:1 even/odd striping falls out.
//
// Compile (needs Qt's qsb; Metal for the Mac) and commit the result:
//   qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o app/gui/shaders/aurora.frag.qsb app/gui/shaders/aurora.frag
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;        // seconds
    float width;    // bitmap width (the sky's width)
    float height;   // bitmap height (520)
    float gain;     // 1
};

// premultiplied colour of an 8-bit rgba stop
vec4 pm(float r, float g, float b, float a) { return vec4(vec3(r, g, b) / 255.0 * a, a); }
vec4 seg(vec4 a, vec4 b, float x0, float x1, float x) { return mix(a, b, clamp((x - x0) / (x1 - x0), 0.0, 1.0)); }

// the column gradients, offset 0 = lower edge, 1 = top (premultiplied interpolation, like the canvas)
vec4 greenGrad(float x) {
    if (x < 0.015) return seg(pm(210.0, 255.0, 230.0, 0.0), pm(215.0, 255.0, 232.0, 0.95), 0.0, 0.015, x);
    if (x < 0.06) return seg(pm(215.0, 255.0, 232.0, 0.95), pm(110.0, 255.0, 170.0, 0.9), 0.015, 0.06, x);
    if (x < 0.2) return seg(pm(110.0, 255.0, 170.0, 0.9), pm(45.0, 235.0, 135.0, 0.6), 0.06, 0.2, x);
    if (x < 0.42) return seg(pm(45.0, 235.0, 135.0, 0.6), pm(30.0, 200.0, 120.0, 0.3), 0.2, 0.42, x);
    if (x < 0.65) return seg(pm(30.0, 200.0, 120.0, 0.3), pm(90.0, 120.0, 170.0, 0.14), 0.42, 0.65, x);
    if (x < 0.82) return seg(pm(90.0, 120.0, 170.0, 0.14), pm(160.0, 70.0, 150.0, 0.09), 0.65, 0.82, x);
    return seg(pm(160.0, 70.0, 150.0, 0.09), pm(170.0, 50.0, 120.0, 0.0), 0.82, 1.0, x);
}
vec4 tealGrad(float x) {
    if (x < 0.02) return seg(pm(200.0, 255.0, 245.0, 0.0), pm(190.0, 255.0, 240.0, 0.8), 0.0, 0.02, x);
    if (x < 0.08) return seg(pm(190.0, 255.0, 240.0, 0.8), pm(80.0, 240.0, 200.0, 0.7), 0.02, 0.08, x);
    if (x < 0.28) return seg(pm(80.0, 240.0, 200.0, 0.7), pm(40.0, 200.0, 170.0, 0.4), 0.08, 0.28, x);
    if (x < 0.55) return seg(pm(40.0, 200.0, 170.0, 0.4), pm(60.0, 140.0, 190.0, 0.18), 0.28, 0.55, x);
    if (x < 0.8) return seg(pm(60.0, 140.0, 190.0, 0.18), pm(140.0, 80.0, 190.0, 0.08), 0.55, 0.8, x);
    return seg(pm(140.0, 80.0, 190.0, 0.08), pm(140.0, 80.0, 190.0, 0.0), 0.8, 1.0, x);
}

const float PI = 3.14159265358979;

vec4 greenOrTeal(int curtain, float x) { return curtain == 0 ? tealGrad(x) : greenGrad(x); }

// One curtain's column at x: its contribution to the pixel centre (cx, cy), premultiplied
vec4 column(int curtain, float x, float cy) {
    float W = width;
    float u = x / W;
    float y0; float a0; float a1; float a2; float f0; float f1; float f2; float s0; float s1; float s2;
    float h; float hf; float g0; float g1; float strength; float p;
    if (curtain == 0) {
        y0 = 320.0; a0 = 26.0; a1 = 12.0; a2 = 5.0; f0 = 2.4; f1 = 7.1; f2 = 19.0;
        s0 = -0.035; s1 = 0.08; s2 = 0.22; h = 160.0; hf = 3.1; g0 = 4.2; g1 = 1.7; strength = 0.5; p = 2.1;
    } else {
        y0 = 410.0; a0 = 38.0; a1 = 16.0; a2 = 6.0; f0 = 3.1; f1 = 8.7; f2 = 23.0;
        s0 = 0.045; s1 = -0.11; s2 = 0.3; h = 235.0; hf = 4.3; g0 = 5.3; g1 = 2.2; strength = 1.0; p = 0.0;
    }
    float base = y0
        + a0 * sin(u * f0 * PI + t * s0 * 6.0 + p)
        + a1 * sin(u * f1 * PI + t * s1 * 6.0)
        + a2 * sin(u * f2 * PI + t * s2 * 6.0 + p);
    float patchV = 0.5 + 0.5 * sin(u * g0 * PI + t * 0.22 + p) * sin(u * g1 * PI - t * 0.13);
    float rays = 0.5 + 0.5 * sin(x * 0.19 + t * 1.6 + 3.0 * sin(x * 0.011 + t * 0.35)) * sin(x * 0.061 - t * 0.9);
    float pulse = 0.88 + 0.12 * sin(t * 2.3 + x * 0.004 + p);
    float ends = max(0.0, min(1.0, min((x + 60.0) / 300.0, (W + 60.0 - x) / 300.0)));
    float light = patchV * (0.3 + 0.7 * rays) * pulse * ends * strength;
    if (light < 0.03)
        return vec4(0.0);
    float tall = h * (0.6 + 0.4 * (0.5 + 0.5 * sin(u * hf * PI + t * 0.25 + p))) * (0.85 + 0.15 * rays);
    vec4 acc = vec4(0.0);
    if (cy >= base - tall && cy < base)
        acc += greenOrTeal(curtain, (base - cy) / tall) * min(1.0, light);
    if (curtain == 1 && light > 0.55 && cy >= base - 2.0 && cy < base + 8.0) {
        float k = (cy - (base - 2.0)) / 10.0;
        float a = 0.75 * (1.0 - k);
        acc += vec4(vec3(255.0, 110.0, 190.0) / 255.0 * a, a) * min(1.0, (light - 0.55) * 1.6);
    }
    return acc * gain;
}

void main() {
    vec2 size = vec2(width, height);
    vec2 c = floor(qt_TexCoord0 * size) + 0.5;     // the pixel's centre, in bitmap pixels
    vec4 sum = vec4(0.0);
    for (int curtain = 0; curtain < 2; curtain++) {
        // column i spans x_i = -10 + 2 i ... x_i + 3 and exists while x_i < width + 10
        float iHi = floor((c.x + 10.0) / 2.0);
        for (int k = 0; k < 2; k++) {
            float i = iHi - float(k);
            float x = -10.0 + 2.0 * i;
            if (i < 0.0 || x >= width + 10.0 || c.x >= x + 3.0)
                continue;
            sum += column(curtain, x, c.y);
        }
    }
    fragColor = min(sum, vec4(1.0)) * qt_Opacity;
}

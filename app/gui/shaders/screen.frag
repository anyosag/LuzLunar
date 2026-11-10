// [fork] Composes the night sky's aurora: the sky gradient behind the band, then the glow (blurred,
// saturate 1.2, opacity 0.85) and the main layer (opacity 0.92) added with the 'screen' blend, as on the
// design canvas (sky-chrome.md 4.4.2 step 9). Both textures are premultiplied.
//
// Compile (needs Qt's qsb; Metal for the Mac) and commit the result:
//   qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o app/gui/shaders/screen.frag.qsb app/gui/shaders/screen.frag
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float bandTop;      // y of the band in the sky
    float skyHeight;    // the sky's height
    float bandHeight;   // 520
};
layout(binding = 1) uniform sampler2D mainTex;
layout(binding = 2) uniform sampler2D glowTex;

// the sky gradient: #05070F 0, #0A0E20 40 %, #111833 78 %, #18204A 100 %
vec3 sky(float g) {
    vec3 a = vec3(5.0, 7.0, 15.0) / 255.0;
    vec3 b = vec3(10.0, 14.0, 32.0) / 255.0;
    vec3 c = vec3(17.0, 24.0, 51.0) / 255.0;
    vec3 d = vec3(24.0, 32.0, 74.0) / 255.0;
    if (g < 0.4) return mix(a, b, g / 0.4);
    if (g < 0.78) return mix(b, c, (g - 0.4) / 0.38);
    return mix(c, d, (g - 0.78) / 0.22);
}

vec3 screenBlend(vec3 b, vec3 s) { return b + s - b * s; }

void main() {
    float y = bandTop + qt_TexCoord0.y * bandHeight;
    vec3 base = sky(clamp(y / skyHeight, 0.0, 1.0));

    vec4 g = texture(glowTex, qt_TexCoord0);
    vec3 gc = g.a > 0.0001 ? g.rgb / g.a : vec3(0.0);
    float s = 1.2;
    vec3 gs = vec3(
        (0.213 + 0.787 * s) * gc.r + (0.715 - 0.715 * s) * gc.g + (0.072 - 0.072 * s) * gc.b,
        (0.213 - 0.213 * s) * gc.r + (0.715 + 0.285 * s) * gc.g + (0.072 - 0.072 * s) * gc.b,
        (0.213 - 0.213 * s) * gc.r + (0.715 - 0.715 * s) * gc.g + (0.072 + 0.928 * s) * gc.b);
    gs = clamp(gs, 0.0, 1.0) * g.a;
    vec3 col = screenBlend(base, gs * 0.85);

    vec4 m = texture(mainTex, qt_TexCoord0);
    col = screenBlend(col, m.rgb * 0.92);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}

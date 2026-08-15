#include <metal_stdlib>
using namespace metal;

// Flux field v2: domain-warped current lines in a single accent over the
// app's pitch base. Structure comes from three ingredients — an organic
// warp (fbm), layered fine flow-lines with defined edges, and a slow depth
// field that makes regions breathe — so the result reads abstract and
// sophisticated rather than as simple sine stripes. Everything is derived
// from one warped coordinate, which keeps the layers coherent.
//
// Precision note: `time` must arrive already reduced (modulo ~1000s);
// wall-clock seconds exceed float32 phase precision and flatten every sin().

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.55;
    for (int i = 0; i < 3; i++) {
        value += amplitude * vnoise(p);
        p = p * 2.02 + float2(17.3, 9.1);
        amplitude *= 0.5;
    }
    return value;
}

// A band of flow-lines over the warped domain. Narrow smoothsteps keep the
// edge defined; the paired halo gives depth without blur.
static float flowLines(float2 r, float scale, float phase, float coreLow, float coreHigh) {
    float wave = sin(r.y * scale + phase);
    float core = smoothstep(coreLow, coreHigh, wave);
    float halo = smoothstep(coreLow - 0.16, coreLow, wave) * 0.28;
    return core + halo;
}

[[ stitchable ]] half4 fluxField(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float energy,
    half4 accent
) {
    float2 uv = position / max(size, float2(1.0, 1.0));
    float aspect = size.x / max(size.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);

    // Energy opens the field gently; the coupling stays soft so replays and
    // throws read smooth, never jumpy.
    float drive = 1.0 + energy * 0.6;
    float t = time;

    // Organic domain warp: two fbm channels bend the whole coordinate frame.
    float2 q = float2(
        fbm(p * 1.5 + float2(0.0, t * 0.030)),
        fbm(p * 1.5 + float2(5.2, -t * 0.024))
    );
    float2 r = p + (q - 0.5) * (0.62 * drive);
    // Slight diagonal shear keeps the currents kinetic at rest.
    r = float2(r.x + r.y * 0.22, r.y - r.x * 0.14);

    // Three line layers at staggered scales and speeds, all sharing the warp.
    float l1 = flowLines(r, 20.0, -t * 0.34, 0.958, 0.992);
    float l2 = flowLines(r + float2(0.31, 0.77), 34.0, t * 0.22, 0.968, 0.994) * 0.62;
    float l3 = flowLines(r + float2(0.83, 0.19), 55.0, -t * 0.15, 0.978, 0.996) * 0.36;

    // Depth field: slow patches brighten and dim regions so the field
    // breathes instead of tiling uniformly.
    float depth = 0.55 + 0.75 * fbm(p * 0.9 + float2(t * 0.012, -t * 0.009));

    float lines = (l1 + l2 + l3) * depth;

    // Quiet ground: a low bed plus a faint wide glow following the warp.
    float bed = (1.0 - uv.y) * 0.05;
    float ambient = fbm(r * 0.6) * 0.045;

    float intensity = lines * (0.26 + 0.34 * energy) + bed + ambient;

    // Fine grain breaks banding without reading as noise.
    float grain = (hash21(uv * 731.0 + fract(t)) - 0.5) * 0.014;

    half3 tint = accent.rgb;
    half3 rgb = tint * half(intensity) + half3(grain, grain, grain);
    return half4(rgb, half(min(1.0, intensity + 0.02)));
}

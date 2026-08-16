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

// ---------------------------------------------------------------------------
// Facets field: large stained-glass voronoi cells. Every cell is an AREA with
// its own luminance that slowly breathes; the shared edges are thin defined
// seams. Reads as dark architectural glass, never as lines over black.
// One 3x3 neighborhood pass per pixel — cheaper than fluxField's fbm stack.
//
// Energy raises luminance only. Cell points move on their own clocks; drive
// never scales time, so a change in energy can never jump the phase.

static float3 facetCells(float2 p, float t) {
    float2 cell = floor(p);
    float f1 = 8.0;
    float f2 = 8.0;
    float lum = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 id = cell + float2(x, y);
            float2 h = float2(hash21(id), hash21(id + 71.7));
            float2 pt = id + 0.5 + 0.38 * float2(
                sin(t * (0.10 + 0.10 * h.x) + h.x * 6.2831),
                cos(t * (0.08 + 0.09 * h.y) + h.y * 6.2831));
            float d = distance(p, pt);
            if (d < f1) {
                f2 = f1;
                f1 = d;
                lum = h.x;
            } else if (d < f2) {
                f2 = d;
            }
        }
    }
    return float3(f1, f2, lum);
}

[[ stitchable ]] half4 facetsField(
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
    float t = time;

    float3 v = facetCells(p * 4.4, t);

    // The cell body: a per-cell luminance with a slow personal breath. The
    // AREAS carry the field — seams only articulate them.
    float breathe = 0.5 + 0.5 * sin(t * 0.14 + v.z * 6.2831);
    float facet = 0.08 + (0.14 + 0.12 * breathe) * v.z;

    // The seam between cells: thin, defined, quiet.
    float seam = 1.0 - smoothstep(0.012, 0.085, v.y - v.x);

    // Regional depth so the glass never tiles uniformly.
    float depth = 0.65 + 0.55 * fbm(p * 1.1 + float2(t * 0.011, -t * 0.008));

    float intensity = facet * depth * (0.85 + 0.55 * energy)
        + seam * 0.07
        + (1.0 - uv.y) * 0.04;

    float grain = (hash21(uv * 731.0 + fract(t)) - 0.5) * 0.014;

    half3 rgb = accent.rgb * half(intensity) + half3(grain, grain, grain);
    return half4(rgb, half(min(1.0, intensity + 0.02)));
}

// ---------------------------------------------------------------------------
// Horizon field: stacked color-field strata. Each boundary is a slow-drifting
// curve with a crisp step and a hairline highlight; everything between is a
// broad area of tone, brighter toward the bottom bed. Cheapest of the set:
// four fbm evaluations per pixel, no warp.

[[ stitchable ]] half4 horizonField(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float energy,
    half4 accent
) {
    float2 uv = position / max(size, float2(1.0, 1.0));
    float aspect = size.x / max(size.y, 1.0);
    float x = uv.x * aspect;
    float t = time;

    float bases[4] = { 0.24, 0.44, 0.64, 0.82 };
    float steps[4] = { 0.050, 0.068, 0.092, 0.120 };

    float intensity = 0.045;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float wob = fbm(float2(x * (1.1 + 0.22 * fi) + fi * 7.3, t * 0.016 + fi * 3.1));
        float b = bases[i] + (wob - 0.5) * 0.17;
        // Area below the boundary gains this stratum's tone. The 12px-ish
        // transition keeps the edge defined without aliasing.
        intensity += smoothstep(b - 0.007, b + 0.007, uv.y) * steps[i] * (1.0 + 0.55 * energy);
        // Hairline along the boundary: the defined aspect glass refracts.
        intensity += smoothstep(0.013, 0.0, abs(uv.y - b)) * 0.06;
    }

    // A slow broad breath over the whole field.
    intensity *= 0.90 + 0.16 * fbm(float2(x * 0.7, uv.y * 0.7) + float2(t * 0.013, -t * 0.010));

    float grain = (hash21(uv * 731.0 + fract(t)) - 0.5) * 0.014;

    half3 rgb = accent.rgb * half(intensity) + half3(grain, grain, grain);
    return half4(rgb, half(min(1.0, intensity + 0.02)));
}

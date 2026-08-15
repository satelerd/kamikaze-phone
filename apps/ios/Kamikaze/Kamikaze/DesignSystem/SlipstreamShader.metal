#include <metal_stdlib>
using namespace metal;

// Flux field: abstract current-lines in a single accent over the app's pitch
// base. Shapes keep defined edges (narrow smoothsteps, no blur) so Liquid
// Glass has real geometry to refract. Runs per-pixel on the GPU — cheaper
// than any blurred-layer composite.

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// One layer of flowing current lines. `scale` sets line count, `speed` the
// drift, `warp` how much the lines bend.
static float currents(float2 uv, float time, float scale, float speed, float warp) {
    float bend = sin(uv.x * 2.4 + time * speed * 0.6) * warp
               + sin(uv.x * 5.1 - time * speed * 0.31 + 1.7) * warp * 0.45;
    float wave = sin((uv.y + bend) * scale - time * speed);
    return wave;
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
    // Gentle diagonal so the field reads kinetic even at rest.
    float2 p = float2(uv.x + uv.y * 0.28, uv.y - uv.x * 0.18);

    float drive = 1.0 + energy * 1.6;

    // Two current layers at different scales; edges stay defined.
    float w1 = currents(p, time, 26.0, 0.50, 0.14 * drive);
    float w2 = currents(p + float2(0.37, 0.61), time, 44.0, 0.78, 0.08 * drive);

    // Sharp core lines plus a tight halo around each — definition, not blur.
    float core1 = smoothstep(0.955, 0.990, w1);
    float halo1 = smoothstep(0.800, 0.955, w1) * 0.24;
    float core2 = smoothstep(0.968, 0.995, w2) * 0.60;
    float halo2 = smoothstep(0.880, 0.968, w2) * 0.16;

    float lines = core1 + halo1 + core2 + halo2;

    // A broad, quiet gradient keeps the lower half grounded.
    float bed = (1.0 - uv.y) * 0.06;

    float intensity = (lines * (0.26 + 0.38 * energy) + bed);

    // Fine grain breaks banding without reading as noise.
    float grain = (hash21(uv * 731.0 + fract(time)) - 0.5) * 0.016;

    half3 tint = accent.rgb;
    half3 rgb = tint * half(intensity) + half3(grain, grain, grain);
    return half4(rgb, half(min(1.0, intensity + 0.02)));
}

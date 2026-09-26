#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// How strongly a point is lit by a soft source: 1 at the source, falling
/// away over `reach` (points, per axis).
static float rautaHalo(float2 p, float2 source, float2 reach) {
    float2 d = (p - source) / reach;
    return exp(-dot(d, d) * 2.2);
}

/// A steady pseudo-random number per dot, so each one twinkles in its own time.
static float rautaHash(float2 cell) {
    return fract(sin(dot(cell, float2(127.1, 311.7))) * 43758.5453);
}

/// RAUTA's light behind the chat.
///
/// RAUTA is the source: a warm wash falls from it, and through the wash runs
/// a dot matrix — the dots the app sets its big numbers in — each dot as large
/// as the light where it sits. A lower light rises from the field.
///
/// At rest the halo breathes. While RAUTA thinks, light is drawn in toward it
/// and the dots twinkle; when the answer lands, one pulse travels out. Every
/// state is a weight the caller eases, so one flows into the next.
///
/// Toward the top and bottom edges the dots melt into their own average: the
/// progressive blur under RAUTA and the field, drawn into the light itself.
///
/// - Parameters:
///   - size: the backdrop's size in points.
///   - source: where RAUTA sits, in points.
///   - time: the resting clock, seconds.
///   - think: 0…1, how far into thinking.
///   - flow: the thinking clock, seconds; advances only as fast as `think`.
///   - pulse: 0…1 progress of the answer's pulse; 1 when there is none.
///   - bottom: how strongly the field's light rises, 0…1.
///   - blurTop, blurBottom: how far the blur reaches from each edge, points.
///   - glow, ink: the wash's colour and the dots'.
///   - strength: an overall scale.
[[ stitchable ]] half4 rautaLight(
    float2 position,
    half4 color,
    float2 size,
    float2 source,
    float time,
    float think,
    float flow,
    float pulse,
    float bottom,
    float blurTop,
    float blurBottom,
    half4 glow,
    half4 ink,
    float strength
) {
    float base = rautaHalo(position, source, float2(size.x * 0.52, clamp(size.y * 0.4, 220.0, 330.0)));
    float r = length(position - source);

    // At rest: a slow breath.
    float field = base * (1.0 + 0.07 * sin(time * 0.8));

    // Thinking: bands of light travelling in toward RAUTA.
    field *= 1.0 + think * 0.4 * sin(r * 0.05 + flow * 3.4);

    // The answer: one ring leaving RAUTA and fading as it goes.
    float reachOut = max(size.x, size.y) * 0.8;
    float ring = exp(-pow((r - pulse * reachOut) / 38.0, 2.0)) * (1.0 - pulse);
    field += ring * 0.55 * smoothstep(0.0, 0.08, 1.0 - pulse);

    field += bottom * rautaHalo(position, float2(size.x * 0.5, size.y + 30.0), float2(size.x * 0.9, 190.0));
    field = saturate(field);

    // The dot matrix: one dot per cell, sized by the light.
    const float cell = 6.5;
    float2 cellIndex = floor(position / cell);
    float2 local = fract(position / cell) - 0.5;
    float dist = length(local) * cell;
    float twinkle = 1.0 + think * 0.55 * sin(time * 5.0 + rautaHash(cellIndex) * 6.2832) * base;
    float radius = cell * 0.4 * sqrt(saturate(field * twinkle));
    float sharp = 1.0 - smoothstep(radius - 0.7, radius + 0.3, dist);

    // The progressive blur: toward either edge a dot becomes the share of its
    // cell it covers. Taken from the steady light, not the twinkle: a twinkle
    // differs cell by cell, and averaged over cells it would read as squares.
    float steady = cell * 0.4 * sqrt(field);
    float coverage = saturate(3.14159 * steady * steady / (cell * cell));
    float blurred = max(
        1.0 - smoothstep(blurTop * 0.3, blurTop, position.y),
        smoothstep(size.y - blurBottom, size.y - blurBottom * 0.3, position.y)
    );
    float dotMask = mix(sharp, coverage, blurred) * smoothstep(0.03, 0.14, field);

    half4 lit = mix(color, glow, half(field * 0.18 * strength));
    return mix(lit, ink, half(dotMask * (0.1 + field * 0.38) * strength));
}

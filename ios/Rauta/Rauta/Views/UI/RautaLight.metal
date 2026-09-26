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

/// RAUTA's light as the app opens: the chat's dot matrix, switching on.
///
/// Stray dots flicker on across the screen like a display waking. A ring
/// closes in from the far corner, sweeping them up with bands of light running
/// in behind it, and collapses on RAUTA. Out of the collapse the halo comes up
/// and one shockwave leaves — it pushes the dots aside as it passes, so the
/// grid itself is seen to move. The same progressive blur as the chat melts
/// the dots toward the top and bottom edges.
///
/// - Parameters:
///   - size: the backdrop's size in points.
///   - source: where RAUTA appears, in points.
///   - time: seconds since the start.
///   - wake: 0…1, how many of the stray dots are on.
///   - gather: 0…1, the closing ring's progress; 0 before it starts.
///   - light: 0…1, how far the halo has come up.
///   - pulse: 0…1 progress of the shockwave; 1 when there is none.
///   - glow, ink: the wash's colour and the dots'.
///   - strength: an overall scale.
[[ stitchable ]] half4 rautaLaunch(
    float2 position,
    half4 color,
    float2 size,
    float2 source,
    float time,
    float wake,
    float gather,
    float light,
    float pulse,
    half4 glow,
    half4 ink,
    float strength
) {
    const float cell = 6.5;
    float2 offset = position - source;
    float r = length(offset);
    float2 away = r > 0.001 ? offset / r : float2(0.0);

    // The shockwave shifts where the grid is read, so the dots near its front
    // are carried outward with it.
    float front = pulse * length(size) * 0.75;
    float wave = exp(-pow((r - front) / 44.0, 2.0)) * (1.0 - pulse);
    float2 p = position - away * wave * 10.0;
    float rp = length(p - source);

    // The halo, as in the chat.
    float base = rautaHalo(p, source, float2(size.x * 0.52, clamp(size.y * 0.4, 220.0, 330.0)));
    float field = base * light * (1.0 + 0.07 * sin(time * 0.8));

    // The closing ring, brighter the tighter it draws, gone as it lands.
    float started = step(0.0001, gather);
    float closing = started * (1.0 - smoothstep(0.9, 1.0, gather));
    float far = length(max(source, size - source));
    float ringAt = (1.0 - gather) * far;
    float ring = exp(-pow((rp - ringAt) / 56.0, 2.0)) * closing * (0.3 + 0.5 * gather);
    float inside = (1.0 - smoothstep(ringAt - 30.0, ringAt + 30.0, rp)) * started;
    float bands = inside * closing * (0.05 + 0.1 * (0.5 + 0.5 * sin(rp * 0.045 + time * 6.0)));
    // What the ring has passed over is swept; once it has closed, everything is.
    float swept = max((1.0 - inside) * started, smoothstep(0.97, 1.0, gather));

    // Stray dots: a scatter of cells flickering on, until the ring sweeps them.
    float2 cellIndex = floor(p / cell);
    float h = rautaHash(cellIndex);
    float h2 = rautaHash(cellIndex + 17.0);
    float stray = step(h, 0.26 * wake) * (1.0 - swept)
        * (0.5 + 0.5 * sin(time * (3.0 + 6.0 * h2) + h2 * 6.2832));

    field = saturate(field + ring + bands + stray * 0.34
        + wave * 0.5 * smoothstep(0.0, 0.06, 1.0 - pulse));

    // The dot matrix: one dot per cell, sized by the light.
    float2 local = fract(p / cell) - 0.5;
    float dist = length(local) * cell;
    float twinkle = 1.0 + closing * 0.5 * sin(time * 5.0 + h * 6.2832);
    float radius = cell * 0.4 * sqrt(saturate(field * twinkle));
    float sharp = 1.0 - smoothstep(radius - 0.7, radius + 0.3, dist);

    // The progressive blur toward the top and bottom edges.
    const float blurTop = 140.0;
    const float blurBottom = 180.0;
    float steady = cell * 0.4 * sqrt(field);
    float coverage = saturate(3.14159 * steady * steady / (cell * cell));
    float blurred = max(
        1.0 - smoothstep(blurTop * 0.3, blurTop, position.y),
        smoothstep(size.y - blurBottom, size.y - blurBottom * 0.3, position.y)
    );
    float dotMask = mix(sharp, coverage, blurred) * smoothstep(0.03, 0.14, field);

    half4 lit = mix(color, glow, half(field * 0.18 * strength));
    return mix(lit, ink, half(dotMask * (0.1 + field * 0.38 + stray * 0.7) * strength));
}

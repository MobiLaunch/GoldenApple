#version 440
// Liquid Glass over an app's own content (apps/lib/Glass.qml, `backdrop`):
// what's behind seen through a thick slab, as HyprGlass draws it over the
// desktop. A rounded-rectangle height field: flat in the middle, falling
// away across a bevel at the edge. Where it falls, the content is bent
// outward (the edge pulls in what lies just beyond it), with the colours
// parting slightly; under the middle a gentle dome magnifies it. A light
// blur on top. The source is the whole surface's backdrop (Backdrops.qml);
// `origin` is where this glass sits in it, so there is something beyond the
// glass's edge to pull in.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // the glass, px
    float radius;       // its corner radius, px
    float bevel;        // width of the edge where it bends, px
    float strength;     // how far the edge reaches out, px
    float dome;         // magnification under the middle (0: none)
    float dispersion;   // how far the colours part at the edge (0..1)
    float blur;         // blur radius, px
    vec2 origin;        // the glass's top-left in the source, px
    vec2 texSize;       // the source's size, px
};
layout(binding = 1) uniform sampler2D source;

float roundRect(vec2 p, vec2 half_, float r) {
    vec2 q = abs(p) - half_ + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Premultiplied, as the source is: a see-through part of the backdrop (a
// sidebar over the desktop) stays see-through.
vec4 sampleAt(vec2 px) {
    vec2 uv = clamp((origin + px) / texSize, vec2(0.0), vec2(1.0));
    vec2 t = vec2(blur) / texSize;
    vec4 c = texture(source, uv) * 0.36;
    c += texture(source, uv + vec2(t.x, 0.0)) * 0.16;
    c += texture(source, uv - vec2(t.x, 0.0)) * 0.16;
    c += texture(source, uv + vec2(0.0, t.y)) * 0.16;
    c += texture(source, uv - vec2(0.0, t.y)) * 0.16;
    return c;
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    vec2 p = px - size * 0.5;
    float r = min(radius, min(size.x, size.y) * 0.5);
    float d = roundRect(p, size * 0.5, r);                  // < 0 inside
    // Height: 0 at the edge, 1 a bevel in; its slope bends the light.
    float h = smoothstep(0.0, 1.0, clamp(-d / max(bevel, 1.0), 0.0, 1.0));
    vec2 e = vec2(0.75, 0.0);
    vec2 n = vec2(roundRect(p + e.xy, size * 0.5, r) - roundRect(p - e.xy, size * 0.5, r),
                  roundRect(p + e.yx, size * 0.5, r) - roundRect(p - e.yx, size * 0.5, r));
    n = n / max(length(n), 1e-4);                           // outward
    float bend = (1.0 - h) * (1.0 - h) * strength;
    // The dome: sample nearer the middle, so it looks magnified.
    vec2 swell = -p * dome * h;
    vec2 at = px + n * bend + swell;
    vec2 fringe = n * bend * dispersion;
    vec4 c = sampleAt(at);
    // The colours part only in the bevel; across the flat middle one
    // lookup is enough (a third of the work over most of the glass).
    if (bend * dispersion > 0.05)
        c = vec4(sampleAt(at + fringe).r, c.g, sampleAt(at - fringe).b, c.a);
    float coverage = clamp(0.5 - d, 0.0, 1.0);              // antialiased edge
    fragColor = c * coverage * qt_Opacity;
}

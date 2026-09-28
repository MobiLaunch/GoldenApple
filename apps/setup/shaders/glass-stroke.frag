#version 440
// Liquid Glass in any shape: the glass "hello" of Setup Assistant.
//
// mask is the shape (white where the glass is), drawn by the item itself.
// Its edge normal and thickness come from sampling the mask in two rings
// around each pixel (a blurred gradient), so no distance field is needed. The
// backdrop is bent along that normal like a lens, split slightly by colour at
// the rim, and lit by a directional highlight, with the same restraint as
// compositor/liquid-glass/liquid-glass.frag.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 screenSize;    // backdrop size in pixels
    vec4 itemRect;      // this item in backdrop pixels
    float bevel;        // how far in from the edge the glass curves, in pixels
    float strength;     // refraction in pixels
    vec2 lightDir;
    vec4 tint;          // premultiplied
};
layout(binding = 1) uniform sampler2D backdrop;
layout(binding = 2) uniform sampler2D mask;

float sat(float x) { return clamp(x, 0.0, 1.0); }
vec3 sampleBackdrop(vec2 uv) { return texture(backdrop, clamp(uv, vec2(0.001), vec2(0.999))).rgb; }

void main() {
    vec2 texel = 1.0 / itemRect.zw;
    // The mask over two rings (16 directions) around the pixel: its gradient
    // gives the surface normal, its average a smooth, antialiased edge.
    vec2 grad = vec2(0.0);
    float nearSum = 0.0, farSum = 0.0;
    for (int i = 0; i < 16; i++) {
        float a = float(i) * 0.392699;
        vec2 d = vec2(cos(a), sin(a));
        float near = texture(mask, qt_TexCoord0 + d * bevel * 0.4 * texel).a;
        float far = texture(mask, qt_TexCoord0 + d * bevel * texel).a;
        grad += d * (near * 0.55 + far * 0.45);
        nearSum += near; farSum += far;
    }
    float centre = texture(mask, qt_TexCoord0).a;
    float soft = (centre * 2.0 + nearSum / 16.0) / 3.0;
    float m = smoothstep(0.22, 0.62, soft);
    if (m < 0.004) discard;
    float fill = (nearSum + farSum) / 32.0;
    // grad points into the glass; the surface normal points out of it.
    vec2 n = -grad / 16.0;
    vec2 frag = itemRect.xy + qt_TexCoord0 * itemRect.zw;
    vec2 uv = frag / screenSize;

    // Lens: the backdrop pulled in from outside the rim, gently everywhere.
    vec2 bend = -nd * strength * (0.25 + 0.75 * slope * slope);
    vec2 buv = (frag + bend) / screenSize;
    vec2 disp = nd * min(strength * 0.08, 1.5) * slope / screenSize;
    vec3 base = vec3(sampleBackdrop(buv + disp).r, sampleBackdrop(buv).g, sampleBackdrop(buv - disp).b);
    // A little thickness: neighbours across the stroke.
    vec2 t = vec2(-nd.y, nd.x) / screenSize;
    base = base * 0.6 + (sampleBackdrop(buv + t * 1.5) + sampleBackdrop(buv - t * 1.5)) * 0.2;

    vec2 l = normalize(lightDir);
    float facing = sat(dot(nd, -l));
    float opposite = sat(dot(nd, l));
    float grazing = pow(slope, 1.6);

    vec3 col = base;
    col += vec3(0.22 * pow(facing, 1.5) * grazing);          // highlight on the lit rim
    col += vec3(0.08 * pow(opposite, 3.0) * grazing);        // soft catch opposite
    col += vec3(0.05 * (1.0 - slope) * sat(fill));           // light through the body

    float ta = sat(tint.a);
    col = mix(col, tint.rgb / max(ta, 1e-4), ta * mix(0.9, 0.6, slope));
    // Darker, denser glass right at the edge reads as thickness.
    col *= mix(1.0, 0.9, pow(slope, 3.0) * (1.0 - facing));

    fragColor = vec4(col * m, m) * qt_Opacity;
}

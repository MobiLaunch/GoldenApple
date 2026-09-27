// Liquid Glass: per-surface refraction + specular rim.
//
// Status: reference shader for the planned Hyprland plugin (see README.md).
// Hyprland's built-in blur gives us the frosted base; this pass runs on the
// already-blurred backdrop inside a glass surface's rounded rectangle and adds
// what blur alone can't: lens-like bending near the rim and a moving light catch.
// The maths matches prototype/js/glass.js so the browser reference and the
// compositor agree.
//
// Uniforms (supplied by the plugin per layer surface):
//   tex         the blurred backdrop, in screen space
//   surfaceRect x, y, w, h of the glass shape in pixels
//   radius      corner radius in pixels
//   bezel       width of the refracting band along the rim, in pixels (≈12–16)
//   strength    maximum displacement in pixels (≈10–16)
//   lightDir    normalised direction light comes from (default: top-left)
//   tint        premultiplied tint colour painted over the result

precision highp float;

varying vec2 v_texcoord;
uniform sampler2D tex;
uniform vec2 screenSize;
uniform vec4 surfaceRect;
uniform float radius;
uniform float bezel;
uniform float strength;
uniform vec2 lightDir;
uniform vec4 tint;

// Signed distance to a rounded rectangle centred at the origin (negative inside).
float sdRoundRect(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 frag = v_texcoord * screenSize;
    vec2 centre = surfaceRect.xy + surfaceRect.zw * 0.5;
    vec2 p = frag - centre;
    float d = sdRoundRect(p, surfaceRect.zw * 0.5, radius);
    if (d > 0.0) discard;

    // Outward surface normal from the SDF gradient.
    vec2 e = vec2(1.0, 0.0);
    vec2 n = normalize(vec2(
        sdRoundRect(p + e.xy, surfaceRect.zw * 0.5, radius) - sdRoundRect(p - e.xy, surfaceRect.zw * 0.5, radius),
        sdRoundRect(p + e.yx, surfaceRect.zw * 0.5, radius) - sdRoundRect(p - e.yx, surfaceRect.zw * 0.5, radius)) + 1e-5);

    // Convex lens profile: 0 in the flat centre, 1 at the rim (smoothstep falloff).
    float t = clamp(1.0 + d / bezel, 0.0, 1.0);
    float k = t * t * (3.0 - 2.0 * t);

    // Refraction: sample the backdrop pulled inwards, with a touch of
    // chromatic dispersion so edges pick up a faint colour fringe.
    vec2 offset = -n * k * strength;
    vec2 uv = (frag + offset) / screenSize;
    vec2 disp = n * k * 0.9 / screenSize;
    vec3 col = vec3(
        texture2D(tex, uv + disp).r,
        texture2D(tex, uv).g,
        texture2D(tex, uv - disp).b);

    // Specular rim: bright where the rim faces the light, dimmer opposite.
    float facing = dot(n, -normalize(lightDir));
    float rim = smoothstep(1.6, 0.0, -d) * (0.35 + 0.65 * max(facing, 0.0));
    float glow = smoothstep(bezel * 0.9, 0.0, -d) * 0.12 * max(facing, 0.0);
    col += vec3(rim * 0.55 + glow);

    // Tint on top (premultiplied), then antialias the outer edge.
    col = mix(col, tint.rgb / max(tint.a, 1e-4), tint.a);
    float alpha = clamp(-d, 0.0, 1.0);
    gl_FragColor = vec4(col * alpha, alpha);
}

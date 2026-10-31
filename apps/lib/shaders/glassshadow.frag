#version 440
// A piece of glass's shadow (apps/lib/Glass.qml), in one pass: a rounded
// rectangle's shadow, blurred as a Gaussian (erf across its edge) and dropped
// a little, with the glass's own shape cut out so the glass stays
// see-through. It replaces a MultiEffect over a layer, which cost every
// control an offscreen texture and several blur passes.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // this item: the glass and `pad` all round, px
    vec2 glass;         // the glass, px
    float pad;          // room for the shadow on each side, px
    float radius;       // the glass's corner radius, px
    float sigma;        // the blur, px
    float offsetY;      // how far the shadow drops, px
    float strength;     // its opacity
    vec4 color;
};

float roundRect(vec2 p, vec2 half_, float r) {
    vec2 q = abs(p) - half_ + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Abramowitz & Stegun 7.1.26.
float erf_(float x) {
    float s = sign(x);
    x = abs(x);
    float t = 1.0 / (1.0 + 0.3275911 * x);
    float y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x);
    return s * y;
}

void main() {
    vec2 px = qt_TexCoord0 * size - vec2(pad);          // in the glass's own coordinates
    vec2 half_ = glass * 0.5;
    float r = min(radius, min(half_.x, half_.y));
    float shadow = roundRect(px - half_ - vec2(0.0, offsetY), half_, r);
    float a = 0.5 - 0.5 * erf_(shadow / (max(sigma, 0.5) * 1.41421356));
    float outside = clamp(roundRect(px - half_, half_, r) + 0.5, 0.0, 1.0);
    float alpha = a * outside * strength * color.a;
    fragColor = vec4(color.rgb * alpha, alpha) * qt_Opacity;
}

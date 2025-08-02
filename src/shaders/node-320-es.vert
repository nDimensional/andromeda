#version 320 es
precision highp float;
precision highp int;

in vec2 aPos;
in vec2 aOffset;

uniform vec2 uResolution;
uniform vec2 uOffset;
uniform float uScale;
uniform float uDevicePixelRatio;

out vec2 vCenter;
out float vRadius;

void main() {
    vec2 c = (uOffset + aOffset) * uScale;
    vec2 v = aPos * vec2(100.0) * uScale + c;
    gl_Position = vec4(v / uResolution, 0.0, 1.0);
    vCenter = (uResolution * uDevicePixelRatio / 2.0) + c;

    float r = 20.0;
    vRadius = max(2.0, uScale * r);
}

#version 410 core
layout(location = 1) in vec2 aOffset;
layout(location = 0) in vec2 aPos;
layout(location = 2) in float aDegree;
uniform vec2 uResolution;
uniform vec2 uOffset;
uniform float uScale;
uniform float uDevicePixelRatio;
out vec2 vCenter;
out float vRadius;
void main() {
    // vec2 vPos = (aPos * vec2(100.0) + uOffset + aOffset) * vec2(uScale) / uResolution;
    // gl_Position = vec4(vPos, 0.0, 1.0);
    // vCenter = (uResolution * uDevicePixelRatio / 2) + (uOffset + aOffset) * uScale;
    // vRadius = max(2, uScale * (20 + sqrt(aDegree)));

    vec2 c = (uOffset + aOffset) * uScale;
    // vec2 v = aPos * vec2(100.0) * uScale + c;
    vec2 v = aPos * vec2(100.0);
    gl_Position = vec4(v / uResolution, 0.0, 1.0);
    // gl_Position = vec4(aPos.x, aPos.y, 0.0, 1.0);

    vCenter = (uResolution * uDevicePixelRatio / 2.0) + c;
    vRadius = max(2.0, uScale * (20.0 + sqrt(aDegree)));
}

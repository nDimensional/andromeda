#version 320 es
precision highp float;

in vec2 vCenter;
in float vRadius;

out vec4 FragColor;

uniform vec2 uResolution;

void main() {
    vec2 pixelPos = gl_FragCoord.xy;
    float dist = distance(pixelPos, vCenter);
    float alpha = 1.0 - smoothstep(vRadius - 2.0, vRadius, dist);
    FragColor = vec4(0.0, 0.0, 0.0, alpha);
}

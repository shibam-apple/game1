shader_type canvas_item;
// Cinema finish over the 3D view: soft vignette and a touch of film grain.
uniform float vignette = 0.4;
uniform float grain = 0.03;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 c = UV - 0.5;
	float v = smoothstep(0.35, 0.95, length(c * vec2(1.0, 0.82)) * 1.35) * vignette;
	float g = (hash(floor(UV * vec2(1280.0, 720.0)) + floor(TIME * 24.0) * 7.31) - 0.5) * 2.0 * grain;
	float light = max(g, 0.0);
	float dark = max(-g, 0.0) + v;
	float a = clamp(light + dark, 0.0, 1.0);
	COLOR = vec4(vec3(light / max(a, 0.0001)), a);
}

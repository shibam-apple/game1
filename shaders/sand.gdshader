shader_type spatial;
// Wind-rippled desert sand. Fully procedural, no texture files:
// large colour drift, fine grain, directional ripples and near-camera glints.

uniform sampler2D grain_n : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D drift_n : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D vary : repeat_enable, filter_linear_mipmap;
uniform vec3 col_light : source_color = vec3(0.66, 0.43, 0.27);
uniform vec3 col_dark : source_color = vec3(0.47, 0.28, 0.17);
uniform float ripple_strength = 0.1;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz;
	float dist = length(VERTEX);
	float near = 1.0 - smoothstep(18.0, 70.0, dist);

	float big = texture(vary, uv * 0.006).r;
	float mid = texture(vary, uv * 0.045 + vec2(0.37, 0.11)).r;

	// ripples: stripes across the wind, bent by noise so they never line up
	float phase = (uv.x * 0.94 + uv.y * 0.34) * 9.5 + mid * 7.0 + big * 12.0;
	float rip_h = sin(phase);
	vec2 rip_n = cos(phase) * vec2(0.94, 0.34) * ripple_strength * near;

	vec2 g = texture(grain_n, uv * 1.9).rg - 0.5;
	vec2 d = texture(drift_n, uv * 0.11).rg - 0.5;
	vec2 n = g * 0.55 * near + d * 0.9 + rip_n;

	vec3 col = mix(col_dark, col_light, clamp(big * 0.75 + mid * 0.45, 0.0, 1.0));
	col *= 0.93 + 0.07 * rip_h * near;
	ALBEDO = col;
	NORMAL_MAP = vec3(n + 0.5, 1.0);
	NORMAL_MAP_DEPTH = 1.1;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;

	// quartz glints close to the camera
	float spark = texture(vary, uv * 7.0).r * texture(vary, uv * 11.3 + vec2(0.5)).r;
	EMISSION = vec3(1.0, 0.86, 0.66) * smoothstep(0.62, 0.8, spark) * 0.5 * (1.0 - smoothstep(4.0, 22.0, dist));
}

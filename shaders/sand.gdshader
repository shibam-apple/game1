shader_type spatial;
// Desert ground from scanned sand (Poly Haven), with rain-damp patches and
// shallow pools on the flat duelling ground that mirror the sky.

uniform sampler2D dry_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D dry_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D dry_arm : repeat_enable, filter_linear_mipmap;
uniform sampler2D wet_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D wet_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D gravel_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D gravel_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D vary : repeat_enable, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.9, 0.64, 0.45);
uniform float wet_amount : hint_range(0.0, 1.0) = 0.3;
uniform float wet_radius = 34.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 uv = wpos.xz;
	float dist = length(VERTEX);
	float far = smoothstep(10.0, 55.0, dist) * 0.85;
	float big = texture(vary, uv * 0.006).r;

	// two tiling scales, blended by distance, so the repeat never shows
	vec3 alb = mix(texture(dry_albedo, uv * 0.21).rgb, texture(dry_albedo, uv * 0.033 + vec2(0.4)).rgb, far);
	vec3 nrm = mix(texture(dry_normal, uv * 0.21).rgb, texture(dry_normal, uv * 0.033 + vec2(0.4)).rgb, far);
	vec3 arm = texture(dry_arm, uv * 0.21).rgb;
	alb *= tint * mix(0.84, 1.1, big);
	float rough = arm.g;

	// stony, gravelly stretches break up the smooth sand near the camera
	float gm = smoothstep(0.42, 0.62, texture(vary, uv * 0.017 + vec2(0.61, 0.29)).r) * (1.0 - far);
	vec3 galb = texture(gravel_albedo, uv * 0.28).rgb * tint * 1.25;
	alb = mix(alb, galb, gm * 0.85);
	nrm = mix(nrm, texture(gravel_normal, uv * 0.28).rgb, gm);
	rough = mix(rough, 0.95, gm);

	// where the rain has not dried yet
	float w = texture(vary, uv * 0.021 + vec2(0.13, 0.71)).r + (wet_amount - 0.5) * 0.3;
	float where = smoothstep(0.90, 0.985, wnrm.y) * (1.0 - smoothstep(wet_radius * 0.7, wet_radius, length(wpos.xz)));
	float damp = smoothstep(0.47, 0.56, w) * where;
	float pool = smoothstep(0.585, 0.615, w) * where;

	vec3 walb = texture(wet_albedo, uv * 0.3).rgb * tint * 0.62;
	vec3 wn = texture(wet_normal, uv * 0.3).rgb;
	alb = mix(alb, walb, damp);
	nrm = mix(nrm, wn, damp);
	rough = mix(rough, 0.32, damp);

	// standing water: dark, flat, mirror-smooth
	alb = mix(alb, walb * 0.45, pool);
	nrm = mix(nrm, vec3(0.5, 0.5, 1.0), pool * 0.96);
	rough = mix(rough, 0.03, pool);

	ALBEDO = alb;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 1.25;
	ROUGHNESS = rough;
	AO = mix(arm.r, 1.0, pool);
	SPECULAR = mix(0.35, 0.75, pool);
}

// Faceted low-poly cel shading.
// Three tone bands (lit / mid / shadow) with warm tinted shadows, crisp cast
// shadows, a soft rim, and banded pools of light from lamps at night.
// Meshes are built with flat (per-face) normals, which gives the faceted look.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 mid_tone : source_color = vec4(0.8, 0.72, 0.76, 1.0);
uniform vec4 shade_tone : source_color = vec4(0.5, 0.42, 0.55, 1.0);
uniform float band_high : hint_range(-1.0, 1.0) = 0.45;
uniform float band_low : hint_range(-1.0, 1.0) = 0.0;
uniform float band_soft : hint_range(0.0, 0.3) = 0.02;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.18;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.0;
uniform float emission_strength = 0.0;
uniform bool use_vertex_color = false;

void fragment() {
	vec3 c = albedo.rgb;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	EMISSION = c * emission_strength;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	if (LIGHT_IS_DIRECTIONAL) {
		float shadow = smoothstep(0.35, 0.65, ATTENUATION);
		float lit_hi = smoothstep(band_high - band_soft, band_high + band_soft, ndl) * shadow;
		float lit_lo = smoothstep(band_low - band_soft, band_low + band_soft, ndl) * shadow;
		vec3 tone = mix(shade_tone.rgb, mid_tone.rgb, lit_lo);
		tone = mix(tone, vec3(1.0), lit_hi);
		DIFFUSE_LIGHT += tone * LIGHT_COLOR / PI;

		float rim = 1.0 - clamp(dot(VIEW, NORMAL), 0.0, 1.0);
		rim = smoothstep(0.72, 0.76, rim) * lit_lo;
		SPECULAR_LIGHT += rim * rim_strength * LIGHT_COLOR / PI;

		if (specular_strength > 0.0) {
			vec3 h = normalize(LIGHT + VIEW);
			SPECULAR_LIGHT += step(0.96, dot(NORMAL, h)) * lit_hi * specular_strength * LIGHT_COLOR / PI;
		}
	} else {
		// Lamps: two bands of light so pools look painted, not smooth.
		float l = clamp(ndl, 0.0, 1.0) * ATTENUATION;
		float banded = step(0.04, l) * 0.55 + step(0.25, l) * 0.45;
		DIFFUSE_LIGHT += banded * LIGHT_COLOR / PI;
	}
}

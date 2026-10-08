// Bright anime cel shading.
// Two clean tones (lit / shadow) with a soft painted edge and a cool tinted
// shadow, an optional soft "core" highlight, a crisp rim light, and banded
// pools of lamp light at night. Characters use smooth normals (soft anime
// forms); buildings keep flat normals (crisp low-poly planes).
shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 mid_tone : source_color = vec4(0.86, 0.8, 0.86, 1.0);   // unused by 2-tone, kept for compatibility
uniform vec4 shade_tone : source_color = vec4(0.62, 0.56, 0.76, 1.0);
uniform float band_high : hint_range(-1.0, 1.0) = 0.62;
uniform float band_low : hint_range(-1.0, 1.0) = 0.02;
uniform float band_soft : hint_range(0.0, 0.3) = 0.045;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.32;
uniform float highlight : hint_range(0.0, 1.0) = 0.06;
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
		float shadow = smoothstep(0.3, 0.7, ATTENUATION);
		float lit = smoothstep(band_low - band_soft, band_low + band_soft, ndl) * shadow;
		vec3 tone = mix(shade_tone.rgb, vec3(1.0), lit);
		// a soft brighter "core" where the light hits square on
		tone += highlight * smoothstep(band_high - band_soft, band_high + band_soft, ndl) * shadow;
		DIFFUSE_LIGHT += tone * LIGHT_COLOR / PI;

		// Anime rim light: a bright crisp edge on the silhouette, strongest on the lit side.
		float fres = 1.0 - clamp(dot(VIEW, NORMAL), 0.0, 1.0);
		float rim = smoothstep(0.62, 0.7, fres) * (0.35 + 0.65 * lit);
		SPECULAR_LIGHT += rim * rim_strength * LIGHT_COLOR / PI;

		if (specular_strength > 0.0) {
			vec3 h = normalize(LIGHT + VIEW);
			SPECULAR_LIGHT += smoothstep(0.93, 0.95, dot(NORMAL, h)) * lit * specular_strength * LIGHT_COLOR / PI;
		}
	} else {
		// Lamps: two bands so the pools look painted.
		float l = clamp(ndl, 0.0, 1.0) * ATTENUATION;
		float banded = smoothstep(0.03, 0.06, l) * 0.45 + smoothstep(0.28, 0.32, l) * 0.3;
		DIFFUSE_LIGHT += banded * LIGHT_COLOR / PI;
	}
}

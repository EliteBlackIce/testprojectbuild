// Anime-style cel shading: hard light/shadow split with tinted (purple-ish)
// shadows, a crisp specular highlight and a bright rim light.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 shade_color : source_color = vec4(0.52, 0.47, 0.78, 1.0);
uniform float shade_threshold : hint_range(-1.0, 1.0) = 0.15;
uniform float shade_softness : hint_range(0.0, 0.5) = 0.025;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.25;
uniform float specular_size : hint_range(0.0, 1.0) = 0.94;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.35;
uniform float rim_size : hint_range(0.0, 1.0) = 0.68;
uniform float emission_strength = 0.0;

void fragment() {
	ALBEDO = albedo.rgb;
	EMISSION = albedo.rgb * emission_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(shade_threshold - shade_softness, shade_threshold + shade_softness, ndl);
	lit *= step(0.5, ATTENUATION);
	vec3 band = mix(shade_color.rgb, vec3(1.0), lit);
	DIFFUSE_LIGHT += band * LIGHT_COLOR / PI;

	vec3 h = normalize(LIGHT + VIEW);
	float spec = step(specular_size, dot(NORMAL, h)) * lit;
	SPECULAR_LIGHT += spec * specular_strength * LIGHT_COLOR / PI;

	float rim = 1.0 - dot(VIEW, NORMAL);
	rim = smoothstep(rim_size - 0.02, rim_size + 0.02, rim) * lit;
	SPECULAR_LIGHT += rim * rim_strength * LIGHT_COLOR / PI;
}

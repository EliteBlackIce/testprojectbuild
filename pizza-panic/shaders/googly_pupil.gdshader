// Flat black pupil with a little white anime sparkle.
shader_type spatial;
render_mode unshaded;

void fragment() {
	vec2 uv = UV * vec2(2.0, 1.0);
	float sparkle = 1.0 - step(0.07, distance(uv, vec2(0.62, 0.32)));
	ALBEDO = mix(vec3(0.05, 0.03, 0.07), vec3(1.0), sparkle);
}

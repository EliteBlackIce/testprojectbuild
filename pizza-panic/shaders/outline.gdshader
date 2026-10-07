// Inverted-hull ink outline, used as next_pass on toon materials.
// Faceted meshes have split normals, so the hull is pushed outward from the
// mesh's center instead of along normals (works well for convex parts).
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(0.17, 0.11, 0.1, 1.0);
uniform float outline_width = 0.02;

void vertex() {
	vec3 dir = VERTEX;
	float len = length(dir);
	if (len > 0.0001) {
		VERTEX += dir / len * outline_width;
	}
}

void fragment() {
	ALBEDO = outline_color.rgb;
}

// Inverted-hull outline. Used as next_pass on toon materials.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.12, 0.07, 0.16, 1.0);
uniform float outline_width = 0.035;
// Boxes have split normals, which tear the outline at corners. For those we
// push vertices away from the mesh center instead.
uniform bool expand_from_center = false;

void vertex() {
	if (expand_from_center) {
		VERTEX += normalize(VERTEX + vec3(0.0001)) * outline_width * 1.4;
	} else {
		VERTEX += NORMAL * outline_width;
	}
}

void fragment() {
	ALBEDO = outline_color.rgb;
}

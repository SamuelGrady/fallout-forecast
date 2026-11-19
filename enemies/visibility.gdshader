shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
void vertex() {
	VERTEX += NORMAL * 0.018;
}
void fragment() {
	ALBEDO = vec3(0.95, 1.0, 0.32);
}

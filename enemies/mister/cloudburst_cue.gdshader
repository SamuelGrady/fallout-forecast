shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float countdown = -1.0;

void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float distance_to_center = length(point);
	if (distance_to_center > 1.0) {
		discard;
	}

	// Give the boundary a dark backing so the amber holds up on painted
	// pavement as well as asphalt. The hatch identifies the dangerous side.
	float hatch = 1.0 - smoothstep(0.20, 0.30, fract((point.x + point.y) * 5.5));
	float rim = smoothstep(0.87, 0.90, distance_to_center);
	float amber_edge = smoothstep(0.91, 0.93, distance_to_center) *
		(1.0 - smoothstep(0.975, 0.99, distance_to_center));
	float timer = 1.0 - smoothstep(0.018, 0.039, abs(distance_to_center - countdown));
	vec3 amber = vec3(1.0, 0.57, 0.16);
	vec3 interior = mix(vec3(0.24, 0.12, 0.04), amber, max(hatch * 0.52, timer * 0.68));
	ALBEDO = mix(mix(interior, vec3(0.08, 0.043, 0.024), rim), amber, amber_edge);
	ALPHA = max(mix(0.20 + hatch * 0.28 + timer * 0.22, 0.85, rim), amber_edge);
}

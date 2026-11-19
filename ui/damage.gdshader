shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = smoothstep(0.22, 0.95, max(abs(p.x), abs(p.y)));
	COLOR = vec4(vec3(1.0, 0.08, 0.16), strength * (0.12 + edge * 0.8));
}

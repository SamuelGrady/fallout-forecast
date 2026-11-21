shader_type spatial;

uniform sampler2D ripple_pattern : source_color, filter_nearest, repeat_enable;
varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = world_xz * vec2(0.086, 0.105);
	vec2 drift = vec2(TIME * 0.038, -TIME * 0.018);
	vec3 texture_color = texture(ripple_pattern, uv + drift).rgb;
	float swell = sin(world_xz.y * 0.84 + world_xz.x * 0.16 - TIME * 1.06);
	float chop = sin(world_xz.x * 0.63 - world_xz.y * 1.31 + TIME * 0.74);
	float gleam = smoothstep(0.92, 1.24, swell + chop * 0.40);
	ALBEDO = mix(vec3(0.09, 0.20, 0.26), texture_color * vec3(0.48, 0.69, 0.75), 0.61);
	ALBEDO += gleam * vec3(0.07, 0.13, 0.12);
	ROUGHNESS = 0.72;
	SPECULAR = 0.28;
}

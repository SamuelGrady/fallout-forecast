shader_type canvas_item;
// Fast WebGL2 VHS overlay: zero screen_texture copies. Renders 240-line CRT
// scanlines, analog tape grain, edge vignette, rolling tracking bar, and
// lightning/downed static snow using pure alpha compositing.

uniform float lines = 240.0;
uniform float scanline_strength = 0.22;
uniform float vignette_strength = 0.42;
uniform float glitch = 0.0;
uniform float interface_only = 0.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	float fx = 1.0 - interface_only * 0.55;

	// 240-line CRT scanlines + faint RGB phosphor chroma edge tint.
	float scan = step(0.5, fract(uv.y * lines * 0.5)) * scanline_strength * fx;
	vec2 v = uv - 0.5;
	float vig = clamp(dot(v, v) * 2.2 * vignette_strength, 0.0, 0.75);

	// Subtle horizontal VHS tape grain and rolling faint head-switch bar.
	float row = floor(uv.y * lines);
	float col = floor(uv.x * 320.0);
	float grain = (hash(col * 13.7 + row * 71.3 + floor(t * 24.0)) - 0.5);
	float dark_a = clamp(scan + vig, 0.0, 0.82);

	// VHS tracking distortion bands + rolling sync bar + static snow on glitch.
	float band = step(1.0 - glitch * 0.45, hash(floor(uv.y * 18.0) + floor(t * 14.0)));
	float bar = 1.0 - smoothstep(0.0, 0.025, abs(fract(uv.y + t * 0.18) - 0.5) - 0.475);
	float snow_a = clamp((bar * 0.28 + band * 0.22 + abs(grain) * 0.32) * glitch * fx, 0.0, 0.65);

	// Subtle cyan/pink VHS chroma edge tint + bright snow when glitching.
	vec3 dark_tint = vec3(0.03, 0.015, 0.055) + vec3(0.04, 0.0, 0.03) * abs(v.x);
	vec3 snow_col = mix(vec3(0.72, 0.84, 0.9), vec3(0.95, 0.85, 0.92), step(0.0, grain));

	// Combine dark scanline/vignette layer with additive-feeling snow/grain.
	float total_a = clamp(dark_a + snow_a + abs(grain) * 0.045 * fx, 0.0, 0.85);
	vec3 out_col = mix(dark_tint, snow_col, clamp((snow_a + max(0.0, grain) * 0.05 * fx) / max(total_a, 0.001), 0.0, 1.0));
	COLOR = vec4(out_col, total_a);
}

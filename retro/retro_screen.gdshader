shader_type canvas_item;
// RetroScreen post effect: low-res pixelation, color bleed, ordered dither,
// scanlines, vignette and VHS tracking glitches. Drawn on a CanvasLayer under
// the HUD, so it only touches the 3D view.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
// Virtual vertical resolution (PS1 era: 240 lines). Width follows the aspect.
uniform float lines = 240.0;
// Colour levels per channel after dithering (32 = 15-bit colour).
uniform float levels = 32.0;
uniform float dither_strength = 1.0;
uniform float bleed_pixels = 0.75;
uniform float scanline_strength = 0.18;
uniform float vignette_strength = 0.35;
// 0 = clean tape, 1 = full tracking glitch (lightning, downed).
uniform float glitch = 0.0;
uniform float time_offset = 0.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return m[i] / 16.0 - 0.5;
}

void fragment() {
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 res = vec2(floor(lines * size.x / size.y), lines);
	vec2 uv = SCREEN_UV;
	float t = TIME + time_offset;

	// VHS tracking: rows slide sideways in bands, a rolling noise bar.
	float row = floor(uv.y * res.y);
	float band = step(1.0 - glitch * 0.35, hash(floor(uv.y * 18.0) + floor(t * 12.0)));
	float wobble = sin(uv.y * 40.0 + t * 30.0) * 0.004 * glitch;
	uv.x += band * (hash(row + floor(t * 20.0)) - 0.5) * 0.06 * glitch + wobble;
	uv.x += (hash(row * 0.37 + floor(t * 60.0)) - 0.5) * 0.0015;  // constant tape jitter

	// Pixelate to the virtual resolution.
	vec2 cell = floor(uv * res);
	vec2 puv = (cell + 0.5) / res;
	vec2 px = vec2(bleed_pixels / res.x, 0.0);
	vec3 col;
	col.r = texture(screen_texture, puv + px).r;
	col.g = texture(screen_texture, puv).g;
	col.b = texture(screen_texture, puv - px).b;

	// Ordered dither, then quantize.
	col += bayer4(cell) * dither_strength / levels;
	col = floor(col * levels + 0.5) / levels;

	// Scanlines on the virtual lines, vignette.
	col *= 1.0 - scanline_strength * step(0.5, fract(uv.y * res.y * 0.5));
	vec2 v = SCREEN_UV - 0.5;
	col *= 1.0 - vignette_strength * dot(v, v) * 2.0;

	// Rolling tracking bar and snow when glitching.
	float bar = smoothstep(0.0, 0.02, abs(fract(SCREEN_UV.y + t * 0.15) - 0.5) - 0.48);
	col = mix(col, vec3(0.9), (1.0 - bar) * 0.25 * glitch);
	col += (hash(cell.x * 13.1 + cell.y * 71.7 + floor(t * 30.0)) - 0.5) * 0.25 * glitch;

	COLOR = vec4(col, 1.0);
}

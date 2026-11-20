shader_type spatial;
// PS1-style surface: vertices snap to a coarse screen grid (wobble), nearest
// texture filtering, optional affine texture warping. RetroMaterials swaps
// opaque StandardMaterial3Ds for this at runtime, copying their colour and
// texture (including world triplanar for the graybox grid).

render_mode diffuse_lambert, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform bool triplanar = false;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
// Snap grid in clip space; 0 turns snapping off.
uniform float snap = 120.0;
uniform bool affine = false;
uniform bool use_vertex_color = false;
uniform float dry_roughness = 1.0;
uniform float wetness = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying float affine_w;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (snap > 0.0 && !triplanar) {
		vec2 grid = vec2(snap * VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, snap);
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;
	affine_w = clip.w;
	UV = UV * uv_scale.xy + uv_offset.xy;
	if (affine) {
		UV *= affine_w;
	}
}

void fragment() {
	vec4 c = albedo;
	if (use_vertex_color) {
		// Vertex colours are authored in sRGB (MeshMerge); match albedo's space.
		vec3 v = COLOR.rgb;
		vec3 lin = mix(pow((v + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), v * (1.0 / 12.92), lessThan(v, vec3(0.04045)));
		c *= vec4(lin, COLOR.a);
	}
	if (use_texture) {
		if (triplanar) {
			vec3 w = pow(abs(world_normal), vec3(4.0));
			w /= (w.x + w.y + w.z);
			vec3 p = world_pos * uv_scale;
			c *= texture(albedo_texture, p.zy) * w.x + texture(albedo_texture, p.xz) * w.y + texture(albedo_texture, p.xy) * w.z;
		} else {
			vec2 uv = affine ? UV / affine_w : UV;
			c *= texture(albedo_texture, uv);
		}
	}
	ALBEDO = c.rgb * (1.0 - 0.42 * wetness);
	ROUGHNESS = mix(dry_roughness, 0.25, wetness);
	SPECULAR = 0.48 * wetness;
}

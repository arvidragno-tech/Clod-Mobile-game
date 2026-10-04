shader_type canvas_item;
// Black-market "bad signal": magenta scanlines, rare horizontal tears that
// shift the picture sideways, and faint chroma split. Subtle by design.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float intensity : hint_range(0.0, 1.0) = 0.6;
uniform vec4 tint : source_color = vec4(1.0, 0.24, 0.5, 1.0);

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = floor(TIME * 12.0);
	float band = floor(uv.y * 48.0);
	float tear = step(0.985, hash(band + t * 3.1)) * intensity;
	float shift = (hash(band * 7.0 + t) - 0.5) * 0.035 * tear;
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(shift + 0.0015 * intensity, 0.0)).r;
	col.g = texture(screen_tex, uv + vec2(shift, 0.0)).g;
	col.b = texture(screen_tex, uv + vec2(shift - 0.0015 * intensity, 0.0)).b;
	float scan = step(0.5, fract(FRAGCOORD.y / 4.0)) * 0.05 * intensity;
	col = mix(col, tint.rgb, scan + tear * 0.15);
	COLOR = vec4(col, 1.0);
}

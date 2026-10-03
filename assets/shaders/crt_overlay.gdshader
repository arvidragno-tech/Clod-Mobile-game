shader_type canvas_item;
// Subtle CRT treatment drawn over the whole game: scanlines, vignette and a
// faint animated grain. Kept deliberately light so the UI stays readable.

uniform float scanline_strength : hint_range(0.0, 0.5) = 0.07;
uniform float scanline_density = 1.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float noise_strength : hint_range(0.0, 0.2) = 0.025;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// Scanline every 3 physical pixels approx.
	float line = step(0.5, fract(FRAGCOORD.y / (3.0 * scanline_density)));
	float darkness = line * scanline_strength;
	vec2 centered = uv - 0.5;
	float vignette = smoothstep(0.35, 0.85, length(centered * vec2(1.0, 0.8))) * vignette_strength;
	float grain = (hash(floor(FRAGCOORD.xy / 3.0) + vec2(TIME * 7.0, TIME * 3.0)) - 0.5) * noise_strength;
	float alpha = clamp(darkness + vignette + max(grain, 0.0), 0.0, 1.0);
	COLOR = vec4(vec3(0.0), alpha);
}

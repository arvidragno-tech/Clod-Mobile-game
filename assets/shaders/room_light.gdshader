shader_type canvas_item;
// Lifts the shadows of a dark pixel-art scene without washing out its
// highlights (Settings > ROOM BRIGHTNESS). lift 1.0 = as drawn.
uniform float lift = 1.2;

void fragment() {
	vec4 c = COLOR;  // already texture x modulate in Godot 4
	c.rgb = pow(max(c.rgb, vec3(0.0)), vec3(1.0 / max(lift, 0.1)));
	COLOR = c;
}

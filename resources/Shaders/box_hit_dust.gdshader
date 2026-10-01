shader_type canvas_item;
render_mode unshaded;

uniform vec4 dust_color : source_color = vec4(0.50, 0.28, 0.12, 1.0);

void fragment() {
	COLOR *= dust_color;
}

shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_modifier : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec4 col = texture(TEXTURE, UV);
    // 원본 색상과 지정한 플래시 색상을 flash_modifier(0~1) 비율에 따라 섞습니다
    col.rgb = mix(col.rgb, flash_color.rgb, flash_modifier);
    COLOR = col;
}

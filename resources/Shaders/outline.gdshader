shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 10.0) = 1.0;
uniform bool is_active = false;

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_modifier : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec4 col = texture(TEXTURE, UV);
    vec4 final_col = col;
    final_col.rgb = mix(final_col.rgb, flash_color.rgb, flash_modifier);

    if (is_active && col.a == 0.0) {
        vec2 size = TEXTURE_PIXEL_SIZE * outline_width;
        float a = 0.0;
        
        // 8방향 체크로 외곽선 부드럽게 생성
        a += texture(TEXTURE, UV + vec2(0.0, -size.y)).a;
        a += texture(TEXTURE, UV + vec2(0.0, size.y)).a;
        a += texture(TEXTURE, UV + vec2(-size.x, 0.0)).a;
        a += texture(TEXTURE, UV + vec2(size.x, 0.0)).a;
        a += texture(TEXTURE, UV + vec2(-size.x, -size.y)).a;
        a += texture(TEXTURE, UV + vec2(size.x, -size.y)).a;
        a += texture(TEXTURE, UV + vec2(-size.x, size.y)).a;
        a += texture(TEXTURE, UV + vec2(size.x, size.y)).a;
        
        if (a > 0.0) {
            COLOR = outline_color;
        } else {
            COLOR = final_col;
        }
    } else {
        COLOR = final_col;
    }
}

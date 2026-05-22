shader_type canvas_item;

// [기본 외곽선]
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 10.0) = 1.0;
uniform bool is_active = false;

// [색상 플래시 - 피격/착지용]
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_modifier : hint_range(0.0, 1.0) = 0.0;

// [글로우 효과 - 보너스용]
uniform bool glow_active = false;
uniform vec4 glow_color : source_color = vec4(0.0, 1.0, 1.0, 1.0); // 시안색
uniform float glow_intensity : hint_range(0.0, 5.0) = 0.0;

// [디졸브 효과 - 사망용]
uniform float dissolve_value : hint_range(0.0, 1.1) = 0.0;

// 노이즈 함수 (디졸브용)
float rand(vec2 co) {
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

void fragment() {
    vec4 col = texture(TEXTURE, UV);
    vec4 final_col = col;
    
    // 1. 디졸브 (Dissolve) 처리
    float noise = rand(UV + floor(TIME * 10.0) * 0.001); // 픽셀 느낌 노이즈
    if (col.a > 0.0 && dissolve_value > 0.0) {
        if (noise < dissolve_value) {
            discard; // 픽셀 버림
        }
    }

    // 2. 전체 색상 플래시 적용 (피격/착지)
    final_col.rgb = mix(final_col.rgb, flash_color.rgb, flash_modifier);

    // 3. 글로우 (Glow) 처리 - 오라 느낌
    if (glow_active && col.a > 0.0) {
        float pulse = (sin(TIME * 10.0) * 0.5 + 0.5) * glow_intensity;
        final_col.rgb = mix(final_col.rgb, glow_color.rgb, pulse * 0.5);
    }

    // 4. 외곽선 처리
    if (is_active && col.a == 0.0) {
        vec2 size = TEXTURE_PIXEL_SIZE * outline_width;
        float a = 0.0;
        
        a += texture(TEXTURE, UV + vec2(0.0, -size.y)).a;
        a += texture(TEXTURE, UV + vec2(0.0, size.y)).a;
        a += texture(TEXTURE, UV + vec2(-size.x, 0.0)).a;
        a += texture(TEXTURE, UV + vec2(size.x, 0.0)).a;
        
        if (a > 0.0) {
            COLOR = outline_color;
        } else {
            COLOR = vec4(final_col.rgb, final_col.a);
        }
    } else {
        COLOR = vec4(final_col.rgb, final_col.a);
    }
}

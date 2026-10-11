shader_type canvas_item;

// 같은 스프라이트로 색만 다른 몹을 만들 때 쓰는 몸 색 셰이더 (쥐 변종 등).
// 원본 밝기(명암)는 살리고 색만 tint_color로 바꾼다. 피격 플래시(flash_modifier)와 사망 디졸브(dissolve_value)는
// CombatBody2D / EnemyBase가 이름으로 건드리므로 outline.gdshader와 같은 이름을 쓴다.
uniform vec4 tint_color : source_color = vec4(1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 1.0;
uniform float tint_brightness : hint_range(0.0, 8.0) = 2.5; // 원본이 어두우면 키운다

uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_modifier : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve_value : hint_range(0.0, 1.1) = 0.0;

float rand(vec2 co) {
	return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (dissolve_value > 0.0 && rand(UV + floor(TIME * 10.0) * 0.001) < dissolve_value) {
		discard;
	}
	float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	vec3 tinted = clamp(tint_color.rgb * lum * tint_brightness, 0.0, 1.0);
	col.rgb = mix(col.rgb, tinted, tint_strength);
	col.rgb = mix(col.rgb, flash_color.rgb, flash_modifier);
	COLOR = col;
}

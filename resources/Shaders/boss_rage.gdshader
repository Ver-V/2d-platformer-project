shader_type canvas_item;

// 보스 몸 셰이더: 광폭화(rage_amount)하면 붉은 기가 돌며 은은하게 맥동한다.
// 피격 플래시(flash_modifier)·사망 디졸브(dissolve_value)는 CombatBody2D / EnemyBase가 이름으로 건드리므로 같은 이름을 쓴다.
uniform vec4 rage_color : source_color = vec4(1.0, 0.25, 0.2, 1.0);
uniform float rage_amount : hint_range(0.0, 1.0) = 0.0;
uniform float rage_pulse_speed = 6.0;

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
	float pulse = 0.8 + 0.2 * sin(TIME * rage_pulse_speed);
	vec3 raged = col.rgb * mix(vec3(1.0), rage_color.rgb, 0.6) + rage_color.rgb * 0.12;
	col.rgb = mix(col.rgb, raged, rage_amount * pulse);
	col.rgb = mix(col.rgb, flash_color.rgb, flash_modifier);
	COLOR = col;
}

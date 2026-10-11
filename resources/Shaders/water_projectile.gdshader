shader_type canvas_item;

// 물 투사체: 원본(불꽃) 그림의 명암만 살리고 물색으로 칠한다.
// Projectile.set_parryable_mode가 modulate를 바꾸면(패링 가능 신호색, 반사된 색) 물색 대신 그 색으로 칠해서,
// 파란 몸에 신호색이 곱해져 묻히지 않고 또렷하게 보이게 한다.
uniform vec4 water_color : source_color = vec4(0.3, 0.65, 1.0, 1.0);
uniform float brightness : hint_range(0.0, 4.0) = 1.6;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 m = COLOR.rgb / max(tex.rgb, vec3(0.001)); // COLOR = 텍스처 × modulate → modulate만 꺼낸다
	m = clamp(m, 0.0, 1.0);
	bool plain = m.r + m.g + m.b > 2.97; // modulate가 흰색이면 기본 물색
	vec3 tint = plain ? water_color.rgb : m;
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(clamp(tint * lum * brightness, 0.0, 1.0), COLOR.a);
}

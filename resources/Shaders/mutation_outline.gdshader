shader_type canvas_item;

// 변이체 윤곽선 (MobMutation). mode: 0 = 고정 색, 1 = 무지개(빠르게 반짝), 2 = 주기적으로 반짝
uniform vec4 outline_color : source_color = vec4(1.0);
uniform float outline_width : hint_range(0.0, 3.0) = 1.0; // 픽셀 단위
uniform int mode = 0;
uniform float rainbow_speed = 3.0; // 초당 색상환 회전 수
uniform float flicker_speed = 18.0; // 무지개 밝기 깜빡임 속도
uniform float pulse_period = 5.0; // 이 주기(초)마다
uniform float pulse_length = 0.6; // 이 시간 동안 반짝인다

// 사망 디졸브 (EnemyBase._fade_out_and_free가 dissolve_value를 올린다)
uniform float dissolve_value : hint_range(0.0, 1.1) = 0.0;

float rand(vec2 co) {
	return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 hue_to_rgb(float h) {
	vec3 k = abs(fract(vec3(h) + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return clamp(k - 1.0, 0.0, 1.0);
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (dissolve_value > 0.0 && rand(UV + floor(TIME * 10.0) * 0.001) < dissolve_value) {
		discard;
	}
	if (col.a > 0.0) {
		COLOR = col;
	} else {
		// 둘레 outline_width 픽셀 안에 그림이 있으면 윤곽선
		float a = 0.0;
		float r2 = outline_width * outline_width + 0.5;
		for (int x = -3; x <= 3; x++) {
			for (int y = -3; y <= 3; y++) {
				if ((x == 0 && y == 0) || float(x * x + y * y) > r2) {
					continue;
				}
				a = max(a, texture(TEXTURE, UV + vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE).a);
			}
		}
		vec4 oc = outline_color;
		if (mode == 1) {
			oc.rgb = hue_to_rgb(fract(TIME * rainbow_speed + (UV.x + UV.y) * 4.0));
			oc.a *= 0.65 + 0.35 * sin(TIME * flicker_speed);
		} else if (mode == 2) {
			float t = mod(TIME, pulse_period);
			oc.a *= t < pulse_length ? sin(t / pulse_length * PI) : 0.0;
		}
		COLOR = a > 0.0 ? vec4(oc.rgb, oc.a * a) : col;
	}
}

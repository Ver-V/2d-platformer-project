shader_type canvas_item;

// 월드 좌표 기준: center(플레이어 위치)에서 radius 밖은 darkness 색으로 가린다.
uniform vec2 center = vec2(0.0);
uniform float radius = 64.0;
uniform float softness = 12.0; // 경계를 부드럽게 흐리는 폭 (월드 픽셀)
uniform vec4 darkness : source_color = vec4(0.0, 0.0, 0.0, 1.0);

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float dist = distance(world_pos, center);
	float shade = smoothstep(radius - softness, radius, dist);
	COLOR = vec4(darkness.rgb, darkness.a * shade);
}

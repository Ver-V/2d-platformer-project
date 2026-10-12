shader_type canvas_item;

// 월드 좌표 기준: center(플레이어 위치)에서 radius 밖은 darkness 색으로 가린다.
// 켜진 횃불 등 추가 빛(light_centers / light_radii, 앞에서 light_count개)의 원 안도 밝게 둔다.
const int MAX_LIGHTS = 16; // VisionLimit.MAX_LIGHTS와 같아야 한다

uniform vec2 center = vec2(0.0);
uniform float radius = 64.0;
uniform float softness = 12.0; // 경계를 부드럽게 흐리는 폭 (월드 픽셀)
uniform vec4 darkness : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform int light_count = 0;
uniform vec2 light_centers[16];
uniform float light_radii[16];

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float shade = smoothstep(radius - softness, radius, distance(world_pos, center));
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= light_count) {
			break;
		}
		float r = light_radii[i];
		shade = min(shade, smoothstep(r - softness, r, distance(world_pos, light_centers[i])));
	}
	COLOR = vec4(darkness.rgb, darkness.a * shade);
}

#!/usr/bin/env bash
# 회귀 테스트 전체 실행. 하나라도 실패하면 exit 1.
# 테스트 스크립트의 종료 코드만 보면 런타임 스크립트 에러(검사가 중간에 멈춤)가 PASS로 보이므로,
# 출력에 "SCRIPT ERROR"가 있어도 실패로 친다.
#
# 사용법: ./run_tests.sh            (전체)
#         ./run_tests.sh enemy      (이름에 enemy가 들어간 테스트만)

cd "$(dirname "$0")" || exit 1

# 데스크톱 / 노트북 Godot 경로 중 있는 것 (GODOT 환경 변수로 직접 지정 가능)
if [ -z "$GODOT" ]; then
	for candidate in \
		"/c/Users/dktmv/Desktop/개발자/Godot_v4.5.1-stable_win64_console.exe" \
		"/c/Users/User/Desktop/Compiler/Godot_v4.5.1-stable_win64_console.exe"; do
		if [ -f "$candidate" ]; then
			GODOT="$candidate"
			break
		fi
	done
fi
if [ -z "$GODOT" ] || [ ! -f "$GODOT" ]; then
	echo "Godot console build not found. Set GODOT=/path/to/Godot_v4.5.1-stable_win64_console.exe"
	exit 1
fi

TESTS="${TESTS:-tutorial_regressions item_shop_regressions enemy_regressions stage02_regressions status_effect_regressions combat_regressions mutation_regressions}"
FILTER="$1"
FAILED=""
LOG="$(mktemp)"

for t in $TESTS; do
	if [ -n "$FILTER" ] && [[ "$t" != *"$FILTER"* ]]; then
		continue
	fi
	# 런타임 에러로 run_checks()가 멈추면 quit()에 도달하지 못해 Godot가 끝나지 않으므로 시간 제한을 둔다
	timeout "${TEST_TIMEOUT:-300}" "$GODOT" --headless --path . --script "res://tests/$t.gd" > "$LOG" 2>&1
	code=$?
	errors="$(grep -A1 "SCRIPT ERROR" "$LOG")"
	summary="$(grep -E "regression checks: (PASS|FAIL)" "$LOG" | tail -1)"
	if [ $code -ne 0 ] || [ -n "$errors" ] || [ -z "$summary" ]; then
		FAILED="$FAILED $t"
		echo "FAIL  $t (exit $code)"
		# 실패한 check 메시지와 스크립트 에러
		grep -E "^ERROR|SCRIPT ERROR|^\s+at: " "$LOG" | grep -v "Main_Font\|initialize_theme" | head -40
		[ $code -eq 124 ] && echo "      (timed out after ${TEST_TIMEOUT:-300}s — a script error probably stopped run_checks before quit())"
		[ -z "$summary" ] && echo "      (no summary line — the test stopped before finishing)"
	else
		echo "PASS  $t"
	fi
done
rm -f "$LOG"

if [ -n "$FAILED" ]; then
	echo "Failed:$FAILED"
	exit 1
fi
echo "All tests passed."

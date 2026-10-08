#!/usr/bin/env bash
# 공개 저장소(포트폴리오, 이력서 링크)에 올릴 파일만 내보낸다. 작업은 private 저장소에서만 한다.
# 사용법 (Git Bash): ./tools/publish_showcase.sh [공개 저장소 클론 폴더]   기본값: ../2d-platformer-showcase
# 마지막 커밋(HEAD) 기준으로 복사하므로 먼저 private에 커밋할 것. 공개 쪽 커밋/푸시는 결과를 확인하고 직접 한다.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$SRC/../2d-platformer-showcase}"
PUBLIC_URL="https://github.com/Ver-V/2d-platformer-project.git"

# 공개할 경로. 외부 에셋(Assets/, resources/Music, resources/Portraits, Main_Font, addons/godot_mcp)과
# CLAUDE.md, 작업 로그는 여기에 넣지 않는다.
PUBLIC_PATHS=(
	Script Scenes tests tools run_tests.sh addons/persist_ids
	resources/Dialogues resources/i18n resources/items resources/shops resources/loot
	resources/status_effects resources/Shaders
	project.godot export_presets.cfg default_bus_layout.tres icon.svg icon.svg.import
	README.md credits.txt .gitignore .gitattributes .editorconfig
)
# 위 폴더 안에 섞여 들어간 에셋도 빼낸다
EXCLUDE_GLOBS=('*.png' '*.png.import' '*.jpg' '*.jpg.import' '*.mp3' '*.mp3.import'
	'*.wav' '*.wav.import' '*.ogg' '*.ogg.import' '*.ttf' '*.otf' '*.tmp')

if [ ! -d "$DEST/.git" ]; then
	git clone "$PUBLIC_URL" "$DEST"
fi
if [ -n "$(git -C "$DEST" status --porcelain)" ]; then
	echo "공개 저장소 폴더에 정리 안 된 변경이 있습니다: $DEST" >&2
	exit 1
fi
git -C "$DEST" pull --ff-only

# 공개 폴더를 비우고 HEAD의 허용 경로만 다시 채운다 (지워진 파일도 반영되게)
find "$DEST" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
git -C "$SRC" archive HEAD -- "${PUBLIC_PATHS[@]}" | tar -x -C "$DEST"
for glob in "${EXCLUDE_GLOBS[@]}"; do
	find "$DEST" -path "$DEST/.git" -prune -o -type f -name "$glob" -print -exec rm -f {} +
done

git -C "$DEST" add -A
echo
echo "== 공개 저장소에 반영될 변경 ($DEST) =="
git -C "$DEST" status --short
echo
echo "확인 후: cd \"$DEST\" && git commit -m \"<메시지>\" && git push"

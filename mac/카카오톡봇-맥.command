#!/bin/bash
# 카카오 발송기 (맥용) 실행기
# 이 파일을 두 번 눌러 실행합니다.

cd "$(dirname "$0")" || exit 1
SCRIPT="kakao-mac.js"

if [ ! -f "$SCRIPT" ]; then
  echo "kakao-mac.js 를 찾을 수 없습니다. 두 파일을 같은 폴더에 두세요."
  read -r -p "엔터를 누르면 닫힙니다." _
  exit 1
fi

run() { osascript -l JavaScript "$SCRIPT" "$@"; }

while true; do
  echo ""
  echo "=========================================="
  echo "  카카오 발송기 (맥용) v0.1"
  echo "=========================================="
  echo "  1) 쓸 수 있는 상태인지 확인"
  echo "  2) 카카오톡 화면 구조 저장   ← 처음에 이것부터"
  echo "  3) 채팅방 목록 읽기"
  echo "  4) 방 하나 열어 보기"
  echo "  5) 보내기 연습 (실제로 안 보냄)"
  echo "  6) 실제로 보내기"
  echo "  0) 끝내기"
  echo ""
  read -r -p "번호를 고르세요: " choice

  case "$choice" in
    1)
      run check
      ;;
    2)
      OUT="카카오톡-화면구조.txt"
      echo "저장 중입니다. 잠시 기다려 주세요..."
      run dump 8 > "$OUT" 2>&1
      echo "저장했습니다: $(pwd)/$OUT"
      echo "이 파일을 보내 주시면 맥 화면 구조에 맞게 고칠 수 있습니다."
      ;;
    3)
      run rooms
      ;;
    4)
      read -r -p "방 이름: " room
      [ -n "$room" ] && run open "$room"
      ;;
    5)
      read -r -p "방 이름: " room
      read -r -p "보낼 글: " message
      if [ -n "$room" ] && [ -n "$message" ]; then
        run send "$room" "$message"
      fi
      ;;
    6)
      read -r -p "방 이름: " room
      read -r -p "보낼 글: " message
      if [ -n "$room" ] && [ -n "$message" ]; then
        echo ""
        echo "'$room' 에 실제로 보냅니다."
        read -r -p "정말 보내려면 예 라고 입력하세요: " confirm
        if [ "$confirm" = "예" ]; then
          run send "$room" "$message" --live
        else
          echo "취소했습니다."
        fi
      fi
      ;;
    0)
      exit 0
      ;;
    *)
      echo "1 부터 6 사이의 번호나 0 을 눌러 주세요."
      ;;
  esac
done

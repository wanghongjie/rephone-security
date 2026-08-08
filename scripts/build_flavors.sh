#!/usr/bin/env bash
# 构建矩阵脚本（Android / iOS）：China / Global 两个市场。
#
# 用法：
#   ./scripts/build_flavors.sh <os> <market> <artifact> [build-type]
#
# 参数：
#   os           : android | ios
#   market       : china   | global
#   artifact     : apk | aab (仅 android) | ios (仅 ios)
#   build-type   : release (默认) | debug
#
# 示例：
#   # 构建国内版 Android APK（Release）
#   ./scripts/build_flavors.sh android china apk
#
#   # 构建海外版 Android App Bundle（Release）
#   ./scripts/build_flavors.sh android global aab
#
#   # 调试版：国内版 Android APK（Debug）
#   ./scripts/build_flavors.sh android china apk debug
#
#   # 构建海外版 iOS（Release）
#   ./scripts/build_flavors.sh ios global ios

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

log()  { printf '[build_flavors] %s\n' "$*"; }
die()  { printf '[build_flavors][ERROR] %s\n' "$*" >&2; exit 2; }

OS="${1:-}"; MARKET="${2:-}"; ARTIFACT="${3:-}"; BUILD_TYPE="${4:-release}"

case "${OS}" in
  android|ios) ;;
  *) die "非法 os='${OS}'，可选：android / ios";;
esac
case "${MARKET}" in
  china|global) ;;
  *) die "非法 market='${MARKET}'，可选：china / global";;
esac
case "${BUILD_TYPE}" in
  debug|release) ;;
  *) die "非法 build-type='${BUILD_TYPE}'，可选：debug / release";;
esac

FLUTTER_ARGS=("--${BUILD_TYPE}")
ANDROID_PROJECT_ARGS=()

case "${OS}" in
  android)
    case "${ARTIFACT}" in apk|aab) ;; *) die "Android artifact 只允许 apk / aab，当前：${ARTIFACT}" ;; esac
    case "${MARKET}" in
      global)
        FLUTTER_ARGS+=(
          "--flavor" "global"
          "-t" "lib/main.dart"
          "--dart-define=MARKET=global"
        )
        ANDROID_PROJECT_ARGS+=("targetRegion=global")
        ;;
      china)
        FLUTTER_ARGS+=(
          "--flavor" "china"
          "-t" "lib/main_china.dart"
          "--dart-define=MARKET=china"
        )
        ;;
    esac
    CMD=(flutter "build" "${ARTIFACT}" "${FLUTTER_ARGS[@]}")
    if [[ "${#ANDROID_PROJECT_ARGS[@]}" -gt 0 ]]; then
      EXTRA=()
      for arg in "${ANDROID_PROJECT_ARGS[@]}"; do EXTRA+=("--android-project-arg=${arg}"); done
      CMD+=("${EXTRA[@]}")
    fi
    ;;
  ios)
    if [[ "${ARTIFACT}" != "ios" ]]; then die "iOS artifact 只允许 ios，当前：${ARTIFACT}"; fi
    case "${MARKET}" in
      global)
        FLUTTER_ARGS+=(
          "--flavor" "Global"
          "-t" "lib/main.dart"
          "--dart-define=MARKET=global"
        )
        ;;
      china)
        FLUTTER_ARGS+=(
          "--flavor" "China"
          "-t" "lib/main_china.dart"
          "--dart-define=MARKET=china"
        )
        ;;
    esac
    CMD=(flutter "build" "${ARTIFACT}" "${FLUTTER_ARGS[@]}")
    ;;
esac

log "OS=${OS} MARKET=${MARKET} ARTIFACT=${ARTIFACT} BUILD_TYPE=${BUILD_TYPE}"
log "CMD: ${CMD[*]}"
"${CMD[@]}"

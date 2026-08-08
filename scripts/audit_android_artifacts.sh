#!/usr/bin/env bash
# Android 产物审计脚本：解压 APK/AAB 并粗扫不应出现在国内版中的包名/资源。
#
# 用法：
#   ./scripts/audit_android_artifacts.sh <apk|aab> <market> <file>
#
#   market = china  ：黑名单检查（不允许出现 gms/firebase/billingclient/gma 等关键字）
#   market = global ：仅做基线打印（不失败），便于对比。
#
# 示例：
#   ./scripts/audit_android_artifacts.sh apk china build/app/outputs/flutter-apk/app-china-release.apk

set -euo pipefail

ARTIFACT="${1:-}"
MARKET="${2:-}"
FILE="${3:-}"

case "${ARTIFACT}" in apk|aab) ;; *) echo "用法: $0 <apk|aab> <china|global> <file>" >&2; exit 2 ;; esac
case "${MARKET}" in china|global) ;; *) echo "market 必须 china|global" >&2; exit 2 ;; esac
if [[ ! -f "${FILE}" ]]; then echo "文件不存在: ${FILE}" >&2; exit 2; fi

FILE_ABS="$(cd "$(dirname "${FILE}")" && pwd)/$(basename "${FILE}")"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_BASE}"' EXIT

echo "[audit_android_artifacts] ARTIFACT=${ARTIFACT} MARKET=${MARKET}"
echo "[audit_android_artifacts] FILE=${FILE_ABS}"
echo "[audit_android_artifacts] TMPDIR=${TMPDIR_BASE}"

if [[ "${ARTIFACT}" == "apk" ]]; then
  (cd "${TMPDIR_BASE}" && unzip -q "${FILE_ABS}")
else
  (cd "${TMPDIR_BASE}" && unzip -q "${FILE_ABS}")
fi

BLACKLIST=(
  "com/google/android/gms/"
  "com/google/firebase/"
  "com/android/billingclient/"
  "com/google/android/gms/ads/"
  "META-INF/com/google/android/gms/"
  "META-INF/firebase/"
  "classes-global"
  "play-services-"
  "firebase-"
)

echo ""
echo "[audit_android_artifacts] ===== 关键条目（示例） ====="
find "${TMPDIR_BASE}" -maxdepth 2 -type d -print 2>/dev/null | sed 's#^#  #' | head -n 20 || true

echo ""
echo "[audit_android_artifacts] ===== 黑名单命中统计 ===== "
set +e
HITS=$(mktemp)
for entry in "${BLACKLIST[@]}"; do
  if [[ "${ARTIFACT}" == "apk" ]]; then
    # 1) 直接对整个解压目录做路径/文件名匹配
    c=$(find "${TMPDIR_BASE}" -iname "*${entry}*" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${c}" != "0" ]]; then
      echo "  path-hit: ${entry} => ${c}"
      echo "${entry}|${c}|path" >> "${HITS}"
    fi
    # 2) dex 级只统计「真正可加载的 Java 类描述符」，形如
    #    Lcom/google/android/gms/tasks/TaskCompletionSource;
    #    避免把 import 字符串、R8 保留的 debug 源码引用、dart 端非类命名字符串误算为命中。
    classRegex='^L'${entry//\//\\/}'[A-Za-z0-9_$]*;'
    dc=$(find "${TMPDIR_BASE}" -iname "*.dex" -print0 2>/dev/null \
      | xargs -0 strings 2>/dev/null | grep -E -c -- "${classRegex}" || true)
    dc=${dc:-0}
    if [[ "${dc}" != "0" ]]; then
      echo "  dex-hit : ${entry} => ${dc} (类描述符)"
      echo "${entry}|${dc}|dex" >> "${HITS}"
    fi
  else
    # AAB: 主要扫描 base.zip 内 classes.dex 与 manifest
    c=$(find "${TMPDIR_BASE}" -iname "*${entry}*" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${c}" != "0" ]]; then
      echo "  path-hit: ${entry} => ${c}"
      echo "${entry}|${c}|path" >> "${HITS}"
    fi
  fi
done
set -e

if [[ "${MARKET}" == "global" ]]; then
  echo ""
  echo "[audit_android_artifacts] global 模式：仅展示命中，不失败"
  exit 0
fi

if [[ ! -s "${HITS}" ]]; then
  echo ""
  echo "✓ [audit_android_artifacts] china 模式：未命中黑名单（粗查通过）"
  exit 0
fi

echo ""
echo "✗ [audit_android_artifacts] china 模式：存在黑名单命中；具体见上文统计。"
echo "  如为误报，可把对应条目移除/收敛为更精确的字符串。"
exit 1

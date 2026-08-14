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
#
# ------------------------------------------------------------------------------
# 【关键实现】global 构建：在 pubspec 层面移除国内支付 SDK
# ------------------------------------------------------------------------------
# 海外版本上架 Google Play / App Store 严禁出现任何国内支付 SDK 痕迹（例如微信支付 fluwx）。
# 仅通过 Dart 层条件 import + Android productFlavor exclude 仍会留下以下遗留物：
#   · :fluwx AndroidManifest 中的 WXEntryActivity / FluwxFileProvider / queries com.tencent.mm
#   · .aar 中的 classes.dex 含 com/jarvan/fluwx 包名
# Play 自动静态审核会命中后轻则开发者验证或直接拒审。
#
# 因此 market=global 时，采用以下流程在构建前从 pubspec.yaml/lock 直接移除 fluwx 依赖：
#   1. 将 pubspec.yaml / pubspec.lock 原子备份到 /tmp 下随机文件名；
#   2. perl 多行正则精准删除 2 行中文注释 + 1 行 fluwx: ^x.y.z 共 3 行块（精准到 dependency_overrides 之前不留空行断层）；
#   3. 强制 flutter pub get 让 .dart_tool/package_config.json / GeneratedPluginRegistrant 重建；
#   4. 执行构建；
#   5. trap EXIT/INT/TERM 无论构建成功失败 ctrl-c 都还原，确保开发者本地仓库不留脏代码
#
# market=china 时：不做任何 pubspec 变动，直接构建
# ------------------------------------------------------------------------------

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

# ==============================================================================
# global 构建：pubspec 临时补丁安装 + 原子还原（trap 保证）
# ------------------------------------------------------------------------------
# 说明：
#   PUBSPEC_PATCHED 标记=1 时，trap 回调中才会执行还原，避免 china 构建误操作。
#   BACKUP_DIR 放在 /tmp 下，与项目目录保持干净，使用 mktemp -d 防并发构建相互覆盖。
# ==============================================================================
PUBSPEC_PATCHED=0
# 注意：BACKUP_DIR 必须声明为 readonly / 全局字符串，避免某些 bash 版本在 trap
# 触发时进入子 shell 导致变量丢失；这里不用 export（仅本脚本使用），但使用
# 「绝对路径 + 在创建后立刻 dump 日志」确保可追踪。
BACKUP_DIR=""

cleanup_pubspec_patch() {
    # 关键：此函数在 set -euo pipefail 模式下运行，且作为 trap 回调，
    # 任何一步命令若返回非 0 都会导致整个 trap 中断（且 exit code 可能被置），
    # 进而造成 pubspec.yaml 未还原的严重后果。因此每条关键命令都显式
    # 追加 || true 进行 soft-fail；文件复制后用 cmp 或 md5 校验确认。
    if [[ "${PUBSPEC_PATCHED}" -ne 1 ]]; then
        return 0
    fi
    if [[ -z "${BACKUP_DIR}" || ! -d "${BACKUP_DIR}" ]]; then
        log "WARNING: PUBSPEC_PATCHED=1 但 BACKUP_DIR='${BACKUP_DIR}' 不存在，跳过还原"
        return 0
    fi

    log "cleanup: 还原 pubspec.yaml / pubspec.lock 至构建前状态 (BACKUP_DIR=${BACKUP_DIR}) ..."

    local restored_yaml=0 restored_lock=0
    if [[ -f "${BACKUP_DIR}/pubspec.yaml" ]]; then
        cp -f "${BACKUP_DIR}/pubspec.yaml" "${ROOT_DIR}/pubspec.yaml" 2>/dev/null || true
        if cmp -s "${BACKUP_DIR}/pubspec.yaml" "${ROOT_DIR}/pubspec.yaml" 2>/dev/null; then
            restored_yaml=1
        fi
    fi
    if [[ -f "${BACKUP_DIR}/pubspec.lock" ]]; then
        cp -f "${BACKUP_DIR}/pubspec.lock" "${ROOT_DIR}/pubspec.lock" 2>/dev/null || true
        if cmp -s "${BACKUP_DIR}/pubspec.lock" "${ROOT_DIR}/pubspec.lock" 2>/dev/null; then
            restored_lock=1
        fi
    fi

    if [[ "${restored_yaml}" -eq 1 && "${restored_lock}" -eq 1 ]]; then
        log "cleanup: pubspec.yaml / pubspec.lock 已成功还原，强制重算 .dart_tool/package_config.json (恢复 fluwx 条目)..."
        # 恢复 .dart_tool 必须执行。直接删除 .dart_tool/package_config.json 强制 flutter pub get 重新生成，
        # 避免 flutter 使用 stale 缓存导致下一次 china 构建找不到 fluwx。
        rm -f "${ROOT_DIR}/.dart_tool/package_config.json" \
              "${ROOT_DIR}/.dart_tool/package_config_subset" \
              "${ROOT_DIR}/.dart_tool/flutter_build/"*"/kernel_snapshot_program.d" 2>/dev/null || true
        (
            set +e
            cd "${ROOT_DIR}"
            flutter pub get --no-example
            echo "[cleanup: flutter pub get exit=$?" >/dev/null
        ) || true
        # 最终校验：package_config.json 中必须出现 fluwx 才能认为恢复完成
        if grep -q "fluwx" "${ROOT_DIR}/.dart_tool/package_config.json" >/dev/null 2>&1; then
            log "cleanup: .dart_tool/package_config.json 已含 fluwx，恢复完成"
        else
            log "cleanup: WARNING package_config.json 未检测到 fluwx，如后续构建失败请手动执行 flutter pub get"
        fi
    else
        log "cleanup: WARNING 文件还原失败，请手动从 ${BACKUP_DIR} 复制 pubspec.yaml / pubspec.lock 回项目根目录"
    fi

    # 即使还原失败，也尽量删掉备份临时目录避免 /tmp 污染
    rm -rf "${BACKUP_DIR}" 2>/dev/null || true
    PUBSPEC_PATCHED=0
    log "cleanup: done"
}
# 兼容 bash trap 语法：一次挂多个信号；另额外 TRAP 到 EXIT 防止脚本任何路径下正常退出遗漏清理
trap cleanup_pubspec_patch EXIT INT TERM HUP QUIT ABRT

apply_global_pubspec_patch() {
    log "market=global：为彻底移除 pubspec 中的 fluwx 微信 SDK 依赖（构建结束 trap 自动还原）..."
    BACKUP_DIR="$(mktemp -d -t rephone_global_build_pubspec_bak.XXXXXXXX)"

    cp -a "${ROOT_DIR}/pubspec.yaml" "${BACKUP_DIR}/pubspec.yaml"
    cp -a "${ROOT_DIR}/pubspec.lock" "${BACKUP_DIR}/pubspec.lock"

    # 精准删除：
    #   第 68 行：# 微信支付 SDK（仅国内版本 ...
    #   第 69 行：# 当前使用 6.x ...
    #   第 70 行：fluwx: ^6.0.2
    # 采用 perl -0777 多行模式，slurp 整文件替换；正则精确匹配「换行+任意空白+注释+依赖 三行块，不留空行断层。
    # 注：\s* 兼容行首空格数变化；[^\n]* 兼容注释未来升级版本号变化；当前 pubspec.yaml 中 dependency_overrides 之前出现
    #     唯一出现多行块就这一处。
    perl -0777 -i -pe \
      's/\n\s*#\s*微信支付 SDK[^\n]*\n\s*#\s*当前使用\s+6\.x[^\n]*\n\s*fluwx\s*:\s*[^\n]*//' \
      "${ROOT_DIR}/pubspec.yaml"

    if grep -qiE '^\s*fluwx\s*:' "${ROOT_DIR}/pubspec.yaml" >/dev/null 2>&1; then
        die "pubspec.yaml 中仍存在 fluwx 依赖声明，perl 补丁未命中，请检查文件中文注释格式是否变动"
    fi
    log "pubspec.yaml fluwx 依赖已移除，执行 flutter pub get 重建 package_config.json..."
    (cd "${ROOT_DIR}" && flutter pub get)
    PUBSPEC_PATCHED=1
    log "global 构建环境准备就绪"
}

if [[ "${MARKET}" == "global" ]]; then
    apply_global_pubspec_patch
fi

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

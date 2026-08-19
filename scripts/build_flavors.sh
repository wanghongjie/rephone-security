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
# 【关键实现】构建期 pubspec 依赖裁剪：实现国内 / 海外包的原生 SDK 隔离
# ------------------------------------------------------------------------------
# 海外版上架 Google Play / App Store 严禁出现任何国内支付 SDK 痕迹（例如微信支付 fluwx）：
#   · :fluwx AndroidManifest 中的 WXEntryActivity / FluwxFileProvider / queries com.tencent.mm
#   · .aar 中的 classes.dex 含 com/jarvan/fluwx 包名
# Play 自动静态审核会命中后轻则开发者验证或直接拒审。
#
# 国内版（安卓各厂商市场 / iOS 国区）不应携带 Google Play Billing / StoreKit 商店支付 SDK：
#   · :in_app_purchase_android 原生插件会把 Play BillingClient 链接进国内 APK
#   · :in_app_purchase_storekit 会把 StoreKit.framework 链接进 iOS 包
# 厂商市场 SDK 扫描 / Play 依赖申报都会因此产生不必要的合规风险。
#
# Dart 层已通过 DTO（lib/flavors/iap_models.dart）完成代码隔离——业务层不引用任何
# in_app_purchase 类型；但原生插件仍由 pubspec 依赖注入 GeneratedPluginRegistrant，
# 所以必须再做构建期 pubspec 裁剪才能真正断掉原生链路：
#
# market=global 时，构建前从 pubspec.yaml/lock 直接移除 fluwx 依赖；
# market=china  时，构建前从 pubspec.yaml/lock 直接移除国内版不应携带的商店支付 /
#   Firebase / AdMob 依赖（共 7 个）：
#     in_app_purchase / in_app_purchase_android / in_app_purchase_storekit
#     firebase_core / firebase_messaging / firebase_crashlytics / google_mobile_ads
#
# 统一流程：
#   1. 将 pubspec.yaml / pubspec.lock 原子备份到 /tmp 下随机文件名；
#   2. perl 多行正则精准删除目标依赖行；
#   3. 强制 flutter pub get 让 .dart_tool/package_config.json / GeneratedPluginRegistrant 重建；
#   4. 执行构建；
#   5. trap EXIT/INT/TERM 无论构建成功失败 ctrl-c 都按 patch 方向还原，确保本地仓库不留脏代码
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
# patch 方向：global（移除 fluwx）| china（移除 in_app_purchase*）。
# cleanup 还原时按该方向校验并恢复对应依赖，避免误还原成另一个市场的状态。
PUBSPEC_PATCH_MARKET=""
# 注意：BACKUP_DIR 必须声明为 readonly / 全局字符串，避免某些 bash 版本在 trap
# 触发时进入子 shell 导致变量丢失；这里不用 export（仅本脚本使用），但使用
# 「绝对路径 + 在创建后立刻 dump 日志」确保可追踪。
BACKUP_DIR=""

cleanup_pubspec_patch() {
    # ==========================================================================
    # 【关键设计：函数入口立即关闭 set -euo pipefail】
    # --------------------------------------------------------------------------
    # trap 回调中任何一步命令的非 0 退出都会在 set -e 下导致整个回调被 bash
    # 立刻中断（包括以下极容易忽略的 non-zero 场景）：
    #   · grep "xxx" file  —— 如果没匹配到 grep exit=1
    #   · grep -c "xxx"    —— 匹配到 0 行 grep exit=1
    #   · cmp -s a b       —— 文件不同 cmp exit=1
    #   · rm -f file 不存在时 —— 某些 bash 版本会 non-zero
    #   · flutter pub get  —— 网络或 lock 不一致时 non-zero
    # 之前版本因此多次出现 cleanup 中途退出 → pubspec.yaml 未还原的严重事故。
    # 所以本函数第一条命令必须显式 set +euo pipefail，关闭所有严格模式，
    # 然后通过 restored_yaml/restored_lock 变量在应用层追踪错误状态。
    # ==========================================================================
    set +euo pipefail

    if [[ "${PUBSPEC_PATCHED}" -ne 1 ]]; then
        return 0
    fi
    if [[ -z "${BACKUP_DIR}" || ! -d "${BACKUP_DIR}" ]]; then
        log "WARNING: PUBSPEC_PATCHED=1 但 BACKUP_DIR='${BACKUP_DIR}' 不存在，跳过还原"
        return 0
    fi

    log "cleanup: 还原 pubspec.yaml / pubspec.lock 至构建前状态 (BACKUP_DIR=${BACKUP_DIR}) ..."

    restored_yaml=0
    restored_lock=0
    if [[ -f "${BACKUP_DIR}/pubspec.yaml" ]]; then
        cp -f "${BACKUP_DIR}/pubspec.yaml" "${ROOT_DIR}/pubspec.yaml"
        if cmp -s "${BACKUP_DIR}/pubspec.yaml" "${ROOT_DIR}/pubspec.yaml"; then
            restored_yaml=1
        fi
    fi
    if [[ -f "${BACKUP_DIR}/pubspec.lock" ]]; then
        cp -f "${BACKUP_DIR}/pubspec.lock" "${ROOT_DIR}/pubspec.lock"
        if cmp -s "${BACKUP_DIR}/pubspec.lock" "${ROOT_DIR}/pubspec.lock"; then
            restored_lock=1
        fi
    fi

    # 按 patch 方向确定「需要验证恢复的包」与「flutter pub upgrade 恢复的包」。
    # global → fluwx；china → in_app_purchase* 三件套。
    case "${PUBSPEC_PATCH_MARKET}" in
      global)
        PATCH_CHECK_PKG="fluwx"
        PATCH_RESTORE_DEPS=(fluwx)
        ;;
      china)
        PATCH_CHECK_PKG="in_app_purchase"
        PATCH_RESTORE_DEPS=(in_app_purchase in_app_purchase_android in_app_purchase_storekit \
                            firebase_core firebase_messaging firebase_crashlytics google_mobile_ads)
        ;;
      *)
        log "WARNING: 未知 PUBSPEC_PATCH_MARKET='${PUBSPEC_PATCH_MARKET}'，跳过依赖恢复校验"
        PATCH_CHECK_PKG=""
        PATCH_RESTORE_DEPS=()
        ;;
    esac

    if [[ "${restored_yaml}" -eq 1 && "${restored_lock}" -eq 1 ]]; then
        log "cleanup: pubspec.yaml / pubspec.lock 已成功还原，强制重算 .dart_tool/package_config.json (恢复 ${PATCH_CHECK_PKG} 条目)..."
        rm -f "${ROOT_DIR}/.dart_tool/package_config.json" \
              "${ROOT_DIR}/.dart_tool/package_config_subset" \
              "${ROOT_DIR}/.dart_tool/flutter_build/"*"/kernel_snapshot_program.d"
        (
            cd "${ROOT_DIR}"
            flutter pub get --no-example 2>&1 | tail -3
        )
        # grep -c 命中 0 行时 exit=1，本函数内已 set +e，所以直接取 grep -c 结果，
        # 没命中时返回值是空 -> 用 awk 兜底成 0，-le 判断即可。
        has_pkg_count=0
        if [[ -n "${PATCH_CHECK_PKG}" ]]; then
          raw_count="$(grep -c "\"${PATCH_CHECK_PKG}\"" "${ROOT_DIR}/.dart_tool/package_config.json" 2>/dev/null)"
          if [[ -n "${raw_count}" ]]; then
            # shell 算术扩展，取第 1 行整数（防止出现多行或尾随换行导致 -gt 语法错）
            has_pkg_count=$(( raw_count + 0 ))
          fi
        fi
        if [[ "${has_pkg_count}" -gt 0 ]]; then
            log "cleanup: .dart_tool/package_config.json 已含 ${PATCH_CHECK_PKG} (${has_pkg_count} 条)，恢复完成"
        else
            log "cleanup: package_config.json 未检测到 ${PATCH_CHECK_PKG} (count=${has_pkg_count})，重试 flutter pub get..."
            (
                cd "${ROOT_DIR}"
                rm -f ".dart_tool/package_config.json" ".dart_tool/package_config_subset"
                # 关键修复：patch 期间 pub get 会把 pubspec.lock 中的对应包整段 entry 删除，
                # 恢复 pubspec.lock 原文件后，再次 flutter pub get 可能因「lockfile 仍与 package_config.json
                # 状态相匹配」而增量跳过。因此显式 `flutter pub upgrade <deps>` 强制重算锁文件、
                # 并把依赖重写回 package_config.json。upgrade 仅对 patch 相关包生效，不会牵动其他包。
                flutter pub get --no-example 2>&1 | tail -2
                if [[ "${#PATCH_RESTORE_DEPS[@]}" -gt 0 ]]; then
                    flutter pub upgrade "${PATCH_RESTORE_DEPS[@]}" 2>&1 | tail -3
                fi
            )
            raw_count2=0
            if [[ -n "${PATCH_CHECK_PKG}" ]]; then
              rc2="$(grep -c "\"${PATCH_CHECK_PKG}\"" "${ROOT_DIR}/.dart_tool/package_config.json" 2>/dev/null)"
              [[ -n "${rc2}" ]] && raw_count2=$(( rc2 + 0 ))
            fi
            if [[ "${raw_count2}" -gt 0 ]]; then
                log "cleanup: 重试后 package_config.json 已含 ${PATCH_CHECK_PKG} (${raw_count2} 条)，恢复完成"
            else
                log "cleanup: WARNING package_config.json 仍未检测到 ${PATCH_CHECK_PKG}，如后续构建失败请手动执行 flutter pub get"
            fi
        fi
    else
        log "cleanup: WARNING 文件还原失败 (yaml=${restored_yaml} lock=${restored_lock})，请手动从 ${BACKUP_DIR} 复制 pubspec.yaml / pubspec.lock 回项目根目录"
    fi

    rm -rf "${BACKUP_DIR}"
    PUBSPEC_PATCHED=0
    PUBSPEC_PATCH_MARKET=""
    log "cleanup: done"
}
# 兼容 bash trap 语法：一次挂多个信号；另额外 TRAP 到 EXIT 防止脚本任何路径下正常退出遗漏清理。
# 必须包含 PIPE：脚本输出被管道消费者提前关闭（如 `... | head`）时会收到 SIGPIPE，
# 若不 trap，bash 默认行为是立即终止且不触发 EXIT trap，导致 pubspec 补丁无法还原、
# 工作区遗留脏状态（后续构建会误报「脏状态」）。
trap cleanup_pubspec_patch EXIT INT TERM HUP QUIT ABRT PIPE

apply_global_pubspec_patch() {
    log "market=global：为彻底移除 pubspec 中的 fluwx 微信 SDK 依赖（构建结束 trap 自动还原）..."
    BACKUP_DIR="$(mktemp -d -t rephone_global_build_pubspec_bak.XXXXXXXX)"

    cp -a "${ROOT_DIR}/pubspec.yaml" "${BACKUP_DIR}/pubspec.yaml"
    cp -a "${ROOT_DIR}/pubspec.lock" "${BACKUP_DIR}/pubspec.lock"

    # 【关键防御】备份完成后立刻校验「备份文件里 fluwx 依赖声明」确实存在。
    # 否则一旦上一轮构建失败，工作目录 pubspec.yaml 本身就处于「已删除 fluwx」的脏状态，
    # 本次备份会把「脏状态」当成「原始状态」存下来，cleanup 还原后仍是脏的，
    # 后续 china 构建将遇到 package:fluwx not found 且难以排查。
    # 通过业务语义级的 grep 判断（而非字节级 cmp）彻底避免该类错误。
    if ! grep -qiE '^\s*fluwx\s*:' "${BACKUP_DIR}/pubspec.yaml"; then
        _BADDIR="${BACKUP_DIR}"
        BACKUP_DIR=""
        rm -rf "${_BADDIR}"
        # 重要：PUBSPEC_PATCHED 仍为 0，确保 EXIT trap 不执行任何「从脏 BACKUP 还原」逻辑，
        # 防止本就存在的工作目录正确文件被脏 BACKUP 覆盖还原回错误状态。
        die "BACKUP_DIR/pubspec.yaml 中未检测到 fluwx 依赖，工作目录可能处于上一次构建失败后的脏状态，请手动 flutter pub get 或还原 pubspec.yaml 后重试"
    fi

    # 精准删除：
    #   fluwx: ^6.0.2    （整一行，包括其上方紧邻的换行符）
    # 采用 perl -0777 多行模式，slurp 整文件替换；
    # 正则「\n[ \t]*fluwx\s*:\s*[^\n]*」匹配一个换行 + 0~N 个空格/tab + fluwx: + 到行尾全部内容。
    # 替换为空字符串后，前一行 package_info_plus 的结尾 \n 会直接衔接下一行 dependency_overrides
    #   之前的空行，不会产生断层的双空行。
    perl -0777 -i -pe \
      's/\n[ \t]*fluwx\s*:\s*[^\n]*//' \
      "${ROOT_DIR}/pubspec.yaml"

    if grep -qiE '^\s*fluwx\s*:' "${ROOT_DIR}/pubspec.yaml" >/dev/null 2>&1; then
        die "pubspec.yaml 中仍存在 fluwx 依赖声明，perl 补丁未命中，请检查 fluwx: 行的缩进或格式"
    fi
    log "pubspec.yaml fluwx 依赖已移除，执行 flutter pub get 重建 package_config.json..."
    (cd "${ROOT_DIR}" && flutter pub get)
    PUBSPEC_PATCHED=1
    PUBSPEC_PATCH_MARKET="global"
    log "global 构建环境准备就绪"
}

apply_china_pubspec_patch() {
    log "market=china：为彻底移除 pubspec 中的 in_app_purchase* / firebase* / google_mobile_ads 依赖（构建结束 trap 自动还原）..."
    BACKUP_DIR="$(mktemp -d -t rephone_china_build_pubspec_bak.XXXXXXXX)"

    cp -a "${ROOT_DIR}/pubspec.yaml" "${BACKUP_DIR}/pubspec.yaml"
    cp -a "${ROOT_DIR}/pubspec.lock" "${BACKUP_DIR}/pubspec.lock"

    # 【关键防御】备份完成后立刻校验「备份文件里 in_app_purchase / firebase_core 依赖声明」确实存在。
    # 否则一旦上一轮构建失败，工作目录 pubspec.yaml 本身就处于「已删除对应依赖」的脏状态，
    # 本次备份会把「脏状态」当成「原始状态」存下来，cleanup 还原后仍是脏的，
    # 后续 global 构建将遇到 package:xxx not found 且难以排查。
    if ! grep -qiE '^\s*in_app_purchase\s*:' "${BACKUP_DIR}/pubspec.yaml" || \
       ! grep -qiE '^\s*firebase_core\s*:' "${BACKUP_DIR}/pubspec.yaml"; then
        _BADDIR="${BACKUP_DIR}"
        BACKUP_DIR=""
        rm -rf "${_BADDIR}"
        # 重要：PUBSPEC_PATCHED 仍为 0，确保 EXIT trap 不执行任何「从脏 BACKUP 还原」逻辑，
        # 防止本就存在的工作目录正确文件被脏 BACKUP 覆盖还原回错误状态。
        die "BACKUP_DIR/pubspec.yaml 中未检测到 in_app_purchase / firebase_core 依赖，工作目录可能处于上一次构建失败后的脏状态，请手动 flutter pub get 或还原 pubspec.yaml 后重试"
    fi

    # 精准删除以下 7 行（含每行上方紧邻的换行符）：
    #   in_app_purchase: ^3.2.0
    #   in_app_purchase_android: ^0.4.0+8
    #   in_app_purchase_storekit: ^0.3.0
    #   firebase_core: any
    #   firebase_messaging: any
    #   firebase_crashlytics: ^5.0.8
    #   google_mobile_ads: any
    # 采用 perl -0777 多行模式，slurp 整文件替换；
    # 正则「\n[ \t]*(?:in_app_purchase(?:_android|_storekit)?|firebase_core|firebase_messaging|
    #   firebase_crashlytics|google_mobile_ads)\s*:\s*[^\n]*」+ /g 逐行删除。
    # 前缀不会误伤：in_app_purchase_android 行的 in_app_purchase 后紧跟 _android，不满足 \s*:；
    # firebase_core_platform_interface 行的 firebase_core 后紧跟 _，同样不满足 \s*:。
    perl -0777 -i -pe \
      's/\n[ \t]*(?:in_app_purchase(?:_android|_storekit)?|firebase_core|firebase_messaging|firebase_crashlytics|google_mobile_ads)\s*:\s*[^\n]*//g' \
      "${ROOT_DIR}/pubspec.yaml"

    if grep -qiE '^\s*(in_app_purchase(_android|_storekit)?|firebase_core|firebase_messaging|firebase_crashlytics|google_mobile_ads)\s*:' "${ROOT_DIR}/pubspec.yaml" >/dev/null 2>&1; then
        die "pubspec.yaml 中仍存在 in_app_purchase* / firebase* / google_mobile_ads 依赖声明，perl 补丁未命中，请检查依赖行缩进或格式"
    fi
    log "pubspec.yaml in_app_purchase* / firebase* / google_mobile_ads 依赖已移除，执行 flutter pub get 重建 package_config.json..."
    (cd "${ROOT_DIR}" && flutter pub get)
    PUBSPEC_PATCHED=1
    PUBSPEC_PATCH_MARKET="china"
    log "china 构建环境准备就绪"
}

case "${MARKET}" in
  global)
    apply_global_pubspec_patch
    ;;
  china)
    apply_china_pubspec_patch
    ;;
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

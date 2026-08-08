#!/usr/bin/env bash
# Dart 侧 import 审计脚本：用于校验「国内入口链路」不直接 import 海外 SDK 包。
# 这是一个“粗粒度白名单”检查，用于 Phase2/后续 CI 防回退。
#
# 用法：
#   ./scripts/audit_dart_imports.sh <chain>
#
#   chain = china | global
#
# - china : 审计 main_china.dart 链路：
#           * main_china.dart 本身不得出现 firebase_* / in_app_purchase* / google_mobile_ads，
#             也不得 import 任何 *_global.dart 实现文件；
#           * lib/ 其余文件不得非法 import（见 PATTERN），
#             但能力门面层（service_facades/placeholder/membership_page/*_noop/ad_service_china）
#             与海外专用实现 *_global.dart（仅应由 main.dart import）设为白名单放行。
# - global: 仅打印出现次数，不失败（允许业务/具体实现 import）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

CHAIN="${1:-}"
case "${CHAIN}" in china|global) ;; *) echo "用法: $0 <china|global>" >&2; exit 2 ;; esac

PATTERN='package:(firebase_core|firebase_messaging|firebase_crashlytics|in_app_purchase|in_app_purchase_android|in_app_purchase_storekit|google_mobile_ads)'

if [[ "${CHAIN}" == "global" ]]; then
  echo "[audit_dart_imports][global] 仅统计命中次数（不失败）："
  grep -RInE "${PATTERN}" lib || true
  exit 0
fi

echo "[audit_dart_imports][china] 开始扫描 china 链路的非法 import..."

# ------------------------------------------------------------
# 1) main_china.dart 精确规则：
#    a) 不得直接 import 海外 SDK 包
#    b) 不得 import 任何 *_global.dart 实现（国内入口只能 import noop/china 实现）
# ------------------------------------------------------------
PRIMARY_HITS=$(grep -nE "${PATTERN}" lib/main_china.dart || true)
if [[ -n "${PRIMARY_HITS}" ]]; then
  echo "✗ lib/main_china.dart 命中非法 SDK import:"
  echo "${PRIMARY_HITS}"
  exit 1
fi

GLOBAL_IMPL_HITS=$(grep -nE "import.*(_global\.dart|ads_services\.dart|iap_services\.dart|push_services\.dart)" lib/main_china.dart || true)
if [[ -n "${GLOBAL_IMPL_HITS}" ]]; then
  echo "✗ lib/main_china.dart 不得直接 import 海外实现或兼容 barrel，请改为仅 import *_noop.dart / ad_service_china.dart："
  echo "${GLOBAL_IMPL_HITS}"
  exit 1
fi

# 反向：main.dart 也不应该 import 国内专用实现
MAIN_DART_CHINA_IMPL_HITS=$(grep -nE "import.*(ad_service_china\.dart|crash_service_noop\.dart)" lib/main.dart || true)
if [[ -n "${MAIN_DART_CHINA_IMPL_HITS}" ]]; then
  echo "✗ lib/main.dart 不得 import 国内专用实现，请切换为 *_global.dart 或通用 *_noop.dart："
  echo "${MAIN_DART_CHINA_IMPL_HITS}"
  exit 1
fi

# ------------------------------------------------------------
# 2) 其余 lib 文件扫描：排除已知的 global-specific 实现、
#    门面层、平台插件类型暴露（service_facades/placeholder/membership_page），
#    以及实现文件（*_global.dart/*_noop.dart/ad_service_china.dart）。
# ------------------------------------------------------------
SECONDARY_HITS=$(grep -RInE "${PATTERN}" lib \
  --exclude="push_service.dart" \
  --exclude="iap_service.dart" \
  --exclude="ad_service_global.dart" \
  --exclude="iap_service_global.dart" \
  --exclude="push_service_global.dart" \
  --exclude="crash_service_global.dart" \
  --exclude="*_global.dart" \
  --exclude="ad_service_noop.dart" \
  --exclude="iap_service_noop.dart" \
  --exclude="push_service_noop.dart" \
  --exclude="ad_service_china.dart" \
  --exclude="service_facades.dart" \
  --exclude="placeholder_services.dart" \
  --exclude="ads_services.dart" \
  --exclude="iap_services.dart" \
  --exclude="push_services.dart" \
  --exclude="membership_page.dart" \
  --exclude="main.dart" || true)

if [[ -z "${SECONDARY_HITS}" ]]; then
  echo "✓ china 链路未命中非法 SDK import（粗扫通过）"
  exit 0
fi

echo "✗ 以下 Dart 文件命中非法 SDK import（请改走 AppEnv 能力门面）："
echo "${SECONDARY_HITS}"
exit 1

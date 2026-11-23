#!/usr/bin/env bash
set -euo pipefail

# Build, ad-hoc sign, optionally install (/Applications/Click.app),
# and/or package (DMG + ZIP) Click for macOS.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DO_INSTALL=false
DO_PACKAGE=false
UNIVERSAL=false
CONFIGURATION="Release"
DERIVED_DATA="${DERIVED_DATA:-/tmp/click-dd}"
SPM_DIR="${SPM_DIR:-/tmp/click-spm}"
OUT_DIR="${REPO_ROOT}/dist"

usage() {
    cat <<'EOF'
Usage: scripts/build-and-install.sh [options]

Options:
  --install     Install built Click.app to /Applications/Click.app
  --package     Create Click-<version>.dmg, Click-<version>.zip, and SHA256SUMS.txt in ./dist
  --universal   Build universal binary (arm64 + x86_64) instead of active architecture only
  --help        Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            DO_INSTALL=true
            shift
            ;;
        --package)
            DO_PACKAGE=true
            shift
            ;;
        --universal)
            UNIVERSAL=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

find_xcodebuild() {
    if [[ -n "${DEVELOPER_DIR:-}" && -x "${DEVELOPER_DIR}/usr/bin/xcodebuild" ]]; then
        echo "${DEVELOPER_DIR}/usr/bin/xcodebuild"
        return 0
    fi

    local active_dir
    active_dir="$(xcode-select -p 2>/dev/null || true)"
    if [[ -n "${active_dir}" && -x "${active_dir}/usr/bin/xcodebuild" ]]; then
        echo "${active_dir}/usr/bin/xcodebuild"
        return 0
    fi

    local candidate
    for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app /Applications/Xcode*.app; do
        if [[ -x "${candidate}/Contents/Developer/usr/bin/xcodebuild" ]]; then
            echo "${candidate}/Contents/Developer/usr/bin/xcodebuild"
            return 0
        fi
    done

    echo "Error: Xcode (xcodebuild) not found. Install Xcode or set DEVELOPER_DIR." >&2
    return 1
}

XCODEBUILD="$(find_xcodebuild)"
echo "Using xcodebuild: ${XCODEBUILD}"

BUILD_ARGS=(
    -project "${REPO_ROOT}/click.xcodeproj"
    -scheme click
    -configuration "${CONFIGURATION}"
    -derivedDataPath "${DERIVED_DATA}"
    -clonedSourcePackagesDirPath "${SPM_DIR}"
    -onlyUsePackageVersionsFromResolvedFile
    -skipMacroValidation
    CODE_SIGN_IDENTITY=-
    DEVELOPMENT_TEAM=
    CODE_SIGN_STYLE=Manual
    ENABLE_HARDENED_RUNTIME=NO
)

if [[ "${UNIVERSAL}" == true ]]; then
    BUILD_ARGS+=(
        ARCHS="arm64 x86_64"
        ONLY_ACTIVE_ARCH=NO
    )
fi

echo "Building Click (${CONFIGURATION})..."
"${XCODEBUILD}" "${BUILD_ARGS[@]}" build

APP_BUNDLE="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/click.app"
if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "Error: Built app not found at ${APP_BUNDLE}" >&2
    exit 1
fi

# Re-sign embedded frameworks and app bundle ad-hoc without Hardened Runtime
# so dyld Library Validation does not reject ad-hoc-signed third-party frameworks.
echo "Signing embedded frameworks and Click.app ad-hoc..."
for fw in "${APP_BUNDLE}/Contents/Frameworks/"*.framework; do
    if [[ -d "${fw}" ]]; then
        codesign --force --sign - --timestamp=none "${fw}"
    fi
done

codesign --force --sign - \
    --entitlements "${REPO_ROOT}/click/click.entitlements" \
    --timestamp=none \
    --generate-entitlement-der \
    "${APP_BUNDLE}"

codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_BUNDLE}/Contents/Info.plist")"
echo "Built Click ${VERSION} at ${APP_BUNDLE}"

if [[ "${DO_INSTALL}" == true ]]; then
    echo "Installing to /Applications/Click.app..."
    rsync -a --delete "${APP_BUNDLE}/" "/Applications/Click.app/"
    codesign --verify --deep --strict "/Applications/Click.app"
    echo "Installed /Applications/Click.app"
fi

if [[ "${DO_PACKAGE}" == true ]]; then
    mkdir -p "${OUT_DIR}"
    STAGE_DIR="$(mktemp -d /tmp/click-package.XXXXXX)"
    trap 'rm -rf "${STAGE_DIR}"' EXIT

    ditto "${APP_BUNDLE}" "${STAGE_DIR}/Click.app"

    ZIP_PATH="${OUT_DIR}/Click-${VERSION}.zip"
    DMG_PATH="${OUT_DIR}/Click-${VERSION}.dmg"
    rm -f "${ZIP_PATH}" "${DMG_PATH}"

    echo "Creating ${ZIP_PATH}..."
    ditto -c -k --sequesterRsrc --keepParent "${STAGE_DIR}/Click.app" "${ZIP_PATH}"

    echo "Creating ${DMG_PATH}..."
    DMG_SRC="${STAGE_DIR}/dmg-root"
    mkdir -p "${DMG_SRC}"
    ditto "${STAGE_DIR}/Click.app" "${DMG_SRC}/Click.app"
    ln -s /Applications "${DMG_SRC}/Applications"

    hdiutil create \
        -volname "Click ${VERSION}" \
        -srcfolder "${DMG_SRC}" \
        -ov \
        -format UDZO \
        "${DMG_PATH}"

    (
        cd "${OUT_DIR}"
        shasum -a 256 "Click-${VERSION}.dmg" "Click-${VERSION}.zip" > SHA256SUMS.txt
    )

    echo "Packaged release artifacts in ${OUT_DIR}:"
    ls -lh "${DMG_PATH}" "${ZIP_PATH}" "${OUT_DIR}/SHA256SUMS.txt"
fi

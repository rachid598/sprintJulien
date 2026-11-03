#!/usr/bin/env bash
# Requires the caller's own Apple development team and installed signing identity.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SPRINTTIMER_TEAM_ID:?Définir SPRINTTIMER_TEAM_ID avec votre équipe Apple Developer.}"
export_method="${SPRINTTIMER_EXPORT_METHOD:-debugging}"
case "$export_method" in
  debugging|release-testing|app-store-connect) ;;
  *) printf '%s\n' 'Méthode inconnue. Utiliser debugging, release-testing ou app-store-connect.' >&2; exit 2 ;;
esac
build_dir="${SPRINTTIMER_BUILD_DIR:-.build-signing}"
mkdir -p "$build_dir" dist
options_file="$build_dir/ExportOptions.plist"
python3 - "$options_file" "$SPRINTTIMER_TEAM_ID" "$export_method" <<'PY'
import plistlib, sys
with open(sys.argv[1], "wb") as stream:
    plistlib.dump({"method": sys.argv[3], "teamID": sys.argv[2],
                  "signingStyle": "automatic", "destination": "export"}, stream)
PY
xcodebuild -project SprintTimer.xcodeproj -scheme SprintTimer \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$build_dir/SprintTimer.xcarchive" \
  -allowProvisioningUpdates "DEVELOPMENT_TEAM=$SPRINTTIMER_TEAM_ID" archive
xcodebuild -exportArchive -archivePath "$build_dir/SprintTimer.xcarchive" \
  -exportPath dist -exportOptionsPlist "$options_file" -allowProvisioningUpdates
if [[ ! -f dist/SprintTimer.ipa ]]; then
  printf '%s\n' "Xcode n'a pas produit dist/SprintTimer.ipa. Consulter les erreurs d’export." >&2
  exit 1
fi
printf '%s\n' 'IPA signé exporté : dist/SprintTimer.ipa'

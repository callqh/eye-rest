#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source_app="$PWD/build/休息一下.app"
destination="$HOME/Applications/休息一下.app"
if [[ ! -d "$source_app" ]]; then
  print -u2 "请先运行 ./scripts/build-app.sh"
  exit 1
fi
if [[ -e "$destination" ]]; then
  identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$identifier" != "com.liuqh.eyerest" ]]; then
    print -u2 "同名应用已存在，未覆盖：$destination"
    exit 1
  fi
fi
mkdir -p "$HOME/Applications"
ditto "$source_app" "$destination"
codesign --verify --strict "$destination"
print "Installed: $destination"

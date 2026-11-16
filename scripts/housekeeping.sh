#!/bin/bash
# Clears a finished round of builds and tests: this project's derived data,
# MeshKit's SwiftPM build and the visual sweep's captures. All regenerate.
# Archives in .build/archive stay: they are release files. Refuses while a
# build of this project runs.
set -eu
cd "$(dirname "$0")/.."
# This project's builds only: other projects' sessions may be building too.
here=$(pwd)
for pid in $(pgrep -x xcodebuild; pgrep -f "swift-build|swift-test"); do
    cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
    if [[ "$cwd" == "$here"* ]] || ps -o args= -p "$pid" | grep -q "Facets.xcodeproj"; then
        echo "A build of this project is running; try again when it's done." >&2
        exit 1
    fi
done
# Debug copies of the app share the installed app's bundle id; Launch Services keeps
# them registered after their folder is gone, so they're unregistered with it. (Only
# Mac builds: the Mac never registers iOS ones.)
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
apps=()
if [ -d .build/DerivedData/Build/Products ]; then
    while IFS= read -r app; do apps+=("$here/$app"); done < <(find .build/DerivedData/Build/Products -path "*-iphone*" -prune -o -name "*.app" -type d -print -prune)
fi
for dir in .build/DerivedData .build/sweep Packages/MeshKit/.build; do
    if [ -d "$dir" ]; then
        echo "removing $(du -sh "$dir" | cut -f1)  $dir"
        rm -rf "$dir"
    fi
done
for app in ${apps[@]+"${apps[@]}"}; do
    echo "unregistering $app"
    "$lsregister" -u "$app" || true
done
# The installed app takes its file types and Quick Look extensions back.
if [ ${#apps[@]} -gt 0 ] && [ -d /Applications/Facets.app ]; then
    "$lsregister" -f /Applications/Facets.app || true
fi
df -h / | tail -1

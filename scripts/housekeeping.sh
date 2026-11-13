#!/bin/bash
# Clears a finished round of builds and tests: this project's derived data and
# MeshKit's SwiftPM build. Both regenerate. Archives aren't kept here, so nothing
# of a release is touched. Refuses while a build runs.
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
for dir in .build Packages/MeshKit/.build; do
    [ -d "$dir" ] && echo "removing $(du -sh "$dir" | cut -f1)  $dir" && rm -rf "$dir"
done
df -h / | tail -1

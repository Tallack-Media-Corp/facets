#!/bin/zsh
# Visual sweep: captures every screen on iPhone, iPad and Mac, light and dark, into
# .build/sweep/<platform>/<appearance>/*.png, with one contact sheet per platform and
# appearance (.build/sweep/<platform>-<appearance>.png). Look at every sheet before a
# build goes out (docs/consistency.md).
#
#   scripts/sweep.sh [iphone] [ipad] [mac]     (default: all three)
#   SWEEP_ONLY=<regex>   only screens whose name matches, e.g. SWEEP_ONLY='^library$'
#   SWEEP_WAIT=<seconds> settle time per screen (default 5)
#
# Builds once per platform into .build/DerivedData. Simulators: "Facets Shots iPhone"
# and "Facets Shots iPad", shut down at the end if this script booted them. The Mac
# app runs in the background with FACETS_BACKGROUND=1 and is captured by window id,
# so it never takes focus; the Mac part refuses if any other Facets is running (the
# debug build shares the real app's bundle id, preferences and library). On the Mac
# the library is the real one: the sweep's screens only read it.
set -euo pipefail
cd "$(dirname "$0")/.."
here=$(pwd)
OUT=.build/sweep
TOOLS=.build/sweep/tools
WAIT=${SWEEP_WAIT:-5}
ONLY=${SWEEP_ONLY:-.}
platforms=("$@"); (( $#platforms )) || platforms=(iphone ipad mac)
appearances=(light dark)

# Room first: a build and a few hundred screenshots.
free_gb=$(df -g / | awk 'NR==2 {print $4}')
if (( free_gb < 15 )); then
    echo "Only ${free_gb} GB free; the sweep needs 15 GB. Run scripts/housekeeping.sh first." >&2
    exit 1
fi
# One build of this project at a time (the same check as housekeeping.sh).
for pid in $(pgrep -x xcodebuild || true); do
    cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
    if [[ "$cwd" == "$here"* ]] || ps -o args= -p "$pid" | grep -q "Facets.xcodeproj"; then
        echo "A build of this project is running; try again when it's done." >&2
        exit 1
    fi
done

# Everything this run starts is stopped on the way out, whatever happens: each
# simulator as soon as its platform is done, and anything left on any exit.
typeset -ga booted
booted=()
mac_pid=""
shutdown_sim() {
    xcrun simctl ui "$1" appearance light 2>/dev/null || true
    xcrun simctl shutdown "$1" 2>/dev/null || true
    booted=(${booted:#$1})
}
cleanup() {
    if [[ -n "$mac_pid" ]]; then kill "$mac_pid" 2>/dev/null || true; fi
    local udid
    for udid in $booted; do shutdown_sim "$udid"; done
}
trap cleanup EXIT
trap 'exit 130' INT TERM
failed=()

# Screens: "name|SETTING=value ...", using the app's DEBUG launch settings (listed in
# FacetsApp.swift). On a simulator the first library screen puts the sample in an
# empty library, so the library, Search and Move have a model to show. Tips stay
# off (FACETS_TIPS=0) except on the tip screens, which show the next tip of the
# tour not yet seen on that device.
viewer="FACETS_OPEN=sample FACETS_TIPS=0"
ios_screens=(
    "library|FACETS_TAB=library FACETS_SAMPLE=library FACETS_TIPS=0"
    "library-tip|FACETS_TAB=library"
    "browse|FACETS_TAB=browse FACETS_TIPS=0"
    "move-sheet|FACETS_TAB=library FACETS_SAMPLE=library FACETS_SHEET=move FACETS_TIPS=0"
    "recents|FACETS_TAB=recents FACETS_TIPS=0"
    "search|FACETS_TAB=search FACETS_TIPS=0"
    "settings|FACETS_TAB=settings FACETS_TIPS=0"
    "settings-printer-bed|FACETS_TAB=settings FACETS_PAGE=printerBed FACETS_TIPS=0"
    "settings-recently-deleted|FACETS_TAB=settings FACETS_PAGE=recentlyDeleted FACETS_DELETED=demo FACETS_TIPS=0"
    "settings-about|FACETS_TAB=settings FACETS_PAGE=about FACETS_TIPS=0"
    "viewer|$viewer FACETS_BED=bambu-a1"
    "viewer-no-printer|$viewer FACETS_BED=none"
    "viewer-too-small|$viewer FACETS_BED=bambu-a1mini"
    "viewer-tip|FACETS_OPEN=sample FACETS_BED=bambu-a1"
    "viewer-info|$viewer FACETS_BED=bambu-a1 FACETS_INFO=1"
    "viewer-measure|$viewer FACETS_BED=bambu-a1 FACETS_TOOL=measure"
    "viewer-lay-flat|$viewer FACETS_BED=bambu-a1 FACETS_TOOL=layFlat"
    "viewer-section|$viewer FACETS_BED=bambu-a1 FACETS_TOOL=section"
    "viewer-unit-card|$viewer FACETS_BED=bambu-a1 FACETS_UNITS=1"
    "viewer-printers|$viewer FACETS_BED=bambu-a1 FACETS_SHEET=printers"
)
# The Mac's library is the real one, and the debug build shares the real app's
# preferences: nothing that writes them (FACETS_BED, FACETS_TAB=library|browse,
# FACETS_TIPS_DONE; FACETS_SAMPLE and FACETS_DELETED are simulator-only anyway).
# The printer is whichever the owner chose.
mac_screens=(
    "library|FACETS_TIPS=0"
    "library-tip|"
    "move-sheet|FACETS_SHEET=move FACETS_TIPS=0"
    "recents|FACETS_TAB=recents FACETS_TIPS=0"
    "search|FACETS_TAB=search FACETS_TIPS=0"
    "settings|FACETS_TAB=settings FACETS_TIPS=0"
    "settings-printer-bed|FACETS_TAB=settings FACETS_PAGE=printerBed FACETS_TIPS=0"
    "settings-recently-deleted|FACETS_TAB=settings FACETS_PAGE=recentlyDeleted FACETS_TIPS=0"
    "settings-about|FACETS_TAB=settings FACETS_PAGE=about FACETS_TIPS=0"
    "viewer|$viewer"
    "viewer-tip|FACETS_OPEN=sample"
    "viewer-info|$viewer FACETS_INFO=1"
    "viewer-measure|$viewer FACETS_TOOL=measure"
    "viewer-lay-flat|$viewer FACETS_TOOL=layFlat"
    "viewer-section|$viewer FACETS_TOOL=section"
    "viewer-unit-card|$viewer FACETS_UNITS=1"
    "viewer-printers|$viewer FACETS_SHEET=printers"
)

mkdir -p "$TOOLS"
for tool in contact-sheet window-ids; do
    [[ "$TOOLS/$tool" -nt scripts/sweep/$tool.swift ]] || swiftc -O -o "$TOOLS/$tool" scripts/sweep/$tool.swift
done

# A fresh folder for one platform and appearance.
fresh() {
    rm -rf ".build/sweep/${1:?}/${2:?}"
    mkdir -p ".build/sweep/$1/$2"
}

sheet() { # platform appearance columns
    local shots=($OUT/$1/$2/[0-9]*.png(N))
    if (( ${#shots} )); then
        "$TOOLS/contact-sheet" "$OUT/$1-$2.png" "$3" 1000 $shots && echo "sheet: $OUT/$1-$2.png"
    fi
}

xcodegen generate --quiet
if (( ${platforms[(Ie)iphone]} || ${platforms[(Ie)ipad]} )); then
    echo "Building for the simulator..."
    xcodebuild -project Facets.xcodeproj -scheme Facets -destination "generic/platform=iOS Simulator" \
        -derivedDataPath .build/DerivedData build -quiet 2>&1 | grep -v appintentsmetadataprocessor || true
    APP=.build/DerivedData/Build/Products/Debug-iphonesimulator/Facets.app
    [[ -d $APP ]] || { echo "The simulator build failed." >&2; exit 1; }
    BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
fi

# Boots a simulator (once more after a short wait if it fails) and checks the app
# can launch on it: a first boot sometimes leaves SpringBoard crash-looping, which
# another boot clears.
boot_sim() { # udid
    local attempt
    for attempt in 1 2; do
        if ! xcrun simctl list devices | grep -F "$1" | grep -q Booted; then
            xcrun simctl boot "$1" 2>&1 || { echo "Boot failed; trying again." >&2; sleep 5; continue; }
            booted+=($1)
        fi
        xcrun simctl bootstatus "$1" -b >/dev/null 2>&1 || true
        xcrun simctl install "$1" "$APP" || return 1
        sleep 2
        if xcrun simctl launch --terminate-running-process "$1" "$BUNDLE" >/dev/null 2>&1; then return 0; fi
        # Restart it only if this run booted it: someone else may be using it.
        (( ${booted[(Ie)$1]} )) || return 1
        echo "The app wouldn't launch; restarting the simulator." >&2
        shutdown_sim "$1"; sleep 3
    done
    return 1
}

sweep_sim() { # platform simulator-name columns
    local platform=$1 name=$2 columns=$3
    local udid=$(xcrun simctl list devices | grep -F "    $name (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
    [[ -n "$udid" ]] || { echo "No simulator named \"$name\"." >&2; return 1; }
    if ! boot_sim "$udid"; then
        echo "$platform: the simulator didn't come up." >&2
        if (( ${booted[(Ie)$udid]} )); then shutdown_sim "$udid"; fi
        return 1
    fi
    local appearance n entry screen settings setting vars
    for appearance in $appearances; do
        xcrun simctl ui "$udid" appearance "$appearance"
        fresh "$platform" "$appearance"
        # The first launch after a change can miss its settings: warm up.
        xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" >/dev/null; sleep 3
        n=0
        for entry in $ios_screens; do
            screen=${entry%%|*} settings=${entry#*|}
            n=$((n + 1))
            [[ "$screen" =~ $ONLY ]] || continue
            vars=()
            for setting in ${=settings}; do vars+=("SIMCTL_CHILD_$setting"); done
            env $vars xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" >/dev/null
            sleep "$WAIT"
            xcrun simctl io "$udid" screenshot "$OUT/$platform/$appearance/$(printf %02d $n)-$screen.png" >/dev/null 2>&1
            echo "$platform $appearance $screen"
        done
        xcrun simctl terminate "$udid" "$BUNDLE" 2>/dev/null || true
        sheet "$platform" "$appearance" "$columns"
    done
    # Only one simulator up at a time, and none left behind.
    if (( ${booted[(Ie)$udid]} )); then shutdown_sim "$udid"; fi
}

sweep_mac() {
    # A Mac copy of Facets (simulator apps aren't in a Contents/MacOS folder).
    if pgrep -f "Facets.app/Contents/MacOS/Facets" >/dev/null; then
        echo "Skipping the Mac: Facets is running, and the debug build shares its bundle id. Quit it, then run scripts/sweep.sh mac." >&2
        return 1
    fi
    echo "Building for the Mac..."
    xcodebuild -project Facets.xcodeproj -scheme FacetsMac -derivedDataPath .build/DerivedData build -quiet 2>&1 \
        | grep -v appintentsmetadataprocessor || true
    local app=$here/.build/DerivedData/Build/Products/Debug/Facets.app
    [[ -d $app ]] || { echo "The Mac build failed." >&2; return 1; }
    local appearance entry screen settings setting n id vars windows window
    for appearance in $appearances; do
        fresh mac "$appearance"
        n=0
        for entry in $mac_screens; do
            screen=${entry%%|*} settings=${entry#*|}
            n=$((n + 1))
            [[ "$screen" =~ $ONLY ]] || continue
            vars=(--env FACETS_BACKGROUND=1 --env "FACETS_APPEARANCE=$appearance")
            for setting in ${=settings}; do vars+=(--env "$setting"); done
            open -g -n "$app" $vars
            sleep "$WAIT"
            mac_pid=$(pgrep -n -f "$app/Contents/MacOS/Facets" || true)
            if [[ -z "$mac_pid" ]]; then echo "mac $appearance $screen: the app didn't start" >&2; continue; fi
            # The window the screen is about: the model's for viewer screens (titled
            # by the sample's name), otherwise the front one (Settings opens last,
            # library screens have only the library window).
            windows=("${(@f)$("$TOOLS/window-ids" "$mac_pid")}")
            id=${windows[1]%%$'\t'*}
            if [[ "$screen" == viewer* ]]; then
                for window in $windows; do
                    if [[ "${window#*$'\t'}" == 3DBenchy ]]; then id=${window%%$'\t'*}; break; fi
                done
            fi
            if [[ -z "$id" ]]; then
                echo "mac $appearance $screen: no window found" >&2
            elif screencapture -l "$id" -x -o "$OUT/mac/$appearance/$(printf %02d $n)-$screen.png"; then
                echo "mac $appearance $screen"
            else
                echo "mac $appearance $screen: window $id couldn't be captured (on another Space?)" >&2
            fi
            # Only the copy this script started.
            kill "$mac_pid" 2>/dev/null || true
            while kill -0 "$mac_pid" 2>/dev/null; do sleep 0.2; done
            mac_pid=""
        done
        sheet mac "$appearance" 4
    done
}

for platform in $platforms; do
    case $platform in
        iphone) sweep_sim iphone "Facets Shots iPhone" 6 || failed+=(iphone) ;;
        ipad) sweep_sim ipad "Facets Shots iPad" 4 || failed+=(ipad) ;;
        mac) sweep_mac || failed+=(mac) ;;
        *) echo "Unknown platform \"$platform\" (iphone, ipad or mac)." >&2; exit 2 ;;
    esac
done
df -h / | tail -1
if (( ${#failed} )); then
    echo "Failed: $failed" >&2
    exit 1
fi

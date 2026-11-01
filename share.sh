#!/bin/bash
# Copy a file into the server file dump and print its public URL.
# Usage: share.sh FILE [--project NAME] [--topic TEXT] [--move]
#   Layout:  ~/share/<project>/<YYYY-MM-DD>-<topic>/<file>
#   Public:  https://files.code.aleksei.dev/<project>/<date-topic>/<file>
# Defaults: project = name of the current directory, topic = "misc".
# The dump is read-only over HTTP and behind Authelia.
set -eu

SRC=""
PROJECT=""
TOPIC="misc"
MOVE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --project) PROJECT="${2:?--project needs a value}"; shift 2 ;;
        --topic)   TOPIC="${2:?--topic needs a value}"; shift 2 ;;
        --move)    MOVE=1; shift ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        -*) echo "error: unknown option $1" >&2; exit 2 ;;
        *) SRC="$1"; shift ;;
    esac
done

[ -n "$SRC" ] || { echo "error: no file given (see --help)" >&2; exit 2; }
[ -f "$SRC" ] || { echo "error: not a file: $SRC" >&2; exit 1; }

BASE="${SHARE_ROOT:-$HOME/share}"
[ -n "$PROJECT" ] || PROJECT="$(basename "$PWD")"

slug() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

PROJECT_SLUG=$(slug "$PROJECT")
TOPIC_SLUG=$(slug "$TOPIC")
[ -n "$PROJECT_SLUG" ] || { echo "error: project name has no latin letters or digits" >&2; exit 1; }

DIR="$BASE/$PROJECT_SLUG/$(date +%F)-$TOPIC_SLUG"
mkdir -p "$DIR"
chmod 755 "$BASE" "$BASE/$PROJECT_SLUG" "$DIR"

NAME=$(basename "$SRC")
DEST="$DIR/$NAME"
if [ -e "$DEST" ]; then
    stem="${NAME%.*}"
    ext=""
    case "$NAME" in *.*) ext=".${NAME##*.}" ;; esac
    DEST="$DIR/$stem-$(date +%H%M%S)$ext"
fi

if [ "$MOVE" = "1" ]; then
    mv "$SRC" "$DEST"
else
    cp "$SRC" "$DEST"
fi
chmod 644 "$DEST"

URL="https://files.code.aleksei.dev/${PROJECT_SLUG}/$(basename "$DIR")/$(basename "$DEST")"
echo "$URL"
echo "saved: $DEST" >&2

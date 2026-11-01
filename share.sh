#!/bin/bash
# Copy a file into the server file dump and print its links.
# Usage: share.sh FILE [--project NAME] [--topic TEXT] [--move] [--public]
#   Layout:  <share root>/<project>/<YYYY-MM-DD>/[<topic>/]<file>
#   Private: <SHARE_URL>/<project>/<date>/[<topic>/]<file>   needs a login
#   Public:  <SHARE_URL>/public/<uuid>/<file>                no login
# Defaults: project = current directory name; no topic folder unless --topic.
# Settings come from .env next to this script:
#   SHARE_URL         private tree, behind the login
#   SHARE_PUBLIC_URL  host for published links, open to readers and crawlers
#   SHARE_ROOT        the directory both trees live in
# --public  publishes through a symlink under public/<uuid>/ and logs it
# The dump is read-only over HTTP; only public/ and robots.txt skip the login.
set -eu

CONF_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$CONF_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$CONF_DIR/.env"
    set +a
fi

SRC=""
PROJECT=""
TOPIC=""
MOVE=0
PUBLIC=0

while [ $# -gt 0 ]; do
    case "$1" in
        --project) PROJECT="${2:?--project needs a value}"; shift 2 ;;
        --topic)   TOPIC="${2:?--topic needs a value}"; shift 2 ;;
        --move)    MOVE=1; shift ;;
        --public)  PUBLIC=1; shift ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        -*) echo "error: unknown option $1" >&2; exit 2 ;;
        *) SRC="$1"; shift ;;
    esac
done

[ -n "$SRC" ] || { echo "error: no file given (see --help)" >&2; exit 2; }
[ -f "$SRC" ] || { echo "error: not a file: $SRC" >&2; exit 1; }

BASE="${SHARE_ROOT:-$CONF_DIR/share}"
[ -n "$PROJECT" ] || PROJECT="$(basename "$PWD")"
PUB_BASE="${SHARE_URL:-}"
[ -n "$PUB_BASE" ] || echo "warning: SHARE_URL is not set in .env, printing local paths" >&2

slug() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

# URLs cannot carry spaces or Cyrillic, so filenames are transliterated first.
# Without python3 the result is empty and the caller falls back to a plain name.
ascii_slug() {
    python3 -c '
import re, sys
map_ = {"а":"a","б":"b","в":"v","г":"g","д":"d","е":"e","ё":"e","ж":"zh","з":"z",
        "и":"i","й":"y","к":"k","л":"l","м":"m","н":"n","о":"o","п":"p","р":"r",
        "с":"s","т":"t","у":"u","ф":"f","х":"h","ц":"c","ч":"ch","ш":"sh","щ":"shch",
        "ъ":"","ы":"y","ь":"","э":"e","ю":"yu","я":"ya"}
s = sys.argv[1].lower()
s = "".join(map_.get(c, c) for c in s)
print(re.sub(r"[^a-z0-9._-]+", "-", s).strip("-"))
' "$1" 2>/dev/null || true
}

link() {
    printf '%s/%s\n' "${PUB_BASE%/}" "$1"
}

PROJECT_SLUG=$(slug "$PROJECT")
TOPIC_SLUG=$(slug "$TOPIC")
[ -n "$PROJECT_SLUG" ] || { echo "error: project name has no latin letters or digits" >&2; exit 1; }

DAY="$(date +%F)"
DIR="$BASE/$PROJECT_SLUG/$DAY"
[ -n "$TOPIC_SLUG" ] && DIR="$DIR/$TOPIC_SLUG"
mkdir -p "$DIR"
chmod 755 "$BASE" "$BASE/$PROJECT_SLUG" "$BASE/$PROJECT_SLUG/$DAY" "$DIR"

# URLs cannot carry spaces or non-latin letters, so the stored name is slugged.
BASE_NAME="$(basename "$SRC")"
EXT=""
case "$BASE_NAME" in
    *.*) EXT=".$(printf '%s' "${BASE_NAME##*.}" | tr '[:upper:]' '[:lower:]')" ;;
esac
STEM="$(ascii_slug "${BASE_NAME%.*}")"
if [ -z "$STEM" ]; then
    STEM="file-$(date +%H%M%S)"
    echo "warning: $BASE_NAME has no usable name, stored as $STEM$EXT" >&2
fi
NAME="$STEM$EXT"

DEST="$DIR/$NAME"
if [ -e "$DEST" ]; then
    DEST="$DIR/$STEM-$(date +%H%M%S)$EXT"
fi

if [ "$MOVE" = "1" ]; then
    mv "$SRC" "$DEST"
else
    cp "$SRC" "$DEST"
fi
chmod 644 "$DEST"

REL="$(basename "$DEST")"
[ -n "$TOPIC_SLUG" ] && REL="$TOPIC_SLUG/$REL"
echo "$(link "$PROJECT_SLUG/$DAY/$REL")"
echo "saved: $DEST" >&2

if [ "$PUBLIC" = "1" ]; then
    PUB_ID="$(uuidgen 2>/dev/null || openssl rand -hex 16)"
    PUB_ID="$(printf '%s' "$PUB_ID" | tr '[:upper:]' '[:lower:]')"
    PDIR="$BASE/public/$PUB_ID"
    mkdir -p "$PDIR"
    chmod 755 "$BASE/public" "$PDIR"
    PLINK="$PDIR/$(basename "$DEST")"
    ln -sfn "$(realpath --relative-to="$PDIR" "$DEST")" "$PLINK"
    # Public links live on their own host when one is configured: a
    # robots.txt that says "disallow everything" next to "allow /public"
    # is read strictly by some clients, and those are the readers a
    # public link is meant for.
    if [ -n "${SHARE_PUBLIC_URL:-}" ]; then
        PUBURL="${SHARE_PUBLIC_URL%/}/${PUB_ID}/$(basename "$DEST")"
    else
        PUBURL="$(link "public/${PUB_ID}/$(basename "$DEST")")"
    fi
    echo "$PUBURL"
    echo "public link: $PLINK -> $(readlink "$PLINK")" >&2

    # The journal is the only way back from a uuid to the file it publishes.
    JOURNAL="$BASE/public-links.md"
    [ -f "$JOURNAL" ] || printf '%s\n' \
        '# Published links' \
        '' \
        'Files published with --public. The public column opens without a login;' \
        'the private column is the path inside the dump. Delete the uuid folder' \
        'under public/ to unpublish a file.' \
        '' \
        '| published | public link | private path |' \
        '|---|---|---|' > "$JOURNAL"
    printf '| %s | [%s](%s) | %s |\n' \
        "$(date '+%F %H:%M')" "$(basename "$DEST")" "$PUBURL" "$PROJECT_SLUG/$DAY/$REL" \
        >> "$JOURNAL"
    chmod 644 "$JOURNAL"
fi

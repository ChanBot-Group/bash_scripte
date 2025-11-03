#!/bin/bash

# ===============================
# Download JSON files from GitHub repo
# Usage: ./json.sh [folder]
# ===============================

TOKEN=""  # GitHub Token
USER="pelican-eggs"
REPO="eggs"
BRANCH="master"

FOLDER="${1:-}"  # z.B. game_eggs
OUTPUT_BASE="./json_files"
mkdir -p "$OUTPUT_BASE"

download_json(){
    local path="$1"
    local api_url="https://api.github.com/repos/$USER/$REPO/contents/$path?ref=$BRANCH"

    # Token Header
    if [ -n "$TOKEN" ]; then
        HEADER="Authorization: token $TOKEN"
    else
        HEADER=""
    fi

    response=$(curl -s -H "$HEADER" "$api_url")

    if echo "$response" | jq -e 'type=="array"' >/dev/null 2>&1; then
        echo "$response" | jq -r '.[] | @base64' | while read -r line; do
            _jq(){ echo "${line}" | base64 --decode | jq -r "${1}"; }

            type=$(_jq '.type')
            name=$(_jq '.name')
            download_url=$(_jq '.download_url')

            if [ "$type" == "file" ] && [[ "$name" == *.json ]]; then
                # Nur der erste Unterordner unter dem angegebenen Ordner
                first_subdir=$(echo "$path" | sed "s|^$FOLDER/||" | cut -d'/' -f1)
                target_dir="$OUTPUT_BASE/$first_subdir"
                mkdir -p "$target_dir"

                echo "Downloading $name to $target_dir..."
                wget -q -O "$target_dir/$name" "$download_url"

            elif [ "$type" == "dir" ]; then
                download_json "$path/$name"
            fi
        done
    else
        echo "⚠️ Warning: API response not a JSON array (maybe rate-limited or wrong path)"
        echo "$response" | head -n 10
    fi
}

download_json "$FOLDER"

echo "✅ Done. JSON files are in $OUTPUT_BASE"

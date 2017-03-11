#!/usr/bin/env bash

SOURCE_DIR="${1}" && shift
DEST_DIR="${2}" && shift
FILES=("${@}")

for FILE in "${FILES[@]}"; do



done;



#list recursive oldest first
#find . -type f -exec ls -tr {} +

#available mbs
#df -m . | tail -1 | awk '{print $4}'

#total mbs
#df -m .  | tail -1 | awk '{print $2}'

#percentage
#percent=$((200*$item/$total % 2 + 100*$item/$total))
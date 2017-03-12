#!/usr/bin/env bash

SOURCE="${1}" #Dropbox:/personal/Media/Shows
TARGET="${2}" #/data/Media/Unsorted

REMOTE_FILES="$(rclone --config /etc/rclone/rclone.conf ls --max-depth 1 "${SOURCE}" | cut -d' ' -f2-)"

while IFS=$'\n' read FILE; do

    echo 'test'

done <<< "${REMOTE_FILES}"
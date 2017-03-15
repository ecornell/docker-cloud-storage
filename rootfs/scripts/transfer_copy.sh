#!/usr/bin/env bash
[[ "${DEBUG}" == "true" ]] && set -x

set -u -o pipefail

DEST_DIR="${1}" && shift
FILES=("${@}")

for FILE in "${FILES[@]}"; do

    [[ ! -f "${FILE}" ]] && continue

    RCLONE_TRANSFER_FILE "copy" "${FILE}" "${DEST_DIR}" || { echo "ERROR TRANSFERRING (${FILE}). EXITING." && exit 1 }

done;
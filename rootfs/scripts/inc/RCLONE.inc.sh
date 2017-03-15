#!/usr/bin/env bash

function RCLONE_TRANSFER_FILE(){

    local TYPE="${1}"
    local SOURCE="${2}"
    local TARGET_DIR="${3}"

    local SOURCE_DIR="$(dirname "${SOURCE}")"

    [[ "${TYPE}" != "copy" ]] && [[ "${TYPE}" != "move" ]] && return 1

    [[ -z "${SOURCE-}" ]] && return 1

    [[ ! -f ${SOURCE} ]] && echo "Not an actual file (${SOURCE}). Skipping." && return 1

    FILENAME="$(basename "${SOURCE}")"

    [[ "${TYPE}" == "copy" ]] && local RCLONE_CMD="copy" && echo "Attempting to COPY file (${SOURCE}..."

    [[ "${TYPE}" == "move" ]] && local RCLONE_CMD="move" && echo "Attempting to MOVE file (${SOURCE})..."

    rclone --config /etc/rclone/rclone.conf "${RCLONE_CMD}" --stats 60s "${SOURCE_DIR}" "${TARGET_DIR}" --include "/$(printf "%q" "${FILENAME}")"

    local EXIT_STATUS=$?

    return ${EXIT_STATUS}

}
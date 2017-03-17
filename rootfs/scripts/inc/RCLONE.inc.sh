#!/usr/bin/env bash

function RCLONE_TRANSFER_FILES_RELATIVE(){

    local TYPE="${1}" && shift
    local SOURCE_DIR="${1}" && shift
    local DEST_DIR="${1}" && shift
    local FILE_PATHS=("${@}")

    for FILE_PATH in "${FILE_PATHS[@]}"; do

        [[ ! -f "${FILE_PATH}" ]] && continue

        FILE_NAME="$(basename "${FILE_PATH}")"

        RELATIVE_PATH="${FILE_PATH#"${SOURCE_DIR}"}" RELATIVE_PATH="${RELATIVE_PATH%"${FILE_NAME}"}"

        RCLONE_TRANSFER_FILE "${TYPE}" "${FILE_PATH}" "${DEST_DIR}${RELATIVE_PATH}" || exit 1

    done;

}

function RCLONE_TRANSFER_FILE(){

    local TYPE="${1}"
    local SOURCE="${2}"
    local DEST_DIR="${3}"

    [[ "${TYPE}" != "copy" ]] && [[ "${TYPE}" != "move" ]] && return 1

    [[ -z "${SOURCE-}" ]] && return 1

    [[ ! -f ${SOURCE} ]] && echo "Not an actual file (${SOURCE}). Skipping." && return 1

    local SOURCE_DIR="$(dirname "${SOURCE}")"

    local FILENAME="$(basename "${SOURCE}")"

    [[ "${TYPE}" == "copy" ]] && local RCLONE_CMD="copy" && echo -n "Attempting to COPY file (${SOURCE}..."

    [[ "${TYPE}" == "move" ]] && local RCLONE_CMD="move" && echo -n "Attempting to MOVE file (${SOURCE})..."

    rclone --config /etc/rclone/rclone.conf "${RCLONE_CMD}" "${SOURCE_DIR}" "${DEST_DIR}" --include "/$(printf "%q" "${FILENAME}")" --stats 60s -v

    local EXIT_STATUS=$?

    [[ "${EXIT_STATUS}" == "0" ]] && echo "SUCCESS" || echo "FAILURE"

    return $?

}
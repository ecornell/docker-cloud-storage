#!/usr/bin/env bash
[[ "${DEBUG}" == "true" ]] && set -x

SOURCE_DIR="${1}" && shift
DEST_DIR="${1}" && shift
FILES=("${@}")
FREE_PERCENT_CONCERN=50

function CHECK_SPACE(){

    echo -n "Checking free space..."

    TOTAL_MBS="$(df -m "${SOURCE_DIR}"  | tail -1 | awk '{print $2}')"

    FREE_MBS="$(df -m "${SOURCE_DIR}" | tail -1 | awk '{print $4}')"

    FREE_PERCENT=$((200*${FREE_MBS}/${TOTAL_MBS} % 2 + 100*${FREE_MBS}/${TOTAL_MBS}))

    echo "${FREE_MBS} MB USED / ${TOTAL_MBS} MB TOTAL (${FREE_PERCENT}% FREE)"

    (( ${FREE_PERCENT} >= ${FREE_PERCENT_CONCERN} )) && echo "Free % (${FREE_PERCENT}) less than concern percent (${FREE_PERCENT_CONCERN})." && return 0 || echo "Free % (${FREE_PERCENT}) more than concern percent (${FREE_PERCENT_CONCERN})." && return 1

}

function TRANSFER_FILE(){

    local TYPE="${1}"
    local FILE="${2}"

    [[ "${TYPE}" != "copy" ]] && [[ "${TYPE}" != "move" ]] && return 1

    [[ -z "${FILE-}" ]] && return 1

    [[ ${FILE} != ${SOURCE_DIR}* ]] && echo "File (${FILE}) not from SOURCE_DIR (${SOURCE_DIR}). Skipping." && return 1

    [[ ! -f ${FILE} ]] && echo "Not an actual file (${FILE}). Skipping." && return 1

    RELATIVE_PATH="${FILE#"${SOURCE_DIR}"}"

    [[ "${TYPE}" == "copy" ]] && local RCLONE_CMD="copyto"
    [[ "${TYPE}" == "move" ]] && local RCLONE_CMD="moveto"

    rclone --config /etc/rclone/rclone.conf "${RCLONE_CMD}" "${FILE}" "${DEST_DIR}${RELATIVE_PATH}"

    local EXIT_STATUS=$?

    return ${EXIT_STATUS}


}

for FILE in "${FILES[@]}"; do

    TRANSFER_FILE "copy" "${FILE}" || { echo "ERROR TRANSFERING. EXITING." && exit 1; }

done;

CHECK_SPACE && exit 0

echo "Free space on SOURCE_DIR (${SOURCE_DIR}) less than ${FREE_PERCENT_CONCERN}% working to free up space..."

FILES="$(find ${SOURCE_DIR} ! -path '${SOURCE_DIR}/Unsorted/*' -type f -exec ls -tr {} +)"

while IFS=$'\n' read FILE; do

    echo "${FILE}"

    TRANSFER_FILE "move" "${FILE}" || { echo "ERROR TRANSFERING. EXITING." && exit 1; }

    CHECK_SPACE && break;

done <<< "${FILES}"
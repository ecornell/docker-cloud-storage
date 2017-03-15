#!/usr/bin/env bash
[[ "${DEBUG}" == "true" ]] && set -x

set -u -o pipefail

DEST_DIR="${1}"
SOURCE_DIR="${2}"
FREE_PERCENT_CONCERN=50
LOCK_FILE="/tmp/migrate_files.lock"
MAX_TRANSFERS=10

. "$(dirname "$0")/inc/LOCK.inc.sh"
. "$(dirname "$0")/inc/RCLONE.inc.sh"

function CHECK_SPACE(){

    echo -n "Checking free space..."

    TOTAL_MBS="$(df -m "${SOURCE_DIR}"  | tail -1 | awk '{print $2}')"

    FREE_MBS="$(df -m "${SOURCE_DIR}" | tail -1 | awk '{print $4}')"

    FREE_PERCENT=$((200*${FREE_MBS}/${TOTAL_MBS} % 2 + 100*${FREE_MBS}/${TOTAL_MBS}))

    echo "${FREE_MBS} MB AVAILABLE / ${TOTAL_MBS} MB TOTAL (${FREE_PERCENT}% FREE)"

    (( ${FREE_PERCENT} >= ${FREE_PERCENT_CONCERN} )) && echo "Free % (${FREE_PERCENT}) less than concern percent (${FREE_PERCENT_CONCERN})." && return 0 || echo "Free % (${FREE_PERCENT}) more than concern percent (${FREE_PERCENT_CONCERN})." && return 1

}

LOCKED_IS && exit 0

LOCK_SET

declare -A IN_USE

while ! CHECK_SPACE; do

    echo "Working to free up space..."

    IFS=$'\n' FILES=("$(find ${SOURCE_DIR} -type f -exec ls -ctr {} +)");

    echo "Found (${#FILES[@]}) to move..."

    [[ -z "${FILES[@]-}" ]] && break;

    for INDEX in "${!FILES[@]}"; do

        FILE="${FILES["${INDEX}"]}"

        [[ "${IN_USE["${FILE}"]}" == "1" ]] && unset FILES["${INDEX}"]

    done

    FILES="${FILES[@]}"

    [[ -z "${FILES[@]-}" ]] && break;

    FILE_PATH="${FILES[0]}"

    FILE_NAME="$(basename "${FILE_PATH}")"

    RELATIVE_PATH="${FILE_PATH#"${SOURCE_DIR}"}" RELATIVE_PATH="${RELATIVE_PATH%"${FILE_NAME}"}"

    #CHECK TO SEE IF FILE IS IN USE
    fuser -s "${FILE_PATH}" && IN_USE["${FILE_PATH}"]=1 && break

    TRANSFER_FILE "move" "${FILE_PATH}" "${DEST_DIR}${RELATIVE_PATH}" || { echo "ERROR TRANSFERING (${FILE_PATH}). EXITING." && exit 1 }

    find "$(dirname "${FILE_PATH}")" -type d -empty -delete

done

LOCK_UNSET
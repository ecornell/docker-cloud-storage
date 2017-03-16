#!/usr/bin/env bash
[[ "${DEBUG}" == "true" ]] && set -x

set -u -o pipefail

SOURCE_DIR="${1}"
DEST_DIR="${2}"
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

LOCK_IS && exit 0

LOCK_SET

declare -A IN_USE

while ! CHECK_SPACE; do

    echo "Working to free up space..."

    IFS=$'\n' FILES=("$(find ${SOURCE_DIR} -type f -exec ls -ctr {} +)");

    for FILE_PATH in "${FILES[@]}"; do

        [[ -n "${IN_USE["${FILE_PATH}"]}" ]] && FILE_PATH= && continue

        break;

    done

    [[ -z "${FILE_PATH-}" ]] && echo "Found (0) to move. Exiting." && break;

    echo "Moving (${FILE_PATH})..."

    #CHECK TO SEE IF FILE IS IN USE
    fuser -s "${FILE_PATH}" && IN_USE["${FILE_PATH}"]=1 && continue

    RCLONE_TRANSFER_FILES_RELATIVE "move" "${SOURCE_DIR}" "${DEST_DIR}" "${FILE_PATH}" || { echo "ERROR TRANSFERING (${FILE_PATH}). EXITING." && exit 1; }

    find "$(dirname "${FILE_PATH}")" -type d -empty -delete

done

LOCK_UNSET
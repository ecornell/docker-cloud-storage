#!/usr/bin/env bash
[[ "${DEBUG}" == "true" ]] && set -x

set -u
set -o pipefail

SOURCE_DIR="${1}" && shift
DEST_DIR="${1}" && shift
FILES=("${@}")
FREE_PERCENT_CONCERN=50
LOCK_FILE="/tmp/migrate_files.lock"
MAX_TRANSFERS=10

function CHECK_SPACE(){

    echo -n "Checking free space..."

    TOTAL_MBS="$(df -m "${SOURCE_DIR}"  | tail -1 | awk '{print $2}')"

    FREE_MBS="$(df -m "${SOURCE_DIR}" | tail -1 | awk '{print $4}')"

    FREE_PERCENT=$((200*${FREE_MBS}/${TOTAL_MBS} % 2 + 100*${FREE_MBS}/${TOTAL_MBS}))

    echo "${FREE_MBS} MB AVAILABLE / ${TOTAL_MBS} MB TOTAL (${FREE_PERCENT}% FREE)"

    (( ${FREE_PERCENT} >= ${FREE_PERCENT_CONCERN} )) && echo "Free % (${FREE_PERCENT}) less than concern percent (${FREE_PERCENT_CONCERN})." && return 0 || echo "Free % (${FREE_PERCENT}) more than concern percent (${FREE_PERCENT_CONCERN})." && return 1

}

function TRANSFER_FILE(){

    local TYPE="${1}"
    local FILE="${2}"

    [[ "${TYPE}" != "copy" ]] && [[ "${TYPE}" != "move" ]] && return 1

    [[ -z "${FILE-}" ]] && return 1

    [[ ${FILE} != ${SOURCE_DIR}* ]] && echo "File (${FILE}) not from SOURCE_DIR (${SOURCE_DIR}). Skipping." && return 1

    [[ ! -f ${FILE} ]] && echo "Not an actual file (${FILE}). Skipping." && return 1



    FILENAME="$(basename "${FILE}")"
    RELATIVE_PATH="${FILE#"${SOURCE_DIR}"}" && RELATIVE_PATH="${RELATIVE_PATH%"${FILENAME}"}"

    [[ "${TYPE}" == "copy" ]] && local RCLONE_CMD="copy" && echo "Attempting to COPY file (${FILE}..."
    [[ "${TYPE}" == "move" ]] && local RCLONE_CMD="move" && echo "Attempting to MOVE file (${FILE})..."

    rclone --config /etc/rclone/rclone.conf "${RCLONE_CMD}" --stats 60s -vv --dump-filters "${SOURCE_DIR}${RELATIVE_PATH}" "${DEST_DIR}${RELATIVE_PATH}" --include "/$(printf "%q" "${FILENAME}")" && find "${SOURCE_DIR}${RELATIVE_PATH}" -type d -empty -delete

    local EXIT_STATUS=$?

    return ${EXIT_STATUS}


}

function LOCK(){

    echo $$ > "${LOCK_FILE}"

    return 0

}

function UNLOCK(){

    echo "" > "${LOCK_FILE}"

    return 0

}

function IS_LOCKED(){

    [[ ! -f ${LOCK_FILE} ]] && return 1

    local PID="$(cat "${LOCK_FILE}")"

    [[ -z "${PID}" ]] && return 1

    #LOCKED and PID IS RUNNING
    ps -p ${PID} > /dev/null && return 0

    UNLOCK && return 0

}

function waitForAny(){

    set +x

    local PID=

    while [[ -n "${PIDS[@]}" ]]; do

        echo "WAITING FOR ANY JOBS (${PIDS[@]})..."

        for INDEX in ${!PIDS[@]}; do

            PID="${PIDS[${INDEX}]}"

            ps -p ${PID} > /dev/null && continue

            PID_COMPLETE="${PID}"

            unset PIDS[${INDEX}]

            PIDS=( "${PIDS[@]}" )

            break 2

        done

        sleep 1

    done;

    [[ "${DEBUG}" == "true" ]] && set -x

    return 0

}

#A little time for files to settle if trigger was happening
sleep 2

PIDS=();
for FILE in "${FILES[@]}"; do

    [[ "$(jobs -rp | wc -l | tr -d '[:space:]')" >= "${MAX_THREADS}" ]] && waitForAny

    TRANSFER_FILE "copy" "${FILE}" || { echo "ERROR TRANSFERRING (${FILE}). EXITING." } &

    PIDS+=("$!")

done;

wait "${PIDS[@]}"

IS_LOCKED && exit 0

while ! CHECK_SPACE; do

    echo "Working to free up space..."

    IFS=$'\n' FILES=("$(find ${SOURCE_DIR} ! -path '${SOURCE_DIR}/Unsorted/*' -type f -exec ls -ctr {} +)");

    echo "Found (${#FILES[@]}) to move..."

    [[ -z "${FILES[@]-}" ]] && break;

    TRANSFER_FILE "move" "${FILE[0]}" || { echo "ERROR TRANSFERING (${FILE[0]}). EXITING." }

done
#!/bin/bash

[[ "${DEBUG}" == "true" ]] && set -x

SOURCE="$(dirname "${1}")"
shift

# Check if inotofywait is installed.
hash inotifywait 2>/dev/null
if [ $? -eq 1 ]; then
  echo "Unable to execute the script. Please make sure that inotify-utils
  is installed in the system."
  exit 1
fi

RUNNING=0
WAITING=()

RUN() {

    [[ "${DEBUG}" == "true" ]] && set -x

    FILE="${FILE}"

    [[ -z "${FILE}" ]] && echo "\$FILE not set. Exiting." && exit 1

    echo "Running command (${CMD})..."
    RESULT="$(eval "${1}")"
    EXIT=$?
    echo "Done at ($(date)) with exit status (${EXIT})."
    return ${EXIT}

}

function cleanup {
  trap - HUP INT TERM QUIT EXIT
  kill -- -$$
  exit $1
}

trap cleanup HUP INT TERM QUIT EXIT

inotifywait  -m -e create -e modify -e moved_to --format '%w%f' ${WATCHER_OPTIONS} "${SOURCE}" | \
while read TFILE; do

    [[ ! -e ${TFILE} ]] && continue

    [[ "${TFILE}" == "${SOURCE}" ]] && echo "Event on root path with no file. Skipping." && continue

    [[ "${DEBUG}" == "true" ]] && set -x

    [[ "${RUNNING}" == 1 ]] && WAITING+=("${TFILE}") && continue

    RUNNING=1 && WAITING+=("${TFILE}")

    while [[ ${#WAITING[@]} > 0 ]]; do

        ORIG_CMD="$*"
        FILE="${WAITING[0]}"
        CMD="$(echo "${*}")"
        echo "Event triggered for (${FILE})..."

        RUN "${CMD}"
        #EXIT=$?

        #Exit code 23 is from rsync and can happen
        #[[ "${EXIT}" != "0" && "${EXIT}" != "23" ]] && echo "Problem with command (${CMD}). Return code (${EXIT}). Exiting." && exit ${EXIT}

	WAITING=("${WAITING[@]:1}")

    done

    RUNNING=0

done &
wait $!
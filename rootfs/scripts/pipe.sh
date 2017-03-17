#!/usr/bin/env bash
[[ "${DEBUG}" == "true" ]] && set -x

set -u -o pipefail

trap "QUIT" TERM INT

#PROVIDES:
# LOCK_SET, LOCK_UNSET, LOCK_IS
#USES:
# LOCK_FILE
. "$(dirname "$0")/inc/LOCK.inc.sh"

#PROVIDES:
# QUEUE_SHIFT, QUEUE_UNSHIFT, QUEUE_PUSH, QUEUE_PUSH_MANY, QUEUE_PUSH_FAIL, QUEUE_READ
#USES:
# QUEUE, QITEM
. "$(dirname "$0")/inc/QUEUE.inc.sh"

#PROVIDES:
# WAITFORANY
#USES:
# PIDS
. "$(dirname "$0")/inc/WAIT.inc.sh"


function SHOW_HELP(){

    echo "NOT RUNNING PIPE CORRECTLY. YOU NEED HELP."

}


function LOG(){

    echo "${LOG_PREFIX-}${@}"

}

function RUN(){

    set +e

    local PID=$(sh -c 'echo $PPID');
    local QITEM="${1}"
    local STATUS_PATH="${PIPE_TMP_DIR}/${PID}${STATUS_SUFFIX}"
    local LOG_PATH="${PIPE_TMP_DIR}/${PID}${LOG_SUFFIX}"

    touch "${LOG_PATH}"

    LOG_PREFIX="${LOG_PREFIX}JOB (${PID}) "

    LOG "STARTING"

    [[ -e "${STATUS_PATH}" ]] && rm "${STATUS_PATH}" &> /dev/null

    local CMD_ACTUAL="${CMD/"{}"/"\"${QITEM-}\""}"

    LOG "RUNNING COMMAND (${CMD_ACTUAL})"

    local LOCAL

    /bin/bash -c "${CMD_ACTUAL}" 2>&1 | tee "${LOG_PATH}" | while read LINE; do
        [[ "${PIPE_OUTPUT_CMD_LOG-}" == "true" ]] && LOG "CMD OUTPUT: ${LINE}"
    done

    local STATUS=$?

    echo "${STATUS}" > "${STATUS_PATH}"

    LOG "COMPLETE. STATUS (${STATUS})"

    return "${STATUS}"

}

function QUIT(){

    [[ "${DEBUG}" == "true" ]] && set -x

    PIDS_STOP

    LOCK_UNSET

    exit ${1-}

}

function PIDS_STOP(){

    PIDS_CHECK

    LOG "STOPPING JOBS"

    for QITEM in "${!PIDS[@]}"; do

        LOG_PREFIX=""

        [[ -z "${QITEM-}" ]] && LOG "ERROR: UNKNOWN." && exit 1

        LOG_PREFIX="(${QITEM}) "

        PID="${PIDS["${QITEM}"]}"

        [[ -z "${PID-}" ]] && LOG "ERROR: UNKNOWN." && exit 1

        LOG_PREFIX="(${QITEM}) JOB (${PID}) "

        LOG "STOPPING..."

        ps auxwwf

        kill "${PID}" || { LOG "UNABLE TO STOP. CHECKING TO SEE IF IT COMPLETED BEFORE WE TRIED TO STOP"; PIDS_CHECK; continue; }

        LOG "STOPPED"

        PIDS_CLEAN "${QITEM}" "${PID}"

        unset PIDS["${QITEM}"]

        LOG "ADDING BACK TO QUEUE"

        QUEUE_UNSHIFT || { LOG "FAILED TO ADD BACK TO QUEUE"; QUEUE_PUSH_FAIL; continue; }

    done

    LOG_PREFIX=""

    LOG "STOPPING JOBS DONE"

}

function PIDS_CLEAN(){

    local QITEM="${1}"
    local PID="${2}"

    STATUS_PATH="${PIPE_TMP_DIR}/${PID}${STATUS_SUFFIX}"
    LOG_PATH="${PIPE_TMP_DIR}/${PID}${LOG_SUFFIX}"

    rm "${STATUS_PATH}"
    rm "${LOG_PATH}"

    return 0

}

function PIDS_CHECK(){

    local JOB_STATUS=
    local FAILED_COUNT=
    local PID_COUNT=

    LOG "CHECKING FOR FINISHED JOBS..."

    #Go through all jobs and see if they completed
    for QITEM in "${!PIDS[@]}"; do

        [[ -z "${QITEM-}" ]] && LOG "ERROR: UNKNOWN." && exit 1

        PID="${PIDS["${QITEM}"]}"

        [[ -z "${PID-}" ]] && LOG "ERROR: UNKNOWN." && exit 1

        STATUS_PATH="${PIPE_TMP_DIR}/${PID}${STATUS_SUFFIX}"
        LOG_PATH="${PIPE_TMP_DIR}/${PID}${LOG_SUFFIX}"

        #If the job hasn't outputted a status, it probably hasn't completed
        if [[ ! -e ${STATUS_PATH} ]]; then

            #If job is still actually running (and we can confirm it by a PID, skip this loop
            ps -p ${PID} > /dev/null && continue

            #otherwise, the job has failed or been terminated somehow, so we requeue it
            QUEUE_UNSHIFT

            PIDS_CLEAN "${QITEM}" "${PID}"

            unset PIDS["${QITEM}"]

            continue

        fi

        LOG_PREFIX="(${QITEM}) JOB (${PID}) "

        LOG "PROCESSING RESULTS..."

        local JOB_STATUS=""

        read JOB_STATUS < "${STATUS_PATH}" || QUIT 1

        LOG "STATUS (${JOB_STATUS})"

        if [[ "${PIPE_OUTPUT_CMD_LOG}" != "true" ]] && [[ "${JOB_STATUS}" != "0" ]] || [[ "${DEBUG}" == "true" ]]; then

            #LOG "LOG OUTPUT: $(cat "${LOG_PATH}")"

            while read LINE; do
                LOG "LOG OUTPUT: ${LINE}"
            done <<< "$(<"${LOG_PATH}")"

            #LOG "LOG STOP"

        fi

        if [[ "${JOB_STATUS}" != "0" ]]; then

            if [[ "${JOB_STATUS}" == "100" ]]; then

                LOG "JOB CAUGHT EXIT SIGNAL. ADDING BACK TO QUEUE."

                QUEUE_UNSHIFT

            else

                 #Increment total failed count
                (( FAILED++ ))

                #Increment item failed count
                QUEUE_FAILED["${QITEM}"]=$((${QUEUE_FAILED["${QITEM}"]:-0} + 1))

                local FAILED_COUNT="${QUEUE_FAILED["${QITEM}"]}"

                LOG "INCREMENTED FAILED COUNT. ITEM (${FAILED_COUNT-}) TOTAL (${FAILED-})"

                if (( "${FAILED_COUNT}" < "${PIPE_MAX_FAILED_PER_QITEM}" )); then

                    LOG "ADDING BACK TO QUEUE"

                    QUEUE_PUSH
                else

                    LOG "EXCEEDED MAX FAILURES (${PIPE_MAX_FAILED_PER_QITEM}). NOT RETURNING TO QUEUE."

                    QUEUE_PUSH_FAIL

                 fi

            fi

        else

            (( ${FAILED} > 0 )) && ((FAILED--))

            LOG "DECREMENTED FAILED COUNT. TOTAL (${FAILED-})"

        fi

        PIDS_CLEAN "${QITEM}" "${PID}"

        ##save the index
        unset PIDS["${QITEM}"]

        LOG "REMOVED FROM ACTIVE JOBS LIST"

        LOG_PREFIX=""

    done

    LOG "DONE CHECKING FOR FINISHED JOBS"

    local PID_COUNT=0

    [[ -n "${PIDS[@]-}" ]] && PID_COUNT="${#PIDS[@]}"

    LOG "JOBS STILL RUNNING (${PID_COUNT-})"

}

while getopts hvt: opt; do
    case $opt in
        h)  SHOW_HELP
            exit 0
            ;;
        v)  DEBUG=TRUE
            ;;
        t)  PIPE_MAX_THREADS="$OPTARG"
            ;;
        *)  SHOW_HELP >&2
            exit 1
            ;;
    esac
done

shift "$((OPTIND-1))" # Shift off the options and optional --.

PIPE_TMP_DIR="${PIPE_TMP_DIR:-/tmp}"
PIPE_OUTPUT_CMD_LOG="${PIPE_OUTPUT_CMD_LOG:-true}"
PIPE_QUEUE_IFS=${PIPE_QUEUE_IFS:-$'\n\t'}
PIPE_MAX_FAILED=10
PIPE_MAX_FAILED_PER_QITEM=2
PIPE_MAX_THREADS="${PIPE_MAX_THREADS:-1}"

CMD="${@}"
CMD_MD5="$(printf '%s' "${CMD[@]}" | md5sum | awk '{print $1}')"
QUEUE_FILE="${PIPE_TMP_DIR}/${CMD_MD5}.queue"
QUEUE_FILE_ORIG="${PIPE_TMP_DIR}/${CMD_MD5}.queue"
QUEUE_FILE_FAILED="${PIPE_TMP_DIR}/${CMD_MD5}.failed"
LOCK_FILE="${PIPE_TMP_DIR}/${CMD_MD5}.lock"
LOG_SUFFIX=".log"
STATUS_SUFFIX=".status"
FAILED=0

unset QUEUE && declare -a QUEUE
unset QUEUE_NEW && declare -a QUEUE_NEW
unset QUEUE_FAILED && declare -A QUEUE_FAILED
unset PIDS && declare -A PIDS

[[ -z "${CMD-}" ]] && SHOW_HELP && exit 1

while IFS=$"${PIPE_QUEUE_IFS}" read -r -t 0.5 QITEM; do
    [[ -z "${QITEM-}" ]] && continue
    QUEUE_NEW+=("${QITEM}")
done && unset QITEM

#Append potential ondisk queue with incoming items
[[ -n "${QUEUE_NEW[@]-}" ]] && { QITEM=("${QUEUE_NEW[@]}") && QUEUE_PUSH_MANY && unset QITEM || exit 1; }

#If already locked, exit
LOCK_IS && echo "${CMD_MD5}" && exit 0

#LOCK SO WE CAN RUN
LOCK_SET || exit 1

unset QUEUE_NEW

while QUEUE_SHIFT; do

    #Clear log prefix
    LOG_PREFIX=""

    LOG "QUEUED ITEMS WAITING FOR PROCESSING ($((${#QUEUE[@]} + 1)))..."

    if (( ${FAILED} > 0 )); then

        (( "${FAILED}" >= "${PIPE_MAX_FAILED}" )) && { LOG "EXCEEDED MAX TOTAL FAILED (${PIPE_MAX_FAILED}). EXITING."; QUIT 1; }

        echo "FAILED COUNT (${FAILED}), THROTTLING FOR $(( 2 ** ${FAILED} )) SECONDS" && sleep "$(( 2 ** ${FAILED} ))"

    fi

    #recognize QUEUE_SHIFT gives us QITEM
    QITEM="${QITEM}"

    LOG_PREFIX="(${QITEM}) "

    LOG "PROCESSING"

    #execute the given command
    RUN "${QITEM}" &

    #save pid of background job
    PID=$!

    #fail if for some reason the pid couldn't be realized
    [[ -z "${PID-}" ]] && LOG "ERROR: COULD NOT DETERMINE PID" && exit 1

    #add pid to associative array with QITEM as key
	PIDS["${QITEM}"]="${PID}"

    #clear log prefix (will be carried in to subshell so no need to keep it)
	LOG_PREFIX=""

    #run through a waiting pattern if there are no more jobs or we are at our max threads
    while JOB_COUNT="$(jobs -rp | wc -l | tr -d '[:space:]')" && (( "${JOB_COUNT}" >= "${PIPE_MAX_THREADS}" )) || ( QUEUE_READ && [[  -z "${QUEUE[@]-}" ]] && [[ -n "${PIDS[@]-}" ]] ); do

        [[ -n "${PIDS[@]-}" ]] && PID_COUNT="${#PIDS[@]}"

        LOG "JOB RUNNING (${JOB_COUNT}), JOBS TRACKING (${PID_COUNT-0}), QUEUE COUNT (${#QUEUE[@]})"

        WAITFORANY "${PIDS[@]}"

        PIDS_CHECK

    done

done

LOG "DONE"

QUEUE_REMOVE_FILE
LOCK_UNSET && exit 0
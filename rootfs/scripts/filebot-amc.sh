#!/usr/bin/env bash
[[ "${DEBUG}" == "true" ]] && set -x

set -u
set -o pipefail
#IFS=$'\n\t'

export HOME="/data"

MAX_THREADS="${MAX_THREADS:-1}"

DEST="${1}" && shift
FILES=("${@-}")

[[ -z "${DEST-}" ]] && logger "Must provide destination as first argument." && exit 1
[[ -z "${FILES-}" ]] && logger "Must provide at least file after destination. Exiting." && exit 1

# Configuration
FILEBOT_ACTION="move"
FIlEBOT_UNSORTED="y"
FILEBOT_CONFLICT="override"
FILEBOT_CLEAN="y"
FILEBOT_MUSIC="n"
FILEBOT_SUBTITLES="en"
FILEBOT_EXCLUDE_PATH="/data/.filebot/exclude.txt"
FILEBOT_MOVIEFORMAT=$"Movies/{n} ({y})/{n} ({y}){' -  pt'+pi} - [{vf}, {vc}, {ac}{', '+source}]{'.'+lang}"
FILEBOT_SERIESFORMAT=$"Shows/{n}/{episode.special ? 'Specials' : 'Season '+s.pad(2)}/{n} - {episode.special ? 'S00E'+special.pad(2) : s00e00} - {t.replaceAll(/[\`\´\‘\’\ʻ]/, /'/).replaceAll(/[!?.]+$/).replacePart(', Part \$1')} [{vf}, {vc}, {ac}{', '+source}]{'.'+lang}"

#[[ ! -e ${DEST} ]] && logger "Destination does not exist (${DEST})." && exit 1

TMP_DIR="/tmp"
LOG_SUFFIX=".log"
RESULT_SUFFIX=".result"
STATUS_SUFFIX=".status"

FAILED=0
JOB_IDS=()

CMD=$(cat <<-'SETVAR'
 filebot -script fn:amc --output "${DEST}" "${ARG}" \
        --action "${FILEBOT_ACTION}" \
        -non-strict \
        -no-xattr \
        --log-lock no \
        --conflict "${FILEBOT_CONFLICT}" \
        --def   excludeList="${FILEBOT_EXCLUDE_PATH}" \
                unsorted="${FIlEBOT_UNSORTED}" \
                clean="${FILEBOT_CLEAN}" \
                music="${FILEBOT_MUSIC}" \
                subtitles="${FILEBOT_SUBTITLES}" \
                movieFormat="${FILEBOT_MOVIEFORMAT}" \
                seriesFormat="${FILEBOT_SERIESFORMAT}"
SETVAR
)

function run(){

    local PID=$(sh -c 'echo $PPID');
    local ARG="${1}"
    local STATUS_PATH="${TMP_DIR}/${PID}${STATUS_SUFFIX}"
    local RESULT_PATH="${TMP_DIR}/${PID}${RESULT_SUFFIX}"
    local LOG_PATH="${TMP_DIR}/${PID}${LOG_SUFFIX}"

    touch "${LOG_PATH}"

    #log "JOB (${PID}) STARTING"

    if [[ "${DEBUG}" == "true" ]]; then
        eval "${CMD}"
    else
        eval "${CMD} >> ${LOG_PATH} 2>&1 "
    fi

    local STATUS=$?

    echo "${STATUS}" > "${STATUS_PATH}"

    if [[ "${STATUS}" != "0" ]]; then

        echo "${ARG}" > "${RESULT_PATH}"

    else

        touch "${RESULT_PATH}"

    fi



    #log "JOB (${PID}) COMPLETE (${STATUS})"

    return "${STATUS}"

}

function complete(){

    STATUS="$1"
    RESULT="$2"

    if [[ "${STATUS}" != "0" ]]; then

        log -n "STATUS (${STATUS}) ADDING FILE (${RESULT}) BACK "

        FILES+=("${RESULT}")

    fi

}

function waitForAny(){

    set +x

    local PIDS="${@}"
    local PID=

    log "WAITING FOR ANY JOBS (${PIDS})..."

    while [[ true ]]; do

        for PID in ${PIDS}; do

            ps -p ${PID} > /dev/null || break 2

        done

        sleep 1

    done;

    [[ "${DEBUG}" == "true" ]] && set -x

    return 0

}


while [[  -n "${FILES[@]-}" ]]; do

    (( ${FAILED} > 0 )) && log "SLEEPING on FAILED (${FAILED})..." && sleep "$(( 2 ** ${FAILED} ))"

    FILE="${FILES[0]}"

    FILES=("${FILES[@]:1}")

    [[ ! -e ${FILE} ]] && continue

    run "${FILE}" &

    JOB_ID=$!

    [[ -z "${JOB_ID-}" ]] && exit 1

	JOB_IDS+=("${JOB_ID}")

    while (( "$(jobs -rp | wc -l | tr -d '[:space:]')" >= "${MAX_THREADS}" )) || ( [[  -z "${FILES[@]-}" ]] && [[ -n "${JOB_IDS[@]-}" ]] ); do

        JOB_COUNT="$(jobs -rp | wc -l | tr -d '[:space:]')"

        #log "JOB COUNT (${JOB_COUNT}), FILE COUNT (${#FILES[@]}), WAITING..."

        waitForAny "${JOB_IDS[@]}"

        #log "CHECKING FOR FINISHED JOBS..."

        #Go through all jobs and see if they completed
        JOB_IDS_COMPLETED=()
        for JOB_ID in "${JOB_IDS[@]}"; do

            [[ -z "${JOB_ID-}" ]] && exit 1

            STATUS_PATH="${TMP_DIR}/${JOB_ID}${STATUS_SUFFIX}"
            RESULT_PATH="${TMP_DIR}/${JOB_ID}${RESULT_SUFFIX}"
            LOG_PATH="${TMP_DIR}/${JOB_ID}${LOG_SUFFIX}"

            [[ ! -e ${STATUS_PATH} ]] && continue

            #LOG_PREFIX="JOB (${JOB_ID})"

            #log "${LOG_PREFIX} PROCESSING..."

            read STATUS_CODE < "${STATUS_PATH}"

            read RESULT < "${RESULT_PATH}"

            #log "${LOG_PREFIX} STATUS (${STATUS_CODE})"

            #log "${LOG_PREFIX} RESULT (${RESULT})"

            if [[ "${STATUS_CODE}" != "0" ]]; then

                ((FAILED++))

                cat "${LOG_PATH}"

                #log "${LOG_PREFIX} INCREMENTED FAILED (${FAILED})"

            else

                (( ${FAILED} > 0 )) && ((FAILED--))

            fi

            #log "${LOG_PREFIX} RUNNING COMPLETE FUNCTION: "

            complete "${STATUS_CODE}" "${RESULT}"

            #log "${LOG_PREFIX} COMPLETE FUNCTION END";

            rm "${STATUS_PATH}"
            rm "${RESULT_PATH}"
            rm "${LOG_PATH}"

            ##save the index
            JOB_IDS_COMPLETED+=("${JOB_ID}")

            #log "${LOG_PREFIX} ADDED TO JOB_IDS_COMPLETED (${JOB_IDS_COMPLETED[@]-})"

        done

        #log "DONE CHECKING FOR FINISHED JOBS"

        #CLEAN JOB_IDS
        if (( "${#JOB_IDS_COMPLETED[@]}" > 0 )); then

            #create new job_ids array
            NEW_JOB_IDS=()

            #Loop through the indexes of the job_ids
            for JOB_ID in "${JOB_IDS[@]}"; do

                #Loop through each of the jobs_completed (indexes)
                for PID_COMPLETED in "${JOB_IDS_COMPLETED[@]}"; do

                    #if we find the index continue past the outer loop (so the new jobs_id array won't have the JOB_ID
                    [[ "${PID_COMPLETED}" == "${JOB_ID}" ]] && continue 2

                done

                #add the JOB_ID to the new jobs_id array
                NEW_JOB_IDS+=("${JOB_ID}")

            done

            #replace old job_ids with new job_ids
            if (( "${#NEW_JOB_IDS[@]-}" > 0 )); then
                JOB_IDS=("${NEW_JOB_IDS[@]-}")
            else
                JOB_IDS=()
            fi

            #log "JOBS: ${JOB_IDS[@]-}"

        fi

    done

done
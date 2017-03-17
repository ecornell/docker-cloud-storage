#!/usr/bin/env bash

#PROVIDES:
# QUEUE_SHIFT, QUEUE_UNSHIFT, QUEUE_PUSH, QUEUE_PUSH_MANY, QUEUE_PUSH_FAIL, QUEUE_READ
#USES:
# QUEUE, QITEM

function QUEUE_SHIFT(){

    QUEUE_READ || return 1

    [[ -z "${QUEUE[@]-}" ]] && return 1

    QITEM="${QUEUE[0]}"

    QUEUE=("${QUEUE[@]:1}")

    QUEUE_SAVE

}

function QUEUE_UNSHIFT(){

    [[ -z "${QITEM-}" ]] && return 1

    QUEUE_READ || return 1

    if [[ -n "${QUEUE[@]-}" ]]; then
        QUEUE=("${QITEM}" "${QUEUE[@]}")
    else
        QUEUE=("${QITEM}")
    fi

    QUEUE_SAVE || return 1

}

function QUEUE_PUSH(){

    [[ -z "${QITEM-}" ]] && return 1

    QUEUE_READ

    QUEUE+=("${QITEM}")

    QUEUE_SAVE || return 1

}

function QUEUE_PUSH_MANY(){

    [[ -z "${QITEM[@]-}" ]] && return 1

    declare -p | grep -eq '^declare -[Aa] QITEM=' &> /dev/null || return 1

    QUEUE_READ

    if [[ -n "${QUEUE[@]-}" ]]; then
        QUEUE=("${QUEUE[@]-}" "${QITEM[@]}")
    else
        QUEUE=("${QITEM[@]}")
    fi

    QUEUE_SAVE || return 1

}

function QUEUE_PUSH_FAIL(){

    QUEUE_FILE="${QUEUE_FILE_FAILED}"

    QUEUE_PUSH

    local RETURN=$?

    QUEUE_FILE="${QUEUE_FILE_ORIG}"

    return "${RETURN}"

}

function QUEUE_READ(){

    QUEUE=()

    local QITEM

    [[ ! -f ${QUEUE_FILE} ]] && return 0

    while IFS=$'\n' read QITEM; do
        [[ -n "${QITEM-}" ]] && QUEUE+=("${QITEM}")
    done < "${QUEUE_FILE}"

    return 0

}

##PRIVATE
function QUEUE_SAVE(){

    if [[ -z "${QUEUE[@]-}" ]]; then
        echo "" > "${QUEUE_FILE}" && return 0 || return 1
    else
        printf "%s\n" "${QUEUE[@]-}" > "${QUEUE_FILE}" && return 0 || return 1
    fi

}

function QUEUE_REMOVE_FILE(){

    local FORCE="${1-false}"

    if [[ "${FORCE}" != "true" ]]; then

        QUEUE_READ

        [[ -n "${QUEUE[@]-}" ]] && LOG "ERROR: TRYING TO REMOVE QUEUE FILE WITH ITEMS STILL QUEUED. EXITING." && QUIT 1

    fi

    [[ -f "${QUEUE_FILE}" ]] && rm "${QUEUE_FILE}"

    return 0

}
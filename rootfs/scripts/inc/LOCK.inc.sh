#!/usr/bin/env bash

function LOCK_SET(){

    [[ -z "${LOCK_FILE-}" ]] && return 1

    echo $$ > "${LOCK_FILE}" || return 1

    echo "LOCK SET AT (${LOCK_FILE}) FOR ($$)"

    return 0

}

function LOCK_UNSET(){

    [[ -z "${LOCK_FILE-}" ]] && return 1

    rm "${LOCK_FILE}" || return 1

    echo "LOCK UNSET AT (${LOCK_FILE})"

    return 0

}

function LOCK_IS(){

    echo "LOCK CHECK..."

    [[ -z "${LOCK_FILE-}" ]] && echo "LOCK NOT FOUND." && return 1

    [[ ! -f ${LOCK_FILE} ]] && echo "LOCK NOT FOUND." && return 1

    local PID="$(cat "${LOCK_FILE}")"

    [[ -z "${PID}" ]] && echo "LOCK NOT FOUND." && return 1

    #LOCKED and PID IS RUNNING
    ps --noheaders -p ${PID} &> /dev/null && echo "LOCK WAS FOUND." && return 0

    LOCK_UNSET && echo "LOCK NOT FOUND." && return 1

}
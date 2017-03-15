#!/usr/bin/env bash

function LOCK_SET(){

    [[ -z "${LOCK_FILE-}" ]] && return 1

    echo $$ > "${LOCK_FILE}" || return 1

    return 0

}

function LOCK_UNSET(){

    [[ -z "${LOCK_FILE-}" ]] && return 1

    rm "${LOCK_FILE}" || return 1

    return 0

}

function LOCK_IS(){

    [[ -z "${LOCK_FILE-}" ]] && return 1

    [[ ! -f ${LOCK_FILE} ]] && return 1

    local PID="$(cat "${LOCK_FILE}")"

    [[ -z "${PID}" ]] && return 1

    #LOCKED and PID IS RUNNING
    local LOCKED_CMD="$(ps --noheaders -p ${PID} -o cmd)" && [[ "${0}" == "${LOCKED_CMD}" ]] && return 0

    LOCK_UNSET && return 1

}
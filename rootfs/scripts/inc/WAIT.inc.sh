#!/usr/bin/env bash

function WAITFORANY(){

    set +x

    local PID=

    echo "WAITING FOR A JOB TO COMPLETE (${PIDS[@]-})..."

    while [[ -n "${PIDS[@]-}" ]]; do

        for PID in "${PIDS[@]-}"; do

            ps -p ${PID} > /dev/null || break 2

        done

        sleep 1

    done;

    [[ "${DEBUG-}" == "true" ]] && set -x

    return 0

}

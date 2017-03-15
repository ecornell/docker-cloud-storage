#!/usr/bin/env bash
[[ "${DEBUG}" == "true" ]] && set -x

set -u -o pipefail

DEST_DIR="${1}" && shift
SOURCE_DIR="${1}" && shift
FILES=("${@}")

"${FILES[@]}" | /scripts/parallel.sh "/scripts/transfer_copy.sh ${DEST_DIR} {}"
/scripts/transfer_tier.sh "${DEST_DIR}" "${SOURCE_DIR}"
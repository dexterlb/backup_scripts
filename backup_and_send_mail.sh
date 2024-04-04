#!/bin/bash

set -euo pipefail
cdir="$(dirname "$(readlink -f "${0}")")"

. "${cdir}"/config.sh

function msg {
    echo "${@}" >&2
}

output_file="$(mktemp)"
trap 'rm -rf -- "${output_file}"' EXIT

fail=0
"${cdir}"/backup.sh 2>&1 | tee >(ts '%Y-%m-%d %H:%M:%S' > "${output_file}") || fail=1

if [[ "${fail}" -ne 0 ]]; then
    msg "Script has failures. Sending mail."
    mail -s "$(hostname) backups have errors" "${error_email}" < "${output_file}"
fi

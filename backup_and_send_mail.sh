#!/bin/bash

set -euo pipefail
cdir="$(dirname "$(readlink -f "${0}")")"

. "${cdir}"/config.sh

function msg {
    echo "${@}" >&2
}

if which mail &>/dev/null; then
    mail_cmd=mail
elif which s-nail &>/dev/null; then
    mail_cmd=s-nail
else
    msg "unable to find a command for sending mail"
    exit 1
fi

output_file="$(mktemp)"
trap 'rm -rf -- "${output_file}"{,.sync}' EXIT
mkfifo "${output_file}".sync

fail=0
"${cdir}"/backup.sh 2>&1 | tee >(ts '%Y-%m-%d %H:%M:%S' > "${output_file}"; echo > "${output_file}".sync) || fail=1
cat "${output_file}".sync

if [[ "${fail}" -ne 0 ]]; then
    msg "Script has failures. Sending mail."
    "${mail_cmd}" -s "$(hostname) backups have errors" "${error_email}" < "${output_file}"
fi

#!/usr/bin/env bash
set -e -u -o pipefail
cdir="$(dirname "$(readlink -f "${0}")")"

function msg {
    echo "${@}" >&2
}

if ! cmp <(cat "${cdir}"/config.sh | grep -oE '^[a-zA-Z_-]+=') <(cat "${cdir}"/config.example.sh | grep -oE '^[a-zA-Z_-]+='); then
    msg "fatal: config.sh and config.example.sh contain different var definitions"
    exit 1
fi

. "${cdir}"/config.sh

fail=0

# NOTE start all commands in background and wait for them to finish.
# Reason: bash ignores any signals while child process is executing and thus my trap exit hook is not triggered.
# However if put in subprocesses, wait(1) waits until the process finishes OR signal is received.
# Reference: https://unix.stackexchange.com/questions/146756/forward-sigterm-to-child-in-bash
function wait_check {
    wait $1 || { fail=1; msg "command failed!"; }
}

check_cache_dir="$(readlink -f "${cdir}/../check_cache")/$(date +'%Y%m%d%H%M%S')"
mkdir -p "${check_cache_dir}"
msg "will use dir ${check_cache_dir} for restic check cache"

function clear_cache {
    msg "removing cache dir ${check_cache_dir}"
    rm -rf "${check_cache_dir}"
}
# Clean up lock if we are killed.
# If killed by systemd, like $(systemctl stop restic), then it kills the whole cgroup and all it's subprocesses.
# However if we kill this script ourselves, we need this trap that kills all subprocesses manually.
function exit_hook {
    msg "In exit_hook(), being killed" >&2
    jobs -p | xargs kill
    ${restic_cmd} -r "${repo}" unlock
    clear_cache
}
trap exit_hook INT TERM

export RESTIC_PASSWORD="${repo_password}"

# Remove locks from other stale processes to keep the automated backup running.
msg "unlocking repo"
"${restic_cmd}" -r "${repo}" unlock &
wait_check $!

# Do the backup!

for bp in "${backups[@]}"; do
    IFS=: read tag spec path <<< "${bp}"

    case "${spec}" in
        dir)
            msg
            msg
            msg "backing up dir ${tag} (${path})"
            msg
            msg "performing checks on ${path}"
            msg

            "${cdir}"/check_dir.sh "${path}" &
            wait_check $!

            if [[ -f "${path}"/.backup_exclude ]]; then
                excludes=(--exclude-file "${path}"/.backup_exclude)
            else
                excludes=()
            fi

            ${restic_cmd} -r "${repo}" backup \
                --verbose \
                --one-file-system \
                --tag ${common_tag} \
                --tag ${tag} \
                "${excludes[@]}" \
                "${path}" &
            wait_check $!
            ;;
        default)
            fail=1
            msg "unknown backup spec: '${spec}'"
            ;;
    esac
done

msg
msg
msg "cleaning up old backups"
msg
# Dereference and delete/prune old backups.
# See restic-forget(1) or http://restic.readthedocs.io/en/latest/060_forget.html
# --group-by only the tag and path, and not by hostname. This allows the same backup
# to be done by multiple hosts (if they can access the same data)
"${restic_cmd}" -r "${repo}" forget \
    --verbose \
    --tag ${common_tag} \
    --prune \
    --group-by "paths,tags" \
    "${retention[@]}" &
wait_check $!

# Check repository for errors.
# NOTE this takes much time (and data transfer from remote repo?), maybe we need to do this in a separate systemd.timer which is run less often.
${restic_cmd} -r "${repo}" check --with-cache --cache-dir "${check_cache_dir}" &
wait_check $!

clear_cache &
wait_check $!

msg "Backup & cleaning is done."
if [[ "${fail}" -ne 0 ]]; then
    msg "Some errors were present."
    exit 1
fi

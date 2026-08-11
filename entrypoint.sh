#!/bin/sh
set -eu

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

require_value() {
    name="$1"
    value="$2"
    [ -n "${value}" ] || fail "${name} must be set"
}

require_positive_integer() {
    name="$1"
    value="$2"
    case "${value}" in
        ''|*[!0-9]*)
            fail "${name} must be a positive integer"
            ;;
    esac
    [ "${value}" -gt 0 ] || fail "${name} must be greater than zero"
}

require_dir() {
    [ -d "$1" ] || fail "Required directory does not exist: $1"
}

require_readable_dir() {
    require_dir "$1"
    [ -r "$1" ] && [ -x "$1" ] || fail "Required directory is not readable: $1"
}

require_writable_dir() {
    require_dir "$1"
    [ -r "$1" ] && [ -w "$1" ] && [ -x "$1" ] || fail "Required directory is not writable: $1"
}

require_file() {
    [ -f "$1" ] || fail "Required file does not exist: $1"
}

require_readable_file() {
    require_file "$1"
    [ -r "$1" ] || fail "Required file is not readable: $1"
}

require_writable_file() {
    require_file "$1"
    [ -r "$1" ] && [ -w "$1" ] || fail "Required file is not writable: $1"
}

ROLE="${ROLE:-}"
PUID="${PUID:-}"
PGID="${PGID:-}"
TZ="${TZ:-}"
RECOLL_CONFDIR="${RECOLL_CONFDIR:-/recoll/config}"
RECOLL_TMPDIR="/recoll/tmp"
TMPDIR="/recoll/tmp"
HOME="/recoll/tmp"

require_value ROLE "${ROLE}"
require_value PUID "${PUID}"
require_value PGID "${PGID}"
require_value TZ "${TZ}"
require_positive_integer PUID "${PUID}"
require_positive_integer PGID "${PGID}"

case "${TZ}" in
    /*|*..*)
        fail "TZ must name a zone under /usr/share/zoneinfo"
        ;;
esac
[ -f "/usr/share/zoneinfo/${TZ}" ] || fail "Unknown TZ: ${TZ}"

export RECOLL_CONFDIR RECOLL_TMPDIR TMPDIR HOME TZ

if [ "$(id -u)" -eq 0 ]; then
    exec setpriv \
        --reuid="${PUID}" \
        --regid="${PGID}" \
        --clear-groups \
        --inh-caps=-all \
        "$0" "$@"
fi

[ "$(id -u)" -eq "${PUID}" ] || fail "Runtime UID does not match PUID=${PUID}"
[ "$(id -g)" -eq "${PGID}" ] || fail "Runtime GID does not match PGID=${PGID}"

require_readable_dir /documents/source
require_readable_dir "${RECOLL_CONFDIR}"
require_readable_file "${RECOLL_CONFDIR}/recoll.conf"
require_readable_file "${RECOLL_CONFDIR}/mimeconf"

require_indexer_storage() {
    require_writable_dir "${RECOLL_CONFDIR}"
    require_writable_file "${RECOLL_CONFDIR}/missing"
    require_writable_dir /recoll/index
    require_writable_dir /recoll/cache
    require_writable_dir /recoll/state
    require_writable_file /recoll/state/idxstatus.txt
    require_writable_dir /recoll/tmp
}

require_webui_storage() {
    require_readable_dir /recoll/index
    require_writable_dir /recoll/cache
    require_writable_dir /recoll/tmp
}

case "${ROLE}" in
    indexer)
        require_indexer_storage

        interval="${RECOLL_INDEX_INTERVAL_SECONDS:-}"
        run_on_start="${RECOLL_INDEX_RUN_ON_START:-}"
        require_value RECOLL_INDEX_INTERVAL_SECONDS "${interval}"
        require_value RECOLL_INDEX_RUN_ON_START "${run_on_start}"
        require_positive_integer RECOLL_INDEX_INTERVAL_SECONDS "${interval}"

        child_pid=""

        terminate_child() {
            if [ -n "${child_pid}" ] && kill -0 "${child_pid}" 2>/dev/null; then
                kill -TERM "${child_pid}" 2>/dev/null || true
                wait "${child_pid}" || true
            fi
            exit 0
        }

        run_index() {
            recollindex &
            child_pid="$!"

            set +e
            wait "${child_pid}"
            rc="$?"
            set -e

            child_pid=""
            if [ "${rc}" -ne 0 ]; then
                printf '%s\n' "recollindex exited with status ${rc}" >&2
            fi
        }

        trap terminate_child INT TERM HUP

        case "${run_on_start}" in
            true|1|yes)
                run_index
                ;;
            false|0|no)
                ;;
            *)
                fail "RECOLL_INDEX_RUN_ON_START must be true/false, 1/0, or yes/no"
                ;;
        esac

        while :; do
            sleep "${interval}" &
            child_pid="$!"
            wait "${child_pid}"
            child_pid=""
            run_index
        done
        ;;

    webui)
        require_webui_storage
        exec python3 \
            /opt/recoll-webui/webui-standalone.py \
            -a 0.0.0.0 \
            -p 8080 \
            -c "${RECOLL_CONFDIR}"
        ;;

    update-once)
        require_indexer_storage
        exec recollindex
        ;;

    retry-once)
        require_indexer_storage
        exec recollindex -k
        ;;

    reindex-in-place)
        require_indexer_storage
        exec recollindex -Z
        ;;

    *)
        fail "Unknown ROLE: ${ROLE}"
        ;;
esac

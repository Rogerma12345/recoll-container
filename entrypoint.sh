#!/bin/sh
set -eu

ROLE="${ROLE:-indexer}"
RECOLL_CONFDIR="${RECOLL_CONFDIR:-/recoll/config}"

export RECOLL_CONFDIR

require_dir() {
    if [ ! -d "$1" ]; then
        echo "Required directory does not exist: $1" >&2
        exit 1
    fi
}

require_file() {
    if [ ! -f "$1" ]; then
        echo "Required file does not exist: $1" >&2
        exit 1
    fi
}

require_writable_dir() {
    require_dir "$1"

    if [ ! -w "$1" ]; then
        echo "Required directory is not writable: $1" >&2
        exit 1
    fi
}

require_dir /documents/source
require_dir "${RECOLL_CONFDIR}"
require_file "${RECOLL_CONFDIR}/recoll.conf"

case "${ROLE}" in
    indexer)
        require_writable_dir /recoll/index
        require_writable_dir /recoll/cache
        require_writable_dir /recoll/tmp

        interval="${RECOLL_INDEX_INTERVAL_SECONDS:-21600}"
        run_on_start="${RECOLL_INDEX_RUN_ON_START:-true}"
        child_pid=""

        case "${interval}" in
            ''|*[!0-9]*)
                echo "RECOLL_INDEX_INTERVAL_SECONDS must be an integer" >&2
                exit 1
                ;;
        esac

        if [ "${interval}" -lt 1 ]; then
            echo "RECOLL_INDEX_INTERVAL_SECONDS must be greater than zero" >&2
            exit 1
        fi

        terminate_child() {
            if [ -n "${child_pid}" ] && kill -0 "${child_pid}" 2>/dev/null; then
                kill -TERM "${child_pid}" 2>/dev/null || true
                wait "${child_pid}" || true
            fi
            exit 0
        }

        trap terminate_child INT TERM HUP

        run_index() {
            recollindex &
            child_pid="$!"

            set +e
            wait "${child_pid}"
            rc="$?"
            set -e

            child_pid=""

            if [ "${rc}" -ne 0 ]; then
                echo "recollindex exited with status ${rc}" >&2
            fi
        }

        case "${run_on_start}" in
            true|1|yes)
                run_index
                ;;
            false|0|no)
                ;;
            *)
                echo "Invalid RECOLL_INDEX_RUN_ON_START value" >&2
                exit 1
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
        exec python3 \
            /opt/recoll-webui/webui-standalone.py \
            -a 0.0.0.0 \
            -p 8080 \
            -c "${RECOLL_CONFDIR}"
        ;;

    update-once)
        exec recollindex
        ;;

    retry-once)
        exec recollindex -k
        ;;

    reindex-in-place)
        exec recollindex -Z
        ;;

    *)
        echo "Unknown ROLE: ${ROLE}" >&2
        exit 1
        ;;
esac


_GET_CALLER_INFO()
{
    if [[ "${FUNCNAME[2]}" != "main" ]]; then
        echo -n "("
        if [ "${BASH_SOURCE[3]}" ]; then
            echo -n "${BASH_SOURCE[3]//$SRC_DIR\//}:"
        fi
        if [ "${BASH_LINENO[2]}" ]; then
            echo -n "${BASH_LINENO[2]}:"
        fi
        echo -n "${FUNCNAME[2]}) "
    else
        echo -n "("
        if [ "${BASH_SOURCE[2]}" ]; then
            echo -n "${BASH_SOURCE[2]//$SRC_DIR\//}:"
        fi
        if [ "${BASH_LINENO[1]}" ]; then
            echo -n "${BASH_LINENO[1]}"
        fi
        echo -n ") "
    fi
}

LOG()
{
    local INDENT="${INDENT_LEVEL:=0}"

    echo -e "$(printf "%*s%s" "$INDENT" "" "$1")"
}

LOGE()
{
    local RED="\033[0;31m"
    local RESET="\033[0m"

    echo -e "${RED}$(_GET_CALLER_INFO)${1}${RESET}" >&2
}

LOGW()
{
    local YELLOW="\033[0;33m"
    local RESET="\033[0m"

    echo -e "${YELLOW}$(_GET_CALLER_INFO)${1}${RESET}" >&2
}

LOG_STEP_IN()
{
    local BOLD
    local RESET="\033[0m"

    if [[ "$1" == "true" ]]; then
        BOLD="\033[1;37m"
        shift
    fi

    if [ "$1" ]; then
        LOG "${BOLD}${1}${RESET}"
    fi

    local INDENT="${INDENT_LEVEL:=0}"
    export INDENT_LEVEL="$((INDENT + 2))"
}

LOG_STEP_OUT()
{
    local INDENT="${INDENT_LEVEL:=0}"
    if [ "$INDENT_LEVEL" -gt 0 ]; then
        export INDENT_LEVEL=$((INDENT - 2))
    fi
}

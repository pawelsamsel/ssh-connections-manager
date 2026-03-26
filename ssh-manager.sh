#!/usr/bin/env bash
# SSH Connection Manager — bash port of ssh-manager.js

CONFIG_FILE="$(cd "$(dirname "$0")" && pwd)/ssh-connections-config"

# ── Colors ────────────────────────────────────────────────────────────────────
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
BG_BLUE=$'\033[44m'
BG_CYAN=$'\033[46m'
FG_WHITE=$'\033[97m'
FG_BLACK=$'\033[30m'

# ── State ─────────────────────────────────────────────────────────────────────
declare -a HOSTS HOSTNAMES USERS PORTS IDENTITIES
FILTERED=()
cursor=0
offset=0
search_query=""
pending_delete=0
message=""
message_color=""

# ── Terminal helpers ──────────────────────────────────────────────────────────
clear_screen() { printf '\033[2J\033[H'; }
hide_cursor()  { printf '\033[?25l'; }
show_cursor()  { printf '\033[?25h'; }
get_cols()     { tput cols  2>/dev/null || echo 80; }
get_rows()     { tput lines 2>/dev/null || echo 24; }

raw_on()  { stty -echo -icanon min 1 time 0 2>/dev/null; }
raw_off() { stty sane 2>/dev/null; }
lc()      { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ── Config I/O ────────────────────────────────────────────────────────────────
load_connections() {
    HOSTS=(); HOSTNAMES=(); USERS=(); PORTS=(); IDENTITIES=()
    [[ ! -f "$CONFIG_FILE" ]] && return

    local idx=-1
    while IFS= read -r raw || [[ -n "$raw" ]]; do
        local line="${raw#"${raw%%[![:space:]]*}"}"   # ltrim
        [[ -z "$line" || "$line" == \#* ]] && continue

        if [[ "$(lc "$line")" == host\ * ]]; then
            (( idx++ ))
            local hname="${line:5}"
            HOSTS[$idx]="${hname#"${hname%%[![:space:]]*}"}"
            HOSTNAMES[$idx]=""; USERS[$idx]=""; PORTS[$idx]="22"; IDENTITIES[$idx]=""
        elif (( idx >= 0 )); then
            local key="${line%% *}" val="${line#* }"
            case "$(lc "$key")" in
                hostname)     HOSTNAMES[$idx]="$val" ;;
                user)         USERS[$idx]="$val" ;;
                port)         PORTS[$idx]="$val" ;;
                identityfile) IDENTITIES[$idx]="$val" ;;
            esac
        fi
    done < "$CONFIG_FILE"
}

save_connections() {
    local out="" count=${#HOSTS[@]}
    for (( i=0; i<count; i++ )); do
        [[ $i -gt 0 ]] && out+=$'\n'
        out+="Host ${HOSTS[$i]}"$'\n'
        out+="  HostName ${HOSTNAMES[$i]}"$'\n'
        out+="  User ${USERS[$i]}"$'\n'
        [[ "${PORTS[$i]}" != "22" ]] && out+="  Port ${PORTS[$i]}"$'\n'
        [[ -n "${IDENTITIES[$i]}" ]] && out+="  IdentityFile ${IDENTITIES[$i]}"$'\n'
    done
    printf '%s' "$out" > "$CONFIG_FILE"
}

# ── Filtering ─────────────────────────────────────────────────────────────────
update_filtered() {
    FILTERED=()
    local q; q=$(lc "$search_query")
    local count=${#HOSTS[@]}
    for (( i=0; i<count; i++ )); do
        if [[ -z "$q" ]] \
        || [[ "$(lc "${HOSTS[$i]}")"     == *"$q"* ]] \
        || [[ "$(lc "${HOSTNAMES[$i]}")" == *"$q"* ]] \
        || [[ "$(lc "${USERS[$i]}")"     == *"$q"* ]]; then
            FILTERED+=("$i")
        fi
    done
}

# ── Rendering ─────────────────────────────────────────────────────────────────
trunc() {
    local s="$1" max="$2"
    (( ${#s} > max )) && printf '%s…' "${s:0:$((max-1))}" || printf '%s' "$s"
}

hline() {
    local W="$1"
    printf "${DIM}"
    printf '─%.0s' $(seq 1 "$W")
    printf "${RESET}\n"
}

render() {
    update_filtered
    local W; W=$(get_cols)
    local rows; rows=$(get_rows)
    local visible=$(( rows - 12 ))
    (( visible < 3 )) && visible=3
    local total=${#FILTERED[@]}

    clear_screen

    # Header
    printf "${BG_CYAN}${FG_BLACK}${BOLD}%-${W}s${RESET}\n" "  SSH Connection Manager"
    printf "${DIM}%-${W}s${RESET}\n" "  Config: $CONFIG_FILE"
    printf '\n'

    # Search bar
    if [[ -n "$search_query" ]]; then
        printf "  ${BOLD}Search:${RESET} ${CYAN}%s${RESET}${DIM}▌${RESET}  ${DIM}(ESC to clear)${RESET}\n\n" "$search_query"
    else
        printf "  ${DIM}Start typing to search…${RESET}\n\n"
    fi

    local count=${#HOSTS[@]}
    if (( count == 0 )); then
        printf "${DIM}  No connections yet. Press Ctrl+N to add one.${RESET}\n"
    elif (( total == 0 )); then
        printf "${DIM}  No matches for \"%s\"${RESET}\n" "$search_query"
    else
        local nameW=$(( W * 30 / 100 ))
        local hostW=$(( W * 30 / 100 ))
        local userW=$(( W * 15 / 100 ))
        local portW=8

        printf "${BOLD}${CYAN}  %-${nameW}s %-${hostW}s %-${userW}s %-${portW}s${RESET}\n" \
            "NAME" "HOSTNAME" "USER" "PORT"
        hline "$W"

        local end=$(( offset + visible ))
        (( end > total )) && end=$total

        for (( i=offset; i<end; i++ )); do
            local idx=${FILTERED[$i]}
            local name host user port
            name=$(trunc "${HOSTS[$idx]}"     "$nameW")
            host=$(trunc "${HOSTNAMES[$idx]}" "$hostW")
            user=$(trunc "${USERS[$idx]}"     "$userW")
            port="${PORTS[$idx]:-22}"

            if (( i == cursor )); then
                printf "${BG_BLUE}${FG_WHITE}${BOLD}▶ %-${nameW}s %-${hostW}s %-${userW}s %-${portW}s${RESET}\n" \
                    "$name" "$host" "$user" "$port"
            else
                printf "  %-${nameW}s ${DIM}%-${hostW}s${RESET} ${GREEN}%-${userW}s${RESET} ${YELLOW}%-${portW}s${RESET}\n" \
                    "$name" "$host" "$user" "$port"
            fi
        done

        if (( total > visible )); then
            local pct=$(( offset * 100 / (total - visible) ))
            printf "${DIM}\n  Showing $((offset+1))–${end} of ${total}  (${pct}%% scrolled)${RESET}\n"
        fi
    fi

    printf '\n'
    hline "$W"

    # Help bar
    printf "${BOLD}${CYAN}↑↓${RESET} ${DIM}navigate${RESET}  "
    printf "${BOLD}${CYAN}Enter${RESET} ${DIM}connect${RESET}  "
    printf "${BOLD}${CYAN}^N${RESET} ${DIM}new${RESET}  "
    printf "${BOLD}${CYAN}^E${RESET} ${DIM}edit${RESET}  "
    printf "${BOLD}${CYAN}^D${RESET} ${DIM}delete${RESET}  "
    printf "${BOLD}${CYAN}ESC${RESET} ${DIM}search/quit${RESET}  "
    printf "${BOLD}${CYAN}^C${RESET} ${DIM}quit${RESET}\n"

    if [[ -n "$message" ]]; then
        printf "\n${message_color}%s${RESET}\n" "$message"
    fi
}

# ── Forms ─────────────────────────────────────────────────────────────────────
ask_field() {
    local prompt="$1" default="$2" answer
    local hint=""
    [[ -n "$default" ]] && hint=" (${DIM}${default}${RESET})"
    printf "${YELLOW}%s${RESET}%b: " "$prompt" "$hint"
    IFS= read -r answer
    [[ -z "$answer" ]] && answer="$default"
    printf '%s' "$answer"
}

# ── Actions ───────────────────────────────────────────────────────────────────
do_connect() {
    (( ${#FILTERED[@]} == 0 )) && return
    local idx=${FILTERED[$cursor]}

    show_cursor; raw_off; clear_screen
    printf "\n${CYAN}Connecting to ${BOLD}%s${RESET}${CYAN} (%s@%s)...${RESET}\n\n" \
        "${HOSTS[$idx]}" "${USERS[$idx]}" "${HOSTNAMES[$idx]}"

    ssh -F "$CONFIG_FILE" "${HOSTS[$idx]}"

    printf "\n${DIM}Connection closed.${RESET}\n"
    message="Disconnected from ${HOSTS[$idx]}"
    message_color="$DIM"
    load_connections
    hide_cursor; raw_on
    render
}

do_add() {
    show_cursor; raw_off; clear_screen

    printf "${BOLD}${CYAN}Add new SSH connection${RESET}\n"
    printf "${DIM}"; printf '─%.0s' {1..40}; printf "${RESET}\n\n"

    local host hostname user port identity

    host=$(ask_field "Name / alias (Host)" "")
    if [[ -z "$host" ]]; then
        message="Cancelled."; message_color="$DIM"
        hide_cursor; raw_on; render; return
    fi

    hostname=$(ask_field "Hostname / IP" "")
    if [[ -z "$hostname" ]]; then
        message="Cancelled."; message_color="$DIM"
        hide_cursor; raw_on; render; return
    fi

    user=$(ask_field "Username" "${USER:-root}")
    port=$(ask_field "Port" "22")
    identity=$(ask_field "IdentityFile (optional)" "")

    local new_idx=${#HOSTS[@]}
    HOSTS[$new_idx]="$host"
    HOSTNAMES[$new_idx]="$hostname"
    USERS[$new_idx]="${user:-${USER:-root}}"
    PORTS[$new_idx]="${port:-22}"
    IDENTITIES[$new_idx]="$identity"

    save_connections
    cursor=$new_idx; search_query=""; offset=0
    message="Added: $host"; message_color="$GREEN"
    hide_cursor; raw_on; render
}

do_edit() {
    (( ${#FILTERED[@]} == 0 )) && return
    local idx=${FILTERED[$cursor]}

    show_cursor; raw_off; clear_screen

    printf "${BOLD}${CYAN}Edit connection: %s${RESET}\n" "${HOSTS[$idx]}"
    printf "${DIM}"; printf '─%.0s' {1..40}; printf "${RESET}\n\n"

    local host hostname user port identity

    host=$(ask_field "Name / alias"          "${HOSTS[$idx]}")
    hostname=$(ask_field "Hostname / IP"     "${HOSTNAMES[$idx]}")
    user=$(ask_field "Username"              "${USERS[$idx]}")
    port=$(ask_field "Port"                  "${PORTS[$idx]:-22}")
    identity=$(ask_field "IdentityFile (optional)" "${IDENTITIES[$idx]}")

    HOSTS[$idx]="${host:-${HOSTS[$idx]}}"
    HOSTNAMES[$idx]="${hostname:-${HOSTNAMES[$idx]}}"
    USERS[$idx]="${user:-${USERS[$idx]}}"
    PORTS[$idx]="${port:-22}"
    IDENTITIES[$idx]="$identity"

    save_connections
    message="Updated: ${HOSTS[$idx]}"; message_color="$GREEN"
    hide_cursor; raw_on; render
}

do_delete_prompt() {
    (( ${#FILTERED[@]} == 0 )) && return
    local idx=${FILTERED[$cursor]}
    pending_delete=1
    message="Delete \"${HOSTS[$idx]}\"? Y to confirm, any other key to cancel."
    message_color="$RED"
    render
}

do_delete_confirm() {
    (( ${#FILTERED[@]} == 0 )) && return
    local idx=${FILTERED[$cursor]}
    local host_name="${HOSTS[$idx]}"

    local new_H=() new_HN=() new_U=() new_P=() new_I=()
    local count=${#HOSTS[@]}
    for (( i=0; i<count; i++ )); do
        (( i == idx )) && continue
        new_H+=("${HOSTS[$i]}"); new_HN+=("${HOSTNAMES[$i]}")
        new_U+=("${USERS[$i]}"); new_P+=("${PORTS[$i]}")
        new_I+=("${IDENTITIES[$i]}")
    done
    HOSTS=("${new_H[@]}"); HOSTNAMES=("${new_HN[@]}")
    USERS=("${new_U[@]}"); PORTS=("${new_P[@]}")
    IDENTITIES=("${new_I[@]}")

    update_filtered
    local new_total=${#FILTERED[@]}
    (( cursor >= new_total )) && cursor=$(( new_total > 0 ? new_total - 1 : 0 ))

    save_connections
    message="Deleted: $host_name"; message_color="$YELLOW"
    render
}

move_up() {
    if (( cursor > 0 )); then
        cursor=$(( cursor - 1 ))
        if (( cursor < offset )); then offset=$cursor; fi
    fi
}

move_down() {
    local total=${#FILTERED[@]}
    if (( cursor < total - 1 )); then
        cursor=$(( cursor + 1 ))
        local rows; rows=$(get_rows)
        local visible=$(( rows - 12 ))
        if (( visible < 3 )); then visible=3; fi
        if (( cursor >= offset + visible )); then
            offset=$(( cursor - visible + 1 ))
        fi
    fi
}

do_quit() {
    show_cursor; raw_off; clear_screen
    printf "${DIM}Bye!${RESET}\n"
    exit 0
}

# ── Main loop ─────────────────────────────────────────────────────────────────
main() {
    load_connections
    hide_cursor
    raw_on
    trap 'show_cursor; raw_off; exit 0' INT TERM

    render

    while true; do
        IFS= read -r -s -n1 key

        # Arrow keys send ESC [ A/B/C/D — read byte by byte with integer timeout
        if [[ "$key" == $'\x1b' ]]; then
            IFS= read -r -s -n1 -t 1 k1 2>/dev/null; key="${key}${k1}"
            IFS= read -r -s -n1 -t 1 k2 2>/dev/null; key="${key}${k2}"
        fi

        if (( pending_delete )); then
            pending_delete=0
            if [[ "$key" == "y" || "$key" == "Y" ]]; then
                do_delete_confirm
            else
                message="Delete cancelled."; message_color="$DIM"
                render
            fi
            continue
        fi

        message=""

        case "$key" in
            $'\x1b[A') move_up;   render ;;   # Arrow Up
            $'\x1b[B') move_down; render ;;   # Arrow Down
            $'\r'|$'\n') do_connect ;;         # Enter
            $'\x0e') do_add ;;                 # Ctrl+N
            $'\x05') do_edit ;;                # Ctrl+E
            $'\x04') do_delete_prompt ;;       # Ctrl+D
            $'\x03') do_quit ;;               # Ctrl+C
            $'\x1b')                           # ESC (bare — no sequence)
                if [[ -n "$search_query" ]]; then
                    search_query=""; cursor=0; offset=0; render
                else
                    do_quit
                fi
                ;;
            $'\x7f')                           # Backspace
                if (( ${#search_query} > 0 )); then
                    search_query="${search_query:0:$((${#search_query}-1))}"
                    cursor=0; offset=0
                fi
                render
                ;;
            *)
                # Printable → append to search
                if [[ ${#key} -eq 1 && "$key" == [[:print:]] ]]; then
                    search_query+="$key"; cursor=0; offset=0; render
                fi
                ;;
        esac
    done
}

main

#!/usr/bin/env bash

umask "${YO_UMASK:-077}"
set -o pipefail
set -e

# Defaults to ~/.config
TOP_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

# Defaults to ~/.config/yo
YO_CONFIG_DIR="${YO_CONFIG_DIR:-$TOP_CONFIG_DIR/yo}"
mkdir -p "$YO_CONFIG_DIR"

# Defaults to ~/.config/token
YO_TOKEN_PATH="${YO_TOKEN_PATH:-$YO_CONFIG_DIR/token}"

YO_BASE_URL="${YO_BASE_URL:-https://api.yocli.io}"

die() { cat >&2; exit 1; }

server_error_msg() {
cat <<EOF
It seems that the yo backend at '$YO_BASE_URL' is down right now, please try
again later.
EOF
}

small_term_msg() {
cat <<"EOF"
Your terminal is too small to display the pairing QR Code properly.
Hint: Try making it larger and invoking `yo` again!
EOF
}

# Usage:
#     log CATEGORY <<< "Message goes here"
log() {
    if [ -n "$DEBUG" ]; then
        echo -n "$1 | ${FUNCNAME[1]}: " >&2
        cat >&2
    fi
}

# Usage:
#     link_w_qr STR-TO-DISPLAY
text_display_qr() {
    if (( 22 < "$(tput lines)" )); then
        echo -n "$1" | qrencode -t utf8
    else
        small_term_msg | die
    fi
}

display_qr() {
    local title="yo"
    if [[ -n $DISPLAY || -n $WAYLAND_DISPLAY ]]; then
        if type feh >/dev/null 2>&1; then
            echo -n "$1" | qrencode --size 10 -o - | feh -x --title "$title" -g +200+200 - &
        elif type gm >/dev/null 2>&1; then
            echo -n "$1" | qrencode --size 10 -o - | gm display -title "$title" -geometry +200+200 - &
        elif type display >/dev/null 2>&1; then
            echo -n "$1" | qrencode --size 10 -o - | display -title "$title" -geometry +200+200 - &
        else
            text_display_qr "$1"
        fi
    else
        text_display_qr "$1"
    fi
}

# Usage:
#     yo APNS-COLLAPSE-ID [ APNS-PUSH-TYPE ]
yo() {
    curl --silent -o /dev/null -w '%{http_code}' \
         -X POST \
         -F apns-collapse-id="$1" \
         ${2:+-F apns-push-type="$2"} \
         -F pc_token="$(< "$YO_TOKEN_PATH")" \
         -L "${YO_BASE_URL}/yo" 2>/dev/null
}

# Usage:
#     yo-repeatedly HTTP-RETRY-LOW HTTP-RETRY-HIGH [ MAX-RETRY-TIMES APNS-PUSH-TYPE ]
yo_repeatedly() {
    local collapse_id
    collapse_id="$(uuidgen)"
    log DEBUG <<< "HTTP codes inside ${1}..${2} will prompt a retry up to ${3:-256} times"
    for (( i=0; "$i"<"${3:-256}"; i++ )); do
        if [ -n "$!" ] && ! ps -p "$!" >/dev/null; then
            echo "Aborted." >&2
            exit 1
        fi
        local status
        status="$(yo "$collapse_id" ${4:+"$4"})"
        if (("$status"<"${1}" || "${2}"<="$status" )); then
            log DEBUG <<< "Try #${i}, status=${status}: OUTside retry range, not retrying anymore"
            break
        else
            log DEBUG <<< "Try #${i}, status=${status}: INside retry range, retrying in 1 sec..."
            sleep 1
        fi
    done
    log DEBUG <<< "Final HTTP status: ${status}"
    echo "$status"
}

new_token() {
    local yo_token
    yo_token="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    log INFO <<< "Generated PC token: '${yo_token}'"
    log INFO <<< "Saving newly generated PC token to: '$YO_TOKEN_PATH'"
    echo "$yo_token" > "$YO_TOKEN_PATH"
    echo "$yo_token"
}

# Usage:
#     link_w_qr PC_TOKEN
link_w_qr() {
    log INFO <<< "Displaying QR code for '${YO_BASE_URL}/?p=${1}'"
    display_qr "${YO_BASE_URL}/?p=${1}"
    log DEBUG <<< "Polling backend for success..."
    local status
    status="$(yo_repeatedly 400 500 "" background)"
    [ -n "$!" ] && kill $!
    if ((500 <= "$status" && "$status" < 600)); then
        server_error_msg | die
    else
        echo "Sucessfully linked a mobile device!"
    fi
}

source "$(dirname "$0")/platform/$(uname | cut -d _ -f 1 | tr '[:upper:]' '[:lower:]').sh" 2>/dev/null # PLATFORM_FUNCTION_FILE

if [ ! -e "$YO_TOKEN_PATH" ]; then
    echo "No mobile device linked. Let's fix that :-)"
    link_w_qr "$(new_token)"
else
    status="$(yo_repeatedly 500 600 5 alert)"
    if (("$status" < 200 && 300 <= "$status" )); then
        if [ "$status" -eq 410 ]; then
            echo "Mobile device no longer linked. Let's fix that :-)"
            link_w_qr "$(new_token)"
        elif ((500 <= "$status" && "$status" < 600)); then
            server_error_msg | die
        else
            die <<< "Unknown error. Status code: ${status}"
        fi
    fi
fi

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

bold=$(tput smso)
nobold=$(tput rmso)

underline=$(tput smul)
nounderline=$(tput rmul)

server_error_msg() {
cat <<EOF
It seems that the yo backend at '$YO_BASE_URL' is down right now, please try
again later.
EOF
}

term_too_small_msg() {
cat <<"EOF"
Your terminal is too small to display the pairing QR Code properly.
Hint: Try making it larger and invoking `yo` again!
EOF
}

qr_waiting_msg() {
cat <<EOF
Waiting for successful pairing...

Hint: Hit Ctrl-C to exit.
EOF
}

pair_success_msg() {
cat <<EOF
Success: Linked an iOS device!

Hint: Try sending your first notification:

    \$ $PROGRAM

EOF
}

already_paired_msg() {
cat <<EOF
Your computer has already been paired with an iOS device.

Hint: To re-pair your computer with your iOS device, invoke the following:

    \$ $PROGRAM ${underline}re${nounderline}pair

EOF
}

brand_new_pc_msg() {
cat <<"EOF"
Looks like it's your first time using Yo, welcome!
EOF
}

qr_scan_prompt_msg() {
cat <<"EOF"
Scan the QR code displayed below using the Yo iOS app to pair or re-pair this
computer with your iOS device.
EOF
}

pc_token_not_paired_msg() {
cat <<EOF
You must first pair with an iOS device before you can send notifications.

Hint: Invoke the following command to pair with an iOS device:

    \$ $PROGRAM pair

EOF
}

apns_gone_msg() {
cat <<EOF
It would seem that your device has been unregistered from Apple's notification
services. This can happen if you've uninstalled/reinstalled the Yo app, if
you've just restored your iOS device from a backup, etc.

Hint: To re-pair your computer with your iOS device, invoke the following:

    \$ $PROGRAM ${underline}re${nounderline}pair

EOF
}

notification_dispatched_msg() {
cat <<EOF
Success: Notification dispatched to your paired iOS device!

Hint: Notifications not showing up? Try re-pairing with:

    \$ $PROGRAM ${underline}re${nounderline}pair

EOF
}

repair_msg() {
cat <<EOF
Removing the existing pairing and establishing a new one!
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
    text_display_qr "$1"
}

# Usage:
#     yo PC-TOKEN APNS-COLLAPSE-ID [ APNS-PUSH-TYPE ]
yo() {
    curl --silent -o /dev/null -w '%{http_code}' \
         -X POST \
         -F apns-collapse-id="$2" \
         ${3:+-F apns-push-type="$3"} \
         -F pc_token="$1" \
         -L "${YO_BASE_URL}/yo" 2>/dev/null
}

# Usage:
#     yo-repeatedly PC-TOKEN HTTP-RETRY-LOW HTTP-RETRY-HIGH [ MAX-RETRY-TIMES APNS-PUSH-TYPE ]
yo_repeatedly() {
    local collapse_id
    collapse_id="$(uuidgen)"
    local max_tries
    # max_tries="${4:-1800}"
    max_tries="${4:-10}"
    log DEBUG <<< "HTTP codes inside ${2}..${3} will prompt a retry up to ${max_tries} times"
    for (( i=0; "$i"<"$max_tries"; i++ )); do
        local status
        status="$(yo "$1" "$collapse_id" ${5:+"$5"})"
        if (( "$status"<"${2}" || "${3}"<="$status" )); then
            # Good, exit
            log DEBUG <<< "Try #${i}, status=${status}: OUTside retry range, not retrying anymore"
            break
        else
            # Bad, retry
            log DEBUG <<< "Try #${i}, status=${status}: INside retry range, retrying in 1 sec..."
            sleep 1
        fi
    done
    if [ "$i" = "$max_tries" ]; then
        log DEBUG <<< "Timed out after ${max_tries} tries"
        echo "TIMEOUT"
    else
        log DEBUG <<< "Final HTTP status: ${status}"
        echo "$status"
    fi
}

# Usage:
#     link_w_qr PC_TOKEN
link_w_qr() {
    local yo_token
    yo_token="$1"
    qr_scan_prompt_msg
    log INFO <<< "Displaying QR code for '${YO_BASE_URL}/?p=${yo_token}'"
    display_qr "${YO_BASE_URL}/?p=${yo_token}"
    echo
    log DEBUG <<< "Polling backend for success..."
    qr_waiting_msg
    local status
    status="$(yo_repeatedly "${yo_token}" 400 500 "" background)"
    if [ "$status" = "TIMEOUT" ]; then
        die <<< "Pairing timed out."
    elif (( "$status" < 200 || 300 <= "$status" )); then
        if (( 500 <= "$status" && "$status" < 600 )); then
            server_error_msg | die
        else
            die <<< "Unknown error. Status code: ${status}"
        fi
    else
        pair_success_msg
    fi
}

source "$(dirname "$0")/platform/$(uname | cut -d _ -f 1 | tr '[:upper:]' '[:lower:]').sh" 2>/dev/null # PLATFORM_FUNCTION_FILE

cmd_usage() {
cat <<EOF
Usage:
    $PROGRAM [ping]
        Send a notification to currently paired mobile devices.
    $PROGRAM pair
        Pair with a mobile device for the first time.
    $PROGRAM repair
        Change the currently paired mobile device.
    $PROGRAM help
        Show this text.
EOF
}

is_paired_serverside() {
    curl --silent -o /dev/null -w '%{http_code}' \
         -X GET \
         -F pc_token="$1" \
         -L "${YO_BASE_URL}/notification_bindings" 2>/dev/null
}

cmd_pair() {
    local yo_token
    yo_token="$(< "$YO_TOKEN_PATH")"
    local status
    status="$(is_paired_serverside "$yo_token")"
    log INFO <<< "notification_bindings: ${status}"
    if (( "$status" < 200 || 300 <= "$status" )); then
        # Outside of 2xx
        if [ "$status" -eq 404 ]; then
            # pc_token exists, but is unpaired server-side
            link_w_qr "$yo_token"
        elif (( 500 <= "$status" && "$status" < 600 )); then
            server_error_msg | die
        else
            die <<< "Unknown error. Status code: ${status}"
        fi
    else
        # Inside of 2xx
        already_paired_msg | die
    fi
}

cmd_repair() {
    repair_msg
    echo
    yo_token="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    log INFO <<< "Generated PC token: '${yo_token}'"
    log INFO <<< "Saving newly generated PC token to: '$YO_TOKEN_PATH'"
    echo "$yo_token" > "$YO_TOKEN_PATH"
    link_w_qr "$yo_token"
}

cmd_ping() {
    local yo_token
    yo_token="$(< "$YO_TOKEN_PATH")"
    local status
    status="$(is_paired_serverside "$yo_token")"
    log INFO <<< "notification_bindings: ${status}"
    if (( "$status" < 200 || 300 <= "$status" )); then
        # Outside of 2xx
        if [ "$status" -eq 404 ]; then
            not_initialized_msg | die
        elif (( 500 <= "$status" && "$status" < 600 )); then
            server_error_msg | die
        else
            die <<< "Unknown error. Status code: ${status}"
        fi
    else
        status="$(yo_repeatedly "$(< "$YO_TOKEN_PATH")" 500 600 5 alert)"
        if (( "$status" < 200 || 300 <= "$status" )); then
            if [ "$status" -eq 404 ]; then
                not_initialized_msg | die
            elif [ "$status" -eq 410 ]; then
                apns_gone_msg | die
            elif (( 500 <= "$status" && "$status" < 600 )); then
                server_error_msg | die
            else
                die <<< "Unknown error. Status code: ${status}"
            fi
        else
            notification_dispatched_msg
        fi
    fi
}

cmd_default() {
    if [ "$#" -eq 0 ]; then
        cmd_ping
    else
        cmd_usage
    fi
}

#
# END subcommand functions
#

PROGRAM="${0##*/}"

if [ ! -e "$YO_TOKEN_PATH" ]; then
    yo_token="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    log INFO <<< "Generated PC token: '${yo_token}'"
    brand_new_pc_msg
    log INFO <<< "Saving newly generated PC token to: '$YO_TOKEN_PATH'"
    echo "$yo_token" > "$YO_TOKEN_PATH"
fi
case "$1" in
    help|--help) shift;          cmd_usage "$@"   ;;
    pair) shift;                 cmd_pair "$@"    ;;
    repair) shift;                 cmd_repair "$@"    ;;
    ping) shift;                 cmd_ping "$@"    ;;
    *)                           cmd_default "$@" ;;
esac
exit 0

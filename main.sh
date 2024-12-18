#! /usr/bin/env bash

# set -xe

# bot_token set from ENV
base_url="https://api.telegram.org/bot$bot_token"


# args :: msg
function log {
    echo "[`date -u +"%Y-%m-%d %H:%M:%S"`]" >> .log
    echo "$1" >> .log
    echo ""   >> .log

    # log rotate, keep only last 10000 lines
    cat .log | tail --lines 10000 > _log
    mv _log .log
}


function fetch_updates {
    last_update=`cat ._last_update_id 2>/dev/null || echo 0`
    raw_response=`curl -X POST \
                       -d "offset=$last_update" \
                       -d "allowed_updates=[\"message\", \"message_reaction\", \"callback_query\", \"chat_member\"]" \
                       "$base_url/getUpdates" \
                  | jq`

    if [ $? -ne 0 ]; then
        log "Error fetch updates"
        log "Cleanup state..."

        mv ._response ._response_error
        rm ._response ._msg
        return
    fi

    echo $raw_response > ._response

    log "Receive response: `cat ._response | jq`"

    _last_update=`cat ._response | jq ".result[-1].update_id"`
    _last_update=$((_last_update+1))

    echo $_last_update > ._last_update_id

    log "New update id: $_last_update"

    i=0
    while [ true ]; do
        result_i=`cat ._response | jq ".result[$i]"`
        [ "$result_i" == "null" ] && break;

        log "Process message: $i"

        process_message "$result_i"
        i=$(($i+1))
    done
}


# args :: msg
function process_message {
    msg="$1"
    log "Process message: $msg"

    echo "$msg" > _msg
    
    cat _msg | grep -E "\"message_reaction\"" && handle_reactions "$msg"
    cat _msg | grep -E "\"message\""          && handle_text_msg  "$msg"

    rm _msg
}


# args :: msg
function handle_reactions {
    log "Handle reactions: $1"

       chat_id=`echo $1 | jq .message_reaction.chat.id`
    message_id=`echo $1 | jq .message_reaction.message_id`
         actor=`echo $1 | jq .message_reaction.user.username`
     reactions=`echo $1 | jq .message_reaction.new_reaction[].emoji`

    base_path=".messages/$chat_id/h${message_id:0:2}/$message_id"
    mkdir -p $base_path

    echo "$reactions" > "$base_path/$actor-reactions"
}


# args :: msg
function handle_text_msg {
    log "Handle text: $1"

       chat_id=`echo $1 | jq .message.chat.id`
    message_id=`echo $1 | jq .message.message_id`
       creator=`echo $1 | jq .message.from`
          text=`echo $1 | jq .message.text`

    base_path=".messages/$chat_id/h${message_id:0:2}/$message_id"
    mkdir -p $base_path

    echo "$creator" >> "$base_path/creator"
    echo "$text"    >> "$base_path/text"

    case `echo $text | xargs` in
        "/reactions" )
            log "Handle /reactions request"
            generate_report $chat_id $message_id
            ;;
        * ) ;;
    esac
}


# args :: chat_id, message_id
function generate_report() {
    log "Start report generating..."

    rm -rf .report

    for base_path in `find .messages -regex "\.messages/$1/*/*/.*-reactions" | cut -f1 -d"\"" | sort | uniq`; do
        creator=$(cat $base_path/creator)
        [ $? -ne 0 ] && continue

        creator_name=$(echo $creator | jq .username)

        mkdir -p .report/$creator_name
        cat $base_path/*-reactions >> .report/$creator_name/reactions
    done

    result=`python3 calculate_stats.py`

    curl -X POST \
         -d "chat_id=$1" \
         -d "reply_to_message_id=$2" \
         -d "text=$result" \
         "$base_url/sendMessage" \
      || log "Error send message"

    log "End report generating..."
}


while [ true ]; do
    fetch_updates
    sleep 5
done

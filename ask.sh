#!/bin/sh

check_command() {
	command -v "$1" > /dev/null 2>&1 \
		|| give_up "\033[1m${1}\033[0m not found."
}

get_topic_id() {
	head -n 1 "$1" \
	| jq -r .interaction.id
}

give_up() {
	printf "\n \033[1;31mERR\033[0m: ${1}\n\n" \
	&& exit 1
}

to_json() {
	printf "%s" "$1" | jq -Rs .
}

check_command curl
check_command jq

TRANSCRIPT_FILE=/tmp/transcript.json
PERSONA=${PERSONA:-'You respond exclusively in plaintext code snippets that can be executed (or compiled) as is. Never format your responses using markdown. If no language is specified, write code in POSIX-compliant sh (or PostgreSQL if dealing with SQL). Always use the most portable syntax. Otherwise, write the code in the language that the user mentions.'}
GEMINI_INTELLECT=${GEMINI_INTELLECT:-'low'}
GEMINI_MODEL=${GEMINI_MODEL:-'gemini-flash-lite-latest'}

INPUT_ITEMS='[]'

while [ $# -gt 0 ]; do
	case "$1" in
		--install)
			LOCAL_BIN_DIR=~/.local/bin
			INSTALL_PATH="${LOCAL_BIN_DIR}/ai"
			mkdir -p "$LOCAL_BIN_DIR"
			cp -iv "$0" "$INSTALL_PATH"
			chmod +x "$INSTALL_PATH"
			exit
			;;
		--uninstall)
			rm -iv "$INSTALL_PATH" "$TRANSCRIPT_FILE"
			exit
			;;
		--forget)
			rm -v "$TRANSCRIPT_FILE"
			exit
			;;
		--echo)
			head -n -1 "$TRANSCRIPT_FILE" \
				| jq -jr '.delta.text // empty'
			exit
			;;
		--dotenv)
			shift
			DOTENV_FILE="$1"
			shift
			test -s "$DOTENV_FILE" && {
				set -a
				. "$DOTENV_FILE"
				set +a
			} || give_up
			;;
		--model)
			shift
			GEMINI_MODEL="$1"
			shift
			;;
		--persona)
			shift
			PERSONA="$1"
			shift
			;;
		--intellect)
			shift
			GEMINI_INTELLECT="$1"
			shift
			;;
		--related | -r)
			PRESERVE_TOPIC=true
			shift
			;;
		--attach | -a)
			shift
			ATTACH_FILE="$1"
			shift
			test -f "$ATTACH_FILE" || give_up "Attached file not found: $ATTACH_FILE"
			MIME_TYPE=$(file -b --mime-type "$ATTACH_FILE" 2>/dev/null || echo "text/plain")
			case "$MIME_TYPE" in
				image/*)
					FILE_DATA=$(base64 < "$ATTACH_FILE" | tr -d '\n')
					INPUT_ITEMS=$(jq -cn \
						--argjson arr "$INPUT_ITEMS" \
						--arg data "$FILE_DATA" \
						--arg mime "$MIME_TYPE" \
						'$arr + [{"type": "image", "data": $data, "mime_type": $mime, "resolution": "low"}]')
					;;
				*)
					INPUT_ITEMS=$(jq -cn \
						--argjson arr "$INPUT_ITEMS" \
						--rawfile data "$ATTACH_FILE" \
						--arg mime "$MIME_TYPE" \
						'$arr + [{"type": "text", "text": $data}]')
					;;
			esac
			;;
		--modality | -m)
			shift
			MODALITY="$1"
			shift
			;;
		--)
			shift
			break
			;;
		-*)
			break
			;;
		*)
			break
			;;
	esac
done

RAW_USER_PROMPT="$*"
test ! -t 0 && RAW_USER_PROMPT="${RAW_USER_PROMPT}\n\n$(cat)"

# Append text prompt if present
test -n "$RAW_USER_PROMPT" && INPUT_ITEMS=$(jq -cn \
	--argjson arr "$INPUT_ITEMS" \
	--arg prompt "$RAW_USER_PROMPT" \
	'$arr + [{"type": "text", "text": $prompt}]')

test "$(echo "$INPUT_ITEMS" | jq 'length // 0')" -eq 0 \
	&& give_up "You didn't ask anything or attach any files."

test -z "$GEMINI_API_KEY" \
	&& give_up "\033[1mGEMINI_API_KEY\033[0m not set."

TOPIC_ID=""
test -f "$TRANSCRIPT_FILE" \
	&& TOPIC_ID="$(get_topic_id "$TRANSCRIPT_FILE")"
GEMINI_URL='https://generativelanguage.googleapis.com/v1beta/interactions?alt=sse'
GEMINI_JSON=$(jq -cn \
	--arg intellect "${GEMINI_INTELLECT:-low}" \
	--arg modality "${GEMINI_MODALITY:-text}" \
	--arg model "$GEMINI_MODEL" \
	--arg persona "$PERSONA" \
	--arg prev_id "$TOPIC_ID" \
	--argjson input "$INPUT_ITEMS" \
	--argjson has_prev "${PRESERVE_TOPIC:-false}" \
	'{
		generation_config: {
			thinking_level: $intellect
		},
		input: $input,
		model: $model,
		response_modalities: [
			$modality
		],
		stream: true,
		system_instruction: $persona,
		tools: [
			{ type: "google_search" },
			{ type: "url_context" }
		]
	} + if $has_prev and $prev_id != "" then {previous_interaction_id: $prev_id} else {} end'
)

curl -sSX POST "$GEMINI_URL" \
	-H "x-goog-api-key: ${GEMINI_API_KEY}" \
	-H 'Content-Type: application/json' \
	-d "$GEMINI_JSON" \
	--no-buffer \
| grep --line-buffered '^data: ' \
| sed -u 's/^data: // ; /^$/d' \
| tee "$TRANSCRIPT_FILE" \
| jq --unbuffered -ej \
	'(.delta.text // .error.message) // empty' \
	2>/dev/null

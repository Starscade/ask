#!/bin/sh

test $(basename "$0") = 'install.sh' && {
	INSTALL_DIR=~/.local/bin
	test -n "$1" && test -d "$1" \
		&& INSTALL_DIR="$1"
	INSTALL_PATH="${INSTALL_DIR}/ask"
	mkdir -pv "$INSTALL_DIR" \
	&& cp -iv "$0" "$INSTALL_PATH" \
	&& chmod -v 0755 "$INSTALL_PATH"
	exit
}

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

check_command curl
check_command jq

TRANSCRIPT_FILE=/tmp/transcript.json
PERSONA=${PERSONA:-'You respond exclusively in plaintext code snippets that can be executed (or compiled) as is. Never format your responses using markdown. If no language is specified, write code in POSIX-compliant sh (or PostgreSQL if dealing with SQL). Always use the most portable syntax. Otherwise, write the code in the language that the user mentions.'}
GEMINI_INTELLECT=${GEMINI_INTELLECT:-'low'}
GEMINI_MODEL=${GEMINI_MODEL:-'gemini-flash-lite-latest'}

INPUT_ITEMS='[]'

while [ $# -gt 0 ]; do
	case "$1" in
		--help | -h)
			printf "\n  \033[1mUSAGE\033[0m: ask [flags] [prompt]\n"
			printf "  \033[1mFLAGS\033[0m:\n\n"
			printf "%s\n" \
			'    --install [DIR]    Install to DIR (default ~/.local/bin)' \
			'    --uninstall        Remove installed script and transcript' \
			'    --forget           Clear chat history' \
			'    --echo             Print the last AI response' \
			'    --env FILE         Load environment variables from FILE' \
			'    --persona TEXT     Set system instruction persona' \
			'    -r, --related      Preserve topic history / context' \
			'    -a, --attach FILE  Attach text or image file' \
			'    -m, --modality     Set response modality' \
			'    --help             Display this help message'
			echo
			exit
			;;
		--version)
			VERSION='v0.1.0 (main)'
			echo "$VERSION"
			exit
			;;
		--uninstall)
			rm -iv "$0" "$TRANSCRIPT_FILE"
			exit
			;;
		--update)
			echo Installing...
			curl -fLsSo "$(command -v "$0")" \
				'https://ask.angus.sh/install.sh' \
				&& echo "$($(command -v "$0") --version)"
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
		--env)
			shift
			DOTENV_FILE="$1"
			shift
			test -s "$DOTENV_FILE" && {
				set -a
				. "$DOTENV_FILE"
				set +a
			} || give_up
			;;
		--modality | -m)
			shift
			MODALITY="$1"
			shift
			;;
		--persona)
			shift
			PERSONA="$1"
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
			test -s "$ATTACH_FILE" || give_up "Attached file not found: $ATTACH_FILE"
			MIME_TYPE=$(file -b --mime-type "$ATTACH_FILE" 2>/dev/null || echo "text/plain")
			case "$MIME_TYPE" in
				image/*)
					FILE_DATA=$(base64 < "$ATTACH_FILE" | tr -d '\n')
					TMP_IMG=$(mktemp)
					printf '%s' "$FILE_DATA" > "$TMP_IMG"
					INPUT_ITEMS=$(jq -cn \
						--argjson arr "$INPUT_ITEMS" \
						--rawfile data "$TMP_IMG" \
						--arg mime "$MIME_TYPE" \
						'$arr + [{
							"type": "image",
							"data": $data,
							"mime_type": $mime
						}]'
					)
					rm "$TMP_IMG"
					;;
				*)
					FILE_DATA="$(jq -Rrs . "$ATTACH_FILE")"
					INPUT_ITEMS=$(jq -cn \
						--argjson arr "$INPUT_ITEMS" \
						--arg data "$FILE_DATA" \
						'$arr + [{
							"type": "text",
							"text": $data
						}]'
					)
					;;
			esac
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

test ! -t 0 && \
INPUT_ITEMS=$(jq -cn \
	--argjson arr "$INPUT_ITEMS" \
	--arg stdin "$(cat)" \
	'$arr + [{
		"type": "text",
		"text": $stdin
	}]'
)

test -n "$RAW_USER_PROMPT" && \
INPUT_ITEMS=$(jq -cn \
	--argjson arr "$INPUT_ITEMS" \
	--arg prompt "$RAW_USER_PROMPT" \
	'$arr + [{
		"type": "text",
		"text": $prompt
	}]'
) || exit 1

test "$(printf '%s' "$INPUT_ITEMS" | cat -v | jq 'length // 0')" -eq 0 \
	&& give_up "You didn't ask anything or attach any files."

test -z "$GEMINI_API_KEY" \
	&& give_up "\033[1mGEMINI_API_KEY\033[0m not set."

TOPIC_ID=""
test -s "$TRANSCRIPT_FILE" \
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

curl -sS "$GEMINI_URL" \
	-H 'Content-Type: application/json' \
	-H "x-goog-api-key: ${GEMINI_API_KEY}" \
	-d "$GEMINI_JSON" \
	--no-buffer \
| grep --line-buffered '^data: ' \
| sed -u 's/^data: // ; /^$/d' \
| tee "$TRANSCRIPT_FILE" \
| jq --unbuffered -ej \
	'(.delta.text // .error.message) // empty' \
	2>/dev/null

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

RAW_USER_PROMPT="$*"
test ! -t 0 && RAW_USER_PROMPT="${RAW_USER_PROMPT}\n\n$(cat)"

test -z "$RAW_USER_PROMPT" \
	&& give_up "You didn't ask anything."

test -s .env && {
	set -a
	. .env
	set +a
}

test -z "$GEMINI_API_KEY" \
	&& give_up "\033[1mGEMINI_API_KEY\033[0m not set."

TOPIC_ID="$(get_topic_id "$TRANSCRIPT_FILE")"
GEMINI_MODEL=${GEMINI_MODEL:-'gemini-flash-lite-latest'}
GEMINI_PERSONA=${GEMINI_PERSONA:-'You respond exclusively in plaintext code snippets that can be executed (or compiled) as is. Never format your responses using markdown. If no language is specified, write code in POSIX-complient sh (or PostgreSQL if dealing with SQL). Always use the most portable syntax. Otherwise, write the code in the language that the user mentions.'}
GEMINI_PERSONA_JSON=$(to_json "$GEMINI_PERSONA")
GEMINI_URL='https://generativelanguage.googleapis.com/v1beta/interactions?alt=sse'
PREVIOUS_INTERACTION=
USER_PROMPT_JSON="$(to_json "$RAW_USER_PROMPT")"

GEMINI_JSON=$(jq -cn \
	--arg modality "${GEMINI_MODALITY:-text}" \
	--arg model "$GEMINI_MODEL" \
	--arg persona "$GEMINI_PERSONA" \
	--arg prev_id "$TOPIC_ID" \
	--arg prompt "$RAW_USER_PROMPT" \
	--argjson has_prev "${GAIA_RELATED:-false}" \
	'{
		generation_config: {
			thinking_level: "low"
		},
		input: [
			{
				text: $prompt,
				type: "text"
			}
		],
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

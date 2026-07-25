#!/bin/sh

check_command() {
	command -v "$1" > /dev/null 2>&1 \
		|| give_up "\033[1m${1}\033[0m not found."
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

test -n "$1" || give_up "You didn't ask anything."

if test -s .env; then
	set -a
	. .env
	set +a
fi

test ! -z "$GEMINI_API_KEY" \
	|| give_up "\033[1mGEMINI_API_KEY\033[0m not set."

GEMINI_MODEL=${GEMINI_MODEL:-'gemini-flash-lite-latest'}
GEMINI_PERSONA=${GEMINI_PERSONA:-'You respond exclusively in plaintext code snippets that can be executed (or compiled) as is. Never format your responses using markdown. If no language is specified, write code in POSIX-complient sh (or PostgreSQL if dealing with SQL). Always use the most portable syntax. Otherwise, write the code in the language that the user mentions.'}
GEMINI_PERSONA_JSON=$(to_json "$GEMINI_PERSONA")
GEMINI_URL='https://generativelanguage.googleapis.com/v1beta/interactions?alt=sse'
USER_PROMPT_JSON="$(to_json "$@")"

RAW_OBJ='{
	"generation_config": {
		"thinking_level": "low"
	},
	"input": [
		{
			"text": '"$USER_PROMPT_JSON"',
			"type": "text"
		}
	],
	"model": "'"$GEMINI_MODEL"'",
	"stream": true,
	"system_instruction": '"$GEMINI_PERSONA_JSON"'
}'

GEMINI_JSON="$(echo "$RAW_OBJ" | jq -c .)"

curl -sSX POST "$GEMINI_URL" \
	-H "x-goog-api-key: ${GEMINI_API_KEY}" \
	-H 'Content-Type: application/json' \
	-d "$GEMINI_JSON" \
	--no-buffer \
| grep --line-buffered '^data: ' \
| sed -u 's/^data: // ; /^$/d' \
| jq --unbuffered -ej \
	'(.delta.text // .error.message) // empty' \
	2>/dev/null

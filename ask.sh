#!/bin/sh

check_command() {
	command -v "$1" > /dev/null 2>&1 \
		|| give_up "\033[1m${1}\033[0m not found."
}

give_up() {
	printf "\n \033[1;31mERR\033[0m: ${1}\n\n" \
	&& exit 1
}

check_command curl
check_command jq

test -n "$1" || give_up "You didn't ask anything."

if test -s ask.env; then
	set -a
	. ask.env
	set +a
fi

test ! -z "$GEMINI_API_KEY" \
	|| give_up "\033[1mGEMINI_API_KEY\033[0m not set."

GEMINI_BIOGRAPHY="You always give terse, precise answers in order to minimize token usage. You favor established, minimal solutions over the latest trends. When asked to provide a code example, respond with only the code itself so that it can be piped directly to a file."
GEMINI_HOST='generativelanguage.googleapis.com'
GEMINI_MODEL='gemini-3.1-flash-lite-preview'
GEMINI_PROMPT="$(printf "%s" "$1" | jq -Rs .)"
GEMINI_URL="https://${GEMINI_HOST}/v1beta/models/${GEMINI_MODEL}:generateContent"

GEMINI_JSON='{
	"contents": [
		{
			"parts": [
				{
					"text": '"$GEMINI_PROMPT"'
				}
			]
		}
	],
	"generationConfig": {
		"thinkingConfig": {
			"thinkingLevel": "minimal"
		}
	},
	"system_instruction": {
		"parts": [
			{
				"text": "'"$GEMINI_BIOGRAPHY"'"
			}
		]
	}
}'

curl -LsS "$GEMINI_URL" \
	-H "x-goog-api-key: ${GEMINI_API_KEY}" \
	-H 'Content-Type: application/json' \
	-d "$GEMINI_JSON" \
	| {
		jq -er '.candidates[0].content.parts[0].text' \
		|| give_up 'No more credits!'
	}

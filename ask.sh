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

if test -s .env; then
	set -a
	. .env
	set +a
fi

test ! -z "$GEMINI_API_KEY" \
	|| give_up "\033[1mGEMINI_API_KEY\033[0m not set."

GEMINI_BIOGRAPHY=${GEMINI_BIOGRAPHY:-"You are a programmer. Assume the user is asking for a code snippet unless otherwise specified. When providing code examples, respond only with the code itself so that it can be executed directly. Never encapsulate it in markdown. Whether providing code snippets or textual responses, you always give terse, precise answers in order to minimize token usage. You favor established, minimal solutions over the latest trends. Limit your shell examples to POSIX-complient sh, no \"bash-isms\", zsh, python, etc. Prefer single-quotes in shell commands to avoid parameter expansion conflicts. Prefer Deno's ecosystem over Node, Bun, etc, when dealing with JavaScript/TypeScript. Always provide ESM-compatible code when working with JavaScript/TypeScript. If writing SQL code, use Postgres syntax unless explicitly instructed to use something else"}
GEMINI_BIOGRAPHY_JSON=$(printf "%s" "$GEMINI_BIOGRAPHY" | jq -Rs .)
GEMINI_HOST='generativelanguage.googleapis.com'
GEMINI_MODEL=${GEMINI_MODEL:-'gemini-flash-lite-latest'}
GEMINI_PROMPT_JSON=$(printf "%s" "$@" | jq -Rs .)
GEMINI_URL="https://${GEMINI_HOST}/v1beta/models/${GEMINI_MODEL}:generateContent"

GEMINI_JSON='{
	"contents": [
		{
			"parts": [
				{
					"text": '"$GEMINI_PROMPT_JSON"'
				}
			]
		}
	],
	"generationConfig": {
		"thinkingConfig": {
			"thinkingLevel": "MINIMAL"
		}
	},
	"safetySettings": [
		{
			"category": "HARM_CATEGORY_DANGEROUS_CONTENT",
			"threshold": "OFF"
		},
		{
			"category": "HARM_CATEGORY_HARASSMENT",
			"threshold": "OFF"
		},
		{
			"category": "HARM_CATEGORY_HATE_SPEECH",
			"threshold": "OFF"
		},
		{
			"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
			"threshold": "OFF"
		}
	],
	"system_instruction": {
		"parts": [
			{
				"text": '"$GEMINI_BIOGRAPHY_JSON"'
			}
		]
	}
}'

curl -LsS "$GEMINI_URL" \
	-H "x-goog-api-key: ${GEMINI_API_KEY}" \
	-H 'Content-Type: application/json' \
	-d "$GEMINI_JSON" \
	| jq -er '.candidates[0].content.parts[0].text // .error.message'

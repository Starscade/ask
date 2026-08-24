# Ask

A proof-of-concept Gemini chat client written entirely in sh.
[[download](https://ask.angus.sh/install.sh)]

---
### USAGE

###### INSTALL
```sh
curl -fLsSo ~/.local/bin/ask ask.angus.sh/install.sh
```

###### FIRST RUN
```sh
export GEMINI_API_KEY= # Your key ...
ask 'Ahoy!'
```

###### PRESERVE CONTEXT
```sh
ask "I like root beer."
ask --related "Do I like root beer?"
```

###### ATTACH A FILE
```sh
ask --attach README.md "Summarize this."
```

###### UNIX PIPES
```sh
cat *.js | ask "Consolidate these into a single TypeScript module." > mod.ts
```

###### PRINT LAST RESPONSE
```sh
ask --echo
```

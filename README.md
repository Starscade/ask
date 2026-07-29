# Ask

A POSIX-compliant shell script for Google Gemini.

---
### USAGE

```sh
export GEMINI_API_KEY= # Your key ...
ask.sh 'Ahoy!'
```

###### INSTALL
```sh
curl -fLsS ask.angus.sh/ask.sh > ~/.local/bin/ask
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

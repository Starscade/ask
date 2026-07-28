# Ask

A POSIX-compliant shell script for Google Gemini.

---
#### USAGE

###### BASIC
```sh
export GEMINI_API_KEY=<your_key>
ask.sh Hello, there.
```

###### INSTALL
```sh
ask.sh --install
ask Hello, there.
```

###### PRESERVE CONTEXT
```sh
ask I like root beer.
ask --related Do I like root beer?
```

###### PRINT LAST RESPONSE
```sh
ask --echo
```

#!/usr/bin/env zsh
# NAME: fun
# DESC: Silly but harmless toys from the old .testrc: jokes, quotes, moody echo, random emoji, wtf counter, random man page
# TAGS: FUN
# DEP: curl (optional), jq (optional), fortune (optional), cowsay (optional)
# DEFAULT: off
# VER: 1.0
# DEV: SilverX
# EXAMPLE: joke
# EXAMPLE: mecho "build passed"
# EXAMPLE: remoji
# | The standalone fun bits of `ZRC/testrc`.
# |
# | | Command | What it does |
# | |---|---|
# | | `joke` | random dad joke (icanhazdadjoke.com) |
# | | `inspire` | random quote (zenquotes.io) |
# | | `wisdom` | `fortune \| cowsay` |
# | | `mecho TEXT` | echo in a random mood |
# | | `remoji` | random emoji, also copied to the clipboard when the `clipboard` addon is on |
# | | `wtf` | increments and shows a WTF counter |
# | | `bored` | open the man page of a random command |
# |
# | Deliberately **not** ported (they override real commands): the joke versions
# | of `cd`, `rm`, `mv`, `mkdir`, `touch`, `ping`, `exit`, `git`, `whoami`, `ls`,
# | the `please` alias and the `precmd` that hit the network after every failed command.

# Random dad joke from icanhazdadjoke.com
alias joke="curl -fsS -H 'Accept: application/json' https://icanhazdadjoke.com/ | jq -r .joke"
# Random inspirational quote from zenquotes.io
alias inspire="curl -fsS https://zenquotes.io/api/random | jq -r '.[0].q + \" - \" + .[0].a'"

typeset -gi WTF_COUNT=${WTF_COUNT:-0}

# wtf — increment and show the WTF counter
wtf() { (( WTF_COUNT++ )); print "WTF count: $WTF_COUNT"; }

# wisdom — a fortune, said by a cow
wisdom() {
  if (( $+commands[fortune] && $+commands[cowsay] )); then
    fortune | cowsay
  else
    msh::warn "I can't predict the future without fortune and cowsay installed..."
  fi
}

# mecho TEXT — echo TEXT in a random mood
mecho() {
  local -a moods=(
    "✨ $* ✨" "Ugh... $*" "Oh, *really*? $*..." "WOW!! $*!! AMAZING!!"
    "*yawn* $*..." "Hm. $*. Sometimes I wonder..." "Behold: $* !"
    "$*. But is that truly what we mean, in the grand scheme of things?"
  )
  print -r -- "${moods[RANDOM % $#moods + 1]}"
}

# remoji — print a random emoji (and copy it when `copy` exists)
remoji() {
  local -a e=(😀 😁 😂 🤣 😃 😄 😅 😆 😉 😊 😋 😎 😍 😘 🙂 🤗 🤩 🤔 🤨 🧐 🙄 😏 😒 😞 😔
    😟 😕 🙁 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😶 😐 😑 😴 😪 😮 😯 😲 🥱 🤤 😇 🤠
    🤑 😈 👿 👹 👺 🤡 💀 👻 👽 👾 🤖 😺 😸 😹 😻 😼 😽 🙀 😿 😾 🙈 🙉 🙊 🐵 🐒 🦍 🦧 🐶 🐕
    🐩 🐺 🦊 🐱 🐈 🐯 🐅 🐆 🐴 🐎 🦄 🦓 🦌 🦬 🐮 🐂 🐃 🐄 🐷 🐖 🐗 🐽 🐸 🐊 🐢 🦎 🐍 🐲 🐉 🦕
    🦖 🐳 🐋 🐬 🐟 🐠 🐡 🦈 🐙 🐚 🦀 🦞 🦐 🦑 🦪 🐌 🦋 🐛 🐜 🐝 🐞 🦗 🦂 🐦 🐧 🐥 🐤 🐣 🦆 🦅
    🦉 🦇 🦝 🪱 🪰 🦟 💪 👈 👉 👆 👇 👍 👎 👊 🤛 🤜 👏 🙌 👐 🤲 🤝 🙏 💅 🤳 💋 👄 🦷 👅 👂 👃)
  typeset -g EMOTE=${e[RANDOM % $#e + 1]}
  print -r -- "$EMOTE"
  (( $+functions[copy] )) && print -rn -- "$EMOTE" | copy 2>/dev/null
  return 0
}

# bored — open the man page of a random command
bored() {
  local page
  page=$(man -k . 2>/dev/null | awk '{print $1}' | shuf -n 1)
  [[ -n $page ]] && man "$page" || msh::warn "No man's system!"
}

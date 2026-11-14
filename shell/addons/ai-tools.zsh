#!/usr/bin/env zsh
# NAME: ai-tools
# DESC: LLM helpers: sgpt with Gemini key rotation, gemini-ping key health check, ejaj (prompt → bash via ollama), jimmy (free chat API)
# TAGS: AI
# DEP: curl, jq, sgpt (optional), ollama (optional)
# DEFAULT: off
# VER: 2.0
# DEV: SilverX
# EXAMPLE: sgpt "explain this regex: ^a+$"
# EXAMPLE: gemini-ping
# EXAMPLE: ejaj            (type a request, the command lands in ./out.sh)
# EXAMPLE: jimmy -s "be terse" "what is a monad"
# | Merged from `shellgpt.zsh`, `llm.zsh`, `ejaj.zsh` and `jimmy.zsh`.
# |
# | **Keys are never stored here.** Put them in the secrets store
# | (`msh secret add GEMINI_API_KEY`, `GEMINI_API_1` … `GEMINI_API_20`) or in
# | your external secrets file; this addon only reads them at call time.
# |
# | | Command | What it does |
# | |---|---|
# | | `sgpt ARGS...` | real `sgpt`, with a random key from `GEMINI_API_KEY` / `GEMINI_API_1..20` |
# | | `gemini-ping` | probe every key against a list of models (`GEMINI_PING_MODELS`) |
# | | `ejaj [-o FILE]` | read a request, ask ollama (`EJAJ_MODEL`) for raw bash, write it to FILE (default out.sh) — **review before running** |
# | | `jimmy [-r] [-s SYSTEM] PROMPT` | ask chatjimmy.ai (free, third-party, llama3.1-8B) |
# | | `antigravity` | alias for `agy` (Google Antigravity CLI) |
# |
# | Ollama model shortcuts exported as tweakables: `q38u`, `q38`, `q38s`, `oss`.

: ${EJAJ_MODEL:=q3.8-shell:latest}
: ${q38u:=srchmnmichael/Qwen3.8-Uncensored:q4_K_M} ${q38:=qwen3.8:27b} ${q38s:=q3.8-shell:latest} ${oss:=gpt-oss:20b}
export q38u q38 q38s oss
(( ${+GEMINI_PING_MODELS} )) || typeset -ga GEMINI_PING_MODELS=(
  gemini-3.6-flash gemini-3.5-flash gemini-3.5-flash-lite gemini-3.1-flash-lite
  gemini-3-flash-preview gemini-2.5-flash gemini-2.5-flash-lite gemini-2.5-pro
)

# ai::gemini_keys — print "NAME" of every set Gemini key variable, one per line (internal)
ai::gemini_keys() {
  local v
  [[ -n ${GEMINI_API_KEY-} ]] && print GEMINI_API_KEY
  for v in GEMINI_API_{1..20}; do [[ -n ${(P)v-} ]] && print $v; done
  return 0
}

# sgpt ARGS... — run shell-gpt with a randomly chosen Gemini key
sgpt() {
  msh::need sgpt || return
  local -a names=( ${(f)"$(ai::gemini_keys)"} )
  (( $#names )) || { msh::err "no GEMINI_API_KEY or GEMINI_API_1..20 set (msh secret add GEMINI_API_KEY)"; return 1; }
  local pick=${names[RANDOM % $#names + 1]}
  GEMINI_API_KEY=${(P)pick} OPENAI_API_KEY=placeholder command sgpt "$@"
}

# gemini-ping — check every Gemini key against every model in GEMINI_PING_MODELS
gemini-ping() {
  msh::need curl jq || return
  local -a names=( ${(f)"$(ai::gemini_keys)"} )
  (( $#names )) || { msh::err "no GEMINI_API_* keys set"; return 1; }
  local O=$'\e[38;5;208m' C=$'\e[0;36m' R=$'\e[0;31m' G=$'\e[0;32m' Y=$'\e[1;33m' B=$'\e[1m' N=$'\e[0m'
  [[ -t 1 && -z ${NO_COLOR-} ]] || O= C= R= G= Y= B= N=
  print -r -- "${Y}Gemini key health check${N}"
  print -r -- "Quotas are per PROJECT; real remaining numbers only in AI Studio"
  print
  local name model resp code body ok tokens retry
  for name in $names; do
    print -r -- "${O}${B}# $name${N}"
    ok=0
    for model in $GEMINI_PING_MODELS; do
      # The key is sent as a header read from a pipe: never in the URL or in ps output.
      resp=$(curl -s -w '\n%{http_code}' -X POST \
        "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent" \
        -H @<(print -r -- "x-goog-api-key: ${(P)name}") -H 'Content-Type: application/json' \
        -d '{"contents":[{"parts":[{"text":"."}]}],"generationConfig":{"maxOutputTokens":1}}' 2>/dev/null)
      code=${resp##*$'\n'} body=${resp%$'\n'*}
      case $code in
        200) tokens=$(jq -r '.usageMetadata.totalTokenCount // 1' <<<"$body" 2>/dev/null)
             print -r -- "  - ${C}$model${N}  [${R}$tokens${N}/${G}?${N}]  ${G}OK${N}"; ok=1 ;;
        404) print -r -- "  - ${C}$model${N}  ${Y}not available${N}" ;;
        429) if [[ $body == *'limit: 0'* ]]; then
               print -r -- "  - ${C}$model${N}  ${R}limit: 0${N}"
             else
               retry=$(jq -r '.error.details[]? | select(."@type" | contains("RetryInfo")) | .retryDelay // empty' <<<"$body" 2>/dev/null | head -1)
               print -r -- "  - ${C}$model${N}  ${R}429${N}${retry:+ (retry $retry)}"
             fi ;;
        *)   print -r -- "  - ${C}$model${N}  HTTP $code" ;;
      esac
    done
    (( ok )) || print -r -- "  ${R}No working model for this key${N}"
    print
  done
  print -r -- "${Y}Note:${N} [used/?] = tokens used by this probe / remaining (not exposed by the API)"
  print "Real quota → https://aistudio.google.com → Rate limits"
}

# ejaj [-o FILE] — ask ollama for a raw bash command and write it to FILE (default out.sh)
ejaj() {
  msh::need ollama || return
  local out=out.sh input
  [[ ${1-} == -o ]] && { out=${2:?ejaj -o FILE}; shift 2; }
  read -r "input?What should the command do? "
  [[ -n $input ]] || return 1
  ollama run "$EJAJ_MODEL" "$input {{ REPLY WITH RAW BASH COMMANDS, NO TALKING, NO MARKDOWN, NO CODEBLOCKS, ONLY RAW COMMAND }}" \
    --think=false --hidethinking >| "$out" || return
  msh::ok "written to $out — review it before running:"
  command cat -- "$out"
}

# jimmy [-r] [-s SYSTEM] PROMPT — ask the free chatjimmy.ai model (third-party service)
jimmy() {
  msh::need curl jq || return
  local raw=0 system=${SYSTEM-}
  while (( $# )); do
    case $1 in
      -r|--raw)    raw=1; shift ;;
      -s|--system) system=$2; shift 2 ;;
      *) break ;;
    esac
  done
  local prompt="$*"
  [[ -n $prompt ]] || { print -u2 'usage: jimmy [-r|--raw] [-s|--system "system prompt"] "prompt"'; return 2; }
  local body
  body=$(jq -n --arg sys "$system" --arg usr "$prompt" '{
    messages: ((if $sys != "" then [{role:"user", content:$sys}] else [] end) + [{role:"user", content:$usr}]),
    chatOptions: ({selectedModel:"llama3.1-8B", topK:8} + (if $sys != "" then {systemPrompt:$sys} else {} end)),
    attachment: null }')
  local resp
  resp=$(curl -s 'https://chatjimmy.ai/api/chat' -H 'content-type: application/json' \
    -H 'origin: https://chatjimmy.ai' -H 'referer: https://chatjimmy.ai/' --data-raw "$body") || return
  local answer=${resp%%'<|stats|>'*}
  answer=${answer%$'\n'}
  if (( raw )); then print -r -- "$answer"; return; fi
  [[ -n $system ]] && { print -P "%F{cyan}[System]:%f"; print -r -- "$system"; print; }
  print -P "%F{yellow}[User]:%f"; print -r -- "$prompt"; print
  print -P "%F{green}[Jimmy]:%f"; print -r -- "$answer"
}

# Google Antigravity CLI
alias antigravity='agy'

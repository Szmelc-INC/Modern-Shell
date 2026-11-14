#!/usr/bin/env zsh
# NAME: gpu-env
# DESC: AMD ROCm / HIP environment and the Ollama models directory on a second disk
# TAGS: AI, SYSTEM
# DEP: rocminfo (optional), ollama (optional)
# DEFAULT: off
# VER: 2.0
# DEV: SilverX
# EXAMPLE: gpu-env        (show what is set)
# | Merged from `GPU.zsh` and `ollama.zsh`. Machine-specific, hence off by default.
# |
# | | Variable | Default | Meaning |
# | |---|---|---|
# | | `ROCM_PATH` | `/opt/rocm` | ROCm install prefix (exported only when it exists) |
# | | `HIP_VISIBLE_DEVICES` | `0` | which GPU HIP may use |
# | | `HSA_OVERRIDE_GFX_VERSION` | unset | set it in msh.conf if your card needs the override (e.g. `12.0.0`) |
# | | `OLLAMA_MODELS` | `/run/media/$USER/data2/OLLAMA/models` | exported only when the directory exists |
# |
# | Fixed while porting: `OLLAMA_MODELS` was set but never exported, so the
# | ollama server never saw it; the path no longer contains a hard-coded user name.

: ${ROCM_PATH:=/opt/rocm}
: ${HIP_VISIBLE_DEVICES:=0}
: ${OLLAMA_MODELS:=/run/media/$USER/data2/OLLAMA/models}
[[ -d $ROCM_PATH ]] && export ROCM_PATH
export HIP_VISIBLE_DEVICES
[[ -n ${HSA_OVERRIDE_GFX_VERSION-} ]] && export HSA_OVERRIDE_GFX_VERSION
[[ -d $OLLAMA_MODELS ]] && export OLLAMA_MODELS

# gpu-env — show the GPU / Ollama variables and whether they are exported
gpu-env() {
  local v
  for v in ROCM_PATH HIP_VISIBLE_DEVICES HSA_OVERRIDE_GFX_VERSION OLLAMA_MODELS; do
    if [[ ${(tP)v} == *export* ]]; then
      printf '%-26s %s\n' $v "${(P)v}"
    else
      printf '%-26s %s\n' $v "${(P)v-<unset>} (not exported)"
    fi
  done
}

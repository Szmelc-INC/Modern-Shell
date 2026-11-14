#!/usr/bin/env zsh
# NAME: archives
# DESC: Extract any archive with one command, pack directories into 7z/zip/rar (optionally encrypted)
# TAGS: FILES
# DEP: tar, unzip (optional), 7z (optional), unrar (optional), zip (optional), rar (optional), zstd (optional)
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: extract foo.tar.gz bar.zip
# EXAMPLE: extract -d out/ backup.7z
# EXAMPLE: archivize                 (full interactive wizard)
# EXAMPLE: archivize -f zip -p ~/Projects/site
# | Merged from ZRC `extract-archives`, the `.zshrc` `extract` and `archivize.zsh`.
# |
# | | Command | What it does |
# | |---|---|
# | | `extract <file>...` | unpack each archive (tar.*, zip, 7z, rar, gz, bz2, xz, zst, Z, deb, rpm) |
# | | `extract -d DIR <file>...` | unpack into DIR (created when missing) |
# | | `extract -l <file>` | list the archive contents instead of extracting |
# | | `archivize [-f 7z\|zip\|rar] [-p] [-H] [DIR]` | pack DIR next to itself as `DIR.<fmt>` |
# | | `archivize` | wizard: asks for path, format, password, file-name encryption |
# |
# | `archivize -p` prompts for the password (hidden input). `--password STRING`
# | still works but is visible in `ps` and in your history, so prefer `-p`.
# | Encrypted file *names* (`-H`) are only available for 7z and rar.
# | Single-file formats (`.gz`, `.bz2`, `.xz`, `.zst`, `.Z`) keep the original and
# | write the result into the current directory (or `-d DIR`).

# extract [-d DIR] [-l] <archive>... — unpack (or list) archives of any common format
extract() {
  emulate -L zsh
  local dest="" list=0 f rc=0
  while (( $# )); do
    case $1 in
      -d|--dir)  dest=$2; shift 2 ;;
      -l|--list) list=1; shift ;;
      -h|--help) print "usage: extract [-d DIR] [-l] <archive>..."; return 0 ;;
      --) shift; break ;;
      -*) msh::err "extract: unknown option $1"; return 2 ;;
      *) break ;;
    esac
  done
  (( $# )) || { print -u2 "usage: extract [-d DIR] [-l] <archive>..."; return 2; }
  for f in "$@"; do
    if [[ ! -f $f ]]; then
      msh::err "extract: '$f' is not a file"; rc=1; continue
    fi
    f=${f:A}
    if (( list )); then
      case ${f:l} in
        *.tar|*.tar.*|*.tgz|*.tbz2|*.tbz|*.txz|*.tzst) tar tvf "$f" ;;
        *.zip|*.jar|*.apk|*.whl) unzip -l "$f" ;;
        *.rar) unrar l "$f" ;;
        *.7z|*.iso) 7z l "$f" ;;
        *) msh::warn "extract: cannot list '$f'"; rc=1 ;;
      esac
      continue
    fi
    (
      if [[ -n $dest ]]; then command mkdir -p -- "$dest" && cd -- "$dest" || exit 1; fi
      case ${f:l} in
        *.tar.bz2|*.tbz2|*.tbz)  tar xvjf "$f" ;;
        *.tar.gz|*.tgz)          tar xvzf "$f" ;;
        *.tar.xz|*.txz)          tar xvJf "$f" ;;
        *.tar.zst|*.tzst)        tar --zstd -xvf "$f" ;;
        *.tar)                   tar xvf "$f" ;;
        # Single-file formats decompress into the current (or -d) directory, original kept.
        *.bz2)                   bunzip2 -c "$f" > "${${f:t}%.*}" ;;
        *.gz)                    gunzip -c "$f" > "${${f:t}%.*}" ;;
        *.xz)                    unxz -c "$f" > "${${f:t}%.*}" ;;
        *.zst)                   unzstd -c "$f" > "${${f:t}%.*}" ;;
        *.lzma)                  unlzma -c "$f" > "${${f:t}%.*}" ;;
        *.zip|*.jar|*.apk|*.whl) unzip "$f" ;;
        *.rar)                   unrar x "$f" ;;
        *.7z|*.iso)              7z x "$f" ;;
        *.z)                     uncompress -c "$f" > "${${f:t}%.*}" ;;
        *.deb)                   ar x "$f" ;;
        *.rpm)                   rpm2cpio "$f" | cpio -idmv ;;
        *) print -u2 "extract: unknown archive type: $f"; exit 1 ;;
      esac
    ) || rc=1
  done
  return rc
}

# archivize [-f 7z|zip|rar] [-p] [-H] [DIR] — pack a directory into an archive next to it
archivize() {
  emulate -L zsh
  setopt extended_glob
  local format=7z password="" target_dir="" visible=yes ask_pass=0 wizard=0
  (( $# )) || wizard=1
  while (( $# )); do
    case $1 in
      -f|--format)     format=$2; shift 2 ;;
      -p)              ask_pass=1; shift ;;
      --password)      password=$2; shift 2 ;;
      -H|--hide-names) visible=no; shift ;;
      -h|--help)
        print -r -- "usage: archivize [-f 7z|zip|rar] [-p] [-H] [--password STR] [DIR]
  -f, --format      archive format (default 7z)
  -p                prompt for a password (hidden input)
  -H, --hide-names  encrypt file names too (7z / rar only)
  --password STR    password on the command line (visible in ps!)
With no arguments a full interactive wizard starts."
        return 0 ;;
      -*) msh::err "archivize: unknown option $1"; return 2 ;;
      *)
        [[ -z $target_dir ]] || { msh::err "archivize: unexpected argument '$1'"; return 2; }
        target_dir=$1; shift ;;
    esac
  done

  if [[ -z $target_dir ]]; then
    wizard=1
    read -r "target_dir?Directory to archive: "
  fi
  [[ -n $target_dir ]] || { msh::err "archivize: no directory given"; return 1; }
  target_dir=${~target_dir}
  target_dir=${target_dir:A}
  [[ -d $target_dir ]] || { msh::err "archivize: '$target_dir' is not a directory"; return 1; }

  msh::info "Archive source: $target_dir"
  local size name
  du -sh -- "$target_dir"/{*,.*}(N) 2>/dev/null | sort -h | while read -r size name; do
    print -r -- "  ${(r:8:)size} ${name:t}"
  done
  print -r -- "  total: $(du -sh -- "$target_dir" | cut -f1)"
  msh::confirm "Proceed with archiving?" || { msh::info "cancelled"; return 0; }

  if (( wizard )); then
    local chosen
    print "Select archive format:"
    select chosen in "7z (recommended)" zip rar; do
      format=${chosen%% *}; break
    done
    msh::confirm "Protect the archive with a password?" && ask_pass=1
  fi
  if (( ask_pass )); then
    local p1 p2
    read -rs "p1?Password: "; print
    read -rs "p2?Confirm password: "; print
    [[ $p1 == "$p2" ]] || { msh::err "archivize: passwords do not match"; return 1; }
    password=$p1
    if (( wizard )) && [[ $format == (7z|rar) ]]; then
      # Default is yes: a plain Enter keeps the file list visible.
      local ans
      read -r "ans?Keep the file list visible without the password? [Y/n] "
      [[ $ans == [nN]* ]] && visible=no
    fi
  fi

  case $format in 7z|zip|rar) ;; *) msh::err "archivize: unsupported format '$format'"; return 1 ;; esac
  msh::need $format || return 127
  local parent=${target_dir:h} base=${target_dir:t}
  local archive="$parent/$base.$format"
  if [[ -e $archive ]]; then
    msh::confirm "$archive exists. Overwrite?" || { msh::info "cancelled"; return 0; }
    rm -f -- "$archive"
  fi

  local -a cmd
  case $format in
    7z)
      cmd=(7z a)
      if [[ -n $password ]]; then cmd+=(-p"$password"); [[ $visible == no ]] && cmd+=(-mhe=on); fi ;;
    zip)
      cmd=(zip -r)
      [[ -n $password ]] && cmd+=(-P "$password") ;;
    rar)
      cmd=(rar a)
      if [[ -n $password ]]; then cmd+=(-p"$password"); [[ $visible == no ]] && cmd+=(-hp); fi ;;
  esac
  cmd+=("$base.$format" "$base")
  ( cd -- "$parent" && "${cmd[@]}" ) || { msh::err "archivize: failed"; return 1; }
  msh::ok "Archive created: $archive"
}

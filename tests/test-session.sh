#!/usr/bin/env bash
# test-session.sh — msh-session against a fake hyprctl (canned JSON + dispatch
# log), in a throwaway $HOME. Never touches the real desktop session.
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT=$PWD
BIN=$ROOT/shell/bin/msh-session

fail=0
red=$'\e[1;31m' green=$'\e[1;32m' reset=$'\e[0m'
[[ -n ${NO_COLOR-} || ! -t 1 ]] && red='' green='' reset=''
pass() { echo "${green}ok${reset}   $1"; }
bad()  { echo "${red}FAIL${reset} $1"; fail=1; }

T=$(mktemp -d)
trap 'kill $SECRET_PID $PLAIN_PID 2>/dev/null; rm -rf "$T"' EXIT
export PYTHONDONTWRITEBYTECODE=1
export HOME=$T/home XDG_CONFIG_HOME=$T/home/.config XDG_DATA_HOME=$T/home/.local/share NO_COLOR=1
export MSH_SESSIONS=$T/store MSH_SESSION_CONFIG=$T/session.toml HYPRLAND_INSTANCE_SIGNATURE=fake
mkdir -p "$HOME/.zsh" "$T/bin" "$HOME/work"
: > "$HOME/.zsh/secure.zsh"

cat > "$MSH_SESSION_CONFIG" <<'EOF'
screenshots = false
atspi = false
hypr_config = false
uwsm = "never"
launch_timeout = 1.0
close_timeout = 1.0
EOF

# Two real processes give the capture real /proc data: one mentions a secret file.
python3 -c 'import time; time.sleep(120)' "$HOME/.zsh/secure.zsh" & SECRET_PID=$!
(cd "$HOME/work" && exec python3 -c 'import time; time.sleep(120)' notes.txt) & PLAIN_PID=$!

client() { # address class title ws x y w h floating pid
  printf '{"address":"%s","mapped":true,"class":"%s","initialClass":"%s","title":"%s","initialTitle":"%s",
  "workspace":{"id":%s,"name":"%s"},"monitor":0,"at":[%s,%s],"size":[%s,%s],"floating":%s,"pinned":false,
  "fullscreen":0,"fullscreenClient":0,"xwayland":false,"grouped":[],"focusHistoryID":0,"pid":%s}' \
    "$1" "$2" "$2" "$3" "$3" "$4" "$4" "$5" "$6" "$7" "$8" "$9" "${10}"
}
write_clients() { printf '[%s,%s]\n' "$1" "$2" > "$T/clients.json"; }
write_clients "$(client 0x1 fakeapp "Notes" 2 100 200 640 480 true "$PLAIN_PID")" \
              "$(client 0x2 secretapp "Secret" 3 0 0 1920 1080 false "$SECRET_PID")"

cat > "$T/bin/hyprctl" <<EOF
#!/usr/bin/env bash
T=$T
EOF
cat >> "$T/bin/hyprctl" <<'EOF'
echo "$*" >> "$T/hyprctl.log"
case "$*" in
  "-j clients") cat "$T/clients.json" ;;
  "-j monitors") echo '[{"id":0,"name":"FAKE-1","description":"fake","width":1920,"height":1080,"refreshRate":60,"x":0,"y":0,"scale":1,"transform":0,"focused":true,"activeWorkspace":{"id":2,"name":"2"},"specialWorkspace":{"id":0,"name":""}}]' ;;
  "-j workspaces") echo '[{"id":2,"name":"2","monitor":"FAKE-1","windows":1},{"id":3,"name":"3","monitor":"FAKE-1","windows":1}]' ;;
  "-j activewindow") echo '{"address":"0x1"}' ;;
  "-j activeworkspace") echo '{"id":2,"name":"2"}' ;;
  "-j version") echo '{"tag":"v0.0.0-fake"}' ;;
  "-j devices") echo '{"keyboards":[]}' ;;
  -j*) echo '[]' ;;
  --batch*)
    # Apply exact resizes/relative moves so the position fixer can converge.
    python3 - "$T/clients.json" "$*" <<'PY'
import json, re, sys
f, cmd = sys.argv[1], sys.argv[2]
cl = json.load(open(f))
for part in cmd[len("--batch "):].split(" ; "):
    m = re.match(r"dispatch (\w+) (.*)", part.strip())
    if not m: continue
    op, arg = m.groups()
    addr = arg.rsplit("address:", 1)[-1]
    for c in cl:
        if c["address"] != addr: continue
        if op == "movetoworkspacesilent":
            ws = arg.split(",")[0]; c["workspace"] = {"id": int(ws), "name": ws}
        elif op == "setfloating": c["floating"] = True
        elif op == "settiled": c["floating"] = False
        elif op == "resizewindowpixel":
            w, h = arg.split(",")[0].split()[1:3]; c["size"] = [int(w), int(h)]
        elif op == "movewindowpixel":
            dx, dy = arg.split(",")[0].split()[:2]; c["at"] = [c["at"][0] + int(dx), c["at"][1] + int(dy)]
json.dump(cl, open(f, "w"))
PY
    echo ok ;;
  *) echo ok ;;
esac
EOF
chmod +x "$T/bin/hyprctl"
export PATH=$T/bin:$PATH

# 1. save → valid TOML, both windows, secret redacted
out=$(python3 "$BIN" save s1 -m "test" 2>&1) || bad "save exited non-zero: $out"
if python3 -c 'import tomllib,sys; d=tomllib.load(open(sys.argv[1],"rb")); assert len(d["windows"])==2' \
     "$MSH_SESSIONS/s1/session.toml"; then pass "save writes a valid session.toml"; else bad "session.toml"; fi
if grep -q 'secure.zsh' "$MSH_SESSIONS/s1/session.toml"; then bad "secret path leaked into snapshot"
else pass "secret file never recorded"; fi
grep -q '"redacted": true' "$MSH_SESSIONS/s1/session.json" && pass "secret command marked redacted" \
  || bad "redaction flag missing"
grep -q "notes.txt" "$MSH_SESSIONS/s1/session.toml" && pass "command line + cwd captured" || bad "cmdline missing"
[[ $(stat -c %a "$MSH_SESSIONS/s1") == 700 ]] && pass "snapshot dir is private (700)" || bad "snapshot mode"

# 2. list/show/json/names
python3 "$BIN" list --names | grep -qx s1 && pass "list --names" || bad "list --names"
python3 "$BIN" list --json | python3 -c 'import json,sys; assert json.load(sys.stdin)[0]["windows"]==2' \
  && pass "list --json" || bad "list --json"
python3 "$BIN" show s1 >/dev/null && pass "show" || bad "show"

# 3. move a window, then restore puts it back (workspace, size, exact position)
write_clients "$(client 0x1 fakeapp "Notes" 5 900 900 300 200 true "$PLAIN_PID")" \
              "$(client 0x2 secretapp "Secret" 3 0 0 1920 1080 false "$SECRET_PID")"
plan=$(python3 "$BIN" restore s1 --dry-run --json)
python3 -c 'import json,sys; p=json.loads(sys.argv[1]); assert len(p["reuse"])==2 and not p["launch"]' "$plan" \
  && pass "dry-run plan reuses matching windows" || bad "plan: $plan"
python3 "$BIN" restore s1 --no-backup --no-state >/dev/null 2>&1
python3 - "$T/clients.json" <<'PY' && pass "restore moves the window back exactly" || bad "restore placement"
import json, sys
c = next(c for c in json.load(open(sys.argv[1])) if c["address"] == "0x1")
assert c["workspace"]["name"] == "2" and c["size"] == [640, 480] and c["at"] == [100, 200], c
PY

# 4. a window that is gone gets launched with its saved command
write_clients "$(client 0x2 secretapp "Secret" 3 0 0 1920 1080 false "$SECRET_PID")" \
              "$(client 0x3 other "Other" 4 0 0 10 10 false "$SECRET_PID")"
: > "$T/hyprctl.log"
python3 "$BIN" switch s1 -y --no-backup --no-state >/dev/null 2>&1
grep -q 'dispatch exec .*notes.txt' "$T/hyprctl.log" && pass "missing window relaunched" || bad "no relaunch"
grep -q 'dispatch closewindow address:0x3' "$T/hyprctl.log" && pass "switch closes foreign windows" \
  || bad "switch did not close"

# 5. automatic backup + prune
python3 "$BIN" switch s1 -y --no-state >/dev/null 2>&1
[[ -n $(python3 "$BIN" list -a --names | grep '^auto-pre-switch-') ]] && pass "switch takes an auto snapshot" \
  || bad "no auto snapshot"

# 6. SNSS parser + TOML emitter round trip
python3 - "$BIN" <<'PY' && pass "SNSS parser + TOML round trip" || bad "SNSS/TOML"
import importlib.machinery, importlib.util, struct, sys, tomllib
loader = importlib.machinery.SourceFileLoader("ms", sys.argv[1])
spec = importlib.util.spec_from_loader("ms", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
def cmd(i, payload): return struct.pack("<HB", len(payload) + 1, i) + payload
def s8(s): b = s.encode(); return struct.pack("<i", len(b)) + b + b"\0" * (-len(b) % 4)
def s16(s): b = s.encode("utf-16-le"); return struct.pack("<i", len(s)) + b + b"\0" * (-len(b) % 4)
nav = lambda t, i, u, ti: cmd(6, struct.pack("<I", 0) + struct.pack("<ii", t, i) + s8(u) + s16(ti))
data = b"SNSS" + struct.pack("<i", 3) + cmd(0, struct.pack("<ii", 1, 10)) + cmd(0, struct.pack("<ii", 1, 11)) \
    + cmd(2, struct.pack("<ii", 11, 1)) + nav(10, 0, "https://a.example/", "A") + nav(11, 0, "https://b.example/", "Bé") \
    + cmd(8, struct.pack("<ii", 1, 1)) + cmd(0, struct.pack("<ii", 2, 12)) + nav(12, 0, "https://c/", "C") \
    + cmd(17, struct.pack("<iq", 2, 0))
w = m.parse_snss(data)
assert len(w) == 1 and [t["url"] for t in w[0]["tabs"]] == ["https://a.example/", "https://b.example/"], w
assert w[0]["selected"] == 1 and w[0]["tabs"][1]["title"] == "Bé"
doc = {"a": 1, "s": 'q"\n\\', "l": [1, 2], "t": {"x": {"y": True}}, "arr": [{"k": "v", "sub": {"z": 1.5}}, {"k": "w"}]}
assert tomllib.loads(m.toml_dumps(doc)) == doc
PY

# 7. Kate: session parse + install as msh-<name> with the stash paths rewritten
python3 - "$BIN" "$T" <<'PY' && pass "Kate session/stash parse + install" || bad "Kate session install"
import importlib.machinery, importlib.util, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("ms", sys.argv[1])
spec = importlib.util.spec_from_loader("ms", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
snap = Path(sys.argv[2]) / "kate-snap"
data = snap / "apps/kate/42"
(data / "stash").mkdir(parents=True)
stash = m.KateHandler.KDATA / "stash/def.katesession"
(data / "session.katesession").write_text(
    "[Document 0]\nURL=file:///tmp/a.txt\n\n[Document 1]\nURL=\nstashedFile=%s/Document 1\n" % stash)
(data / "stash/Document 1").write_text("never saved text")
docs = m.KateHandler.parse(data, "def")
assert docs == [{"url": "/tmp/a.txt"}, {"stashed": "Document 1", "state": "new-unsaved"}], docs
ctx = m.Ctx(m.load_config(), None, snap, "work")
ctx.restoring = True
win = {"proc": {"cmdline": ["kate", "-b"]}, "app": {"handler": "kate", "session": "def", "data": "apps/kate/42"}}
argv = m.KateHandler().launch(ctx, win)
assert argv == ["kate", "-b", "-s", "msh-work"], argv
kd = m.KateHandler.KDATA
text = (kd / "sessions/msh-work.katesession").read_text()
assert "/stash/msh-work.katesession/Document 1" in text and "/stash/def.katesession/" not in text, text
assert (kd / "stash/msh-work.katesession/Document 1").read_text() == "never saved text"
PY

# 8. completions
for sh in zsh bash fish; do
  python3 "$BIN" completion $sh | grep -q msh-session && pass "completion $sh" || bad "completion $sh"
done
bash -n <(python3 "$BIN" completion bash) || bad "bash completion syntax"
zsh -n <(python3 "$BIN" completion zsh) || bad "zsh completion syntax"
cmp -s <(python3 "$BIN" completion zsh) shell/completions/_msh-session && pass "shipped _msh-session up to date" \
  || bad "shell/completions/_msh-session is stale (regenerate it)"

(( fail )) && { echo "${red}session tests failed${reset}"; exit 1; }
echo "${green}session tests ok${reset}"

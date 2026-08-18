#!/usr/bin/env bash
# envdiff.sh - vergleicht zwei helmfile-environments-Ordner Datei fuer Datei
#              und zeigt Unterschiede zweispaltig mit Zeilennummern.
#
#   ./envdiff.sh default dev              # Uebersicht + Side-by-Side-Diffs
#   ./envdiff.sh -s default dev           # nur Uebersichtstabelle
#   ./envdiff.sh -f secrets default dev   # nur Dateien, deren Name "secrets" enthaelt
#   ./envdiff.sh -c 5 default dev         # 5 Zeilen Kontext (default: 2)
#   ./envdiff.sh -W 200 default dev       # Ausgabebreite erzwingen
#   ./envdiff.sh -P default dev           # klassische git-Farben ohne Hintergrund
#   ./envdiff.sh default dev | less -R    # -R noetig, sonst sieht man ^[[36m

set -uo pipefail

SUMMARY_ONLY=0
FILTER=""
CTX=2
WIDTH=""
PLAIN=0

while getopts ":sf:c:W:Ph" opt; do
  case "$opt" in
    s) SUMMARY_ONLY=1 ;;
    f) FILTER="$OPTARG" ;;
    c) CTX="$OPTARG" ;;
    W) WIDTH="$OPTARG" ;;
    P) PLAIN=1 ;;
    h) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unbekannte Option: -$OPTARG" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

A="${1:-default}"
B="${2:-dev}"

for d in "$A" "$B"; do
  [[ -d "$d" ]] || { echo "Kein Verzeichnis: $d" >&2; exit 1; }
done

# ---------- Farbpalette ----------
# Ohne Terminal (Pipe, Datei) komplett farblos. Bei <256 Farben automatisch
# auf die klassische git-Variante (nur Vordergrund) zurueckfallen.
COLORS=$( { tput colors; } 2>/dev/null || echo 8 )
[[ "$COLORS" -lt 256 ]] && PLAIN=1

if [[ -t 1 ]]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'
  D=$'\e[2m'; BD=$'\e[1m'; N=$'\e[0m'
  if [[ "$PLAIN" -eq 1 ]]; then
    DEL=$'\e[31m';        DEL_HI=$'\e[1;31;7m'      # rot / invertiert
    ADD=$'\e[32m';        ADD_HI=$'\e[1;32;7m'      # gruen / invertiert
  else
    DEL=$'\e[38;5;203;48;5;52m';  DEL_HI=$'\e[1;38;5;217;48;5;88m'
    ADD=$'\e[38;5;114;48;5;22m';  ADD_HI=$'\e[1;38;5;157;48;5;28m'
  fi
  CTXC=$'\e[2m'
else
  R=""; G=""; Y=""; C=""; D=""; BD=""; N=""
  DEL=""; DEL_HI=""; ADD=""; ADD_HI=""; CTXC=""
fi

# ---------- Spaltenbreiten ----------
if [[ -z "$WIDTH" ]]; then
  WIDTH=$( { tput cols; } 2>/dev/null )
  [[ -z "$WIDTH" || "$WIDTH" -lt 60 ]] && WIDTH=160
fi
NUMW=4
COLW=$(( (WIDTH - 2*NUMW - 7) / 2 ))
[[ "$COLW" -lt 20 ]] && COLW=20

hr() { printf '%s%s%s\n' "$D" "$(printf '─%.0s' $(seq 1 $((2*COLW + 2*NUMW + 7))))" "$N"; }

# ---------- Side-by-Side-Renderer ----------
side_by_side() {
  local fa="$1" fb="$2"
  diff -U "$CTX" "$fa" "$fb" | awk \
    -v w="$COLW" -v nw="$NUMW" -v N="$N" -v D="$D" \
    -v DEL="$DEL" -v DEL_HI="$DEL_HI" -v ADD="$ADD" -v ADD_HI="$ADD_HI" -v CTXC="$CTXC" '
    function trunc(s) {
      gsub(/\t/, "    ", s)
      if (length(s) > w) return substr(s, 1, w-1) "\xe2\x80\xa6"
      return s
    }
    # gemeinsamer Anfang zweier Strings
    function cpre(a, b,   i, n) {
      n = (length(a) < length(b)) ? length(a) : length(b)
      for (i = 1; i <= n; i++) if (substr(a,i,1) != substr(b,i,1)) return i-1
      return n
    }
    # gemeinsames Ende, hoechstens max Zeichen
    function csuf(a, b, max,   i, la, lb) {
      la = length(a); lb = length(b)
      for (i = 0; i < max; i++)
        if (substr(a, la-i, 1) != substr(b, lb-i, 1)) return i
      return max
    }
    # eine Zelle: Nummer + eingefaerbter, auf w aufgefuellter Text
    # other = Gegenstueck der anderen Seite (fuer Wort-Highlight), "" = keins
    function cell(num, txt, other, col, hi,   t, o, p, s, mx, body, pad, nn) {
      # Fuellzeile (auf dieser Seite existiert keine Zeile) -> leer, ohne Farbe
      if (num == "") return sprintf("%*s", nw, "") " " sprintf("%*s", w, "")
      nn = sprintf("%*d", nw, num)
      t = trunc(txt)
      if (col == CTXC || other == "" || t == "") {
        body = col t
      } else {
        o = trunc(other)
        p = cpre(t, o)
        mx = ((length(t) < length(o)) ? length(t) : length(o)) - p
        s = csuf(t, o, mx)
        body = col substr(t, 1, p) hi substr(t, p+1, length(t)-p-s) col substr(t, length(t)-s+1)
      }
      pad = w - length(t); if (pad < 0) pad = 0
      return D nn N " " body sprintf("%*s", pad, "") N
    }
    function row(ln, lt, lo, lc, lh, rn, rt, ro, rc, rh) {
      printf "%s %s│%s %s\n", cell(ln, lt, lo, lc, lh), D, N, cell(rn, rt, ro, rc, rh)
    }
    function flush(  i, m, lt, rt, ln, rn) {
      m = (nl > nr) ? nl : nr
      for (i = 1; i <= m; i++) {
        lt = (i <= nl) ? L[i]  : ""; ln = (i <= nl) ? la++ : ""
        rt = (i <= nr) ? Rr[i] : ""; rn = (i <= nr) ? lb++ : ""
        row(ln, lt, rt, DEL, DEL_HI, rn, rt == "" ? "" : rt, lt, ADD, ADD_HI)
      }
      nl = 0; nr = 0
    }
    BEGIN { nl = 0; nr = 0; first = 1 }
    /^(---|\+\+\+)/ { next }
    /^@@/ {
      flush()
      match($0, /-[0-9]+/); la = substr($0, RSTART+1, RLENGTH-1) + 0
      match($0, /\+[0-9]+/); lb = substr($0, RSTART+1, RLENGTH-1) + 0
      if (!first) printf "%s%*s ⋯%*s ⋯%s\n", D, nw, "", w, "", N
      first = 0
      next
    }
    /^\\/ { next }
    /^-/  { L[++nl]  = substr($0, 2); next }
    /^\+/ { Rr[++nr] = substr($0, 2); next }
    /^ /  { flush(); row(la, substr($0,2), "", CTXC, CTXC, lb, substr($0,2), "", CTXC, CTXC); la++; lb++; next }
    END { flush() }
  '
}

# ---------- Dateien einsammeln ----------
mapfile -t FILES < <(
  { find "$A" -maxdepth 1 -type f -printf '%f\n'
    find "$B" -maxdepth 1 -type f -printf '%f\n'; } | sort -u
)

declare -a DIFFERING=()
same=0; diffn=0; onlya=0; onlyb=0

printf '%s%-38s %s%s\n' "$BD" "DATEI" "STATUS" "$N"
hr

for f in "${FILES[@]}"; do
  [[ -n "$FILTER" && "$f" != *"$FILTER"* ]] && continue
  fa="$A/$f"; fb="$B/$f"

  if   [[ ! -f "$fb" ]]; then
    printf '%-38s %snur in %s%s\n' "$f" "$Y" "$A" "$N"; ((onlya++))
  elif [[ ! -f "$fa" ]]; then
    printf '%-38s %snur in %s%s\n' "$f" "$C" "$B" "$N"; ((onlyb++))
  elif cmp -s "$fa" "$fb"; then
    printf '%-38s %sidentisch%s\n' "$f" "$G" "$N"; ((same++))
  else
    add=$(diff "$fa" "$fb" | grep -c '^>')
    del=$(diff "$fa" "$fb" | grep -c '^<')
    printf '%-38s %sabweichend%s  (%s+%s%s / %s-%s%s)\n' \
      "$f" "$R" "$N" "$G" "$add" "$N" "$R" "$del" "$N"
    DIFFERING+=("$f"); ((diffn++))
  fi
done

hr
printf '%sidentisch: %d   abweichend: %d   nur %s: %d   nur %s: %d%s\n' \
  "$BD" "$same" "$diffn" "$A" "$onlya" "$B" "$onlyb" "$N"

[[ "$SUMMARY_ONLY" -eq 1 ]] && exit 0
[[ "${#DIFFERING[@]}" -eq 0 ]] && exit 0

for f in "${DIFFERING[@]}"; do
  printf '\n%s%s%s\n' "$BD$C" "$f" "$N"
  printf '%s%*s %-*s   %*s %-*s%s\n' \
    "$BD" "$NUMW" "" "$COLW" "$A" "$NUMW" "" "$COLW" "$B" "$N"
  hr
  side_by_side "$A/$f" "$B/$f"
done

exit 0

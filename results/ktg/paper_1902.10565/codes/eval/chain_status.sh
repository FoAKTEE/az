#!/bin/bash
# chain_status.sh -- mission ktg-train, task production_chain_9x9.
#
# The login-node, READ-ONLY monitoring reader of tasks/production_chain_9x9
# section 5 ("Monitoring is READ-ONLY on the login node ... every 3 h for the
# first 24 h, then every 12 h, and at every link boundary; each run appends to
# $EV/status_log.txt and is the packet's WAL"), built to the section 7 spec:
#
#   sacct of the ktg-loop jobs, the chain state files, cycles / exports / gate
#   lines, bucket-starvation and no-data lines, the last guard triple, du -sb,
#   nlwp max per stage (tail of ps_samples-<jobid>.tsv), GPU util mean (tail of
#   gpu_samples), last selfplay games/h.
#
# It NEVER writes into BASEDIR, never submits, cancels or resubmits anything,
# never touches STOP / .failcount / .breaker_tripped, never runs torch, never
# runs du over the group pool, and never attaches to the compute node. Its only
# write is the append to the status log named by --append. Everything it runs is
# a single-process read (grep / awk / tail / sacct / squeue / du of BASEDIR), so
# it stays inside the two-core login-node budget of section 13.
#
# EXIT CODES
#   0  nothing to escalate (findings may still be printed as NOTICE lines)
#   1  at least one section-11 ESCALATE condition is present; every reason is
#      printed on stdout as "ESCALATE: <signal> -- <evidence>"
#   2  usage error
#
# The section-11 abort table this implements, by its verbatim signals:
#   breaker trips / link fails   .breaker_tripped, sacct FAILED, "failcount now 3/3",
#                                no successor
#   storage stop                 STOP written, "scratch_guard exit 1|2"
#   no export by cycle 8         0 "SAVING MODEL FOR EXPORT" with cycles >= 8.
#                                NARROWED by the repairs validator (commit 3a3532c,
#                                progress.md "Facts from the repairs validator"): the
#                                trainer consumes whole shuffled files, so exports fall
#                                at cycles ~5, 10, 15, 19, 22 and NO EXPORT AT CYCLES
#                                6-9 IS NOT A FAULT. The rule therefore fires only when
#                                cycle 5 itself produced none.
#   bucket starvation            "not enough new data rows, terminating" in >= 3
#                                consecutive cycles
#   no-data exit on a real cycle "Not enough data files to fill a subepoch" at cycle >= 6
#   gate never accepts by 20     models/ empty with cycles >= 20
#   threads over the declaration nlwp max > 32 on any stage
#   export refusal (o15)         exporter non-zero exit, or attn bound > 2.5e4
#   link ended other than TIMEOUT  CANCELLED / NODE_FAIL / OUT_OF_MEMORY; a link with no
#                                "SIGTERM received" line in its log was SIGKILLed (o42:
#                                tell the coordinator BEFORE the successor starts)
# Reported, NOT escalated (section 11 says "report only" / "notify at the next status"):
#   successor PENDING > 24 h, "scratch_guard: WARNING group scratch free space".
#
# usage:
#   chain_status.sh <BASEDIR> [options]
#     --job ID          restrict sacct/monitor reads to one job id (default: every
#                       ktg-loop job of this user in the last 14 days)
#     --log FILE|GLOB   link log(s) to read (repeatable; default
#                       $KTG_ROOT/logs/loop-*.log plus $BASEDIR/logs/*cycle*.txt)
#     --append FILE     append the report here (default
#                       <paper>/evidence/production_chain/status_log.txt)
#     --no-append       print only
#     --no-du           skip the du -sb of BASEDIR
#     --tail-lines N    ps sample rows to read from the tail (default 200000; the
#                       sampler only ever appends, so the tail is the recent state)
#     --first-export-cycle   print ONE integer -- the cumulative cycle number the
#                            first export landed in -- and exit (P4)
#     --first-gate-cycle     the same for the first "Candidate won|lost match" (P5)
#     --quiet           suppress the report body; keep the verdict lines
#
# The two --first-*-cycle forms print the cycle number carried by the
# "cycle N complete -- K cycle(s) recorded" line that FOLLOWS the matched line,
# i.e. K = the cumulative count in $BASEDIR/.cycles_completed, which is the count
# P4/P5 are written against and the only one that survives a link boundary
# (synchronous_loop_9x9.sh:427-428; CYCLE_INDEX itself restarts at 0 each link,
# :295). They print nothing and exit 1 while the event has not happened, or while
# the cycle it happened in has not yet completed.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAPER="$(cd "$HERE/../.." && pwd)"
KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"

NLWP_CAP="${KTG_NLWP_CAP:-32}"            # o03 / o39 (c): the declared thread budget
ATTN_LIMIT=25000                          # export_model_pytorch.py:42 default 2.5e4
NO_EXPORT_BY_CYCLE=8                      # section 11
NO_ACCEPT_BY_CYCLE=20                     # section 11 / c13
STARVATION_RUN=3                          # section 11 (R14)
NODATA_FROM_CYCLE=6                       # section 11 (R16)
PENDING_WARN_HOURS=24                     # section 11 (report only)
GPU_TAIL=5000

BASEDIR=""
JOB=""
LOGS=()
APPEND=""
DO_APPEND=1
DO_DU=1
PS_TAIL=200000
MODE="report"
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --job)                JOB="${2:-}"; shift 2 ;;
    --log)                LOGS+=("${2:-}"); shift 2 ;;
    --append)             APPEND="${2:-}"; shift 2 ;;
    --no-append)          DO_APPEND=0; shift ;;
    --no-du)              DO_DU=0; shift ;;
    --tail-lines)         PS_TAIL="${2:-}"; shift 2 ;;
    --first-export-cycle) MODE="first_export"; shift ;;
    --first-gate-cycle)   MODE="first_gate"; shift ;;
    --quiet)              QUIET=1; shift ;;
    -h|--help)            sed -n '2,72p' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*)                   echo "chain_status.sh: unknown option '$1'" >&2; exit 2 ;;
    *)                    if [ -z "$BASEDIR" ]; then BASEDIR="$1"
                          else echo "chain_status.sh: unexpected argument '$1'" >&2; exit 2; fi
                          shift ;;
  esac
done

if [ -z "$BASEDIR" ]; then
  echo "usage: chain_status.sh <BASEDIR> [--job ID] [--log FILE] [--append FILE] [--no-append]" >&2
  echo "                       [--no-du] [--first-export-cycle] [--first-gate-cycle] [--quiet]" >&2
  exit 2
fi
BASEDIR="${BASEDIR%/}"
[ -n "$APPEND" ] || APPEND="$PAPER/evidence/production_chain/status_log.txt"

sum_lines() { awk '{ s += $1 } END { print s + 0 }'; }

# ---------------------------------------------------------------- log discovery
# Default: the chain's own per-link logs, plus a smoke / dry-run BASEDIR's
# per-cycle logs, so the reader can be exercised before the chain writes one.
if [ "${#LOGS[@]}" -eq 0 ]; then
  if [ -n "$JOB" ]; then LOGS+=("$KTG_ROOT/logs/loop-$JOB.log")
  else                   LOGS+=("$KTG_ROOT/logs/loop-"*.log); fi
  LOGS+=("$BASEDIR/logs/"*cycle*.txt)
fi
LOGFILES=()
for pat in "${LOGS[@]}"; do
  for f in $pat; do
    [ -f "$f" ] && LOGFILES+=("$f")
  done
done
# Oldest first, so "the first export" really is the first one in chain order.
if [ "${#LOGFILES[@]}" -gt 1 ]; then
  mapfile -t LOGFILES < <(ls -tr -- "${LOGFILES[@]}" 2>/dev/null)
fi

# ------------------------------------------------------- cycle-of-a-line helper
cycle_of_first_match() {
  local rx="$1"
  [ "${#LOGFILES[@]}" -gt 0 ] || return 1
  awk -v rx="$rx" '
    seen && /complete -- [0-9]+ cycle\(s\) recorded/ {
      s = $0; sub(/.*complete -- /, "", s); sub(/ cycle\(s\).*/, "", s);
      print s; exit 0
    }
    !seen && $0 ~ rx { seen = 1 }
  ' "${LOGFILES[@]}" 2>/dev/null
}

if [ "$MODE" = "first_export" ]; then
  v="$(cycle_of_first_match 'SAVING MODEL FOR EXPORT')"
  [ -n "$v" ] || exit 1
  echo "$v"; exit 0
fi
if [ "$MODE" = "first_gate" ]; then
  v="$(cycle_of_first_match 'Candidate (won|lost) match')"
  [ -n "$v" ] || exit 1
  echo "$v"; exit 0
fi

# ------------------------------------------------------------------ the report
ESCALATIONS=()
NOTICES=()
esc()    { ESCALATIONS+=("$1"); }
notice() { NOTICES+=("$1"); }

report() {
  local n f sig

  echo "=============================================================================="
  echo "chain_status  $(date -Is)   host=$(hostname -s)"
  echo "BASEDIR   : $BASEDIR"
  echo "KTG_ROOT  : $KTG_ROOT"
  echo "logs read : ${#LOGFILES[@]} file(s)"
  for f in "${LOGFILES[@]}"; do echo "            $f"; done
  echo "=============================================================================="

  # ---- A. slurm -------------------------------------------------------------
  echo ""
  echo "-- A. slurm ---------------------------------------------------------------"
  # -P (pipe-separated) rather than a padded table: a state is "CANCELLED by 30154",
  # which whitespace splitting would tear into three fields.
  local sacct_out="" jid st el start sigterm_seen
  if command -v sacct >/dev/null 2>&1; then
    if [ -n "$JOB" ]; then
      sacct_out="$(sacct -n -P -j "$JOB" -X -o JobID,JobName,Partition,State,Elapsed,Start,End,ExitCode 2>/dev/null)"
    else
      sacct_out="$(sacct -n -P -S now-14days --name=ktg-loop -X -o JobID,JobName,Partition,State,Elapsed,Start,End,ExitCode 2>/dev/null)"
    fi
  fi
  if [ -n "$sacct_out" ]; then
    printf '%s\n' "$sacct_out" | awk -F'|' \
      'BEGIN { printf "%10s %10s %6s %16s %10s %20s %20s %6s\n", "JobID","JobName","Part","State","Elapsed","Start","End","Exit" }
       { printf "%10s %10s %6s %16s %10s %20s %20s %6s\n", $1,$2,$3,$4,$5,$6,$7,$8 }'
  else
    echo "(no ktg-loop job in the last 14 days, or sacct unavailable)"
  fi

  while IFS='|' read -r jid _jn _part st el start _end _ec; do
    [ -n "${jid:-}" ] || continue
    case "$st" in
      TIMEOUT|COMPLETED|RUNNING|PENDING|REQUEUED|RESIZING|SUSPENDED|"") ;;
      *)
        # A job that was never allocated is not a link end: sacct reports it with
        # Start None/Unknown and Elapsed 00:00:00 (job 299366, cancelled while
        # PENDING for the coordinator's re-link, is exactly this shape).
        if [ "${el:-}" = "00:00:00" ] && { [ "${start:-}" = "None" ] || [ "${start:-}" = "Unknown" ]; }; then
          notice "job $jid ended $st without ever being allocated (Start $start, Elapsed $el) -- not a link end, no resume evidence either way"
          continue
        fi
        sigterm_seen=0
        for f in "${LOGFILES[@]}"; do
          case "$f" in
            *"$jid"*) grep -q 'SIGTERM received -- scheduler termination' "$f" 2>/dev/null && sigterm_seen=1 ;;
          esac
        done
        if [ "$sigterm_seen" -eq 1 ]; then
          notice "link $jid ended $st but its log carries 'SIGTERM received -- scheduler termination': a scheduler end, successor continues (o25 walltime half / o33 r1)"
        else
          esc "link ended other than TIMEOUT -- job $jid state $st with no 'SIGTERM received' line in its log (o42: a SIGKILLed link means the successor must reach the coordinator BEFORE it starts)"
        fi
        ;;
    esac
  done <<< "$sacct_out"

  if command -v squeue >/dev/null 2>&1; then
    local pend pid sub subs now hrs
    pend="$(squeue -h -u "$(id -un)" --name=ktg-loop -t PENDING -o '%i %V %r' 2>/dev/null)"
    if [ -n "$pend" ]; then
      echo ""
      echo "pending ktg-loop links (jobid submit_time reason):"
      printf '%s\n' "$pend"
      while read -r pid sub _rsn; do
        [ -n "${pid:-}" ] || continue
        subs="$(date -d "$sub" +%s 2>/dev/null)"; now="$(date +%s)"
        if [ -n "${subs:-}" ]; then
          hrs=$(( (now - subs) / 3600 ))
          if [ "$hrs" -ge "$PENDING_WARN_HOURS" ]; then
            notice "successor $pid has been PENDING ${hrs} h (>= $PENDING_WARN_HOURS h) -- section 11 says report only; never submit a duplicate"
          fi
        fi
      done <<< "$pend"
    fi
  fi

  # ---- B. chain state -------------------------------------------------------
  echo ""
  echo "-- B. chain state ---------------------------------------------------------"
  if [ ! -d "$BASEDIR" ]; then
    echo "BASEDIR does not exist yet -- the first link has not started."
    echo "(a queued job is not an escalation; nothing else can be read)"
    return 0
  fi
  local cycles depth fails
  cycles="$(cat "$BASEDIR/.cycles_completed" 2>/dev/null || echo 0)"
  depth="$(cat "$BASEDIR/.chain_depth" 2>/dev/null || echo '-')"
  fails="$(cat "$BASEDIR/.failcount" 2>/dev/null || echo '-')"
  case "$cycles" in ''|*[!0-9]*) cycles=0 ;; esac
  echo ".cycles_completed : $cycles"
  echo ".chain_depth      : $depth"
  echo ".failcount        : $fails"
  echo "STOP              : $([ -e "$BASEDIR/STOP" ] && echo PRESENT || echo absent)"
  echo ".breaker_tripped  : $([ -e "$BASEDIR/.breaker_tripped" ] && echo PRESENT || echo absent)"

  [ -e "$BASEDIR/.breaker_tripped" ] && \
    esc "breaker trips -- $BASEDIR/.breaker_tripped exists; collect the link logs and the sacct rows, and do not remove .failcount without the human"
  [ -e "$BASEDIR/STOP" ] && \
    esc "storage stop / manual brake -- $BASEDIR/STOP exists; the loop exits cleanly at the top of the next cycle and no successor will run one"

  # ---- C. cycles / exports / gate ------------------------------------------
  echo ""
  echo "-- C. cycles / exports / gate ---------------------------------------------"
  local n_export n_done n_gate n_won n_lost first_exp first_gate n_models
  n_export=0; n_done=0; n_gate=0; n_won=0; n_lost=0
  if [ "${#LOGFILES[@]}" -gt 0 ]; then
    n_export="$(grep -ch 'SAVING MODEL FOR EXPORT'    "${LOGFILES[@]}" 2>/dev/null | sum_lines)"
    n_done="$(  grep -ch 'Done exporting:'            "${LOGFILES[@]}" 2>/dev/null | sum_lines)"
    n_gate="$(  grep -chE 'Candidate (won|lost) match' "${LOGFILES[@]}" 2>/dev/null | sum_lines)"
    n_won="$(   grep -ch 'Candidate won match'        "${LOGFILES[@]}" 2>/dev/null | sum_lines)"
    n_lost="$(  grep -ch 'Candidate lost match'       "${LOGFILES[@]}" 2>/dev/null | sum_lines)"
  fi
  first_exp="$(cycle_of_first_match 'SAVING MODEL FOR EXPORT')"
  first_gate="$(cycle_of_first_match 'Candidate (won|lost) match')"
  n_models="$(ls -1 "$BASEDIR/models" 2>/dev/null | wc -l)"
  echo "cycles completed        : $cycles"
  echo "SAVING MODEL FOR EXPORT : $n_export   (Done exporting: $n_done)"
  echo "first export at cycle   : ${first_exp:-none yet}   (P4 tolerance == 5)"
  echo "gate decisions          : $n_gate   (won $n_won, lost $n_lost)"
  echo "first gate at cycle     : ${first_gate:-none yet}   (P5 tolerance 6 +/- 1)"
  echo "models/ (acceptances)   : $n_models"
  ls -1 "$BASEDIR/models" 2>/dev/null | sed 's/^/    accepted  /'
  echo "rejectedmodels/         : $(ls -1 "$BASEDIR/rejectedmodels" 2>/dev/null | wc -l)"
  ls -1 "$BASEDIR/rejectedmodels" 2>/dev/null | sed 's/^/    rejected  /'
  echo "modelstobetested/       : $(ls -1 "$BASEDIR/modelstobetested" 2>/dev/null | wc -l) awaiting the gate"
  if [ "${#LOGFILES[@]}" -gt 0 ]; then
    echo "gate scores (last 20):"
    grep -hE 'Candidate (won|lost) match' "${LOGFILES[@]}" 2>/dev/null | tail -20 | sed 's/^/    /'
  fi

  if [ "$cycles" -ge "$NO_EXPORT_BY_CYCLE" ] && [ "${n_export:-0}" -eq 0 ]; then
    esc "no export by cycle $NO_EXPORT_BY_CYCLE -- 0 'SAVING MODEL FOR EXPORT' with cycles completed $cycles; o40 refuted. touch STOP and escalate with the train log's 'Not enough data files' / 'Export cycle counter' lines"
  fi
  if [ -n "${first_exp:-}" ] && [ "$first_exp" -ne 5 ]; then
    if [ "$first_exp" -gt 8 ]; then
      esc "first export cycle $first_exp > 8 -- P4 says abort"
    else
      notice "first export cycle $first_exp != 5 -- P4 re-opens o40 (below cycle 9 this is a finding, not an abort)"
    fi
  fi
  if [ -n "${first_gate:-}" ] && { [ "$first_gate" -lt 5 ] || [ "$first_gate" -gt 7 ]; }; then
    notice "first gate decision at cycle $first_gate, outside P5's 6 +/- 1"
  fi
  if [ "$cycles" -ge "$NO_ACCEPT_BY_CYCLE" ] && [ "$n_models" -eq 0 ]; then
    esc "gate never accepts by cycle $NO_ACCEPT_BY_CYCLE -- models/ empty with cycles completed $cycles; escalate with every 'Candidate lost match, score ...' line, and do NOT touch numGamesPerGating, maxVisits or -required-candidate-win-prop"
  fi

  # ---- D. failure signatures ------------------------------------------------
  echo ""
  echo "-- D. failure signatures --------------------------------------------------"
  if [ "${#LOGFILES[@]}" -eq 0 ]; then
    echo "(no log to read)"
  else
    for sig in 'not enough new data rows, terminating' \
               'Not enough data files to fill a subepoch' \
               'Initializing new model!' \
               'No preexisting checkpoint found' \
               'scratch_guard exit' \
               'failcount now' \
               'circuit breaker tripped' \
               'SIGTERM received -- scheduler termination' \
               'scheduler termination at walltime' \
               'cancelling queued successor' \
               'not resubmitting' \
               'failed with exit'; do
      n="$(grep -chF "$sig" "${LOGFILES[@]}" 2>/dev/null | sum_lines)"
      printf '  %-46s %s\n' "$sig" "${n:-0}"
    done

    if grep -qhE 'scratch_guard exit [12]:' "${LOGFILES[@]}" 2>/dev/null; then
      esc "storage stop -- $(grep -hE 'scratch_guard exit [12]:' "${LOGFILES[@]}" 2>/dev/null | tail -1); never bypass the guard, escalate (group pool or cap)"
    fi
    if grep -qh 'circuit breaker tripped' "${LOGFILES[@]}" 2>/dev/null; then
      esc "breaker trips -- $(grep -h 'circuit breaker tripped' "${LOGFILES[@]}" 2>/dev/null | tail -1)"
    fi
    if grep -qhE 'failcount now ([3-9]|[0-9]{2,})/' "${LOGFILES[@]}" 2>/dev/null; then
      esc "link fails -- $(grep -hE 'failcount now ([3-9]|[0-9]{2,})/' "${LOGFILES[@]}" 2>/dev/null | tail -1)"
    fi
    if grep -qh 'failed with exit' "${LOGFILES[@]}" 2>/dev/null; then
      esc "export refusal (R3, o15) -- $(grep -h 'failed with exit' "${LOGFILES[@]}" 2>/dev/null | tail -1); the loop dies each cycle, so this reaches the breaker"
    fi
    if grep -qh 'scratch_guard: WARNING group scratch free space' "${LOGFILES[@]}" 2>/dev/null; then
      notice "group scratch warn -- $(grep -h 'scratch_guard: WARNING group scratch free space' "${LOGFILES[@]}" 2>/dev/null | tail -1); notify the human at this status"
    fi

    # R14: >= 3 CONSECUTIVE cycles carrying a bucket-starvation exit. "Consecutive"
    # is counted over the cycle boundaries, which are the "cycle N complete" lines.
    local starve_run
    starve_run="$(awk '
      /not enough new data rows, terminating/ { hit = 1 }
      /complete -- [0-9]+ cycle\(s\) recorded/ {
        if (hit) { run++; if (run > best) best = run } else { run = 0 }
        hit = 0
      }
      END { print best + 0 }' "${LOGFILES[@]}" 2>/dev/null)"
    printf '  %-46s %s\n' 'longest consecutive-starvation run' "${starve_run:-0}"
    if [ "${starve_run:-0}" -ge "$STARVATION_RUN" ]; then
      esc "bucket starvation (R14) -- 'not enough new data rows, terminating' in $starve_run consecutive cycles; attach check_knobs_9x9.py --throughput \$EV/throughput.json output"
    fi

    # R16: a no-data exit is only a fault once the net is real, i.e. cycle >= 6.
    local nodata_cycle
    nodata_cycle="$(awk '
      /Not enough data files to fill a subepoch/ { pending = 1 }
      /complete -- [0-9]+ cycle\(s\) recorded/ {
        s = $0; sub(/.*complete -- /, "", s); sub(/ cycle\(s\).*/, "", s);
        if (pending && first == "") first = s;
        pending = 0
      }
      END { if (first != "") print first }' "${LOGFILES[@]}" 2>/dev/null)"
    printf '  %-46s %s\n' 'first no-data-exit cycle' "${nodata_cycle:-none}"
    if [ -n "${nodata_cycle:-}" ] && [ "$nodata_cycle" -ge "$NODATA_FROM_CYCLE" ]; then
      esc "no-data exit on a real-net cycle (R16) -- 'Not enough data files to fill a subepoch' first at cycle $nodata_cycle (>= $NODATA_FROM_CYCLE); attach the window sizes from logs/outshuffle.txt"
    fi

    local n_init
    n_init="$(grep -ch 'Initializing new model!' "${LOGFILES[@]}" 2>/dev/null | sum_lines)"
    if [ "${n_init:-0}" -gt 1 ]; then
      esc "re-initialisation -- 'Initializing new model!' appears ${n_init} times; P3 requires exactly one over the whole chain, so a resume has lost the run"
    fi
  fi

  # o15's second signature: the exporter's own data-free attention logit bound.
  if [ -f "$BASEDIR/logs/outexport.txt" ]; then
    local worst
    worst="$(grep -h 'Data-free attention logit bound' "$BASEDIR/logs/outexport.txt" 2>/dev/null \
             | tr ',' '\n' | sed -n 's/.*=\([0-9][0-9]*\)[[:space:]]*$/\1/p' | sort -n | tail -1)"
    printf '  %-46s %s   (export limit %s)\n' 'attn logit bound, max in outexport.txt' "${worst:-n/a}" "$ATTN_LIMIT"
    if [ -n "${worst:-}" ] && [ "$worst" -gt "$ATTN_LIMIT" ]; then
      esc "export refusal (R3, o15) -- data-free attention logit bound $worst > $ATTN_LIMIT in logs/outexport.txt"
    fi
  fi

  # ---- E. storage -----------------------------------------------------------
  echo ""
  echo "-- E. storage -------------------------------------------------------------"
  if [ "${#LOGFILES[@]}" -gt 0 ]; then
    echo "last scratch_guard block:"
    awk '/^== scratch_guard /{buf = ""; keep = 1}
         keep{buf = buf $0 "\n"}
         /^scratch_guard: (OK|WARNING|no usable)/{if (keep) {last = buf; keep = 0}}
         END{printf "%s", last}' "${LOGFILES[@]}" 2>/dev/null | sed 's/^/    /'
    # P10 counts two different things and they must be compared like for like.
    # Every scratch_guard INVOCATION emits one '== scratch_guard ... ==' header
    # and one verdict line, and a link makes one more invocation than it starts
    # cycles: the wrapper's own '[chain link N pre-flight]' call before the loop
    # (loop.sbatch, scratch guard section) plus one '[cycle N pre-gatekeeper]'
    # call per cycle. Counting only the per-cycle headers against ALL 'OK' lines
    # therefore reported a shortfall of exactly one on every healthy link -- job
    # 301099 read 1 logged "1 guard blocks but 2 'scratch_guard: OK' lines" with
    # both verdicts clean. So the equality is over all invocations, and the
    # per-cycle subset is reported separately because that is the count P10 wants
    # equal to the cycles started in the link.
    local n_blocks n_cycle n_ok
    n_blocks="$(grep -ch '^== scratch_guard ' "${LOGFILES[@]}" 2>/dev/null | sum_lines)"
    n_cycle="$(grep -ch '^== scratch_guard .*\[cycle [0-9]* pre-gatekeeper\] ==' "${LOGFILES[@]}" 2>/dev/null | sum_lines)"
    n_ok="$(grep -ch 'scratch_guard: OK' "${LOGFILES[@]}" 2>/dev/null | sum_lines)"
    echo "    guard invocations: ${n_blocks:-0}    'scratch_guard: OK': ${n_ok:-0}    of which [cycle N pre-gatekeeper]: ${n_cycle:-0}"
    echo "    (P10 wants every invocation to carry a clean verdict, and the per-cycle"
    echo "     subset to equal the cycles started in the link; the extra invocation is"
    echo "     the wrapper's own '[chain link N pre-flight]' call, one per link)"
    if [ "${n_blocks:-0}" -ne "${n_ok:-0}" ]; then
      notice "P10: ${n_blocks:-0} scratch_guard invocations but ${n_ok:-0} 'scratch_guard: OK' lines -- a guard call ended without a clean verdict"
    fi
  fi
  if [ "$DO_DU" -eq 1 ]; then
    # BASEDIR only. Never du over the group pool (section 13).
    echo "    du -sb $BASEDIR : $(du -sb "$BASEDIR" 2>/dev/null | cut -f1) B"
  fi

  # ---- F. monitor (tail) ----------------------------------------------------
  echo ""
  echo "-- F. monitor (tail) ------------------------------------------------------"
  local psf gpuf over_cap spdir games sp_elapsed
  psf=""
  if [ -n "$JOB" ] && [ -f "$BASEDIR/monitor/ps_samples-$JOB.tsv" ]; then
    psf="$BASEDIR/monitor/ps_samples-$JOB.tsv"
  else
    psf="$(ls -1t "$BASEDIR/monitor/ps_samples-"*.tsv 2>/dev/null | head -1)"
    [ -n "${psf:-}" ] || psf="$BASEDIR/monitor/ps_samples.tsv"
  fi
  if [ -n "$JOB" ] && [ -f "$BASEDIR/monitor/gpu_samples-$JOB.csv" ]; then
    gpuf="$BASEDIR/monitor/gpu_samples-$JOB.csv"
  else
    gpuf="$(ls -1t "$BASEDIR/monitor/gpu_samples"*.csv 2>/dev/null | head -1)"
  fi
  echo "ps file  : ${psf:-none}"
  echo "gpu file : ${gpuf:-none}"

  over_cap=""
  if [ -n "${psf:-}" ] && [ -f "$psf" ]; then
    echo "nlwp max per stage (last $PS_TAIL sample rows; cap $NLWP_CAP):"
    tail -n "$PS_TAIL" "$psf" | awk -F'\t' -v cap="$NLWP_CAP" '
      NF >= 6 { st = $3; n = $5 + 0; if (n > mx[st]) mx[st] = n }
      END { for (s in mx) printf "    %-12s %6d%s\n", s, mx[s], (mx[s] > cap ? "   OVER CAP" : "") }' | sort
    over_cap="$(tail -n "$PS_TAIL" "$psf" | awk -F'\t' -v cap="$NLWP_CAP" '
      NF >= 6 { st = $3; n = $5 + 0; if (n > mx[st]) mx[st] = n }
      END { bad = ""; for (s in mx) if (mx[s] > cap) bad = bad s "=" mx[s] " "; printf "%s", bad }')"
    echo "    current phase: $(cat "$BASEDIR/monitor/phase" 2>/dev/null || echo unknown)"
    if [ -n "$over_cap" ]; then
      esc "threads over the declaration -- nlwp max > $NLWP_CAP on: $over_cap (o03 refuted at $NLWP_CAP); never lower numGameThreads unilaterally"
    fi
  else
    echo "(no ps samples yet)"
  fi

  if [ -n "${gpuf:-}" ] && [ -f "$gpuf" ]; then
    tail -n "$GPU_TAIL" "$gpuf" | awk -F',' '
      NF >= 4 { u = $3 + 0; m = $4 + 0; s += u; n++;
                if (u > umax) umax = u; if (m > mmax) mmax = m }
      END { if (n) printf "gpu (last %d samples): util_mean %.2f %%  util_max %d %%  mem_used_max %d MiB\n", n, s / n, umax, mmax;
            else print "gpu: no parseable samples" }'
  else
    echo "(no gpu samples yet)"
  fi

  spdir="$(ls -1dt "$BASEDIR/selfplay/"*/ 2>/dev/null | head -1)"
  if [ -n "${spdir:-}" ]; then
    games="$(cat "$spdir"sgfs/*.sgfs 2>/dev/null | grep -c .)"
    echo "newest selfplay net dir : $spdir  ($games game lines)"
    if [ -n "${psf:-}" ] && [ -f "$psf" ]; then
      sp_elapsed="$(tail -n "$PS_TAIL" "$psf" | awk -F'\t' '
        NF >= 6 && $3 == "selfplay" { ph = $2; if (!(ph in lo)) lo[ph] = $1; hi[ph] = $1; last = ph }
        END { if (last != "") printf "%s %.2f", last, hi[last] - lo[last] }')"
      if [ -n "${sp_elapsed:-}" ] && [ "${games:-0}" -gt 0 ]; then
        awk -v g="$games" -v spec="$sp_elapsed" \
          'BEGIN { split(spec, a, " "); t = a[2] + 0;
                   if (t > 0) printf "last selfplay phase     : %s, %.2f s -> %.1f games/h (games counted in the newest net dir; the two coincide only while that dir is the one the phase wrote)\n", a[1], t, g * 3600 / t }'
      fi
    fi
  fi
}

# Redirection, NOT command substitution: a subshell would discard every esc/notice.
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/chain_status.XXXXXX")" || exit 2
trap 'rm -rf "$TMPD"' EXIT
report > "$TMPD/body" 2>&1

{
  echo ""
  echo "-- verdict ----------------------------------------------------------------"
  for m in ${NOTICES[@]+"${NOTICES[@]}"};    do echo "NOTICE:   $m"; done
  for m in ${ESCALATIONS[@]+"${ESCALATIONS[@]}"}; do echo "ESCALATE: $m"; done
  if [ "${#ESCALATIONS[@]}" -gt 0 ]; then
    echo "chain_status: ${#ESCALATIONS[@]} escalate condition(s) -- exit 1."
    echo "Section 11: escalate with data, never tune. No knob, cfg, gating or search"
    echo "parameter change while the chain runs; a finding is an error row plus an"
    echo "escalation, never a silent edit."
  else
    echo "chain_status: OK -- no section-11 escalate condition present."
  fi
} > "$TMPD/verdict"

[ "$QUIET" -eq 1 ] || cat "$TMPD/body"
cat "$TMPD/verdict"

if [ "$DO_APPEND" -eq 1 ]; then
  mkdir -p "$(dirname "$APPEND")" 2>/dev/null
  if { cat "$TMPD/body" "$TMPD/verdict"; echo ""; } >> "$APPEND" 2>/dev/null; then
    echo "(appended to $APPEND)"
  else
    echo "(could not append to $APPEND)" >&2
  fi
fi

[ "${#ESCALATIONS[@]}" -eq 0 ] || exit 1
exit 0

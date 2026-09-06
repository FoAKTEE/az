# HUMAN_DIGEST — ktg-train

**Status: STOPPED by you on 2026-09-06 at 13:03 EDT.** You said "this is good enough already, save all
necessary checkpoints and stop" at 12:57. The chain (link 2 of 9) exited cleanly three minutes later at
cycle 249, nothing was killed mid-write, and everything is checkpointed and verified. Nothing is running.
Nothing is blocked. Nothing needs a decision from you right now.

## Where the checkpoints are, and how to resume

    /home/schmidt/ssci-haiyangw/ktg-checkpoints/2026-09-06_stop

7.2 GB, 10,957 files, every one verified against a manifest (`sha256sum -c MANIFEST.sha256` exits 0, no
failures). It holds the trained models, the trainer's own resumable state, every self-play game that
survived to the stop, the loop scripts and configs as they actually ran, the built game-viewer pages, and
a `README.md` inside the checkpoint directory that carries the full resume procedure (§7 there): restore
`p1/` into the run directory, rebuild the training environment if scratch was cleared, remove the `STOP`
file, run the compute-policy check, then resubmit the training job. It resumes exactly where it left off —
the trainer continues from its last saved checkpoint, about 240,000 samples past the last exported network.
Pointer with the full inventory and a one-command verifier: `results/ktg/paper_1902.10565/evidence/
production_chain/CHECKPOINTS.md`.

## What was achieved

- **249 training cycles** across two chain segments (157 at 1,000 games/cycle, then 92 at 1,800
  games/cycle after a mid-run tuning change you approved), **322,600 self-play games**, **28.95 million**
  training samples, **93 candidate networks accepted** by the built-in quality gate and only **3
  rejected**.
- **The network the run leaves behind is its best one**, on every metric tracked: `t9-s28711040-d3032547`
  has the best policy-loss and move-prediction accuracy of all 93 exports, and it reached that mark in
  the last three networks produced — a value the run was still climbing toward, not a plateau it had
  settled into.
- **A 19-network stretch where the loss numbers stopped improving turned out not to be a real strength
  stall.** A direct 400-game match between the network from partway through that stretch and the earlier
  loss-record network showed the newer one winning about 74% of the time (roughly +183 rating points) —
  clear, measured improvement the loss metric alone was not showing. The same network beat the very first
  accepted network in all 400 games. This also means a monitoring alarm on one particular loss number was
  retired mid-run because it was found to be tracking how often games end in draws, not how well the
  network is learning — a correction to how the run's health was being read, not a change to the run
  itself.
- Full run history, loss curves, and playable game viewers are linked below.

## What remains open, if training is ever resumed

None of this blocked the stop, and none of it needs attention unless you choose to restart the chain:

- **A disk-saving change was prepared but deliberately not applied.** Right now the loop deletes most
  older self-play games fairly aggressively; a one-line fix that would keep much more game history around
  (at a small, measured disk cost) was written, tested, and confirmed safe, but was left un-applied so it
  wouldn't be a moving part at the same time as the stop. If the chain resumes, this fix is ready to apply
  first (or to discard) — it is a five-minute decision either way, not more analysis.
- **Archiving self-play game records before they get deleted** is still an open decision (unchanged from
  last wave) — relevant again only if the chain resumes and keeps deleting older games.
- Two smaller monitoring/bookkeeping items (an unbounded model-storage folder, one stale comment in a
  config file) are noted but harmless either way.
- The separate, smaller 7x7 test run remains stopped, as you ordered on 2026-09-04; nothing further is
  owed on it.

## Pointers

Loss curve: https://claude.ai/code/artifact/b7a554d2-fff8-49e0-8c9b-020c7ac906bb .
Games viewer — link 1: cycles 1–50 https://claude.ai/code/artifact/1944c772-dd3c-4ba1-97e2-677676f97f0b ,
51–107 https://claude.ai/code/artifact/5c7976d9-53d0-4814-9d64-51b75def54e1 ,
81–157 https://claude.ai/code/artifact/30b1f960-5a0c-468d-b9e7-865c766cc635 . Link 2: cycles 1–40
https://claude.ai/code/artifact/51adbcdc-e12e-40c5-982d-d949b1c238e7 , 41–90
https://claude.ai/code/artifact/dcb5ec16-6854-4385-a588-e2234585fb40 .
`progress/ktg-train/RESEARCH_STATE.md` (mission through-line, final state) ·
`progress/ktg-train/nodal_note.md` (closing 10-iteration window) ·
`progress/ktg-train/loop_notes/current_iter.md` (this wave's verbatim verifier output) ·
`results/ktg/paper_1902.10565/evidence/production_chain/{status_log.txt,CHECKPOINTS.md,c14_match_9x9/,
retention_60/,vloss_escalation_memo.md}` · checkpoint pointer
`results/ktg/paper_1902.10565/evidence/production_chain/CHECKPOINTS.md` ·
`results/ktg/GLOBAL_DAG.md` (regenerated this wave).

# Anchor re-verification transcript - `paper_code_map_training`

Mirror: `ref-code/lightvector-KataGo` @ `v1.18.2` = `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4` (verified with `git -C ref-code/lightvector-KataGo rev-parse HEAD` / `describe --tags`).
Host: `login03` (CPU only, no GPU job). Working directory: `/home/schmidt/ssci-haiyangw/az`.

Each block below is the knowledge-ledger row's own `verification.command`, executed VERBATIM,
followed by the same command with `grep -q` replaced by `grep -n` so the matched source lines are
visible. The `grep -n` form is a derived transcript for human reading; the admission evidence is the
verbatim run and its exit code.

Nodes covered: 8. All exited 0.

## `arxiv-1902.10565::loss_targets_metrics`

- ledger `task_id`: `paper_code_map`
- prior row hash: `cd2853a00461114710f3cfc6415bb701bd2283449e50e6bc51dd9fbfa3e217c2` (status `preliminary`)
- `paper_anchor`: `python/katago/train/metrics_pytorch.py:28-35,84-88,118-323,600-607,838-882; python/train.py:143-149,632-750`

Verbatim command:

```
sed -n 856,882p ref-code/lightvector-KataGo/python/katago/train/metrics_pytorch.py | grep -q 'loss_policy_player \* policy_opt_loss_scale'
```

Result: exit `0`, 0.049 s, stdout+stderr empty (`sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), ran at `2026-09-04T03:40:22+00:00`.

Matched source lines (`grep -q` -> `grep -n`):

```
sed -n 856,882p ref-code/lightvector-KataGo/python/katago/train/metrics_pytorch.py | grep -n 'loss_policy_player \* policy_opt_loss_scale'
--- stdout ---
2:            loss_policy_player * policy_opt_loss_scale
exit 0
```

## `arxiv-1902.10565::head_gpool_degeneracy_9x9`

- ledger `task_id`: `paper_code_map`
- prior row hash: `7e1d21dc5ee989f042dfcb2b17e48c9d4144fb679ecf9757634ce24bf9181a44` (status `preliminary`)
- `paper_anchor`: `python/katago/train/model_pytorch.py:492-543,2647,2711,2745,2855,3157-3160`

Verbatim command:

```
sed -n 534p ref-code/lightvector-KataGo/python/katago/train/model_pytorch.py | grep -q 'torch.sqrt(mask_sum_hw) - 14.0' && sed -n 540p ref-code/lightvector-KataGo/python/katago/train/model_pytorch.py | grep -q '/ 100.0 - 0.1' && python3 -c 'import math; o=math.sqrt(81)-14; assert abs(o/10+0.5)<1e-12 and abs(o*o/100-0.1-0.15)<1e-12'
```

Result: exit `0`, 0.107 s, stdout+stderr empty (`sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), ran at `2026-09-04T03:40:22+00:00`.

Matched source lines (`grep -q` -> `grep -n`):

```
sed -n 534p ref-code/lightvector-KataGo/python/katago/train/model_pytorch.py | grep -n 'torch.sqrt(mask_sum_hw) - 14.0' && sed -n 540p ref-code/lightvector-KataGo/python/katago/train/model_pytorch.py | grep -n '/ 100.0 - 0.1' && python3 -c 'import math; o=math.sqrt(81)-14; assert abs(o/10+0.5)<1e-12 and abs(o*o/100-0.1-0.15)<1e-12'
--- stdout ---
1:        mask_sum_hw_sqrt_offset = torch.sqrt(mask_sum_hw) - 14.0
1:        out_pool3 = layer_mean * ((mask_sum_hw_sqrt_offset * mask_sum_hw_sqrt_offset) / 100.0 - 0.1)
exit 0
```

## `arxiv-1902.10565::train_optimizer_schedule`

- ledger `task_id`: `paper_code_map`
- prior row hash: `2b2e3975abcf78628d05db38b025a3120ac3097420174f5ea22d0a27168173ce` (status `preliminary`)
- `paper_anchor`: `python/train.py:83-114,132,140-143,374,523-564,632-750,840-844,938-942,1046-1141; python/muon/muon.py`

Verbatim command:

```
sed -n 1076,1079p ref-code/lightvector-KataGo/python/train.py | grep -q 2000000 && grep -q 'momentum=0.9' ref-code/lightvector-KataGo/python/train.py
```

Result: exit `0`, 0.068 s, stdout+stderr empty (`sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), ran at `2026-09-04T03:40:22+00:00`.

Matched source lines (`grep -q` -> `grep -n`):

```
sed -n 1076,1079p ref-code/lightvector-KataGo/python/train.py | grep -n 2000000 && grep -n 'momentum=0.9' ref-code/lightvector-KataGo/python/train.py
--- stdout ---
1:        elif train_state["global_step_samples"] < 2000000:
844:                optimizer = torch.optim.SGD(get_param_groups(raw_model,train_state,running_metrics), lr=1.0, momentum=0.9)
942:                optimizer = torch.optim.SGD(get_param_groups(raw_model,train_state,running_metrics), lr=1.0, momentum=0.9)
exit 0
```

## `arxiv-1902.10565::train_resume_semantics`

- ledger `task_id`: `paper_code_map`
- prior row hash: `82069ea795eb29e6a4e74ba9473fabfb937d169792589c707c135ed448b15bd8` (status `preliminary`)
- `paper_anchor`: `python/train.py:81,122,124,434-439,573-578,614-622,780-796,850,1206-1213,1350-1351,1440-1451,1845-1889; python/katago/utils/training_data_generator.py:12-20`

Verbatim command:

```
sed -n 780p ref-code/lightvector-KataGo/python/train.py | grep -q get_checkpoint_path && sed -n 1884p ref-code/lightvector-KataGo/python/train.py | grep -q 'hours=12' && sed -n 850p ref-code/lightvector-KataGo/python/train.py | grep -q 'state_dict\["config"\]'
```

Result: exit `0`, 0.093 s, stdout+stderr empty (`sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), ran at `2026-09-04T03:40:22+00:00`.

Matched source lines (`grep -q` -> `grep -n`):

```
sed -n 780p ref-code/lightvector-KataGo/python/train.py | grep -n get_checkpoint_path && sed -n 1884p ref-code/lightvector-KataGo/python/train.py | grep -n 'hours=12' && sed -n 850p ref-code/lightvector-KataGo/python/train.py | grep -n 'state_dict\["config"\]'
--- stdout ---
1:        if not os.path.exists(get_checkpoint_path()) or always_initial_checkpoint:
1:            if now - last_longterm_checkpoint_save_time >= datetime.timedelta(hours=12):
1:            model_config = state_dict["config"] if "config" in state_dict else modelconfigs.config_of_name[model_kind]
exit 0
```

## `arxiv-1902.10565::data_format_pos_len`

- ledger `task_id`: `paper_code_map`
- prior row hash: `b76e4b5c6b038ba3b2278e716429350b1a6cd48253632a857ebf3aba919de1d8` (status `preliminary`)
- `paper_anchor`: `cpp/dataio/trainingwrite.cpp:288-334,1030,1092-1096,1206-1251; python/shuffle.py:39-47; python/katago/train/data_processing_pytorch.py:91; cpp/configs/training/selfplay1_maxsize9.cfg:10-16; python/selfplay/train.sh:88`

Verbatim command:

```
sed -n 91p ref-code/lightvector-KataGo/python/katago/train/data_processing_pytorch.py | grep -q 'pos_len \* pos_len + 7' && sed -n 88p ref-code/lightvector-KataGo/python/selfplay/train.sh | grep -q -- '-pos-len 19' && python3 -c 'L=9; assert 22*((L*L+7)//8)+76+4*(L*L+1)+320+2*L*L+120+5*L*L+6*(L*L+1)==2145'
```

Result: exit `0`, 0.111 s, stdout+stderr empty (`sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), ran at `2026-09-04T03:40:22+00:00`.

Matched source lines (`grep -q` -> `grep -n`):

```
sed -n 91p ref-code/lightvector-KataGo/python/katago/train/data_processing_pytorch.py | grep -n 'pos_len \* pos_len + 7' && sed -n 88p ref-code/lightvector-KataGo/python/selfplay/train.sh | grep -n -- '-pos-len 19' && python3 -c 'L=9; assert 22*((L*L+7)//8)+76+4*(L*L+1)+320+2*L*L+120+5*L*L+6*(L*L+1)==2145'
--- stdout ---
1:        assert binaryInputNCHW.shape[2] == ((pos_len * pos_len + 7) // 8) * 8
1:     -pos-len 19 \
exit 0
```

## `arxiv-1902.10565::training_window_shuffle`

- ledger `task_id`: `paper_code_map`
- prior row hash: `7fa3b46690fb1a5b84ac48380b5a469f5f4fc03a190724fed148af58ee4fc6ed` (status `preliminary`)
- `paper_anchor`: `python/shuffle.py:420-421,777-791,812-815,862-867,1079-1083,1213-1239,1330-1335; python/selfplay/synchronous_loop.sh:58,63,65-66,105; python/selfplay/cleanup_old_dirs.py:12-24`

Verbatim command:

```
sed -n 1077p ref-code/lightvector-KataGo/python/shuffle.py | grep -q 'min(num_random_rows_capped + num_rows, min_rows)' && sed -n 66p ref-code/lightvector-KataGo/python/selfplay/synchronous_loop.sh | grep -q 'Needs to be larger' && sed -n 801p ref-code/lightvector-KataGo/python/shuffle.py | grep -q 'exclude-qvalues'
```

Result: exit `0`, 0.092 s, stdout+stderr empty (`sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), ran at `2026-09-04T03:40:23+00:00`.

Matched source lines (`grep -q` -> `grep -n`):

```
sed -n 1077p ref-code/lightvector-KataGo/python/shuffle.py | grep -n 'min(num_random_rows_capped + num_rows, min_rows)' && sed -n 66p ref-code/lightvector-KataGo/python/selfplay/synchronous_loop.sh | grep -n 'Needs to be larger' && sed -n 801p ref-code/lightvector-KataGo/python/shuffle.py | grep -n 'exclude-qvalues'
--- stdout ---
1:                num_random_rows_capped = min(num_random_rows_capped + num_rows, min_rows)
1:SHUFFLE_KEEPROWS=600000 # Needs to be larger than MAX_TRAIN_SAMPLES_PER_CYCLE, so the shuffler samples enough rows each cycle for the training to use.
1:    optional_args.add_argument('-exclude-qvalues', action="store_true", required=False, help='Exclude Q-value targets (for backwards compatibility with pre-v1.16)')
exit 0
```

## `arxiv-1902.10565::transformer_trunk_b7c96h3tfrs`

- ledger `task_id`: `paper_code_map`
- prior row hash: `1530e3fdfa8ab36d89248afe2d85898f669d3225df6a441bda5d7b9337bead1c` (status `preliminary`)
- `paper_anchor`: `python/katago/train/modelconfigs.py:1008-1029,1887; python/katago/train/model_pytorch.py:2108-2171,3231-3239,3269-3276; python/export_model_pytorch.py:42-43,461,491-494`

Verbatim command:

```
sed -n 1021p ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py | grep -q '"ffnsg"' && sed -n 1887p ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py | grep -q '"b7c96h3tfrs"' && sed -n 1008p ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py | grep -q 'b7c96h3tfrs = {' && sed -n 3308p ref-code/lightvector-KataGo/cpp/neuralnet/cudaandrocmbackend.inc | grep -q 'Non-SwiGLU'
```

Result: exit `0`, 0.123 s, stdout+stderr empty (`sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), ran at `2026-09-04T03:40:23+00:00`.

Matched source lines (`grep -q` -> `grep -n`):

```
sed -n 1021p ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py | grep -n '"ffnsg"' && sed -n 1887p ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py | grep -n '"b7c96h3tfrs"' && sed -n 1008p ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py | grep -n 'b7c96h3tfrs = {' && sed -n 3308p ref-code/lightvector-KataGo/cpp/neuralnet/cudaandrocmbackend.inc | grep -n 'Non-SwiGLU'
--- stdout ---
1:    "block_kind": [item for i in range(1,8) for item in [[f"attn{i}","attnrope"],[f"ffn{i}","ffnsg"]]],
1:    "b7c96h3tfrs": b7c96h3tfrs,
1:b7c96h3tfrs = {
1:      throw StringError("Non-SwiGLU transformer FFN is not yet supported in " KATAGO_GPU_BACKEND_NAME " backend");
exit 0
```

## `arxiv-1902.10565::select_transformer_ladder`

- ledger `task_id`: `select_transformer_ladder`
- prior row hash: `a74c9c2f294a5c137e597f80f524e2dd3953ec35ea5e25e4ed56c9e385778e18` (status `preliminary`)
- `paper_anchor`: `python/katago/train/modelconfigs.py:1008-1029,1057-1077,1453,1886-1895; python/train.py:850`

Verbatim command:

```
sed -n 1886p ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py | grep -q '"b5c48h3tfr": b5c48h3tfr,  # no swiglu' && grep -q '"b8c96h3tfrs": b8c96h3tfrs' ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py && grep -q '"b14c192h6tfrs": b14c192h6tfrs' ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py && sed -n 1021p ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py | grep -q ffnsg && sed -n 1070p ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py | grep -q ffnsg && sed -n 850p ref-code/lightvector-KataGo/python/train.py | grep -q 'state_dict\["config"\]'
```

Result: exit `0`, 0.16 s, stdout+stderr empty (`sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), ran at `2026-09-04T03:40:23+00:00`.

Matched source lines (`grep -q` -> `grep -n`):

```
sed -n 1886p ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py | grep -n '"b5c48h3tfr": b5c48h3tfr,  # no swiglu' && grep -n '"b8c96h3tfrs": b8c96h3tfrs' ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py && grep -n '"b14c192h6tfrs": b14c192h6tfrs' ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py && sed -n 1021p ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py | grep -n ffnsg && sed -n 1070p ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py | grep -n ffnsg && sed -n 850p ref-code/lightvector-KataGo/python/train.py | grep -n 'state_dict\["config"\]'
--- stdout ---
1:    "b5c48h3tfr": b5c48h3tfr,  # no swiglu
1889:    "b8c96h3tfrs": b8c96h3tfrs,
1894:    "b14c192h6tfrs": b14c192h6tfrs,
1:    "block_kind": [item for i in range(1,8) for item in [[f"attn{i}","attnrope"],[f"ffn{i}","ffnsg"]]],
1:    "block_kind": [item for i in range(1,9) for item in [[f"attn{i}","attnrope"],[f"ffn{i}","ffnsg"]]],
1:            model_config = state_dict["config"] if "config" in state_dict else modelconfigs.config_of_name[model_kind]
exit 0
```


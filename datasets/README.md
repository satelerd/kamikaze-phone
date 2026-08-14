# Motion dataset workspace

`datasets/inbox/` stores local, full-resolution imports from devices and message
gateways. It is intentionally ignored by Git: these exports are large working
sets, not automatically approved golden fixtures.

For each import:

1. preserve the source bytes and record their SHA-256;
2. validate schema, IDs, sample counts, timestamps, sequence continuity and
   embedded payload checksums;
3. compare human labels against detector output;
4. promote only reviewed captures to `fixtures/motion/` with manifest entries;
5. keep evaluation and holdout captures separate before tuning recognition.

Never treat `automaticObservation` as ground truth. The human label and outcome
are the reference annotations.

Run the native evaluator from the repository root:

```sh
swift run --package-path apps/ios/Packages/KamikazeMotionCore \
  kamikaze-motion-eval \
  --dataset datasets/inbox/2026-08-13-whatsapp/kamikaze-labelled-dataset-v1.json \
  --split-manifest datasets/splits/iphone15plus-right-2026-08-13-v1.json \
  --set holdout
```

The split manifest is versioned; the full source export remains local. Never
move an ID between development and holdout after inspecting matcher results.

Independent physical-session reports live in `datasets/evaluations/`. Session
2 is a permanent holdout: do not tune against its captures and then continue to
describe it as independent validation.

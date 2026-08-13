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

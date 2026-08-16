# Motion fixture dataset v3

This manifest is the verified index for the native schema-v3 dataset. Its first
entries intentionally reference the immutable Expo schema-v2 captures rather
than copying or rewriting their raw bytes.

The two current entries are `seed` evidence for migration, replay and early
classification regression only. They are manually bounded attempts, so they
must not be used as automatic-segmentation or accuracy evidence.

Every future entry must declare its raw-byte SHA-256, payload schema, intended
uses, split, canonical trick ID or negative outcome, and capture provenance.
Use a `sensor-session` fixture (with armed pre-roll and stable post-roll) for
automatic segmentation. Keep `labelled-attempt` for manually bounded replay,
migration and label evidence.

# Active applications

The two active implementations deliberately live side by side:

- `expo/`: the complete React Native alpha and the place for Android/community work.
- `ios/`: the native Swift beta and the primary iOS product track.

They may evolve at different speeds. Do not import one application's UI or persistence layer directly into the other. Share reviewed sensor evidence through `/fixtures` and describe intentional detector-contract changes in the pull request.

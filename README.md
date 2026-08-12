# Kamikaze: Phone Flip

Inspirado en Kamikaze Phone, la idea de Kamikaze Phone-Flip es crear un app que registre cuando uno hace un phone-flip y te marque si lo hiciste mal o si lo hiciste bien, tambien se podria ir registrando un historial, tamb con la altura maxima que alcanza durante el flip.

## Mobile game prototype

The Expo app lives in [`mobile/`](mobile/README.md). It captures real device motion, detects and classifies phone tricks, reconstructs quaternion replays and now includes a gameplay-first prototype with onboarding, Play, Practice, Locker and Profile.

The original sensor/testing experience is preserved at Git tag `testing-v0.2.0`; the official game-experience work continues independently from that stable baseline.

The complete playable Expo experience is frozen at Git tag `expo-game-v0.3.0`. The official product will be rebuilt natively in SwiftUI; the implementation sequence, architecture and parity gates are documented in [`docs/NATIVE_SWIFT_MIGRATION.md`](docs/NATIVE_SWIFT_MIGRATION.md).

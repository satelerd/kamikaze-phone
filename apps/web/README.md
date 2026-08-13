# KAMIKAZE PHONE 📱🤙

Throw your phone. Land tricks. Trust the towel.

The original idea (registrar un phone-flip y marcar si lo hiciste bien, con historial y
altura máxima) grew into a full sensor-driven game: your phone is the console AND the
controller. Every sensor it has becomes a game mechanic, a radical 90s California surfer
narrates your session, and every trick is reconstructed in 3D.

## Modes

| Mode | What it is | Sensors |
|---|---|---|
| 🌊 Free Ride | Open session, live narrator commentary on every throw | IMU |
| 🎥 Trick Lab | Slow-mo video + 3D trajectory viz + DA3 export | IMU + camera |
| 🛹 Rail Grind | Slide down a metal rail, the magnetometer feels the steel | IMU + magnetometer |
| 🧲 Fridge Surfer | Land on a MacBook or any magnetic surface | IMU + magnetometer |
| 🌒 Eclipse | Throw through darkness, the light sensor times your blackout | IMU + ambient light |
| 📣 Scream Meter | Hype scream = score multiplier | IMU + mic |
| 🔋 Charger Bullseye | Toss it onto the wireless charger, charging = bullseye | IMU + battery |
| 📍 NFC Spots | Claim skate-spots with NFC tags | IMU + NFC |
| 🥔 Hot Potato | Party mode: fuse, narrated names, eliminations. Wrap it in a towel | IMU + TTS |
| 🤝 Co-op Sync | Two phones, one trick: coordination is the score | IMU + WebRTC |

Plus achievements, a 5-dimension style scoring system (way more than a score), an
ElevenLabs soundtrack + SFX, and Bodhi Bytes, the surfer narrator (mutable, and can go
LIVE as a real ElevenLabs conversational agent).

## Run it

```bash
npm install
npm run dev              # then open it on your phone (same network) or use desktop demo buttons
npm run verify:physics   # 51 assertions: synthetic throws through the trick engine
npm run audio:generate   # regenerate soundtrack/SFX (needs ELEVENLABS_API_KEY)
```

Full plan, goals and acceptance criteria: [docs/PLAN.md](docs/PLAN.md).
Compatibility policy: features are gated by live capability detection, never by
platform. iPhone and Pixel both play; Android Chrome unlocks the most sensors.

⚠️ Disclaimer: you are throwing your own phone. Wrap it in a towel. We warned you.

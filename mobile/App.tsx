import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { useKeepAwake } from 'expo-keep-awake';
import {
  ArchivoBlack_400Regular,
  useFonts as useArchivoFonts,
} from '@expo-google-fonts/archivo-black';
import {
  SpaceGrotesk_400Regular,
  SpaceGrotesk_600SemiBold,
  SpaceGrotesk_700Bold,
  useFonts as useSpaceFonts,
} from '@expo-google-fonts/space-grotesk';
import {
  IBMPlexMono_400Regular,
  IBMPlexMono_600SemiBold,
  useFonts as useMonoFonts,
} from '@expo-google-fonts/ibm-plex-mono';

import { AttemptCard } from './src/components/AttemptCard';
import { AxisMeter } from './src/components/AxisMeter';
import { CalibrationHub } from './src/components/CalibrationHub';
import { FlightRing } from './src/components/FlightRing';
import { LivePoseMonitor } from './src/components/LivePoseMonitor';
import { PhoneReplay } from './src/components/PhoneReplay';
import { ScrollLockContext } from './src/components/ScrollLock';
import { useMotionLab } from './src/hooks/useMotionLab';
import { useTrickCatalog, type TrickCatalogController } from './src/hooks/useTrickCatalog';
import { findBestTrickMatch } from './src/motion/trickCatalog';
import type { DetectedAttempt } from './src/motion/types';
import { colors, fonts } from './src/theme';

type Tab = 'play' | 'dojo' | 'cal' | 'lab';

const sensorStatusCopy = {
  checking: 'PERMISSION NEEDED',
  ready: '100HZ REQUESTED',
  denied: 'ACCESS DENIED',
  unavailable: 'NO SENSOR',
  error: 'SENSOR OFFLINE',
} as const;

function Header({ tab, onChange }: { tab: Tab; onChange: (tab: Tab) => void }) {
  return (
    <View style={styles.header}>
      <View>
        <Text style={styles.brand}>KAMIKAZE</Text>
        <Text style={styles.brandSub}>PHONE / PROTO 01</Text>
      </View>
      <View style={styles.tabs}>
        {(['play', 'dojo', 'cal', 'lab'] as Tab[]).map((item) => (
          <Pressable
            accessibilityRole="tab"
            accessibilityState={{ selected: tab === item }}
            hitSlop={8}
            key={item}
            onPress={() => onChange(item)}
            style={[styles.tab, tab === item && styles.tabActive]}
          >
            <Text style={[styles.tabText, tab === item && styles.tabTextActive]}>
              {item.toUpperCase()}
            </Text>
          </Pressable>
        ))}
      </View>
    </View>
  );
}

function PrimaryButton({ label, onPress, tone = 'blue' }: {
  label: string;
  onPress: () => void;
  tone?: 'blue' | 'black' | 'paper';
}) {
  const backgroundColor = tone === 'blue'
    ? colors.cobalt
    : tone === 'black'
      ? colors.asphalt
      : colors.paper;
  const color = tone === 'paper' ? colors.asphalt : colors.white;

  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => [
        styles.primaryButton,
        { backgroundColor, transform: [{ translateX: pressed ? 3 : 0 }, { translateY: pressed ? 3 : 0 }] },
      ]}
    >
      <Text style={[styles.primaryButtonText, { color }]}>{label}</Text>
      <Text style={[styles.arrow, { color }]}>↗</Text>
    </Pressable>
  );
}

function PlayView({
  catalog,
  motion,
  onOpenReplay,
}: {
  catalog: TrickCatalogController;
  motion: ReturnType<typeof useMotionLab>;
  onOpenReplay: () => void;
}) {
  const [recordMode, setRecordMode] = useState<'auto' | 'manual'>('auto');
  const [showReplay, setShowReplay] = useState(false);
  const { snapshot, sensorStatus, arm, disarm } = motion;
  const isSessionActive = ['armed', 'airborne', 'settling'].includes(snapshot.phase);
  const trickMatch = snapshot.lastAttempt
    ? findBestTrickMatch(snapshot.lastAttempt, catalog.definitions)
    : null;
  const instruction = recordMode === 'manual'
    ? motion.manualRecording
      ? 'Recording every sensor sample. Do the trick, catch it, wait a beat, then stop.'
      : 'Manual mode ignores freefall. Start, perform one clean trick, then stop after the catch.'
    : snapshot.phase === 'armed'
    ? 'Throw over something soft. The session starts automatically in freefall.'
    : snapshot.phase === 'airborne'
      ? 'Tracking rotation.'
      : snapshot.phase === 'settling'
        ? 'Keep the phone still for a clean catch.'
        : 'Arm one attempt. Throw. Catch. Read the score.';

  useEffect(() => {
    setShowReplay(false);
  }, [snapshot.lastAttempt?.id]);

  return (
    <>
      <View style={styles.heroCopy}>
        <Text style={styles.kicker}>REAL MOTION / NO CAMERA</Text>
        <Text style={styles.headline}>THROW.{`\n`}CATCH.{`\n`}REPEAT.</Text>
      </View>

      <View style={styles.ringWrap}>
        <FlightRing
          accelG={snapshot.accelG}
          gyroDps={snapshot.gyroDps}
          phase={snapshot.phase}
          rotation={snapshot.rotationDegrees.total}
        />
      </View>

      <Text style={styles.instruction}>{instruction}</Text>

      <View style={styles.captureModeSwitch}>
        {(['auto', 'manual'] as const).map((mode) => (
          <Pressable
            disabled={isSessionActive || motion.manualRecording}
            key={mode}
            onPress={() => setRecordMode(mode)}
            style={[styles.captureModeButton, recordMode === mode && styles.captureModeButtonActive]}
          >
            <Text style={[styles.captureModeText, recordMode === mode && styles.captureModeTextActive]}>
              {mode === 'auto' ? 'AUTO / SENSOR' : 'MANUAL / WINDOW'}
            </Text>
          </Pressable>
        ))}
      </View>

      <View style={styles.statusLine}>
        <View style={[styles.statusDot, sensorStatus === 'ready' && styles.statusDotReady]} />
        <Text style={styles.statusText}>{sensorStatusCopy[sensorStatus]}</Text>
        <Text style={styles.statusHz}>
          {sensorStatus === 'ready' && snapshot.actualHz > 0
            ? `${Math.round(snapshot.actualHz)}HZ LIVE`
            : snapshot.lastAttempt
              ? 'SIMULATED'
              : 'WAITING'}
        </Text>
      </View>

      {recordMode === 'manual' && motion.manualRecording ? (
        <>
          <View style={styles.manualTimecode}>
            <View style={styles.recordDot} />
            <Text style={styles.manualTime}>{(motion.manualElapsedMs / 1000).toFixed(2)}S REC</Text>
          </View>
          <PrimaryButton label="STOP + ANALYZE" onPress={() => { motion.stopManualCapture(); }} tone="black" />
          <Pressable onPress={motion.cancelManualCapture} style={styles.cancelManual}>
            <Text style={styles.cancelManualText}>CANCEL RECORDING</Text>
          </Pressable>
        </>
      ) : recordMode === 'manual' ? (
        <PrimaryButton label="START MANUAL CAPTURE" onPress={() => { motion.startManualCapture(); }} />
      ) : isSessionActive ? (
        <PrimaryButton label="CANCEL ATTEMPT" onPress={disarm} tone="black" />
      ) : (
        <PrimaryButton label={snapshot.phase === 'complete' ? 'ARM NEXT ATTEMPT' : 'ARM ONE ATTEMPT'} onPress={() => { arm(); }} />
      )}

      {snapshot.lastAttempt ? (
        <>
          <AttemptCard attempt={snapshot.lastAttempt} match={trickMatch} />
          <Pressable onPress={() => setShowReplay((value) => !value)} style={styles.replayToggle}>
            <Text style={styles.replayToggleText}>{showReplay ? 'HIDE REPLAY' : 'WATCH REPLAY HERE'}</Text>
            <Text style={styles.replayToggleText}>{showReplay ? '↑' : '↓'}</Text>
          </Pressable>
          {showReplay && (
            <PhoneReplay
              attempt={snapshot.lastAttempt}
              targetDefinition={trickMatch?.definition}
              targetTrick={trickMatch?.definition.name ?? snapshot.lastAttempt.trick}
            />
          )}
          <View style={styles.secondaryAction}>
            <PrimaryButton label="OPEN SESSION TAPE" onPress={onOpenReplay} tone="paper" />
          </View>
        </>
      ) : (
        <View style={styles.emptyCard}>
          <Text style={styles.emptyNumber}>—</Text>
          <View style={styles.emptyCopy}>
            <Text style={styles.emptyTitle}>NO LINE YET</Text>
            <Text style={styles.emptyBody}>Your first completed trick will leave one score and a replay here.</Text>
          </View>
        </View>
      )}

      {!showReplay && (
        <LivePoseMonitor
          actualHz={snapshot.actualHz}
          quaternion={motion.liveQuaternion}
          ready={sensorStatus === 'ready'}
        />
      )}
    </>
  );
}

const trainingTricks = ['PHONE FLIP'];

function HistoryRow({
  attempt,
  match,
  selected,
  onPress,
}: {
  attempt: DetectedAttempt;
  match: ReturnType<typeof findBestTrickMatch>;
  selected: boolean;
  onPress: () => void;
}) {
  const time = new Date(attempt.recordedAtIso).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
  });

  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={[styles.historyRow, selected && styles.historyRowSelected]}
    >
      <View style={styles.historyIndex}>
        <Text style={[styles.historyIndexText, selected && styles.historyIndexTextSelected]}>
          {attempt.source === 'synthetic' ? 'SIM' : time}
        </Text>
      </View>
      <View style={styles.historyCopy}>
        <Text style={[styles.historyTrick, selected && styles.historyTrickSelected]}>{match.definition.name}</Text>
        <Text style={[styles.historyMeta, selected && styles.historyMetaSelected]}>
          {Math.round(match.overallScore * 100)} SCORE / {(match.motionDurationMs / 1000).toFixed(2)}S
        </Text>
      </View>
      <Text style={[styles.historyArrow, selected && styles.historyTrickSelected]}>→</Text>
    </Pressable>
  );
}

function DojoView({ catalog, motion }: { catalog: TrickCatalogController; motion: ReturnType<typeof useMotionLab> }) {
  const { attempts, historyReady } = motion;
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [targetTrick, setTargetTrick] = useState(catalog.definitions[1]?.name ?? trainingTricks[0]);
  const selectedAttempt = attempts.find((attempt) => attempt.id === selectedId) ?? attempts[0] ?? null;
  const selectedMatch = selectedAttempt
    ? findBestTrickMatch(selectedAttempt, catalog.definitions)
    : null;
  const targetDefinition = catalog.definitions.find(({ name }) => name === targetTrick) ?? selectedMatch?.definition;

  useEffect(() => {
    if (selectedId === null && attempts[0]) {
      setTargetTrick(findBestTrickMatch(attempts[0], catalog.definitions).definition.name);
    }
  }, [attempts, catalog.definitions, selectedId]);

  return (
    <>
      <View style={styles.dojoHero}>
        <Text style={styles.kicker}>DOJO / WATCH. TRY. TEACH.</Text>
        <Text style={styles.dojoTitle}>REPLAY{`\n`}YOUR TRICK.</Text>
        <Text style={styles.dojoIntro}>
          Rotation comes from the gyro. Position stays locked until translation can be reconstructed honestly.
        </Text>
      </View>

      <PhoneReplay
        attempt={selectedAttempt}
        targetDefinition={targetDefinition}
        targetTrick={targetTrick}
      />

      <View style={styles.targetSection}>
        <Text style={styles.sectionLabel}>CHOOSE A TARGET</Text>
        <View style={styles.targetTricks}>
          {catalog.definitions.filter(({ family }) => family !== 'air').map((definition) => (
            <Pressable
              accessibilityRole="button"
              key={definition.id}
              onPress={() => setTargetTrick(definition.name)}
              style={[styles.targetChip, targetTrick === definition.name && styles.targetChipActive]}
            >
              <Text style={[styles.targetChipText, targetTrick === definition.name && styles.targetChipTextActive]}>
                {definition.name}
              </Text>
            </Pressable>
          ))}
        </View>
        <Text style={styles.targetHint}>Switch to Target to watch it, then go to Play and make your version.</Text>
      </View>

      <View style={styles.historyHeader}>
        <Text style={styles.sectionLabel}>SESSION TAPE</Text>
        <Text style={styles.historyCount}>{historyReady ? `${attempts.length} SAVED` : 'LOADING'}</Text>
      </View>
      {attempts.length > 0 ? attempts.slice(0, 12).map((attempt) => (
        <HistoryRow
          attempt={attempt}
          key={attempt.id}
          match={findBestTrickMatch(attempt, catalog.definitions)}
          onPress={() => {
            setSelectedId(attempt.id);
            setTargetTrick(findBestTrickMatch(attempt, catalog.definitions).definition.name);
          }}
          selected={selectedAttempt?.id === attempt.id}
        />
      )) : (
        <View style={styles.dojoEmpty}>
          <Text style={styles.dojoEmptyMark}>↗</Text>
          <View style={styles.emptyCopy}>
            <Text style={styles.emptyTitle}>NO SAVED LINES</Text>
            <Text style={styles.emptyBody}>Your next completed catch will appear here with its raw motion path.</Text>
          </View>
        </View>
      )}
    </>
  );
}

function SparkBars({ points }: { points: { accelG: number; gyroDps: number }[] }) {
  return (
    <View style={styles.sparkBars}>
      {Array.from({ length: 28 }).map((_, index) => {
        const point = points[index];
        const height = point ? Math.min(54, 4 + point.gyroDps / 32 + point.accelG * 4) : 4;
        return <View key={index} style={[styles.sparkBar, { height }]} />;
      })}
    </View>
  );
}

function LabView({ motion }: { motion: ReturnType<typeof useMotionLab> }) {
  const { snapshot, sensorStatus, history, requestPermission, simulate } = motion;

  return (
    <>
      <View style={styles.labTitleRow}>
        <View>
          <Text style={styles.kicker}>MOTION LAB / RAW SIGNAL</Text>
          <Text style={styles.labTitle}>KNOW YOUR{`\n`}THREE AXES.</Text>
        </View>
        <View style={styles.liveBadge}>
          <Text style={styles.liveBadgeTop}>{Math.round(snapshot.actualHz || 0)}</Text>
          <Text style={styles.liveBadgeBottom}>HZ</Text>
        </View>
      </View>

      <View style={styles.labPanel}>
        <View style={styles.labPanelHeader}>
          <Text style={styles.panelLabel}>ROTATION PATH</Text>
          <Text style={styles.panelValue}>{snapshot.sampleCount} SAMPLES</Text>
        </View>
        <AxisMeter axis="X" value={snapshot.rotationDegrees.x} accent />
        <AxisMeter axis="Y" value={snapshot.rotationDegrees.y} />
        <AxisMeter axis="Z" value={snapshot.rotationDegrees.z} />
      </View>

      <View style={styles.signalPanel}>
        <View style={styles.labPanelHeader}>
          <Text style={styles.panelLabel}>LIVE ENERGY</Text>
          <Text style={styles.panelValue}>{snapshot.accelG.toFixed(2)}G / {Math.round(snapshot.gyroDps)}°S</Text>
        </View>
        <SparkBars points={history} />
        <View style={styles.signalLegend}>
          <Text style={styles.legendText}>−280MS</Text>
          <Text style={styles.legendText}>NOW</Text>
        </View>
      </View>

      <View style={styles.note}>
        <Text style={styles.noteMark}>!</Text>
        <Text style={styles.noteText}>
          X crosses the width, Y follows the long edge, Z exits through the screen. X is the unstable flip axis.
        </Text>
      </View>

      {sensorStatus !== 'ready' && (
        <PrimaryButton label="ENABLE MOTION SENSOR" onPress={() => { requestPermission(); }} />
      )}
      <View style={sensorStatus !== 'ready' && styles.secondaryAction}>
        <PrimaryButton label="SIMULATE PHONE FLIP" onPress={simulate} tone="paper" />
      </View>
      <Text style={styles.labFootnote}>Synthetic mode verifies the detector and UI. Real values require a physical phone.</Text>
    </>
  );
}

export default function App() {
  useKeepAwake('kamikaze-session');
  const [tab, setTab] = useState<Tab>('play');
  const [scrollLocked, setScrollLocked] = useState(false);
  const motion = useMotionLab();
  const catalog = useTrickCatalog();
  const [archivoLoaded] = useArchivoFonts({ ArchivoBlack_400Regular });
  const [spaceLoaded] = useSpaceFonts({
    SpaceGrotesk_400Regular,
    SpaceGrotesk_600SemiBold,
    SpaceGrotesk_700Bold,
  });
  const [monoLoaded] = useMonoFonts({ IBMPlexMono_400Regular, IBMPlexMono_600SemiBold });

  if (!archivoLoaded || !spaceLoaded || !monoLoaded) {
    return (
      <View style={styles.loading}>
        <ActivityIndicator color={colors.cobalt} />
      </View>
    );
  }

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <ScrollLockContext.Provider value={setScrollLocked}>
        <ScrollView
          contentContainerStyle={styles.content}
          scrollEnabled={!scrollLocked}
          showsVerticalScrollIndicator={false}
        >
          <Header tab={tab} onChange={setTab} />
          {tab === 'play' && <PlayView catalog={catalog} motion={motion} onOpenReplay={() => setTab('dojo')} />}
          {tab === 'dojo' && <DojoView catalog={catalog} motion={motion} />}
          {tab === 'cal' && <CalibrationHub catalog={catalog} motion={motion} />}
          {tab === 'lab' && <LabView motion={motion} />}
          <Text style={styles.footer}>KPF / SENSOR BUILD 0003</Text>
        </ScrollView>
      </ScrollLockContext.Provider>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    backgroundColor: colors.chalk,
    flex: 1,
  },
  content: {
    paddingBottom: 42,
    paddingHorizontal: 20,
  },
  loading: {
    alignItems: 'center',
    backgroundColor: colors.chalk,
    flex: 1,
    justifyContent: 'center',
  },
  header: {
    alignItems: 'flex-start',
    borderBottomColor: colors.asphalt,
    borderBottomWidth: 1.5,
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingBottom: 14,
    paddingTop: 8,
  },
  brand: {
    color: colors.asphalt,
    fontFamily: fonts.display,
    fontSize: 18,
    letterSpacing: -0.5,
  },
  brandSub: {
    color: colors.concrete,
    fontFamily: fonts.mono,
    fontSize: 8,
    letterSpacing: 1.2,
    marginTop: 2,
  },
  tabs: {
    flexDirection: 'row',
    gap: 4,
  },
  tab: {
    borderColor: colors.asphalt,
    borderWidth: 1,
    paddingHorizontal: 8,
    paddingVertical: 8,
  },
  tabActive: {
    backgroundColor: colors.asphalt,
  },
  tabText: {
    color: colors.asphalt,
    fontFamily: fonts.monoBold,
    fontSize: 8,
    letterSpacing: 1,
  },
  tabTextActive: {
    color: colors.chalk,
  },
  heroCopy: {
    marginTop: 26,
  },
  kicker: {
    color: colors.cobalt,
    fontFamily: fonts.monoBold,
    fontSize: 9,
    letterSpacing: 1.5,
  },
  headline: {
    color: colors.asphalt,
    fontFamily: fonts.display,
    fontSize: 48,
    letterSpacing: -2.2,
    lineHeight: 45,
    marginTop: 9,
  },
  ringWrap: {
    alignItems: 'center',
    marginBottom: 12,
    marginTop: 16,
  },
  instruction: {
    color: colors.asphalt,
    fontFamily: fonts.body,
    fontSize: 14,
    lineHeight: 20,
    marginBottom: 14,
    minHeight: 40,
  },
  captureModeSwitch: {
    borderColor: colors.asphalt,
    borderWidth: 1,
    flexDirection: 'row',
    marginBottom: 14,
  },
  captureModeButton: {
    flex: 1,
    paddingHorizontal: 8,
    paddingVertical: 11,
  },
  captureModeButtonActive: {
    backgroundColor: colors.asphalt,
  },
  captureModeText: {
    color: colors.concrete,
    fontFamily: fonts.monoBold,
    fontSize: 7,
    letterSpacing: 0.55,
    textAlign: 'center',
  },
  captureModeTextActive: {
    color: colors.white,
  },
  manualTimecode: {
    alignItems: 'center',
    backgroundColor: colors.coral,
    flexDirection: 'row',
    gap: 9,
    justifyContent: 'center',
    marginTop: 4,
    paddingVertical: 11,
  },
  recordDot: {
    backgroundColor: colors.white,
    borderRadius: 5,
    height: 9,
    width: 9,
  },
  manualTime: {
    color: colors.white,
    fontFamily: fonts.monoBold,
    fontSize: 10,
    letterSpacing: 1,
  },
  cancelManual: {
    alignItems: 'center',
    paddingVertical: 13,
  },
  cancelManualText: {
    color: colors.concrete,
    fontFamily: fonts.monoBold,
    fontSize: 8,
  },
  statusLine: {
    alignItems: 'center',
    borderTopColor: colors.asphalt,
    borderTopWidth: 1,
    flexDirection: 'row',
    paddingVertical: 12,
  },
  statusDot: {
    backgroundColor: colors.coral,
    height: 8,
    marginRight: 8,
    width: 8,
  },
  statusDotReady: {
    backgroundColor: colors.cobalt,
  },
  statusText: {
    color: colors.asphalt,
    fontFamily: fonts.monoBold,
    fontSize: 9,
    letterSpacing: 0.8,
  },
  statusHz: {
    color: colors.concrete,
    fontFamily: fonts.mono,
    fontSize: 9,
    marginLeft: 'auto',
  },
  primaryButton: {
    alignItems: 'center',
    borderColor: colors.asphalt,
    borderWidth: 1.5,
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginRight: 4,
    marginTop: 4,
    paddingHorizontal: 18,
    paddingVertical: 17,
    shadowColor: colors.asphalt,
    shadowOffset: { width: 4, height: 4 },
    shadowOpacity: 1,
    shadowRadius: 0,
  },
  primaryButtonText: {
    fontFamily: fonts.bodyBold,
    fontSize: 14,
    letterSpacing: 0.5,
  },
  arrow: {
    fontFamily: fonts.body,
    fontSize: 20,
  },
  emptyCard: {
    alignItems: 'center',
    borderColor: colors.concrete,
    borderStyle: 'dashed',
    borderWidth: 1,
    flexDirection: 'row',
    marginTop: 24,
    padding: 18,
  },
  emptyNumber: {
    color: colors.concrete,
    fontFamily: fonts.display,
    fontSize: 36,
    marginRight: 16,
  },
  emptyCopy: {
    flex: 1,
  },
  emptyTitle: {
    color: colors.asphalt,
    fontFamily: fonts.bodyBold,
    fontSize: 13,
  },
  emptyBody: {
    color: colors.concrete,
    fontFamily: fonts.body,
    fontSize: 12,
    lineHeight: 17,
    marginTop: 3,
  },
  labTitleRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 28,
  },
  labTitle: {
    color: colors.asphalt,
    fontFamily: fonts.display,
    fontSize: 37,
    letterSpacing: -1.7,
    lineHeight: 38,
    marginTop: 10,
  },
  liveBadge: {
    alignItems: 'center',
    backgroundColor: colors.coral,
    height: 70,
    justifyContent: 'center',
    transform: [{ rotate: '3deg' }],
    width: 70,
  },
  liveBadgeTop: {
    color: colors.white,
    fontFamily: fonts.display,
    fontSize: 25,
  },
  liveBadgeBottom: {
    color: colors.white,
    fontFamily: fonts.monoBold,
    fontSize: 9,
  },
  labPanel: {
    backgroundColor: colors.paper,
    borderColor: colors.asphalt,
    borderWidth: 1.5,
    marginTop: 30,
    padding: 18,
  },
  signalPanel: {
    backgroundColor: colors.asphalt,
    marginTop: 14,
    padding: 18,
  },
  labPanelHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 20,
  },
  panelLabel: {
    color: colors.concrete,
    fontFamily: fonts.monoBold,
    fontSize: 9,
    letterSpacing: 1.2,
  },
  panelValue: {
    color: colors.concrete,
    fontFamily: fonts.mono,
    fontSize: 9,
  },
  sparkBars: {
    alignItems: 'flex-end',
    flexDirection: 'row',
    gap: 3,
    height: 58,
  },
  sparkBar: {
    backgroundColor: colors.cobalt,
    flex: 1,
    minWidth: 2,
  },
  signalLegend: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 8,
  },
  legendText: {
    color: '#77786F',
    fontFamily: fonts.mono,
    fontSize: 8,
  },
  note: {
    alignItems: 'flex-start',
    borderBottomColor: colors.asphalt,
    borderBottomWidth: 1,
    flexDirection: 'row',
    gap: 13,
    marginBottom: 20,
    paddingVertical: 20,
  },
  noteMark: {
    color: colors.coral,
    fontFamily: fonts.display,
    fontSize: 25,
    lineHeight: 25,
  },
  noteText: {
    color: colors.asphalt,
    flex: 1,
    fontFamily: fonts.body,
    fontSize: 13,
    lineHeight: 19,
  },
  labFootnote: {
    color: colors.concrete,
    fontFamily: fonts.mono,
    fontSize: 9,
    lineHeight: 14,
    marginTop: 13,
  },
  footer: {
    color: colors.concrete,
    fontFamily: fonts.mono,
    fontSize: 8,
    letterSpacing: 1,
    marginTop: 38,
    textAlign: 'center',
  },
  secondaryAction: {
    marginTop: 12,
  },
  replayToggle: {
    alignItems: 'center',
    borderColor: colors.asphalt,
    borderWidth: 1.5,
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 12,
    paddingHorizontal: 14,
    paddingVertical: 13,
  },
  replayToggleText: {
    color: colors.asphalt,
    fontFamily: fonts.monoBold,
    fontSize: 8,
    letterSpacing: 0.7,
  },
  dojoHero: {
    marginTop: 27,
  },
  dojoTitle: {
    color: colors.asphalt,
    fontFamily: fonts.display,
    fontSize: 43,
    letterSpacing: -2,
    lineHeight: 42,
    marginTop: 10,
  },
  dojoIntro: {
    color: colors.asphalt,
    fontFamily: fonts.body,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 13,
    maxWidth: 320,
  },
  targetSection: {
    borderBottomColor: colors.asphalt,
    borderBottomWidth: 1,
    paddingBottom: 20,
    paddingTop: 24,
  },
  sectionLabel: {
    color: colors.asphalt,
    fontFamily: fonts.monoBold,
    fontSize: 9,
    letterSpacing: 1.3,
  },
  targetTricks: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 7,
    marginTop: 12,
  },
  targetChip: {
    borderColor: colors.asphalt,
    borderWidth: 1,
    paddingHorizontal: 11,
    paddingVertical: 9,
  },
  targetChipActive: {
    backgroundColor: colors.coral,
    borderColor: colors.coral,
  },
  targetChipText: {
    color: colors.asphalt,
    fontFamily: fonts.monoBold,
    fontSize: 8,
  },
  targetChipTextActive: {
    color: colors.white,
  },
  targetHint: {
    color: colors.concrete,
    fontFamily: fonts.body,
    fontSize: 11,
    lineHeight: 16,
    marginTop: 12,
  },
  historyHeader: {
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingBottom: 12,
    paddingTop: 27,
  },
  historyCount: {
    color: colors.concrete,
    fontFamily: fonts.mono,
    fontSize: 8,
  },
  historyRow: {
    alignItems: 'center',
    borderColor: colors.asphalt,
    borderTopWidth: 1,
    flexDirection: 'row',
    minHeight: 64,
  },
  historyRowSelected: {
    backgroundColor: colors.cobalt,
    borderColor: colors.cobalt,
    marginHorizontal: -8,
    paddingHorizontal: 8,
  },
  historyIndex: {
    width: 50,
  },
  historyIndexText: {
    color: colors.concrete,
    fontFamily: fonts.mono,
    fontSize: 8,
  },
  historyIndexTextSelected: {
    color: '#DDE3FF',
  },
  historyCopy: {
    flex: 1,
  },
  historyTrick: {
    color: colors.asphalt,
    fontFamily: fonts.bodyBold,
    fontSize: 14,
  },
  historyTrickSelected: {
    color: colors.white,
  },
  historyMeta: {
    color: colors.concrete,
    fontFamily: fonts.mono,
    fontSize: 8,
    marginTop: 3,
  },
  historyMetaSelected: {
    color: '#DDE3FF',
  },
  historyArrow: {
    color: colors.asphalt,
    fontFamily: fonts.body,
    fontSize: 18,
    marginLeft: 10,
  },
  dojoEmpty: {
    alignItems: 'center',
    borderColor: colors.concrete,
    borderStyle: 'dashed',
    borderWidth: 1,
    flexDirection: 'row',
    padding: 18,
  },
  dojoEmptyMark: {
    color: colors.coral,
    fontFamily: fonts.display,
    fontSize: 28,
    marginRight: 16,
  },
});

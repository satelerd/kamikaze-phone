import { useEffect, useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import type { TrickCatalogController } from '../hooks/useTrickCatalog';
import { useMotionLab } from '../hooks/useMotionLab';
import {
  inferIdealTrickDefinition,
  type TrickDefinition,
} from '../motion/trickCatalog';
import type { DetectedAttempt, Vector3 } from '../motion/types';
import {
  appendTrickCalibration,
  loadTrickCalibrations,
  type StoredTrickCalibration,
} from '../storage/trickCalibrationHistory';
import { colors, fonts } from '../theme';
import { PhoneReplay } from './PhoneReplay';

type StudioMode = 'catalog' | 'create';

const axisStep: Record<keyof Vector3, number> = { x: 360, y: 360, z: 180 };

function AxisRecipe({
  definition,
  editable,
  onChange,
}: {
  definition: TrickDefinition;
  editable?: boolean;
  onChange?: (definition: TrickDefinition) => void;
}) {
  return (
    <View style={styles.recipe}>
      <View style={styles.recipeHeader}>
        <Text style={styles.recipeTitle}>IDEAL MOTION RECIPE</Text>
        <Text style={styles.recipeDuration}>{definition.durationMs}MS</Text>
      </View>
      {(['x', 'y', 'z'] as const).map((axis) => (
        <View key={axis} style={styles.axisRow}>
          <View style={[styles.axisBadge, axis === 'x' ? styles.axisX : axis === 'y' ? styles.axisY : styles.axisZ]}>
            <Text style={styles.axisBadgeText}>{axis.toUpperCase()}</Text>
          </View>
          <Text style={styles.axisMeaning}>
            {axis === 'x' ? 'WIDTH FLIP' : axis === 'y' ? 'LONG-EDGE FLIP' : 'SHUVIT / FLAT SPIN'}
          </Text>
          {editable && onChange ? (
            <View style={styles.axisEditor}>
              <Pressable
                onPress={() => onChange({
                  ...definition,
                  rotation: { ...definition.rotation, [axis]: definition.rotation[axis] - axisStep[axis] },
                })}
                style={styles.axisEditButton}
              >
                <Text style={styles.axisEditText}>−</Text>
              </Pressable>
              <Text style={styles.axisDegrees}>{definition.rotation[axis] >= 0 ? '+' : ''}{definition.rotation[axis]}°</Text>
              <Pressable
                onPress={() => onChange({
                  ...definition,
                  rotation: { ...definition.rotation, [axis]: definition.rotation[axis] + axisStep[axis] },
                })}
                style={styles.axisEditButton}
              >
                <Text style={styles.axisEditText}>＋</Text>
              </Pressable>
            </View>
          ) : (
            <Text style={styles.axisDegrees}>{definition.rotation[axis] >= 0 ? '+' : ''}{definition.rotation[axis]}°</Text>
          )}
        </View>
      ))}
      {editable && onChange && (
        <View style={styles.durationEditor}>
          <Text style={styles.durationLabel}>IDEAL DURATION</Text>
          <View style={styles.axisEditor}>
            <Pressable
              onPress={() => onChange({ ...definition, durationMs: Math.max(250, definition.durationMs - 100) })}
              style={styles.axisEditButton}
            >
              <Text style={styles.axisEditText}>−</Text>
            </Pressable>
            <Text style={styles.axisDegrees}>{definition.durationMs}MS</Text>
            <Pressable
              onPress={() => onChange({ ...definition, durationMs: Math.min(2200, definition.durationMs + 100) })}
              style={styles.axisEditButton}
            >
              <Text style={styles.axisEditText}>＋</Text>
            </Pressable>
          </View>
        </View>
      )}
    </View>
  );
}

export function TrickCalibration({
  catalog,
  motion,
}: {
  catalog: TrickCatalogController;
  motion: ReturnType<typeof useMotionLab>;
}) {
  const [mode, setMode] = useState<StudioMode>('catalog');
  const [selectedId, setSelectedId] = useState('phone-flip');
  const [attempt, setAttempt] = useState<DetectedAttempt | null>(null);
  const [history, setHistory] = useState<StoredTrickCalibration[]>([]);
  const [newName, setNewName] = useState('');
  const [draft, setDraft] = useState<TrickDefinition | null>(null);
  const selected = catalog.definitions.find(({ id }) => id === selectedId) ?? catalog.definitions[0];
  const activeDefinition = mode === 'create' ? draft : selected;

  useEffect(() => {
    loadTrickCalibrations().then(setHistory);
    return motion.cancelManualCapture;
  }, [motion.cancelManualCapture]);

  useEffect(() => {
    if (!catalog.definitions.some(({ id }) => id === selectedId)) {
      setSelectedId(catalog.definitions[0]?.id ?? 'phone-flip');
    }
  }, [catalog.definitions, selectedId]);

  const examplesForSelected = useMemo(
    () => history.filter(({ expectedTrick }) => expectedTrick === activeDefinition?.name).length,
    [activeDefinition?.name, history],
  );

  const persistExample = (captured: DetectedAttempt, expectedTrick: string) => {
    const record: StoredTrickCalibration = {
      attempt: captured,
      expectedTrick,
      id: `${Date.now()}-${expectedTrick}`,
      recordedAtIso: new Date().toISOString(),
    };
    setHistory((existing) => [record, ...existing].slice(0, 80));
    appendTrickCalibration(record).catch(() => undefined);
  };

  const stopAndAnalyze = () => {
    const captured = motion.stopManualCapture();
    if (!captured) return;
    setAttempt(captured);
    if (mode === 'create') {
      const inferred = inferIdealTrickDefinition(newName, captured);
      setDraft(inferred);
      persistExample(captured, inferred.name);
      return;
    }
    persistExample(captured, selected.name);
  };

  const startCreate = () => {
    motion.cancelManualCapture();
    setAttempt(null);
    setDraft(null);
    setNewName('');
    setMode('create');
  };

  const saveDraft = () => {
    if (!draft) return;
    catalog.saveDefinition({ ...draft, name: newName.trim().toUpperCase() || draft.name });
    setSelectedId(draft.id);
    setMode('catalog');
  };

  return (
    <View style={styles.shell}>
      <View style={styles.studioHeader}>
        <View>
          <Text style={styles.kicker}>CAL / TRICK STUDIO</Text>
          <Text style={styles.title}>BUILD THE{`\n`}TRICK DECK.</Text>
        </View>
        <Pressable onPress={startCreate} style={styles.newButton}>
          <Text style={styles.newButtonPlus}>＋</Text>
          <Text style={styles.newButtonText}>NEW</Text>
        </Pressable>
      </View>
      <Text style={styles.intro}>
        A recording is evidence. The recipe is the clean mathematical version used for previews and scoring.
      </Text>

      <View style={styles.gripPanel}>
        <View>
          <Text style={styles.gripLabel}>STANCE ANALOG / GRIP</Text>
          <Text style={styles.gripHelp}>Mirrors kickflip, heelflip, frontside and backside naming.</Text>
        </View>
        <View style={styles.gripSwitch}>
          {(['right', 'left'] as const).map((hand) => (
            <Pressable
              key={hand}
              onPress={() => catalog.setGripHand(hand)}
              style={[styles.gripButton, catalog.gripHand === hand && styles.gripButtonActive]}
            >
              <Text style={[styles.gripButtonText, catalog.gripHand === hand && styles.gripButtonTextActive]}>
                {hand.toUpperCase()}
              </Text>
            </Pressable>
          ))}
        </View>
      </View>

      {mode === 'catalog' ? (
        <>
          <View style={styles.deckHeader}>
            <Text style={styles.deckLabel}>TRICK DECK</Text>
            <Text style={styles.deckCount}>{catalog.definitions.length} RECIPES</Text>
          </View>
          <View style={styles.trickPicker}>
            {catalog.definitions.map((definition) => (
              <Pressable
                disabled={motion.manualRecording}
                key={definition.id}
                onPress={() => { setSelectedId(definition.id); setAttempt(null); }}
                style={[styles.trickChip, selected.id === definition.id && styles.trickChipActive]}
              >
                <Text style={[styles.trickText, selected.id === definition.id && styles.trickTextActive]}>
                  {definition.name}
                </Text>
                <Text style={[styles.trickFamily, selected.id === definition.id && styles.trickFamilyActive]}>
                  {definition.family.toUpperCase()}{definition.builtIn ? '' : ' / CUSTOM'}
                </Text>
              </Pressable>
            ))}
          </View>
          <View style={styles.selectedCopy}>
            <Text style={styles.selectedName}>{selected.name}</Text>
            <Text style={styles.selectedDescription}>{selected.description}</Text>
          </View>
        </>
      ) : (
        <View style={styles.createPanel}>
          <Text style={styles.createIndex}>{draft ? '02 / CLEAN THE RECIPE' : '01 / NAME + RECORD'}</Text>
          <TextInput
            autoCapitalize="characters"
            editable={!motion.manualRecording}
            onChangeText={(value) => {
              setNewName(value);
              setDraft((current) => current ? { ...current, name: value.trim().toUpperCase() || current.name } : null);
            }}
            placeholder="TRICK NAME"
            placeholderTextColor="#9A9A92"
            style={styles.nameInput}
            value={newName}
          />
          <Text style={styles.createHelp}>
            {draft
              ? 'We quantized the captured motion to skate-like rotation increments. Correct any axis before saving.'
              : 'Hold still, start capture, perform one clean trick, catch, then stop.'}
          </Text>
        </View>
      )}

      {activeDefinition && (
        <>
          <PhoneReplay
            attempt={attempt}
            targetDefinition={activeDefinition}
            targetTrick={activeDefinition.name}
          />
          <AxisRecipe
            definition={activeDefinition}
            editable={mode === 'create' && Boolean(draft)}
            onChange={setDraft}
          />
        </>
      )}

      {attempt && activeDefinition && (
        <View style={styles.verdict}>
          <View>
            <Text style={styles.verdictLabel}>RECORDED</Text>
            <Text style={styles.verdictValue}>{Math.round(attempt.rotationDegrees.total)}° TOTAL</Text>
          </View>
          <Text style={styles.verdictArrow}>→</Text>
          <View style={styles.verdictRight}>
            <Text style={styles.verdictLabel}>IDEALIZED AS</Text>
            <Text style={styles.verdictValue}>{activeDefinition.name}</Text>
          </View>
        </View>
      )}

      {motion.manualRecording ? (
        <>
          <View style={styles.recordingBar}>
            <View style={styles.recordDot} />
            <Text style={styles.recordingText}>{(motion.manualElapsedMs / 1000).toFixed(2)}S / RAW CAPTURE</Text>
          </View>
          <Pressable onPress={stopAndAnalyze} style={styles.stopButton}>
            <Text style={styles.buttonText}>STOP + ANALYZE</Text>
            <Text style={styles.stopMark} />
          </Pressable>
        </>
      ) : mode === 'create' && draft ? (
        <View style={styles.saveRow}>
          <Pressable onPress={() => { setDraft(null); setAttempt(null); }} style={styles.retryButton}>
            <Text style={styles.retryText}>RECORD AGAIN</Text>
          </Pressable>
          <Pressable onPress={saveDraft} style={styles.saveButton}>
            <Text style={styles.buttonText}>SAVE TRICK</Text>
            <Text style={styles.buttonText}>→</Text>
          </Pressable>
        </View>
      ) : (
        <Pressable
          disabled={mode === 'create' && newName.trim().length === 0}
          onPress={() => { motion.startManualCapture(); }}
          style={[styles.startButton, mode === 'create' && newName.trim().length === 0 && styles.buttonDisabled]}
        >
          <Text style={styles.buttonText}>{mode === 'create' ? 'RECORD EXAMPLE' : `RECORD ${selected.name}`}</Text>
          <View style={styles.startMark} />
        </Pressable>
      )}

      {mode === 'create' && !motion.manualRecording && (
        <Pressable onPress={() => setMode('catalog')} style={styles.cancelCreate}>
          <Text style={styles.cancelCreateText}>BACK TO TRICK DECK</Text>
        </Pressable>
      )}

      <View style={styles.tapeHeader}>
        <Text style={styles.tapeTitle}>TRICK TAPE</Text>
        <Text style={styles.tapeCount}>{examplesForSelected} FOR THIS / {history.length} TOTAL</Text>
      </View>
      {history.slice(0, 10).map((record) => (
        <Pressable
          key={record.id}
          onPress={() => {
            const definition = catalog.definitions.find(({ name }) => name === record.expectedTrick);
            if (definition) setSelectedId(definition.id);
            setAttempt(record.attempt);
            setMode('catalog');
          }}
          style={styles.tapeRow}
        >
          <View style={styles.tapeCopy}>
            <Text style={styles.tapeTrick}>{record.expectedTrick}</Text>
            <Text style={styles.tapeMeta}>{Math.round(record.attempt.airtimeMs)}MS · {record.attempt.samples.length} RAW · {Math.round(record.attempt.rotationDegrees.total)}°</Text>
          </View>
          <Text style={styles.tapeArrow}>→</Text>
        </Pressable>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  shell: { paddingTop: 25 },
  studioHeader: { alignItems: 'flex-start', flexDirection: 'row', justifyContent: 'space-between' },
  kicker: { color: colors.cobalt, fontFamily: fonts.monoBold, fontSize: 9, letterSpacing: 1.4 },
  title: { color: colors.asphalt, fontFamily: fonts.display, fontSize: 40, letterSpacing: -1.8, lineHeight: 39, marginTop: 8 },
  intro: { color: colors.asphalt, fontFamily: fonts.body, fontSize: 13, lineHeight: 19, marginTop: 12 },
  newButton: { alignItems: 'center', backgroundColor: colors.coral, borderColor: colors.asphalt, borderWidth: 1.5, height: 65, justifyContent: 'center', transform: [{ rotate: '2deg' }], width: 65 },
  newButtonPlus: { color: colors.white, fontFamily: fonts.bodyBold, fontSize: 20, lineHeight: 20 },
  newButtonText: { color: colors.white, fontFamily: fonts.monoBold, fontSize: 6, letterSpacing: 1, marginTop: 4 },
  gripPanel: { alignItems: 'center', borderColor: colors.asphalt, borderWidth: 1.5, flexDirection: 'row', justifyContent: 'space-between', marginTop: 18, padding: 12 },
  gripLabel: { color: colors.asphalt, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 0.8 },
  gripHelp: { color: colors.concrete, fontFamily: fonts.body, fontSize: 8, marginTop: 3, maxWidth: 185 },
  gripSwitch: { flexDirection: 'row' },
  gripButton: { borderColor: colors.asphalt, borderWidth: 1, paddingHorizontal: 9, paddingVertical: 9 },
  gripButtonActive: { backgroundColor: colors.asphalt },
  gripButtonText: { color: colors.asphalt, fontFamily: fonts.monoBold, fontSize: 6 },
  gripButtonTextActive: { color: colors.white },
  deckHeader: { borderBottomColor: colors.asphalt, borderBottomWidth: 1.5, flexDirection: 'row', justifyContent: 'space-between', marginTop: 24, paddingBottom: 9 },
  deckLabel: { color: colors.asphalt, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 1 },
  deckCount: { color: colors.concrete, fontFamily: fonts.mono, fontSize: 7 },
  trickPicker: { flexDirection: 'row', flexWrap: 'wrap', gap: 7, marginTop: 10 },
  trickChip: { borderColor: colors.asphalt, borderWidth: 1, paddingHorizontal: 10, paddingVertical: 9 },
  trickChipActive: { backgroundColor: colors.coral, borderColor: colors.coral },
  trickText: { color: colors.asphalt, fontFamily: fonts.monoBold, fontSize: 7 },
  trickTextActive: { color: colors.white },
  trickFamily: { color: colors.concrete, fontFamily: fonts.mono, fontSize: 5, marginTop: 3 },
  trickFamilyActive: { color: '#FFE2DD' },
  selectedCopy: { marginTop: 15 },
  selectedName: { color: colors.asphalt, fontFamily: fonts.display, fontSize: 25 },
  selectedDescription: { color: colors.concrete, fontFamily: fonts.body, fontSize: 10, lineHeight: 15, marginTop: 4 },
  createPanel: { backgroundColor: colors.paper, borderColor: colors.asphalt, borderWidth: 1.5, marginTop: 20, padding: 15, shadowColor: colors.asphalt, shadowOffset: { width: 4, height: 4 }, shadowOpacity: 1, shadowRadius: 0 },
  createIndex: { color: colors.cobalt, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 1 },
  nameInput: { borderBottomColor: colors.asphalt, borderBottomWidth: 2, color: colors.asphalt, fontFamily: fonts.display, fontSize: 26, marginTop: 10, paddingBottom: 7, paddingHorizontal: 0 },
  createHelp: { color: colors.concrete, fontFamily: fonts.body, fontSize: 10, lineHeight: 15, marginTop: 10 },
  recipe: { borderColor: colors.asphalt, borderWidth: 1.5, marginTop: 11 },
  recipeHeader: { alignItems: 'center', backgroundColor: colors.asphalt, flexDirection: 'row', justifyContent: 'space-between', padding: 11 },
  recipeTitle: { color: colors.white, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 1 },
  recipeDuration: { color: colors.coral, fontFamily: fonts.monoBold, fontSize: 9 },
  axisRow: { alignItems: 'center', borderTopColor: colors.asphalt, borderTopWidth: 1, flexDirection: 'row', minHeight: 48, paddingHorizontal: 10 },
  axisBadge: { alignItems: 'center', height: 26, justifyContent: 'center', width: 26 },
  axisX: { backgroundColor: colors.coral },
  axisY: { backgroundColor: colors.cobalt },
  axisZ: { backgroundColor: colors.asphalt },
  axisBadgeText: { color: colors.white, fontFamily: fonts.monoBold, fontSize: 8 },
  axisMeaning: { color: colors.concrete, flex: 1, fontFamily: fonts.mono, fontSize: 6, marginLeft: 9 },
  axisDegrees: { color: colors.asphalt, fontFamily: fonts.monoBold, fontSize: 10, minWidth: 54, textAlign: 'center' },
  axisEditor: { alignItems: 'center', flexDirection: 'row' },
  axisEditButton: { alignItems: 'center', borderColor: colors.asphalt, borderWidth: 1, height: 29, justifyContent: 'center', width: 29 },
  axisEditText: { color: colors.asphalt, fontFamily: fonts.bodyBold, fontSize: 13 },
  durationEditor: { alignItems: 'center', borderTopColor: colors.asphalt, borderTopWidth: 1, flexDirection: 'row', justifyContent: 'space-between', minHeight: 49, paddingHorizontal: 10 },
  durationLabel: { color: colors.concrete, fontFamily: fonts.monoBold, fontSize: 7 },
  verdict: { alignItems: 'center', backgroundColor: colors.paper, borderColor: colors.asphalt, borderWidth: 1.5, flexDirection: 'row', justifyContent: 'space-between', marginTop: 11, padding: 13 },
  verdictLabel: { color: colors.concrete, fontFamily: fonts.monoBold, fontSize: 6 },
  verdictValue: { color: colors.asphalt, fontFamily: fonts.bodyBold, fontSize: 9, marginTop: 3 },
  verdictArrow: { color: colors.coral, fontSize: 18 },
  verdictRight: { alignItems: 'flex-end', flex: 1 },
  recordingBar: { alignItems: 'center', backgroundColor: colors.coral, flexDirection: 'row', gap: 9, justifyContent: 'center', marginTop: 11, paddingVertical: 11 },
  recordDot: { backgroundColor: colors.white, borderRadius: 5, height: 9, width: 9 },
  recordingText: { color: colors.white, fontFamily: fonts.monoBold, fontSize: 9, letterSpacing: 0.8 },
  startButton: { alignItems: 'center', backgroundColor: colors.cobalt, borderColor: colors.asphalt, borderWidth: 1.5, flexDirection: 'row', justifyContent: 'space-between', marginTop: 11, padding: 17 },
  stopButton: { alignItems: 'center', backgroundColor: colors.asphalt, borderColor: colors.asphalt, borderWidth: 1.5, flexDirection: 'row', justifyContent: 'space-between', padding: 17 },
  startMark: { backgroundColor: colors.white, borderRadius: 6, height: 12, width: 12 },
  stopMark: { backgroundColor: colors.white, height: 11, width: 11 },
  buttonText: { color: colors.white, fontFamily: fonts.bodyBold, fontSize: 11 },
  buttonDisabled: { opacity: 0.35 },
  saveRow: { flexDirection: 'row', gap: 8, marginTop: 11 },
  retryButton: { alignItems: 'center', borderColor: colors.asphalt, borderWidth: 1.5, justifyContent: 'center', paddingHorizontal: 13 },
  retryText: { color: colors.asphalt, fontFamily: fonts.monoBold, fontSize: 7 },
  saveButton: { alignItems: 'center', backgroundColor: colors.cobalt, borderColor: colors.asphalt, borderWidth: 1.5, flex: 1, flexDirection: 'row', justifyContent: 'space-between', padding: 17 },
  cancelCreate: { alignItems: 'center', paddingVertical: 13 },
  cancelCreateText: { color: colors.concrete, fontFamily: fonts.monoBold, fontSize: 7, textDecorationLine: 'underline' },
  tapeHeader: { borderBottomColor: colors.asphalt, borderBottomWidth: 1.5, flexDirection: 'row', justifyContent: 'space-between', marginTop: 28, paddingBottom: 10 },
  tapeTitle: { color: colors.asphalt, fontFamily: fonts.monoBold, fontSize: 9, letterSpacing: 1 },
  tapeCount: { color: colors.concrete, fontFamily: fonts.mono, fontSize: 7 },
  tapeRow: { alignItems: 'center', borderBottomColor: colors.asphalt, borderBottomWidth: 1, flexDirection: 'row', minHeight: 58 },
  tapeCopy: { flex: 1 },
  tapeTrick: { color: colors.asphalt, fontFamily: fonts.monoBold, fontSize: 9 },
  tapeMeta: { color: colors.concrete, fontFamily: fonts.mono, fontSize: 6, marginTop: 4 },
  tapeArrow: { color: colors.asphalt, fontFamily: fonts.bodyBold, fontSize: 14 },
});

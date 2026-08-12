import { File, Paths } from 'expo-file-system';
import { Platform } from 'react-native';
import * as Sharing from 'expo-sharing';

import { loadExportSnapshot } from '../storage/exportSnapshot';
import { buildExportBundle, type KamikazeExportBundleV2 } from './exportBundle';

export async function shareExportBundle(): Promise<KamikazeExportBundleV2> {
  const snapshot = await loadExportSnapshot();
  const bundle = buildExportBundle(snapshot, {
    app: 'Kamikaze: Phone Flip',
    appVersion: '0.3.0',
    deviceModel: 'unknown',
    osVersion: String(Platform.Version),
    platform: Platform.OS,
    runtime: 'expo',
  });

  if (!await Sharing.isAvailableAsync()) {
    throw new Error('File sharing is unavailable on this device.');
  }

  const timestamp = bundle.exportedAtIso.replaceAll(':', '-');
  const file = new File(Paths.cache, `kamikaze-export-${timestamp}.json`);
  file.create({ intermediates: true, overwrite: true });
  file.write(JSON.stringify(bundle));
  await Sharing.shareAsync(file.uri, {
    dialogTitle: 'Export Kamikaze motion data',
    mimeType: 'application/json',
    UTI: 'public.json',
  });

  return bundle;
}

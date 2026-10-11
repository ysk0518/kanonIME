import { KeyboardSettingsSnapshot, KeyboardSettingsPatch, KeyboardSettingsRecord, KeyboardSettingsChange,
  SettingsPeer, applySettingsPatch, mergeSettingsPatch, copySettings } from './KeyboardSettingsModel';

export function copySettingsRecord(record: KeyboardSettingsRecord): KeyboardSettingsRecord {
  return JSON.parse(JSON.stringify(record)) as KeyboardSettingsRecord;
}

export function effectiveSettings(record: KeyboardSettingsRecord): KeyboardSettingsSnapshot {
  let snapshot: KeyboardSettingsSnapshot = copySettings(record.snapshot);
  for (const change of record.pending) { snapshot = applySettingsPatch(snapshot, change.patch); }
  return snapshot;
}

export function advanceSettingsRecord(record: KeyboardSettingsRecord, now: number): void {
  record.snapshot.revision = Math.max(now, record.snapshot.revision + 1);
}

export function committedSettingsRecord(record: KeyboardSettingsRecord,
  patch: KeyboardSettingsPatch, now: number): KeyboardSettingsRecord {
  const next: KeyboardSettingsRecord = copySettingsRecord(record);
  next.snapshot = applySettingsPatch(next.snapshot, patch);
  if (patch.heightPercent !== undefined) { next.heightChosen = true; }
  if (patch.layoutOrder !== undefined) { next.languagesChosen = true; }
  advanceSettingsRecord(next, now);
  return next;
}

export class QueuedSettingsRecord {
  record: KeyboardSettingsRecord;
  change: KeyboardSettingsChange;
  constructor(record: KeyboardSettingsRecord, change: KeyboardSettingsChange) {
    this.record = record;
    this.change = change;
  }
}

export function queuedSettingsRecord(record: KeyboardSettingsRecord, patch: KeyboardSettingsPatch): QueuedSettingsRecord {
  applySettingsPatch(effectiveSettings(record), patch);
  const next: KeyboardSettingsRecord = copySettingsRecord(record);
  if (next.pending.length > 1) {
    const tail: KeyboardSettingsChange = next.pending[1];
    tail.patch = mergeSettingsPatch(tail.patch, patch);
    return new QueuedSettingsRecord(next, tail);
  }
  const change: KeyboardSettingsChange = new KeyboardSettingsChange();
  change.actor = next.actor;
  change.sequence = next.nextSequence++;
  change.patch = JSON.parse(JSON.stringify(patch)) as KeyboardSettingsPatch;
  next.pending.push(change);
  return new QueuedSettingsRecord(next, change);
}

export function receivedSettingsRecord(record: KeyboardSettingsRecord,
  snapshot: KeyboardSettingsSnapshot, actor: string, sequence: number): KeyboardSettingsRecord {
  const next: KeyboardSettingsRecord = copySettingsRecord(record);
  if (snapshot.revision >= next.snapshot.revision) { next.snapshot = copySettings(snapshot); }
  if (actor === next.actor && sequence >= 0 && sequence < next.nextSequence) {
    next.pending = next.pending.filter((change: KeyboardSettingsChange) => change.sequence > sequence);
  }
  next.bootstrapComplete = true;
  return next;
}

export function acceptedSettingsRecord(record: KeyboardSettingsRecord,
  change: KeyboardSettingsChange, now: number): KeyboardSettingsRecord | undefined {
  const existing: SettingsPeer | undefined = record.peers.find((peer: SettingsPeer) => peer.actor === change.actor);
  if (existing && change.sequence <= existing.sequence) { return undefined; }
  if (existing && change.sequence !== existing.sequence + 1) { return undefined; }
  const next: KeyboardSettingsRecord = copySettingsRecord(record);
  next.snapshot = applySettingsPatch(next.snapshot, change.patch);
  if (change.patch.heightPercent !== undefined) { next.heightChosen = true; }
  if (change.patch.layoutOrder !== undefined) { next.languagesChosen = true; }
  const peer: SettingsPeer = new SettingsPeer();
  peer.actor = change.actor;
  peer.sequence = change.sequence;
  next.peers = next.peers.filter((entry: SettingsPeer) => entry.actor !== change.actor);
  next.peers.push(peer);
  if (next.peers.length > 32) { next.peers.shift(); }
  advanceSettingsRecord(next, now);
  return next;
}

const { KeyboardSettingsSyncCore } = require('../../entry/src/main/ets/common/SettingsSyncCore.ets');
const { KeyboardSettingsRecord, copySettings } = require('../../entry/src/main/ets/common/KeyboardSettingsModel.ets');
const { effectiveSettings, committedSettingsRecord, queuedSettingsRecord, receivedSettingsRecord,
  acceptedSettingsRecord } = require('../../entry/src/main/ets/common/SettingsRecordPolicy.ets');
const { saveSettingsRecord } = require('../../entry/src/main/ets/common/SettingsPersistence.ets');
const { SettingsReceiptStore } = require('../../entry/src/main/ets/common/SettingsReceiptState.ets');

exports.pair = async () => {
  let time = 100; let timerId = 0;
  const timers = new Map(); const messages = [];
  const clock = { schedule(callback, delay) { const id = timerId++; timers.set(id, { callback, due: time + delay }); return id; },
    unschedule(id) { timers.delete(id); },
    async advance(ms) { time += ms; for (const [id, timer] of [...timers]) {
      if (timer.due <= time) { timers.delete(id); timer.callback(); }
    } for (let i = 0; i < 40; i++) { await Promise.resolve(); } }
  };
  function endpoint(actor) {
    const state = { record: new KeyboardSettingsRecord(), logs: [], states: new Map(),
      sent: [], applied: [], failSave: false, failPublish: false, failSubscribe: false, receiver: null };
    state.record.actor = actor; state.record.snapshot.revision = 100;
    const receipt = new SettingsReceiptStore({ schedule: clock.schedule, unschedule: clock.unschedule,
      publish: (scope, saved, applied, status) => state.states.set(scope, { saved, applied, status }), log: () => {} });
    const persist = next => {
      saveSettingsRecord(next, { maximumLength: 10000, write: () => {
        if (state.failSave) { throw new Error('save failed'); }
      }, flush: () => {} }); state.record = next;
    };
    const core = new KeyboardSettingsSyncCore({
      subscribe: async receiver => { if (state.failSubscribe) { throw new Error('subscribe failed'); } state.receiver = receiver; },
      publish: async event => {
        if (state.failPublish) { throw new Error('publish failed'); }
        state.sent.push(event); messages.push(event);
      }, schedule: clock.schedule, unschedule: clock.unschedule, receipt,
      log: message => state.logs.push(message), errorCode: () => 'test-error',
      readSettings: () => effectiveSettings(state.record),
      commitSettings: patch => { persist(committedSettingsRecord(state.record, patch, ++time)); return copySettings(state.record.snapshot); },
      ensureSettingsRevision: () => copySettings(state.record.snapshot),
      queueSettings: patch => { const next = queuedSettingsRecord(state.record, patch); persist(next.record); return next.change; },
      nextSettingsChange: () => state.record.pending[0],
      acceptSettingsChange: change => {
        const next = acceptedSettingsRecord(state.record, change, ++time);
        if (next) { persist(next); }
        return state.record.peers.find(peer => peer.actor === change.actor);
      }, receiveSettings: (snapshot, actor, sequence) => persist(receivedSettingsRecord(state.record, snapshot, actor, sequence)),
      settingsActor: () => state.record.actor, settingsPendingCount: () => state.record.pending.length,
      settingsBaseRevision: () => state.record.snapshot.revision,
      settingsLastPendingSequence: () => state.record.pending.at(-1)?.sequence ?? 0,
      settingsIssuedSequence: () => state.record.nextSequence - 1,
      legacyHeightPresent: () => false, legacyLayoutPresent: () => false,
      importLegacySettings: () => {}, settingsDiagnostics: () => 'test repository'
    });
    core.onApplied = async (snapshot, heightChanged, fromPeer) => {
      state.applied.push({ snapshot: copySettings(snapshot), heightChanged, fromPeer });
    };
    return { state, core, receipt };
  }
  const app = endpoint('1-1'); const ime = endpoint('2-2');
  await app.core.initialize(); await ime.core.initialize(true);
  messages.length = 0; app.state.sent.length = 0; ime.state.sent.length = 0;
  return { app, ime, clock, messages, timers,
    async deliver(name) {
      // Flush finite Promise chains; elapsed wall-clock time is not involved.
      for (let i = 0; i < 40; i++) { await Promise.resolve(); }
      const index = messages.findIndex(event => name === undefined || event.event === name);
      if (index < 0) { throw new Error(`No pending event: ${name}`); }
      const event = messages.splice(index, 1)[0];
      await (event.sender === 'app' ? ime.state.receiver : app.state.receiver)(event);
      return event;
    }, async pump() {
      for (let i = 0; i < 40; i++) { await Promise.resolve(); }
      let count = 0;
      while (messages.length > 0) { if (++count > 100) { throw new Error('Protocol loop'); } await this.deliver(); }
    }
  };
};

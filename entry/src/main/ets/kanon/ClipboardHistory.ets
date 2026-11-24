import { KANON_CLIPBOARD_AUTO_STATUS, KANON_CLIPBOARD_CURRENT_TEXT } from '../common/AppStorageKeys';
import pasteboard from '@ohos.pasteboard';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import bundleManager from '@ohos.bundle.bundleManager';
import { clipboardStore } from '../common/ClipboardStore';

class ClipboardHistory {
  private board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
  private active: boolean = false;
  private generation: number = 0;
  private reading: boolean = false;
  private pending: boolean = false;
  private observedCount: number = -1;
  private updated: () => void = () => { this.refresh(); };

  start(): void {
    if (this.active) { return; }
    this.active = true;
    this.generation++;
    try { this.board.on('update', this.updated); }
    catch (e) {
      this.active = false;
      AppStorage.setOrCreate(KANON_CLIPBOARD_AUTO_STATUS, 'error');
      return;
    }
    this.refresh();
  }

  stop(): void {
    if (!this.active) { return; }
    this.active = false;
    this.generation++;
    this.pending = false;
    AppStorage.setOrCreate(KANON_CLIPBOARD_CURRENT_TEXT, '');
    try { this.board.off('update', this.updated); } catch (e) {}
  }

  refresh(): void {
    if (!this.active) { return; }
    this.pending = true;
    if (!this.reading) { this.drain(); }
  }

  // 消去直後に、進行中の読み取りや同じコピーで履歴が復活しないようにする。
  forgetCurrent(): void {
    this.generation++;
    this.pending = false;
    try { this.observedCount = this.board.getChangeCount(); } catch (e) {}
    AppStorage.setOrCreate(KANON_CLIPBOARD_CURRENT_TEXT, '');
  }

  private async drain(): Promise<void> {
    this.reading = true;
    try {
      while (this.active && this.pending) {
        this.pending = false;
        const generation: number = this.generation;
        const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
          bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
        const granted: abilityAccessCtrl.GrantStatus = await abilityAccessCtrl.createAtManager().checkAccessToken(
          info.appInfo.accessTokenId, 'ohos.permission.READ_PASTEBOARD');
        if (!this.active || generation !== this.generation) { continue; }
        if (granted !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          AppStorage.setOrCreate(KANON_CLIPBOARD_AUTO_STATUS, 'permission');
          continue;
        }
        AppStorage.setOrCreate(KANON_CLIPBOARD_AUTO_STATUS, 'ready');
        const count: number = this.board.getChangeCount();
        if (count === this.observedCount) { continue; }
        if (!this.board.hasDataType(pasteboard.MIMETYPE_TEXT_PLAIN)) {
          this.observedCount = count;
          AppStorage.setOrCreate(KANON_CLIPBOARD_CURRENT_TEXT, '');
          continue;
        }
        const data: pasteboard.PasteData = await this.board.getData();
        if (!this.active || generation !== this.generation) { continue; }
        if (count !== this.board.getChangeCount()) { this.pending = true; continue; }
        this.observedCount = count;
        const value: string = data.hasType(pasteboard.MIMETYPE_TEXT_PLAIN) ? data.getPrimaryText() : '';
        AppStorage.setOrCreate(KANON_CLIPBOARD_CURRENT_TEXT, value);
        clipboardStore.remember(value);
      }
    } catch (e) {
      if (this.active) { AppStorage.setOrCreate(KANON_CLIPBOARD_AUTO_STATUS, 'error'); }
    } finally {
      this.reading = false;
      if (this.active && this.pending) { this.drain(); }
    }
  }
}

export const clipboardHistory: ClipboardHistory = new ClipboardHistory();

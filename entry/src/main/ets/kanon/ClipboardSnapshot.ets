import pasteboard from '@ohos.pasteboard';
import { clipboardStore } from '../common/ClipboardStore';

// クリップボードはユーザーがOSの貼り付けボタンを押した時だけ読む。
class ClipboardSnapshot {
  private text: string = '';
  private status: string = 'empty';
  private epoch: number = 0;

  async capture(): Promise<void> {
    this.clear();
    const epoch: number = this.epoch;
    try {
      const data: pasteboard.PasteData = await pasteboard.getSystemPasteboard().getData();
      if (epoch !== this.epoch) { return; }
      if (data.hasType(pasteboard.MIMETYPE_TEXT_PLAIN)) {
        this.text = data.getPrimaryText();
      }
      this.status = this.text.length > 0 ? 'ready' : 'empty';
      clipboardStore.remember(this.text);
    } catch (e) {
      if (epoch === this.epoch) { this.status = 'error'; }
    }
  }

  getText(): string { return this.text; }
  getStatus(): string { return this.status; }
  clear(): void { this.epoch++; this.text = ''; this.status = 'empty'; }
}

export const clipboardSnapshot: ClipboardSnapshot = new ClipboardSnapshot();

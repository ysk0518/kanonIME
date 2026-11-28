import { HIDDEN_URL_FIELD_KEY, normalizeUrlFieldKey } from '../common/UrlFieldKey';

// EditorAttribute.inputPattern uses inputMethod.TextInputType values.
const TEXT_INPUT_TYPE_URL: number = 6;

export function isUrlInputPattern(inputPattern: number): boolean {
  return inputPattern === TEXT_INPUT_TYPE_URL;
}

export function urlFieldKeyText(inputPattern: number, value: string | undefined): string {
  if (!isUrlInputPattern(inputPattern)) { return ''; }
  const key: string = normalizeUrlFieldKey(value);
  return key === HIDDEN_URL_FIELD_KEY ? '' : key;
}

// These action values are shared by inputMethod.EnterKeyType and ArkUI EnterKeyType.
enum EditorEnterType {
  Go = 2,
  Search = 3,
  Send = 4,
  Next = 5,
  Done = 6
}

export function enterKeyLabel(enterKeyType: number, englishComposing: boolean): string {
  if (englishComposing) { return '改行'; }
  switch (enterKeyType) {
    case EditorEnterType.Go: return '移動';
    case EditorEnterType.Search: return '検索';
    case EditorEnterType.Send: return '送信';
    case EditorEnterType.Next: return '次へ';
    case EditorEnterType.Done: return '完了';
    default: return '改行';
  }
}

export function spaceKeyLabel(mode: string, flick: boolean = false, japaneseComposing: boolean = false): string {
  if (mode === 'EN') { return 'English ␣'; }
  if (mode !== 'JP') { return '␣'; }
  if (!japaneseComposing) { return '日本語 ␣'; }
  return flick ? '候補 ␣' : 'space';
}

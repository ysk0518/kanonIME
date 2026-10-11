import { EditorPort, OpResult } from './ImeCoordinator';

/** Clearing the preview's text does not end the platform's preview session. */
export async function cancelEditorPreview(editor: EditorPort): Promise<OpResult> {
  const epoch: number = editor.getEpoch();
  const cleared: OpResult = await editor.setPreview('', -1, -1);
  if (!cleared.ok) { return cleared; }
  if (epoch !== editor.getEpoch()) { return { ok: false, code: -4 }; }
  // Finish only after clearing, so cancelled text cannot be committed.
  const finished: OpResult = await editor.finishPreview();
  if (epoch !== editor.getEpoch()) { return { ok: false, code: -4 }; }
  return finished;
}

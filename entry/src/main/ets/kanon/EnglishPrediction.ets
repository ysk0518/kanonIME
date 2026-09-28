import { CandidateLabel } from './ImeCoordinator';

export interface EnglishCompletionUndo {
  prefix: string;
  word: string;
  cursor: number;
  epoch: number;
}

// Fixed, locally authored starter vocabulary. No network, history, or learning.
const WORDS: string[] = (
  'the to and that this thanks thank there they their them then these those think thinking thought ' +
  'hello help here have has had happy happiness happen happening hope home how house ' +
  'you your yours yes yesterday year years yet welcome we were well went will with without would ' +
  'what when where which who why work working works world write writing written want wanted ' +
  'good great get getting got going go gone give given glad goodbye game games ' +
  'please people person pretty project problem probably program programming promise ' +
  'can could come coming came call called care change changed check checking clear close ' +
  'are about all also always any anyone anything another ask asked available away ' +
  'be been being because before best better between both back beautiful become believe book books ' +
  'do does done doing down day days different did dinner drink drive during ' +
  'for from first find found feel feeling few fine follow following friend friends free Friday ' +
  'in into if important information interesting idea input internet include included ' +
  'is it its just job join Japanese Japan keyboard key know known kind keep ' +
  'like little live love looking look let leave later last long language learn learning ' +
  'my me more most much make making made many maybe meet meeting message messages morning Monday ' +
  'not now new need next never nice night no nothing number name ' +
  'of on one only other our out over old open once okay online order ' +
  'really right read reading ready remember reply return room run running ' +
  'so some someone something same say said see seen send sending sent ' +
  'should sure sorry start started starting stop still show small school sound ' +
  'take taken time today tomorrow too tell told try trying team test testing text Tuesday Thursday ' +
  'up use using used update understand under until usual usually ' +
  'very visit video view voice value vacation ' +
  'wait waiting way watch water week weekend while white wish Wednesday ' +
  'after again afternoon almost already around answer app application apple ' +
  'birthday business busy buy big bad bring build building browser ' +
  'coffee computer code coding company complete conversation continue correct create ' +
  'dark date dear device display document download data design developer development ' +
  'each early easy email end English enjoy enough every everyone everything example evening ' +
  'family favorite file finish food full function future fast feature feedback ' +
  'guess group green guide girl guy gym guitar ' +
  'hour hours human heart hold hotel holiday hundred Harmony ' +
  'issue image install item invite immediately ' +
  'lunch list light left location link life limit line login ' +
  'music minute minutes month months mode money move mobile model ' +
  'nice news normal note network notification ' +
  'option office off original outside offline ' +
  'phone photo picture plan play place point power possible public private prediction ' +
  'question quick quite quiet quality ' +
  'request resource result review reset release remove record red ' +
  'system setting settings screen search select selection space save saved Saturday Sunday ' +
  'sleep speak special support simple software service second seconds ' +
  'touch type typing tool together travel true turn two three ' +
  'user upload useful unit version visual verify ' +
  'window word words wrong winter warm zoom zero ' +
  'actually absolutely awesome amazing account address agree agreed almost amount animal apartment arrive arrived ' +
  'attention audio autumn afraid alone along although anymore anyway area arm art artist asleep as at August ' +
  'baby bag balance bank beach bed bedroom beginning bike black blue board body born bottle box break breakfast ' +
  'brother budget bus button camera cancel cannot capital car card careful case catch cat charge cheap child children ' +
  'choice choose city class clean clothes cold color comfortable comment common confirm contact control cook cool cost country ' +
  'couple course cover crash credit cut dance daughter decision delicious detail distance dog door double dream dress drop dry ' +
  'earth east eat eaten education either empty energy error especially event exact excited excuse experience explain extra eye ' +
  'face fact fail fall father February fight final finally finger fire five flight floor flower fly form four front funny ' +
  'garden gate gift glass gold gray grow hair hand hard health healthy hear heavy high history hot hungry husband ' +
  'inside instead June July January keypress kitchen lake late laugh length lesson level library local lock lost low ' +
  'machine main March May map market match meal mean middle milk mind miss moment mother mouth movie museum ' +
  'near nearly necessary November October orange page paper parent part party pass payment personal pink police price protect ' +
  'rain reason receive recent rectangle reduce restaurant rice rich road safe salt sea season September share shirt shopping ' +
  'short sick side sister size sky slow smile snow somebody sometimes son soon south spend spring square station story strong ' +
  'student summer sweet table talk taste teacher temperature ten ticket tired top town train tree twelve twenty twice ' +
  'uncle university walk wear weather wedding west whether whole wife wine wonderful worry yellow young December April'
).split(' ');

export class EnglishPrediction {
  private prefix: string = '';
  private start: number = -1;
  private revision: number = 0;
  private items: CandidateLabel[] = [];
  private selectionCollapsed: boolean = true;
  private undo: EnglishCompletionUndo | undefined = undefined;
  editing: boolean = false;

  getPrefix(): string { return this.prefix; }
  getCursor(): number { return this.start < 0 ? -1 : this.start + this.prefix.length; }
  getItems(): CandidateLabel[] { return this.items; }
  getRevision(): number { return this.revision; }
  canSeed(): boolean { return this.selectionCollapsed; }

  rememberCompletion(prefix: string, word: string, cursor: number, epoch: number): void {
    this.undo = { prefix: prefix, word: word, cursor: cursor, epoch: epoch };
    AppStorage.setOrCreate('kanonEnglishUndo', true);
  }

  dropUndo(): void {
    this.undo = undefined;
    AppStorage.setOrCreate('kanonEnglishUndo', false);
  }

  takeUndo(): EnglishCompletionUndo | undefined {
    const value: EnglishCompletionUndo | undefined = this.selectionCollapsed ? this.undo : undefined;
    this.dropUndo();
    return value;
  }

  restorePrefix(prefix: string, cursor: number): void {
    this.clear();
    this.seed(prefix, cursor);
    this.refresh();
  }

  seed(prefix: string, cursor: number): void {
    if (prefix.length > 0 && prefix.length <= 40 && cursor >= prefix.length) {
      this.prefix = prefix;
      this.start = cursor - prefix.length;
    }
  }

  clear(): void {
    this.dropUndo();
    this.prefix = '';
    this.start = -1;
    this.items = [];
    this.revision++;
  }

  selectionChanged(begin: number, end: number): void {
    this.selectionCollapsed = begin === end;
    if (this.editing) { return; }
    if (this.undo !== undefined && (begin !== end || end !== this.undo.cursor)) { this.dropUndo(); }
    if (this.prefix.length === 0) { return; }
    if (begin !== end || end !== this.getCursor()) {
      this.clear();
      if (AppStorage.get<string>('kanonMode') === 'EN') {
        AppStorage.setOrCreate('kanonList', [] as string[]);
        AppStorage.setOrCreate('kanonIdList', [] as number[]);
        AppStorage.setOrCreate('kanonCandidatesExpanded', false);
      }
    }
  }

  text(value: string, cursor: number): void {
    if (!/^[A-Za-z]+$/.test(value)) { this.clear(); return; }
    if (this.prefix.length === 0) { this.start = cursor; }
    this.prefix += value;
    if (this.prefix.length > 40 || this.start < 0) { this.clear(); return; }
    this.refresh();
  }

  backspace(): void {
    this.prefix = this.prefix.substring(0, Math.max(0, this.prefix.length - 1));
    if (this.prefix.length === 0) { this.clear(); }
    else { this.refresh(); }
  }

  private refresh(): void {
    this.revision++;
    this.items = [];
    const lower: string = this.prefix.toLowerCase();
    for (const word of WORDS) {
      const normalized: string = word.toLowerCase();
      if (!normalized.startsWith(lower) || normalized.length <= lower.length) { continue; }
      const suffix: string = normalized.substring(lower.length);
      const label: string = this.prefix + (this.prefix === this.prefix.toUpperCase() ? suffix.toUpperCase() : suffix);
      if (this.items.some((item: CandidateLabel) => item.label === label)) { continue; }
      this.items.push({ id: this.revision * 16 + this.items.length, label: label });
      if (this.items.length >= 8) { break; }
    }
  }
}

export const englishPrediction: EnglishPrediction = new EnglishPrediction();

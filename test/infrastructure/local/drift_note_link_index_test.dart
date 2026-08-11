import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/value_objects/note_link.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_note_link_index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftNoteLinkIndex index;

  NoteLink link(String source, String target, [String display = 'text']) =>
      NoteLink(
        sourceNoteId: source,
        targetNoteId: target,
        displayText: display,
      );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    index = DriftNoteLinkIndex(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('stores outgoing links and reads them back', () async {
    await index.replaceLinksFrom('a', [link('a', 'b'), link('a', 'c')]);

    final outgoing = await index.outgoingFrom('a');
    expect(outgoing.map((l) => l.targetNoteId), unorderedEquals(['b', 'c']));
  });

  test('backlinks find every source pointing at a target', () async {
    await index.replaceLinksFrom('a', [link('a', 'c')]);
    await index.replaceLinksFrom('b', [link('b', 'c')]);

    final backlinks = await index.backlinksTo('c');
    expect(backlinks.map((l) => l.sourceNoteId), unorderedEquals(['a', 'b']));
  });

  test('replacing a note\'s links removes the ones it dropped', () async {
    await index.replaceLinksFrom('a', [link('a', 'b'), link('a', 'c')]);
    await index.replaceLinksFrom('a', [link('a', 'c')]);

    expect(await index.outgoingFrom('a'), hasLength(1));
    expect(await index.backlinksTo('b'), isEmpty);
  });

  test('replacing with an empty list clears outgoing but spares incoming',
      () async {
    await index.replaceLinksFrom('a', [link('a', 'b')]);
    await index.replaceLinksFrom('b', [link('b', 'a')]);

    await index.replaceLinksFrom('a', const []);

    expect(await index.outgoingFrom('a'), isEmpty);
    expect(await index.backlinksTo('a'), hasLength(1));
  });

  test('display text survives the round trip', () async {
    await index.replaceLinksFrom('a', [link('a', 'b', 'Hexagonal')]);
    expect((await index.outgoingFrom('a')).single.displayText, 'Hexagonal');
  });

  test('removeNote drops edges in both directions', () async {
    await index.replaceLinksFrom('a', [link('a', 'b')]);
    await index.replaceLinksFrom('b', [link('b', 'c')]);

    await index.removeNote('b');

    expect(await index.backlinksTo('b'), isEmpty);
    expect(await index.outgoingFrom('b'), isEmpty);
    expect(await index.count(), 0);
  });

  test('count and clear cover the whole index', () async {
    await index.replaceLinksFrom('a', [link('a', 'b'), link('a', 'c')]);
    expect(await index.count(), 2);

    await index.clear();
    expect(await index.count(), 0);
  });

  test('re-indexing the same pair does not duplicate the edge', () async {
    await index.replaceLinksFrom('a', [link('a', 'b')]);
    await index.replaceLinksFrom('a', [link('a', 'b', 'renamed')]);

    expect(await index.count(), 1);
    expect((await index.outgoingFrom('a')).single.displayText, 'renamed');
  });
}

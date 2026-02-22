import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('Delete db path', (tester) async {
    final dir = await getApplicationDocumentsDirectory();
    final dbFolder = Directory(p.join(dir.path, 'NoteX'));
    if (dbFolder.existsSync()) {
      dbFolder.deleteSync(recursive: true);
      print('Deleted NoteX database folder at: ' + dbFolder.path);
    } else {
      print('Not found: ' + dbFolder.path);
    }
  });
}

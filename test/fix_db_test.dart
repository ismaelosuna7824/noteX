import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Delete db path', () {
    final appData = Platform.environment['APPDATA'];
    final userProfile = Platform.environment['USERPROFILE'];
    
    final paths = [
      if (appData != null) '$appData\\NoteX',
      if (userProfile != null) '$userProfile\\Documents\\NoteX',
      if (userProfile != null) '$userProfile\\AppData\\Local\\NoteX',
      if (userProfile != null) '$userProfile\\AppData\\Roaming\\NoteX',
    ];

    for (var path in paths) {
      final dir = Directory(path);
      if (dir.existsSync()) {
        print('Found and deleting: $path');
        dir.deleteSync(recursive: true);
      }
    }
  });
}

import 'package:appstudio/util/command_output.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('commandOutputLines', () {
    test('drops colour codes and keeps a redrawn line as last drawn', () {
      expect(
        commandOutputLines(
          '\x1B[33m⠋ Downloading...\r⠙ Downloading...\r✓ Downloaded.\x1B[0m\n'
          'done\n',
        ),
        ['✓ Downloaded.', 'done'],
      );
    });

    test('folds runs of blank lines and trims the ends', () {
      expect(
        commandOutputLines('\n\na  \r\n\n\n\nb\n\n'),
        ['a', '', 'b'],
      );
    });
  });

  group('failureExcerpt', () {
    test('starts just above the first error line', () {
      final lines = [
        for (var i = 0; i < 30; i++) '+ package_$i 1.0.0',
        'Compiling bin/serverpod_cli.dart...',
        'lib/a.dart:1:2: Error: first',
        'lib/b.dart:3:4: Error: second',
        'Failed to build serverpod_cli:serverpod_cli.',
      ];

      expect(
        failureExcerpt(lines).split('\n'),
        [
          '+ package_29 1.0.0',
          'Compiling bin/serverpod_cli.dart...',
          'lib/a.dart:1:2: Error: first',
          'lib/b.dart:3:4: Error: second',
          'Failed to build serverpod_cli:serverpod_cli.',
        ],
      );
    });

    test('knows git, the Serverpod CLI and lowercase errors', () {
      for (final line in [
        'fatal: not a git repository',
        'error: Your local changes would be overwritten',
        'ERROR: Project fine already exists.',
      ]) {
        expect(
          failureExcerpt(['one', 'two', 'three', line], context: 0),
          line,
          reason: line,
        );
      }
    });

    test('is not fooled by a count of errors or a word in passing', () {
      final lines = [
        for (var i = 0; i < 25; i++) 'line $i',
        'Found 0 errors.',
        'An error occurred while fetching',
      ];

      // No error line, so the tail.
      expect(failureExcerpt(lines).split('\n'), hasLength(20));
    });

    test('with no error line, the last lines', () {
      final lines = [for (var i = 0; i < 30; i++) 'line $i'];

      expect(failureExcerpt(lines, tailLines: 5), 'line 25\nline 26\n'
          'line 27\nline 28\nline 29');
    });
  });
}

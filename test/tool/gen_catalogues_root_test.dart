import 'package:flutter_test/flutter_test.dart';

import '../../tool/gen_catalogues.dart';

/// The generator once defaulted to one developer's checkout. These tests pin
/// the replacement contract: a root must be named, and naming none is a
/// failure that says how to fix it.
void main() {
  test('--longshot-root wins over the environment', () {
    final root = resolveLongshotRoot(
      flagValue: '/srv/longshot',
      environment: const {longshotRootEnvVar: '/env/longshot'},
    );

    expect(root, '/srv/longshot');
  });

  test('LONGSHOT_ROOT is used when the flag is absent', () {
    final root = resolveLongshotRoot(
      flagValue: null,
      environment: const {longshotRootEnvVar: '/env/longshot'},
    );

    expect(root, '/env/longshot');
  });

  test('a blank flag or variable counts as unset', () {
    expect(
      () => resolveLongshotRoot(
        flagValue: '  ',
        environment: const {longshotRootEnvVar: ''},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains('--longshot-root'), contains(longshotRootEnvVar)),
        ),
      ),
    );
  });

  test('neither given fails naming the flag and the environment variable', () {
    expect(
      () => resolveLongshotRoot(
        flagValue: null,
        environment: const <String, String>{},
      ),
      throwsA(
        isA<StateError>()
            .having(
              (error) => error.message,
              'message',
              contains('--longshot-root <path>'),
            )
            .having(
              (error) => error.message,
              'message',
              contains(longshotRootEnvVar),
            )
            .having(
              (error) => error.message,
              'message',
              contains('There is no default'),
            ),
      ),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/update_policy.dart';

void main() {
  group('UpdatePolicy.evaluate contract tests', () {
    test('current version below minSupported requires update', () {
      final result = UpdatePolicy.evaluate(
        currentVersion: '1.3.9',
        minSupportedVersion: '1.4.0',
        latestVersion: '1.5.0',
      );
      expect(result, UpdateRequirement.required);
    });

    test('current version below latest but supported offers optional update', () {
      final result = UpdatePolicy.evaluate(
        currentVersion: '1.4.0',
        minSupportedVersion: '1.4.0',
        latestVersion: '1.5.0',
      );
      expect(result, UpdateRequirement.optional);
    });

    test('current version equal to or above latest requires no update', () {
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.5.0',
          minSupportedVersion: '1.4.0',
          latestVersion: '1.5.0',
        ),
        UpdateRequirement.none,
      );

      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.6.0',
          minSupportedVersion: '1.4.0',
          latestVersion: '1.5.0',
        ),
        UpdateRequirement.none,
      );
    });

    test('numeric comparison correctly handles multi-digit version numbers', () {
      // 1.10.0 is greater than 1.4.0 numerically, but smaller alphabetically!
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.10.0',
          minSupportedVersion: '1.4.0',
          latestVersion: '1.10.0',
        ),
        UpdateRequirement.none,
      );

      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4.0',
          minSupportedVersion: '1.2.0',
          latestVersion: '1.10.0',
        ),
        UpdateRequirement.optional,
      );
    });

    test('missing trailing segments are treated as zero', () {
      // 1.4 is equivalent to 1.4.0
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4',
          minSupportedVersion: '1.4.0',
          latestVersion: '1.4.0',
        ),
        UpdateRequirement.none,
      );

      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.3.9',
          minSupportedVersion: '1.4',
          latestVersion: '2.0',
        ),
        UpdateRequirement.required,
      );
    });

    test('malformed versions safely return UpdateRequirement.none', () {
      // Empty string
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '',
          minSupportedVersion: '1.0.0',
          latestVersion: '2.0.0',
        ),
        UpdateRequirement.none,
      );

      // Letters / words
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.0.0-beta',
          minSupportedVersion: '1.0.0',
          latestVersion: '2.0.0',
        ),
        UpdateRequirement.none,
      );

      // Negative numbers
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '-1.0.0',
          minSupportedVersion: '1.0.0',
          latestVersion: '2.0.0',
        ),
        UpdateRequirement.none,
      );

      // Malformed minSupported or latest
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.0.0',
          minSupportedVersion: 'invalid',
          latestVersion: '2.0.0',
        ),
        UpdateRequirement.none,
      );

      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.0.0',
          minSupportedVersion: '1.0.0',
          latestVersion: 'not_a_version',
        ),
        UpdateRequirement.none,
      );
    });
  });
}

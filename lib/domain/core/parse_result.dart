/// Typed parse outcomes.
library;

import 'field_metadata.dart';
import 'identity.dart';
import 'save_project.dart';

/// The result of opening a save folder.
sealed class ParseResult {
  /// Allows subclasses to be const.
  const ParseResult();
}

/// Every slot opened and every declared field is verified.
final class const ParseOk(final SaveProject project) extends ParseResult;

/// The project opened, but some fields are not verified and are read-only.
final class const ParseUnverified(
  final SaveProject project,
  final List<FieldId> unverifiedFields,
) extends ParseResult;

/// The layout version is unknown, newer than supported, or gapped.
final class const ParseUnsupported(
  final String reason, {
  final int? detectedVersion,
}) extends ParseResult;

/// Input could not form a complete, well-formed project.
final class const ParseCorrupt(final String reason, {final ByteSpan? at})
    extends ParseResult;

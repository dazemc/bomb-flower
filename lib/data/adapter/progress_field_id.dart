import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/save/progress_record.dart';

/// Stable, slot-independent identity for one `progress.sav` record.
FieldId progressFieldId(ProgressRecord record) {
  final hex = record.key.toRadixString(16).padLeft(8, '0');
  return FieldId('progress.$hex');
}

/// Whether [id] is a well-formed, slot-independent `progress.sav` identity.
bool isProgressFieldId(FieldId id) => _progressFieldId.hasMatch(id.value);

/// The 32-bit record hash named by [id], or `null` when it is malformed.
int? progressHashFromFieldId(FieldId id) {
  if (!isProgressFieldId(id)) {
    return null;
  }
  return int.parse(id.value.substring('progress.'.length), radix: 16);
}

final RegExp _progressFieldId = RegExp(r'^progress\.[0-9a-f]{8}$');

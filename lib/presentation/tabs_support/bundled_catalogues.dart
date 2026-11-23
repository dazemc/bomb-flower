/// Process-wide cache for the bundled catalogues the tabs read.
///
/// Four tabs parse `assets/fields/groups.json` (1.3 MB) and the equipment tab
/// parses `assets/catalogue/actors.json`. Both assets are immutable for the
/// life of the process, so parsing them once and sharing the future removes a
/// measurable first-frame cost from every tab switch: the equipment tab paid
/// ~63 ms per visit just to re-parse the actor catalogue.
///
/// Tab constructors still accept an injected catalogue or loader; this cache is
/// only the production default path. A failed load is not cached, so a later
/// attempt retries instead of replaying the error forever.
library;

import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/catalogue/actor_catalogue.dart';
import '../../domain/fields/field_groups.dart';

Future<FieldGroupsCatalogue>? _groups;
Future<ActorCatalogue>? _actors;

/// The bundled field-group catalogue, parsed at most once per process.
Future<FieldGroupsCatalogue> loadFieldGroupsCatalogueOnce() {
  final cached = _groups;
  if (cached != null) {
    return cached;
  }
  final future = rootBundle
      .loadString('assets/fields/groups.json')
      .then(FieldGroupsCatalogue.load);
  _groups = future;
  // Let the next attempt retry rather than pin a permanent failure. The
  // handler returns normally, so this derived future never reports an
  // unobserved error.
  unawaited(
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        if (identical(_groups, future)) {
          _groups = null;
        }
      },
    ),
  );
  return future;
}

/// The bundled actor catalogue, parsed at most once per process.
Future<ActorCatalogue> loadActorCatalogueOnce() {
  final cached = _actors;
  if (cached != null) {
    return cached;
  }
  final future = rootBundle
      .loadString('assets/catalogue/actors.json')
      .then(loadActorCatalogue);
  _actors = future;
  unawaited(
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        if (identical(_actors, future)) {
          _actors = null;
        }
      },
    ),
  );
  return future;
}

/// Forgets the cached catalogues. Tests use this to keep cases hermetic.
void resetBundledCatalogueCache() {
  _groups = null;
  _actors = null;
}

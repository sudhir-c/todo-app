import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// One-time import of the pre-Firebase on-device data (exported to
/// assets/legacy_import.json) into the signed-in user's Firestore data.
///
/// Guarded by a per-account flag so it runs at most once. If the asset is
/// missing or empty, it does nothing and does not set the flag.
Future<void> migrateLegacyDataIfNeeded() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);
  final flagRef = userDoc.collection('meta').doc('legacy_import');

  final flagSnap = await flagRef.get();
  if (flagSnap.data()?['done'] == true) return;

  // Load the bundled export.
  Map<String, dynamic> data;
  try {
    final raw = await rootBundle.loadString('assets/legacy_import.json');
    data = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return; // no export bundled — nothing to do
  }

  final tags = (data['tags'] as List?) ?? const [];
  final recurring = (data['recurring'] as List?) ?? const [];
  final todos = (data['todos'] as List?) ?? const [];
  final skips = (data['skips'] as List?) ?? const [];
  if (todos.isEmpty && tags.isEmpty && recurring.isEmpty) return;

  // Tags: legacy int id -> new Firestore doc id.
  final tagIdMap = <int, String>{};
  for (final t in tags) {
    final ref = await userDoc.collection('tags').add({
      'name': t['name'],
      'color': t['color'],
      'position': t['position'],
    });
    tagIdMap[t['id'] as int] = ref.id;
  }

  // Recurring rules: legacy int id -> new doc id (remapping tag reference).
  final ruleIdMap = <int, String>{};
  for (final r in recurring) {
    final oldTag = r['tag_id'] as int?;
    final ref = await userDoc.collection('recurring').add({
      'description': r['description'],
      'tag_id': oldTag == null ? null : tagIdMap[oldTag],
      'freq': r['freq'],
      'start_day_id': r['start_day_id'],
      'end_day_id': r['end_day_id'],
    });
    ruleIdMap[r['id'] as int] = ref.id;
  }

  // Todos (batched, staying under the 500-op Firestore batch limit).
  var batch = FirebaseFirestore.instance.batch();
  var ops = 0;
  var order = 0;
  Future<void> flush() async {
    if (ops == 0) return;
    await batch.commit();
    batch = FirebaseFirestore.instance.batch();
    ops = 0;
  }

  for (final td in todos) {
    final oldTag = td['tag_id'] as int?;
    final oldRule = td['recurring_id'] as int?;
    final ref = userDoc.collection('todos').doc();
    batch.set(ref, {
      'day_id': td['day_id'],
      'is_completed': td['is_completed'],
      'description': td['description'],
      'tag_id': oldTag == null ? null : tagIdMap[oldTag],
      'recurring_id': oldRule == null ? null : ruleIdMap[oldRule],
      'order': order++,
    });
    ops++;
    if (ops >= 400) await flush();
  }
  await flush();

  // Recurring skips.
  for (final s in skips) {
    final oldRule = s['recurring_id'] as int?;
    final newRule = oldRule == null ? null : ruleIdMap[oldRule];
    if (newRule == null) continue;
    await userDoc.collection('recurring_skips').add({
      'recurring_id': newRule,
      'day_id': s['day_id'],
    });
  }

  await flagRef.set({
    'done': true,
    'migratedAt': FieldValue.serverTimestamp(),
    'todoCount': todos.length,
  });
}

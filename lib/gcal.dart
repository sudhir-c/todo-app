import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// Read-only Google Calendar access used to materialize events as todos.
///
/// The client ID is read from GIDClientID in each platform's Info.plist, so
/// there is no configuration to pass here.
const String kCalendarScope =
    'https://www.googleapis.com/auth/calendar.readonly';

/// A single event pulled from the user's primary calendar.
class GcalEvent {
  final String id;
  final String title;
  final DateTime? start; // local time; null for all-day events

  const GcalEvent({required this.id, required this.title, this.start});

  bool get allDay => start == null;
}

bool _initialized = false;

Future<void> _ensureInitialized() async {
  if (_initialized) return;
  await GoogleSignIn.instance.initialize();
  _initialized = true;
}

/// Interactive connect: Google sign-in plus a calendar.readonly grant.
/// Throws (with a readable message) on failure or cancellation.
Future<void> connectGoogleCalendar() async {
  await _ensureInitialized();
  final account = await GoogleSignIn.instance
      .authenticate(scopeHint: const [kCalendarScope]);
  await account.authorizationClient.authorizeScopes(const [kCalendarScope]);
}

Future<void> disconnectGoogleCalendar() async {
  await _ensureInitialized();
  await GoogleSignIn.instance.signOut();
}

/// Access token via silent re-auth only — never prompts. Null means the user
/// has to reconnect interactively on this device.
Future<String?> _calendarAccessToken() async {
  try {
    await _ensureInitialized();
    final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
    final account = attempt == null ? null : await attempt;
    if (account == null) {
      debugPrint('[gcal] silent auth: no account');
      return null;
    }
    final auth = await account.authorizationClient
        .authorizationForScopes(const [kCalendarScope]);
    if (auth == null) debugPrint('[gcal] silent auth: no authorization');
    return auth?.accessToken;
  } on GoogleSignInException catch (e) {
    debugPrint('[gcal] silent auth exception: ${e.code} ${e.description}');
    return null;
  } catch (e) {
    // The native SDK throws a PlatformException(invalid_grant) when the
    // stored refresh token has been expired or revoked. Drop the dead
    // session so the reconnect flow starts clean.
    debugPrint('[gcal] silent auth failed: $e');
    if (e.toString().contains('invalid_grant')) {
      await GoogleSignIn.instance.signOut();
    }
    return null;
  }
}

/// Events overlapping [day] (local time) from the primary calendar, with
/// recurring events expanded so each occurrence has its own id. Returns null
/// when no silent sign-in is available; throws on HTTP errors.
Future<List<GcalEvent>?> fetchGcalEventsForDay(DateTime day) async {
  final token = await _calendarAccessToken();
  if (token == null) return null;

  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  final uri = Uri.https(
    'www.googleapis.com',
    '/calendar/v3/calendars/primary/events',
    {
      'timeMin': dayStart.toUtc().toIso8601String(),
      'timeMax': dayEnd.toUtc().toIso8601String(),
      'singleEvents': 'true',
      'orderBy': 'startTime',
      'maxResults': '250',
    },
  );
  final response =
      await http.get(uri, headers: {'Authorization': 'Bearer $token'});
  debugPrint('[gcal] events fetch HTTP ${response.statusCode}');
  if (response.statusCode == 401) {
    // The cached token is no longer valid (e.g. the grant was revoked).
    // Drop the dead session so callers see "reconnect needed" instead of
    // an endlessly failing silent sync.
    await GoogleSignIn.instance.signOut();
    return null;
  }
  if (response.statusCode != 200) {
    throw 'Calendar API returned ${response.statusCode}: ${response.body}';
  }

  final json = jsonDecode(utf8.decode(response.bodyBytes));
  final items = (json['items'] as List?) ?? const [];
  final events = <GcalEvent>[];
  for (final raw in items) {
    final item = raw as Map<String, dynamic>;
    final id = item['id'] as String?;
    if (id == null || item['status'] == 'cancelled') continue;
    final start = (item['start'] as Map<String, dynamic>?) ?? const {};
    final startDateTime = start['dateTime'] as String?;
    final summary = (item['summary'] as String?)?.trim();
    events.add(GcalEvent(
      id: id,
      title: (summary == null || summary.isEmpty) ? '(untitled event)' : summary,
      start:
          startDateTime == null ? null : DateTime.parse(startDateTime).toLocal(),
    ));
  }
  return events;
}

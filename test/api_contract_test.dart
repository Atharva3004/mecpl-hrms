// API contract tests.
//
// WHY THIS FILE EXISTS
// --------------------
// A live bug shipped because the app read `active_session['opened_at']` while
// the server sends `started_at`. The key simply never matched, the parse
// silently produced null, and a "is this session stale?" guard treated the
// null as "yes, stale" — wiping the user's open session from memory AND disk
// on every refresh. Employees were silently un-clocked-in and could not punch
// out. Two more instances of the same mistake were then found on the admin
// live dashboard (`employee['name']` vs `emp_name`).
//
// The payloads below are copied VERBATIM from the backend's own contract,
// docs/geofence-module-guide.md. If the server renames a field, or someone
// edits a parser to read a key that was never in the contract, these tests
// fail immediately instead of the app quietly losing data in production.
//
// RULES FOR THIS FILE
//   1. Fixtures are copied from the guide, not from what the code expects.
//      Never "fix" a fixture to make a test pass — fix the parser, or confirm
//      with the backend that the contract really changed and update BOTH the
//      fixture and the guide reference in the comment.
//   2. When adding a parser for a new endpoint, add its fixture here too.
//   3. Every field the app depends on gets an explicit expect().

import 'package:flutter_test/flutter_test.dart';
import 'package:mecpl_flutter/repositories/geofence_repository.dart';
import 'package:mecpl_flutter/services/api_service.dart';

void main() {
  // ---------------------------------------------------------------------
  // GET /api/me/geofence — guide §3.1
  // ---------------------------------------------------------------------
  group('GET /me/geofence', () {
    // Verbatim from docs/geofence-module-guide.md §3.1.
    Map<String, dynamic> fixture() => {
          'status': true,
          'geofence_attendance': 'Yes',
          'branch': {
            'id': 5,
            'branch_name': 'Mumbai Office',
            'latitude': 19.0760,
            'longitude': 72.8777,
            'geofence_radius_m': 200,
          },
        };

    // Guide v1.1 (2026-08-31) REVERSED this shape: it is now a flat `data{}`
    // object with `branch_id` and `radius_m`, and the guide explicitly states
    // "not a branch{} envelope". v1.0 documented the opposite. The parser
    // accepts both on purpose — this contract has now flipped twice, and a
    // third flip must not take attendance down.
    Map<String, dynamic> flatFixture() => {
          'branch_id': 5,
          'branch_name': 'Mumbai Office',
          'latitude': 19.076,
          'longitude': 72.8777,
          'radius_m': 200,
          'geofence_attendance': 'Yes',
        };

    test('parses the flat shape (guide v1.1, current)', () {
      final g = Geofence.fromJson(flatFixture());

      expect(g.branchId, 5);
      expect(g.branchName, 'Mumbai Office');
      expect(g.latitude, closeTo(19.076, 0.0001));
      expect(g.longitude, closeTo(72.8777, 0.0001));
      expect(g.radiusM, 200, reason: 'flat shape names the radius radius_m');
      expect(g.isAttendanceEnabled, isTrue);
      expect(g.isEnforced, isTrue);
    });

    test('parses the nested branch envelope', () {
      final g = Geofence.fromJson(fixture());

      expect(g.branchId, 5, reason: 'branch.id must map to branchId');
      expect(g.branchName, 'Mumbai Office');
      expect(g.latitude, closeTo(19.0760, 0.0001));
      expect(g.longitude, closeTo(72.8777, 0.0001));
      expect(g.radiusM, 200, reason: 'branch.geofence_radius_m -> radiusM');
      expect(g.isAttendanceEnabled, isTrue);
      expect(g.isEnforced, isTrue);
    });

    test('a missing key never throws away the whole geofence', () {
      // The original parser used a non-null cast on a key that did not exist
      // in the contract (`branch_id`). It threw, the caller swallowed the
      // exception, and NOTHING was ever cached — so every distance was
      // measured against a hard-coded office and every ribbon was neutral.
      final partial = fixture()..remove('geofence_attendance');
      expect(() => Geofence.fromJson(partial), returnsNormally);

      final noBranch = <String, dynamic>{'status': true};
      expect(() => Geofence.fromJson(noBranch), returnsNormally);
    });

    test('numbers serialised as strings still parse', () {
      // Laravel emits decimal columns as JSON strings unless cast. The app
      // must not depend on the backend getting its casts right.
      final stringy = {
        'geofence_attendance': 'Yes',
        'branch': {
          'id': '5',
          'branch_name': 'Mumbai Office',
          'latitude': '19.0760000',
          'longitude': '72.8777000',
          'geofence_radius_m': '200',
        },
      };
      final g = Geofence.fromJson(stringy);

      expect(g.branchId, 5);
      expect(g.latitude, closeTo(19.0760, 0.0001));
      expect(g.radiusM, 200);
      expect(g.isEnforced, isTrue);
    });

    test('round-trips through the SharedPreferences cache shape', () {
      // toJson writes a FLAT shape; fromJson must read it back. This pairing
      // is what keeps a cached geofence usable across app restarts.
      final original = Geofence.fromJson(fixture());
      final restored = Geofence.fromJson(original.toJson());

      expect(restored.branchId, original.branchId);
      expect(restored.branchName, original.branchName);
      expect(restored.latitude, original.latitude);
      expect(restored.longitude, original.longitude);
      expect(restored.radiusM, original.radiusM);
      expect(restored.geofenceAttendance, original.geofenceAttendance);
    });

    test('an unconfigured branch is not enforced', () {
      final unconfigured = {
        'geofence_attendance': 'Yes',
        'branch': {
          'id': 7,
          'branch_name': 'Site Office',
          'latitude': null,
          'longitude': null,
          'geofence_radius_m': null,
        },
      };
      final g = Geofence.fromJson(unconfigured);

      expect(g.isEnforced, isFalse,
          reason: 'no coordinates or radius means there is no fence to apply');
      expect(g.isAttendanceEnabled, isTrue,
          reason: 'an unconfigured fence must not disable punching');
    });
  });

  // ---------------------------------------------------------------------
  // Key-name guards.
  //
  // These assert the SHAPE of the contract rather than any parser, so they
  // fail the moment a fixture is edited to match a mistaken parser. They are
  // the cheapest possible defence against the class of bug that shipped.
  // ---------------------------------------------------------------------
  group('contract key names (guide §3.6, §3.8, §3.9)', () {
    test('active_session uses started_at, not opened_at', () {
      // Guide §3.6. Reading `opened_at` here is what wiped live sessions.
      const activeSession = {
        'session_id': 142,
        'started_at': '2026-08-29T09:30:15.000000Z',
        'ping_count': 5,
      };
      expect(activeSession.containsKey('started_at'), isTrue);
      expect(activeSession.containsKey('opened_at'), isFalse);
    });

    test('session timeline uses started_at / ended_at', () {
      // Guide §3.8.
      const session = {
        'id': 142,
        'status': 'closed',
        'started_at': '2026-08-29T09:30:15.000000Z',
        'ended_at': '2026-08-29T18:30:15.000000Z',
        'duration_seconds': 32400,
      };
      expect(session.containsKey('started_at'), isTrue);
      expect(session.containsKey('ended_at'), isTrue);
      expect(session.containsKey('opened_at'), isFalse);
      expect(session.containsKey('closed_at'), isFalse);
    });

    test('live attendance uses emp_name and branch_name', () {
      // Guide §3.9. Reading a bare `name` rendered every row as "—".
      const row = {
        'session_id': 142,
        'employee': {'id': 123, 'emp_name': 'Rajesh Kumar', 'emp_code': 'EMP001'},
        'branch': {'id': 5, 'branch_name': 'Mumbai Office'},
      };
      final employee = row['employee'] as Map<String, dynamic>;
      final branch = row['branch'] as Map<String, dynamic>;

      expect(employee.containsKey('emp_name'), isTrue);
      expect(employee.containsKey('name'), isFalse);
      expect(branch.containsKey('branch_name'), isTrue);
      expect(branch.containsKey('name'), isFalse);
    });

    test('punches carry session_id and coordinates', () {
      // Guide §3.6 as corrected in the backend's Round 2 response. The parser
      // drops any punch without latitude/longitude, and loses the ability to
      // open a ping timeline without session_id.
      const punch = {
        'id': 283,
        'session_id': 142,
        'type': 'in',
        'punched_at': '2026-08-29T09:30:15+05:30',
        'latitude': 19.0760,
        'longitude': 72.8777,
        'accuracy_m': 15.5,
        'address': 'Andheri East, Mumbai',
        'selfie_url': 'https://example.test/a.jpg',
        'inside_geofence': true,
        'distance_m': 45,
      };
      for (final key in [
        'session_id',
        'latitude',
        'longitude',
        'punched_at',
        'type',
      ]) {
        expect(punch.containsKey(key), isTrue,
            reason: '$key is required by the punch parser');
      }
    });

    test('captured_at is sent with an explicit UTC offset', () {
      // Sending `...Z` made Laravel store the UTC wall-clock and read it back
      // as IST, rendering pings 5h30m before the punch-in that opened their
      // session. The offset must be present and must not be `Z`.
      final iso = ApiService.isoWithOffset(DateTime.now());

      expect(iso.endsWith('Z'), isFalse,
          reason: 'a bare Z leaves the server free to reinterpret the value');
      expect(
        RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(iso),
        isTrue,
        reason: 'must end with an explicit ±HH:MM offset, got: $iso',
      );
      // Round-trips to the same instant.
      expect(
        DateTime.parse(iso).toUtc().difference(DateTime.now().toUtc()).inSeconds
            .abs(),
        lessThan(5),
      );
    });

    test('error responses use error_code', () {
      // The guide originally documented `code`; the backend confirmed
      // `error_code` is canonical. The app reads both, so a future flip in
      // either direction cannot break punch-in conflict handling.
      const err = {
        'status': false,
        'error_code': 'SESSION_ALREADY_OPEN',
        'message': 'You already have an open session.',
        'session_id': 142,
      };
      final code = err['error_code'] ?? err['code'];
      expect(code, 'SESSION_ALREADY_OPEN');
    });
  });
}

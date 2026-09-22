// API Service - HTTP Client for HRMS API
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../core/constants/api_constants.dart';
import '../models/user_model.dart';
import '../models/leave_application_model.dart';
import '../models/leave_balance_model.dart';
import '../models/leave_calculation_model.dart';
import '../models/leave_type_model.dart';
import '../models/role_model.dart';
import '../models/attendance_model.dart';
import '../models/leave_info_model.dart';
import '../models/payroll_request_model.dart';
import '../models/branch_model.dart';
import '../models/employee_leaves_list_result.dart';
import '../models/notification_item.dart';
import '../models/requisition_model.dart';
import '../models/form16_status_model.dart';
import '../models/my_documents_model.dart';
import 'session_manager.dart';

class ApiService {
  /// ISO-8601 with an EXPLICIT local UTC offset, e.g.
  /// `2026-08-31T16:27:05.000+05:30`.
  ///
  /// We used to send `.toUtc().toIso8601String()` (…T10:57:05.000Z). Laravel
  /// parses that to the right instant, but Eloquent then writes the Carbon's
  /// own timezone straight into the datetime column — storing `10:57` — and
  /// reads it back in the app timezone (Asia/Kolkata), turning it into
  /// 10:57 **IST**. The result was location pings rendering 5h30m before the
  /// punch-in that opened their session.
  ///
  /// Dart's `toIso8601String()` omits the offset for a local DateTime, so it
  /// has to be appended by hand. Sending the offset makes the value
  /// unambiguous whichever way the server normalises it.
  static String isoWithOffset(DateTime dt) {
    final local = dt.toLocal();
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hh = offset.inHours.abs().toString().padLeft(2, '0');
    final mm = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '${local.toIso8601String()}$sign$hh:$mm';
  }

  /// Inline 401 detector for the legacy code paths that still call
  /// `http.get/post` directly. Notifies SessionManager so main.dart can
  /// kick the user back to the login screen + show a snackbar.
  ///
  /// Skipped intentionally inside `login()` — a 401 there is a wrong-password
  /// response, not an expired session.
  static void _checkAuth(int statusCode) {
    if (statusCode == 401) {
      SessionManager.instance.markExpired(
        reason: 'Your session has expired. Please login again.',
      );
    }
  }

  // Login API call
  static Future<ApiResponse> login({
    required String empCode,
    required String password,
    String? deviceName,
    String? osVersion,
    String? appVersion,
    String? fcmToken,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.loginEndpoint}'),
      );

      request.fields.addAll({
        'emp_code': empCode,
        'password': password,
        if (deviceName != null && deviceName.isNotEmpty)
          'device_name': deviceName,
        if (osVersion != null && osVersion.isNotEmpty) 'os_version': osVersion,
        if (appVersion != null && appVersion.isNotEmpty)
          'app_version': appVersion,
        // Stored against the user so the backend can target this specific
        // device via FCM (push notifications). Optional — older backend builds
        // that don't yet read this field will simply ignore it.
        if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken,
      });
      request.headers.addAll(ApiConstants.headers);

      http.StreamedResponse response = await request.send();
      String responseBody = await response.stream.bytesToString();

      // NOTE: deliberately no _checkAuth() here — a 401 on the login endpoint
      // is "wrong employee code / password", not an expired session.
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return ApiResponse.success(data);
      } else if (response.statusCode == 401) {
        return ApiResponse.error('Incorrect Employee Code or Password');
      } else {
        return ApiResponse.error('Login failed: ${response.reasonPhrase}');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// Verifies that the persisted token still works server-side. Called from
  /// `AuthProvider._bootstrap` on app start and from anywhere we want a
  /// pre-flight check before showing authenticated UI.
  ///
  /// Returns `true` only on a 200 response. A 401 fires SessionManager and
  /// returns false. Network errors throw so callers can distinguish "token
  /// is bad" from "we can't reach the server right now" (in which case we
  /// fall back to optimistic resume).
  static Future<bool> validateToken(String token) async {
    final response = await http
        .get(
          Uri.parse(
            '${ApiConstants.baseUrl}${ApiConstants.validateTokenEndpoint}',
          ),
          headers: {...ApiConstants.headers, 'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      return true;
    }
    if (response.statusCode == 401) {
      // Don't fire SessionManager from here — the bootstrap path handles the
      // expiry directly and we don't want a duplicate snackbar before the
      // login screen even mounts.
      return false;
    }
    throw HttpException(
      'validate-token failed (${response.statusCode}): ${response.reasonPhrase}',
    );
  }

  /// Updates the FCM device token for the currently logged-in user. Called
  /// from `NotificationService.onTokenRefresh` when FCM rotates the token
  /// (app reinstall, data clear, manual delete from Firebase Console).
  /// Best-effort — failure just means the next login will re-register.
  static Future<void> updateFcmToken({
    required String authToken,
    required String fcmToken,
  }) async {
    try {
      await http
          .post(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.updateFcmTokenEndpoint}',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $authToken',
            },
            body: {'fcm_token': fcmToken},
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('⚠️ updateFcmToken failed (ignored): $e');
    }
  }

  /// Fetches a paginated page of in-app notifications for the current user.
  /// Throws on network / non-2xx errors so the provider can show an error
  /// state. 401s also fire `SessionManager` via `_checkAuth`.
  static Future<NotificationPage> fetchNotifications({
    required String authToken,
    int page = 1,
    int perPage = 20,
  }) async {
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.notificationsEndpoint}'
      '?page=$page&per_page=$perPage',
    );
    final response = await http
        .get(
          uri,
          headers: {
            ...ApiConstants.headers,
            'Authorization': 'Bearer $authToken',
          },
        )
        .timeout(const Duration(seconds: 15));
    _checkAuth(response.statusCode);
    if (response.statusCode != 200) {
      throw HttpException(
        'fetchNotifications failed (${response.statusCode}): ${response.reasonPhrase}',
      );
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    return NotificationPage.fromJson(body);
  }

  /// Lightweight badge poll — just the unread count, no list. Used on app
  /// resume / periodic refresh to update the bell without re-fetching the
  /// full notification list.
  static Future<int> fetchUnreadCount({required String authToken}) async {
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.notificationsUnreadCountEndpoint}',
    );
    final response = await http
        .get(
          uri,
          headers: {
            ...ApiConstants.headers,
            'Authorization': 'Bearer $authToken',
          },
        )
        .timeout(const Duration(seconds: 10));
    _checkAuth(response.statusCode);
    if (response.statusCode != 200) {
      throw HttpException(
        'fetchUnreadCount failed (${response.statusCode}): ${response.reasonPhrase}',
      );
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>? ?? const {};
    final raw = data['unread_count'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  /// Marks one notification as read. Returns true on success — the provider
  /// uses this to confirm before flipping the local `isRead` flag.
  static Future<bool> markNotificationRead({
    required String authToken,
    required int notificationId,
  }) async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.notificationsEndpoint}'
        '/$notificationId/mark-as-read',
      );
      final response = await http
          .post(
            uri,
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $authToken',
            },
          )
          .timeout(const Duration(seconds: 10));
      _checkAuth(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('⚠️ markNotificationRead($notificationId) failed: $e');
      return false;
    }
  }

  /// Marks every notification belonging to the current user as read. Returns
  /// true on success.
  static Future<bool> markAllNotificationsRead({
    required String authToken,
  }) async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.notificationsMarkAllReadEndpoint}',
      );
      final response = await http
          .post(
            uri,
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $authToken',
            },
          )
          .timeout(const Duration(seconds: 10));
      _checkAuth(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('⚠️ markAllNotificationsRead failed: $e');
      return false;
    }
  }

  /// Server-side logout — deletes the current token. Called from
  /// `AuthProvider.logout()` before clearing local state. Best-effort: any
  /// network/server error is swallowed so the user can always log out
  /// locally even if offline.
  static Future<void> logoutApi(String token) async {
    try {
      await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.logoutEndpoint}'),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('⚠️ Server logout failed (ignored): $e');
    }
  }

  // Parse user from API response
  static UserModel? parseUserFromResponse(Map<String, dynamic> data) {
    try {
      final userData = data['user'] as Map<String, dynamic>;
      return _parseSingleUser(userData);
    } catch (e) {
      print('Error parsing user data: $e');
      return null;
    }
  }

  // Parse list of employees from response
  static List<UserModel> parseEmployeesFromResponse(Map<String, dynamic> data) {
    try {
      final List<dynamic> employeesData =
          data['data'] ?? data['employees'] ?? [];
      return employeesData
          .map((json) => _parseSingleUser(json as Map<String, dynamic>))
          .whereType<UserModel>()
          .toList();
    } catch (e) {
      print('Error parsing employees: $e');
      return [];
    }
  }

  // Parse daily attendance records where each record wraps an 'employee' object
  static List<UserModel> parseDailyAttendanceFromResponse(
    dynamic responseData,
  ) {
    try {
      final List<dynamic> records = responseData is List
          ? responseData
          : (responseData['data'] ?? []);
      return records
          .map((record) {
            final Map<String, dynamic> recordMap =
                record as Map<String, dynamic>;
            final Map<String, dynamic>? empMap =
                recordMap['employee'] as Map<String, dynamic>?;
            if (empMap == null) return null;

            // Inject attendance details into employee object
            final updatedEmpMap = Map<String, dynamic>.from(empMap);
            updatedEmpMap['status'] = recordMap['status'];
            updatedEmpMap['firstIn'] = recordMap['first_in'];
            updatedEmpMap['lastOut'] = recordMap['last_out'];
            updatedEmpMap['totalWorkHours'] = recordMap['total_work_hours'];

            return _parseSingleUser(updatedEmpMap);
          })
          .whereType<UserModel>()
          .toList();
    } catch (e) {
      print('Error parsing daily attendance list: $e');
      return [];
    }
  }

  // Helper to parse a single user object
  static UserModel? _parseSingleUser(Map<String, dynamic> userData) {
    try {
      // 1. Get Name
      final fullName =
          userData['emp_name']?.toString() ??
          userData['name']?.toString() ??
          'User';
      final nameParts = fullName.split(' ');
      final firstName = nameParts.isNotEmpty ? nameParts.first : 'User';
      final lastName = nameParts.length > 1 ? nameParts.skip(1).join(' ') : '';

      // 2. Extract company_details if present
      final companyDetails =
          userData['company_details'] as Map<String, dynamic>?;

      // 3. Get Role
      final roleFromApi =
          (companyDetails?['role'] ?? userData['role'])?.toString() ??
          'employee';
      UserRole role = _mapApiRoleToUserRole(roleFromApi);

      // 4. Get Designation and Department
      String designation = '';
      final desgObj = companyDetails?['designation'];
      if (desgObj is Map) {
        designation = desgObj['designation_name']?.toString() ?? '';
      } else {
        designation =
            desgObj?.toString() ?? userData['designation']?.toString() ?? '';
      }

      String department = '';
      final deptObj = companyDetails?['department'];
      if (deptObj is Map) {
        department = deptObj['department_name']?.toString() ?? '';
      } else {
        department =
            deptObj?.toString() ?? userData['department']?.toString() ?? '';
      }

      // 5. Get Branch ID
      final branchIdStr =
          (companyDetails?['br_id'] ??
                  userData['branch_id'] ??
                  userData['branchId'] ??
                  userData['br_id'])
              ?.toString();
      final branchId = int.tryParse(branchIdStr ?? '');

      // 6. Get DOB with robust fallbacks
      final rawDob =
          userData['dob'] ??
          userData['date_of_birth'] ??
          userData['birth_date'] ??
          companyDetails?['dob'] ??
          companyDetails?['date_of_birth'] ??
          companyDetails?['birth_date'];
      final dob = DateTime.tryParse(rawDob?.toString() ?? '');

      // 7. Get Address with robust fallbacks
      final addressValue =
          userData['address']?.toString() ??
          userData['personal_address']?.toString() ??
          userData['current_address']?.toString() ??
          userData['permanent_address']?.toString() ??
          companyDetails?['address']?.toString() ??
          '';

      // 8. Get Joining Date with robust fallbacks
      final rawJoinDate =
          companyDetails?['doj'] ??
          companyDetails?['joining_date'] ??
          userData['doj'] ??
          userData['joining_date'];
      final joinDate = DateTime.tryParse(rawJoinDate?.toString() ?? '');

      return UserModel(
        id:
            userData['user_id']?.toString() ??
            userData['id']?.toString() ??
            '0',
        employeeId:
            (companyDetails?['emp_code'] ?? userData['emp_code'])?.toString() ??
            '',
        firstName: firstName,
        lastName: lastName,
        email: userData['email']?.toString() ?? '',
        phone: (userData['mobile_no'] ?? userData['mobile'])?.toString() ?? '',
        designation: designation,
        department: department,
        role: role,
        avatarUrl: userData['emp_image']?.toString(),
        joinDate: joinDate,
        branchId: branchId,
        dob: dob,
        address: addressValue,
        status: userData['status']?.toString(),
        firstIn: userData['firstIn']?.toString(),
        lastOut: userData['lastOut']?.toString(),
        totalWorkHours: userData['totalWorkHours']?.toString(),
      );
    } catch (e) {
      print('Error parsing single user: $e');
      return null;
    }
  }

  // Map API role string to UserRole enum
  static UserRole _mapApiRoleToUserRole(String roleString) {
    final roleLower = roleString.toLowerCase().trim();

    switch (roleLower) {
      case 'director':
        return UserRole.director;
      case 'manager':
        return UserRole.manager;
      case 'admin':
        return UserRole.admin;
      case 'hr admin':
      case 'hr-admin':
      case 'hradmin':
        return UserRole.hrAdmin;
      case 'staff':
        return UserRole.staff;
      case 'on-site admin':
      case 'onsite admin':
      case 'onsiteadmin':
      case 'site-admin':
      case 'site admin':
        return UserRole.onSiteAdmin;
      case 'ho hr':
      case 'ho-hr':
      case 'hohr':
        return UserRole.hoHr;
      case 'employee':
      default:
        return UserRole.employee;
    }
  }

  // Get auth token from response
  static String? getTokenFromResponse(Map<String, dynamic> data) {
    return data['token']?.toString();
  }

  // Get all employees
  static Future<ApiResponse> getEmployees(String token) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.employeeEndpoint}',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error(
          'Failed to fetch employees: ${response.reasonPhrase}',
        );
      }
    } on TimeoutException catch (_) {
      return ApiResponse.error(
        'Connection timed out. Please check your internet connection.',
      );
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Get Pre-Recruitment candidates (interviewed / shortlisted candidates list)
  static Future<ApiResponse> getPreRecruitmentCandidates(String token) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.preRecruitmentCandidatesEndpoint}',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error(
          'Failed to fetch candidates: ${response.reasonPhrase}',
        );
      }
    } on TimeoutException catch (_) {
      return ApiResponse.error(
        'Connection timed out. Please check your internet connection.',
      );
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Submit Pre-Recruitment joining details (photo + statutory PF/ESI info).
  // Multipart POST so the optional candidate photo (emp_image) can be uploaded.
  // `pf` / `esi` are 'Yes'/'No' flags; `uanNo` / `esiNo` are free-text numbers.
  static Future<ApiResponse> submitPreRecruitmentDetails({
    required String token,
    required String id,
    String? photoPath,
    required String pf,
    required String uanNo,
    required String esi,
    required String esiNo,
    required String remarks,
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.preRecruitmentSubmitDetailsEndpoint}',
      );
      final request = http.MultipartRequest('POST', url);

      request.fields.addAll({
        'id': id,
        'pf': pf,
        'uan_no': uanNo,
        'esi': esi,
        'esi_no': esiNo,
        'remarks': remarks,
      });

      // Attach a freshly captured local photo, if any. Skip remote URLs
      // (an existing emp_image returned by the GET) — only new files upload.
      if (photoPath != null &&
          photoPath.isNotEmpty &&
          !photoPath.startsWith('http')) {
        final file = File(photoPath);
        if (await file.exists()) {
          request.files.add(
            await http.MultipartFile.fromPath('emp_image', photoPath),
          );
        }
      }

      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      final streamed = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final body = await streamed.stream.bytesToString();

      _checkAuth(streamed.statusCode);
      if (streamed.statusCode == 200 || streamed.statusCode == 201) {
        try {
          final data = json.decode(body);
          if (data is Map<String, dynamic>) {
            if (data['status'] == false) {
              return ApiResponse.error(
                data['message']?.toString() ?? 'Failed to submit details',
              );
            }
            return ApiResponse.success(data);
          }
          return ApiResponse.success({'message': 'Success'});
        } catch (_) {
          return ApiResponse.success({'message': 'Success'});
        }
      } else {
        try {
          final data = json.decode(body);
          return ApiResponse.error(
            data['message']?.toString() ??
                'Failed to submit details (${streamed.statusCode})',
          );
        } catch (_) {
          return ApiResponse.error(
            'Failed to submit details (${streamed.statusCode}): ${streamed.reasonPhrase}',
          );
        }
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Form 16 — which parts exist for the logged-in employee this financial
  // year. Returns null on any failure so the caller can render an error state
  // rather than distinguishing every network fault.
  static Future<Form16Status?> fetchForm16Status({
    required String token,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.form16StatusEndpoint}',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      _checkAuth(response.statusCode);
      if (response.statusCode != 200) {
        debugPrint(
          '❌ [API] Form 16 status failed: ${response.statusCode} ${response.reasonPhrase}',
        );
        return null;
      }
      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['status'] != true) {
        debugPrint('❌ [API] Form 16 status returned status:false');
        return null;
      }
      return Form16Status.fromJson(decoded);
    } catch (e) {
      debugPrint('❌ [API] fetchForm16Status error: $e');
      return null;
    }
  }

  /// Fetches one Form 16 part as raw PDF bytes. [id] comes from the status
  /// response. Returns null on failure, or if the server answers with JSON
  /// (an error envelope) instead of a PDF.
  static Future<Uint8List?> fetchForm16PdfBytes({
    required String token,
    required int id,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.form16DownloadEndpoint}/$id',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
              // The status call wants JSON; this one wants the file.
              'Accept': 'application/pdf',
            },
          )
          .timeout(const Duration(seconds: 60));

      _checkAuth(response.statusCode);
      if (response.statusCode != 200) {
        debugPrint(
          '❌ [API] Form 16 download $id failed: ${response.statusCode} ${response.reasonPhrase}',
        );
        return null;
      }
      final bytes = response.bodyBytes;
      // A Laravel error envelope comes back 200-with-JSON often enough to be
      // worth rejecting explicitly — a real PDF always starts with '%PDF'.
      if (bytes.length < 5 ||
          bytes[0] != 0x25 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x44 ||
          bytes[3] != 0x46) {
        debugPrint('❌ [API] Form 16 download $id did not return a PDF');
        return null;
      }
      return bytes;
    } catch (e) {
      debugPrint('❌ [API] fetchForm16PdfBytes error: $e');
      return null;
    }
  }

  // My Documents — Form 16 (TRACES parts + MECPL file list) and the medical
  // health card for the current financial year, in one call. Returns null on
  // any failure (including "no financial year configured", which the server
  // answers with 404) so the caller renders one "not available" state rather
  // than distinguishing every fault.
  static Future<MyDocuments?> fetchMyDocuments({required String token}) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.myDocumentsEndpoint}',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      _checkAuth(response.statusCode);
      if (response.statusCode != 200) {
        debugPrint(
          '❌ [API] My documents failed: ${response.statusCode} ${response.reasonPhrase}',
        );
        return null;
      }
      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['status'] != true) {
        debugPrint('❌ [API] My documents returned status:false');
        return null;
      }
      return MyDocuments.fromJson(decoded);
    } catch (e) {
      debugPrint('❌ [API] fetchMyDocuments error: $e');
      return null;
    }
  }

  /// Fetches the medical health card as raw PDF bytes. [id] comes from
  /// `health_card.id` in the my-documents response. Returns null on failure,
  /// or if the server answers with JSON (an error envelope) instead of a PDF.
  static Future<Uint8List?> fetchHealthCardPdfBytes({
    required String token,
    required int id,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.healthCardDownloadEndpoint}/$id',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
              'Accept': 'application/pdf',
            },
          )
          .timeout(const Duration(seconds: 60));

      _checkAuth(response.statusCode);
      if (response.statusCode != 200) {
        debugPrint(
          '❌ [API] Health card download $id failed: ${response.statusCode} ${response.reasonPhrase}',
        );
        return null;
      }
      final bytes = response.bodyBytes;
      // Same guard as Form 16: a real PDF always starts with '%PDF', while a
      // Laravel error envelope can come back 200-with-JSON.
      if (bytes.length < 5 ||
          bytes[0] != 0x25 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x44 ||
          bytes[3] != 0x46) {
        debugPrint('❌ [API] Health card download $id did not return a PDF');
        return null;
      }
      return bytes;
    } catch (e) {
      debugPrint('❌ [API] fetchHealthCardPdfBytes error: $e');
      return null;
    }
  }

  /// Fetches one HR letter as raw PDF bytes.
  ///
  /// [type] is the route slug (`warning`, `confirmation`, `extension`,
  /// `experience`, `promotion`, `appointment`) and [category] the employment
  /// category the letter is issued under (`staff` | `apprentice` |
  /// `consultant`) — HR keeps a separate template per category.
  ///
  /// Returns the bytes on success, or an [error] message fit to show the user.
  /// 404 is the normal "nothing on file" answer, not a fault, so it gets its
  /// own wording rather than the generic failure text.
  static Future<({Uint8List? bytes, String? error})> fetchLetterPdfBytes({
    required String token,
    required String type,
    required String category,
  }) async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.lettersEndpoint}/$type',
      ).replace(queryParameters: {'category': category});

      debugPrint('📤 [API] Letter GET $uri');
      final response = await http
          .get(
            uri,
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
              'Accept': 'application/pdf',
            },
          )
          .timeout(const Duration(seconds: 60));

      _checkAuth(response.statusCode);
      if (response.statusCode == 404) {
        return (bytes: null, error: 'not_found');
      }
      if (response.statusCode != 200) {
        debugPrint(
          '❌ [API] Letter $type/$category failed: ${response.statusCode} ${response.reasonPhrase}',
        );
        return (bytes: null, error: 'failed');
      }

      final bytes = response.bodyBytes;
      // Same guard as Form 16 / health card: a real PDF starts with '%PDF',
      // while a Laravel error envelope can come back 200-with-JSON.
      if (bytes.length < 5 ||
          bytes[0] != 0x25 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x44 ||
          bytes[3] != 0x46) {
        debugPrint('❌ [API] Letter $type/$category did not return a PDF');
        return (bytes: null, error: 'not_found');
      }
      return (bytes: bytes, error: null);
    } catch (e) {
      debugPrint('❌ [API] fetchLetterPdfBytes error: $e');
      return (bytes: null, error: 'failed');
    }
  }

  // Get Employee Payslip
  static Future<ApiResponse> getEmployeePayslip({
    required String token,
    required String empId,
    required String processMonth,
    String payslipType = '',
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseUrl}/emp_salary_payslip'),
      );

      request.fields.addAll({
        'payslip_type': payslipType,
        'emp_id': empId,
        'process_month': processMonth,
      });

      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        // Try parsing as JSON first
        try {
          final data = json.decode(responseBody);
          return ApiResponse.success(data);
        } catch (e) {
          // Return raw response if not JSON
          return ApiResponse.success({'data': responseBody});
        }
      } else {
        // Try to parse error message or return HTML error indication
        if (responseBody.contains('<html')) {
          return ApiResponse.error(
            'Server Error: Target class [PayrollController] does not exist. Please fix the backend API.',
          );
        }
        return ApiResponse.error(
          'Failed to get payslip: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Download Payslip PDF
  /// Fetches the payslip PDF as raw bytes without writing to disk. Used by
  /// the inline preview + full-screen viewer so we can render the same PDF
  /// the user will eventually download/share, but cache it in tmp storage
  /// instead of polluting the public Downloads folder on every preview.
  ///
  /// Hits the same backend endpoint as [downloadPayslip] (`generate_type:
  /// View` semantically — backend treats both the same). Returns null on any
  /// failure so the caller can render an error state.
  static Future<Uint8List?> fetchPayslipPdfBytes({
    required String token,
    required String processMonth,
    String empId = '',
    String payslipType = '',
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseUrl}/download-payslip'),
      );

      request.fields.addAll({
        'process_month': processMonth,
        'payslip_type': payslipType,
        'emp_id': empId,
        // Backend only documents 'Download' as a valid generate_type for
        // /api/download-payslip; using the same value here means the preview
        // gets the byte-identical PDF the user will eventually save.
        'generate_type': 'Download',
      });

      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      final response = await request.send().timeout(
        const Duration(seconds: 60),
      );
      _checkAuth(response.statusCode);
      if (response.statusCode != 200) {
        debugPrint(
          '❌ [API] Payslip bytes fetch failed: ${response.statusCode} ${response.reasonPhrase}',
        );
        return null;
      }
      final bytes = await response.stream.toBytes();
      if (bytes.isEmpty) return null;
      return bytes;
    } catch (e) {
      debugPrint('❌ [API] fetchPayslipPdfBytes error: $e');
      return null;
    }
  }

  static Future<String?> downloadPayslip({
    required String token,
    required String processMonth,
    String empId = '',
    String payslipType = '',
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseUrl}/download-payslip'),
      );

      request.fields.addAll({
        'process_month': processMonth,
        'payslip_type': payslipType,
        'emp_id': empId,
        'generate_type': 'Download',
      });

      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      debugPrint(
        '📤 [API] Download payslip: emp_id=$empId, month=$processMonth',
      );

      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 60),
      );

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final bytes = await response.stream.toBytes();

        if (bytes.isEmpty) {
          debugPrint('❌ [API] Download returned empty response');
          return null;
        }

        // Save to Downloads directory
        final dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        final sanitizedMonth = processMonth.replaceAll(' ', '_');
        final fileName = empId.isNotEmpty
            ? 'Payslip_${empId}_$sanitizedMonth.pdf'
            : 'Payslip_$sanitizedMonth.pdf';
        final filePath = '${dir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        debugPrint('✅ [API] Payslip saved to: $filePath');
        return filePath;
      } else {
        debugPrint(
          '❌ [API] Download failed: ${response.statusCode} ${response.reasonPhrase}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('❌ [API] Download error: $e');
      return null;
    }
  }

  // Get Leave Types
  static Future<List<LeaveType>> getLeaveTypes(String token) async {
    try {
      var request = http.Request(
        'GET',
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.leaveTypesEndpoint}'),
      );

      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      http.StreamedResponse response = await request.send();
      String responseBody = await response.stream.bytesToString();

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        final rawTypes = data is Map ? data['leave_types'] : null;

        // Backend sometimes returns leave_types as a List, other times as a
        // keyed map (e.g. {"0": {...}, "1": {...}, "4": {...}}) with gaps from
        // deleted rows. Handle both.
        final Iterable<dynamic> entries = rawTypes is List
            ? rawTypes
            : rawTypes is Map
            ? rawTypes.values
            : const <dynamic>[];

        return entries
            .whereType<Map<String, dynamic>>()
            .map((j) {
              try {
                return LeaveType.fromJson(j);
              } catch (e) {
                print('⚠️ Error parsing leave type: $e');
                return null;
              }
            })
            .whereType<LeaveType>()
            .toList();
      } else {
        print('Failed to fetch leave types: ${response.reasonPhrase}');
        return [];
      }
    } catch (e) {
      print('Error fetching leave types: $e');
      return [];
    }
  }

  // Calculate Leave Days
  static Future<LeaveCalculationResponse?> calculateLeaveDays({
    required String token,
    required String fromDate,
    required String toDate,
    required String halfDay,
    required String leaveTypeId,
    required String branchId,
    String? employeeId,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.leaveCalculationEndpoint}',
        ),
      );

      request.fields.addAll({
        'from_date': fromDate,
        'to_date': toDate,
        'half_day': halfDay,
        'leave_type_id': leaveTypeId,
        'branch_id': branchId,
      });

      if (employeeId != null) {
        request.fields['employee_id'] = employeeId;
      }

      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      http.StreamedResponse response = await request.send();
      String responseBody = await response.stream.bytesToString();
      print('📦 [API] Fields: ${request.fields}');
      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return LeaveCalculationResponse.fromJson(data);
      } else {
        print('Failed to calculate leave days: ${response.reasonPhrase}');
        return null;
      }
    } catch (e) {
      print('Error calculating leave days: $e');
      return null;
    }
  }

  // Apply Leave
  static Future<ApiResponse> applyLeave({
    required String token,
    required String leaveTypeId,
    required String startDate,
    required String endDate,
    required String reason,
    required String leaveCategory,
    required String halfDayValue,
    required String branchId,
    String? employeeId,
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.leaveApplyEndpoint}',
      );
      var request = http.MultipartRequest('POST', url);

      final fields = {
        'leave_type_id': leaveTypeId,
        'from_date': startDate,
        'to_date': endDate,
        'reason': reason,
        'category': leaveCategory,
        'half_day': halfDayValue,
      };

      request.fields.addAll(fields);

      final headers = {
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
      };

      if (employeeId != null) {
        fields['employee_id'] = employeeId;
        fields['emp_id'] = employeeId; // Add both variations for robustness
      }

      request.headers.addAll(headers);

      print('🚀 [API] POST (Multipart) $url');
      print('📦 [API] Fields: $fields');

      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      print('📥 Response Status: ${response.statusCode}');
      print('📖 Response Body: $responseBody');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final data = json.decode(responseBody);
          return ApiResponse.success(data);
        } catch (e) {
          // If body is not JSON but status is OK
          return ApiResponse.success({'message': 'Success'});
        }
      } else {
        // Check for HTML response indicating auth failure or server error
        if (responseBody.contains('<html') ||
            response.statusCode == 302 ||
            response.statusCode == 401) {
          print(
            '⚠️ [API] Critical Error: Received HTML/Redirect or Unauthorized instead of JSON.',
          );
          return ApiResponse.error(
            'Server error: API redirected or unauthorized. Please re-login or check permissions.',
          );
        }

        try {
          final data = json.decode(responseBody);
          return ApiResponse.error(
            data['message']?.toString() ?? 'Failed to submit leave request',
          );
        } catch (e) {
          return ApiResponse.error(
            'Error ${response.statusCode}: ${response.reasonPhrase}',
          );
        }
      }
    } catch (e) {
      print('❌ [API] Exception: $e');
      return ApiResponse.error('Network error: $e');
    }
  }

  // Store Employee Leave (for applying on behalf of others)
  static Future<ApiResponse> storeEmployeeLeave({
    required String token,
    required String empId,
    required String fromDate,
    required String toDate,
    required String leaveType,
    required String category,
    required String halfDay,
    required String reason,
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.storeEmployeeLeaveEndpoint}',
      );
      var request = http.MultipartRequest('POST', url);

      request.fields.addAll({
        'emp_id': empId,
        'from_date': fromDate,
        'to_date': toDate,
        'leave_type': leaveType,
        'category': category,
        'half_day': halfDay,
        'reason': reason,
      });

      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      print('🚀 [API] POST (Multipart) $url');
      print('📦 [API] Fields: ${request.fields}');

      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      print('📥 Response Status: ${response.statusCode}');
      print('📖 Response Body: $responseBody');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final data = json.decode(responseBody);
          return ApiResponse.success(data);
        } catch (e) {
          return ApiResponse.success({'message': 'Success'});
        }
      } else {
        try {
          final data = json.decode(responseBody);
          return ApiResponse.error(
            data['message']?.toString() ?? 'Failed to submit employee leave',
          );
        } catch (e) {
          return ApiResponse.error(
            'Error ${response.statusCode}: ${response.reasonPhrase}',
          );
        }
      }
    } catch (e) {
      print('❌ [API] Exception: $e');
      return ApiResponse.error('Network error: $e');
    }
  }

  // Delete Employee Leave
  static Future<ApiResponse> deleteEmployeeLeave({
    required String token,
    required String leaveId,
    required String deleteReason,
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.deleteEmployeeLeaveEndpoint}',
      );
      var request = http.MultipartRequest('POST', url);

      request.fields.addAll({
        'leave_id': leaveId,
        'delete_reason': deleteReason,
      });

      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      print('🚀 [API] deleteEmployeeLeave POST (Multipart) $url');
      print('📦 [API] Fields: ${request.fields}');

      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      print('📥 Response Status: ${response.statusCode}');
      print('📖 Response Body: $responseBody');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final data = json.decode(responseBody);
          // Catch API's explicit rejection with success=false message
          if (data['success'] == false && data.containsKey('message')) {
            return ApiResponse.error(data['message'].toString());
          }
          return ApiResponse.success(data);
        } catch (e) {
          return ApiResponse.success({'message': 'Success'});
        }
      } else {
        try {
          final data = json.decode(responseBody);
          return ApiResponse.error(
            data['message']?.toString() ?? 'Failed to delete leave',
          );
        } catch (e) {
          return ApiResponse.error(
            'Error ${response.statusCode}: ${response.reasonPhrase}',
          );
        }
      }
    } catch (e) {
      print('❌ [API] Exception: $e');
      return ApiResponse.error('Network error: $e');
    }
  }

  // Get Leave Balance
  static Future<List<LeaveBalance>> getLeaveBalance({
    required String token,
    required String empId,
  }) async {
    try {
      print('🚀 [API] getLeaveBalance | ID: $empId');

      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.leaveBalanceEndpoint}',
      );

      // Attempt 1: Query parameters (common for GET)
      final queryUrl = url.replace(
        queryParameters: {'emp_id': empId, 'employee_id': empId},
      );
      final response = await http
          .get(
            queryUrl,
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      String responseBody = response.body;
      print('📥 Leave Balance Status: ${response.statusCode}');

      // Attempt 2: If unsuccessful or empty, try headers (some legacy APIs use this)
      _checkAuth(response.statusCode);
      if (response.statusCode != 200 || responseBody.contains('[]')) {
        print('🔄 Falling back to header-based ID for balance...');
        final fallbackResponse = await http
            .get(
              url,
              headers: {
                ...ApiConstants.headers,
                'Authorization': 'Bearer $token',
                'emp_id': empId,
                'employee_id': empId,
              },
            )
            .timeout(const Duration(seconds: 30));

        if (fallbackResponse.statusCode == 200 &&
            !fallbackResponse.body.contains('[]')) {
          responseBody = fallbackResponse.body;
        }
      }

      print('� Leave Balance Body: $responseBody');

      if (responseBody.isNotEmpty && responseBody.contains('{')) {
        try {
          final data = json.decode(responseBody);
          final List<dynamic> balancesData =
              data['leave_balances'] ?? data['balances'] ?? data['data'] ?? [];

          return balancesData
              .map((json) {
                try {
                  return LeaveBalance.fromJson(json as Map<String, dynamic>);
                } catch (e) {
                  print('⚠️ Error parsing single balance item: $e');
                  return null;
                }
              })
              .whereType<LeaveBalance>()
              .toList();
        } catch (e) {
          print('❌ JSON Decode Error in balance: $e');
        }
      }
      return [];
    } catch (e) {
      print('❌ getLeaveBalance Exception: $e');
      return [];
    }
  }

  // Get Leave History (My Applications)
  static Future<List<LeaveApplication>> getLeaveHistory({
    required String token,
    required String empId,
  }) async {
    try {
      var urlPath =
          '${ApiConstants.baseUrl}${ApiConstants.leaveHistoryEndpoint}';

      // Attempt 1: Multipart GET (as per user snippet)
      var multipartRequest = http.MultipartRequest('GET', Uri.parse(urlPath));
      multipartRequest.fields.addAll({'emp_id': empId, 'employee_id': empId});
      multipartRequest.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      print('🚀 [API] GET (Multipart) $urlPath | ID: $empId');
      http.StreamedResponse response = await multipartRequest.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      // If empty or non-200, try standard GET with query parameters
      _checkAuth(response.statusCode);
      if (response.statusCode != 200 ||
          responseBody.contains('"leave_applications":[]') ||
          responseBody.contains('"data":[]')) {
        print('🔄 Falling back to standard GET with query parameters...');
        final queryUrl = Uri.parse(
          urlPath,
        ).replace(queryParameters: {'emp_id': empId, 'employee_id': empId});
        final stdResponse = await http
            .get(
              queryUrl,
              headers: {
                ...ApiConstants.headers,
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 30));

        if (stdResponse.statusCode == 200) {
          responseBody = stdResponse.body;
        }
      }

      print('📥 Final Response: $responseBody');

      if (responseBody.isNotEmpty) {
        try {
          final data = json.decode(responseBody);
          final List<dynamic> historyData =
              data['leave_applications'] ??
              data['leave_history'] ??
              data['data'] ??
              [];

          return historyData
              .map((json) {
                try {
                  return LeaveApplication.fromJson(
                    json as Map<String, dynamic>,
                  );
                } catch (e) {
                  print('⚠️ Error parsing single leave application: $e');
                  return null;
                }
              })
              .whereType<LeaveApplication>()
              .toList();
        } catch (e) {
          print('❌ JSON Decode Error: $e');
        }
      }
      return [];
    } catch (e) {
      print('❌ getLeaveHistory Exception: $e');
      return [];
    }
  }

  // --- Attendance Methods ---

  // Fetch attendance history for the current user
  static Future<ApiResponse> getAttendanceHistory({
    String? startDate,
    String? endDate,
  }) async {
    try {
      String url =
          '${ApiConstants.baseUrl}${ApiConstants.attendanceHistoryEndpoint}';
      if (startDate != null || endDate != null) {
        url += '?';
        if (startDate != null) url += 'start_date=$startDate&';
        if (endDate != null) url += 'end_date=$endDate';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: ApiConstants.headers,
      );

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error(
          'Failed to fetch attendance: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Fetch team attendance (daily attendance API)
  static Future<ApiResponse> getTeamAttendance({
    required String token,
    required String date,
    String? branchId,
    String? role,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.dailyAttendanceEndpoint}',
        ),
      );

      request.fields.addAll({
        'date': date,
        'br_id': branchId ?? '',
        'role': role ?? '',
      });
      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error(
          'Failed to fetch team attendance: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Fetch regularization data for a date range (used by Regularize Attendance screen)
  static Future<ApiResponse> getMyRegularizationData({
    required String token,
    required String fromDate,
    required String toDate,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.myRegularizationDataEndpoint}',
        ),
      );

      request.fields.addAll({'from_date': fromDate, 'to_date': toDate});
      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error(
          'Failed to fetch regularization data: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Clock In
  static Future<ApiResponse> clockIn({
    required String time,
    required String location,
    double? latitude,
    double? longitude,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.clockInEndpoint}'),
      );

      request.fields.addAll({
        'time': time,
        'location': location,
        if (latitude != null) 'latitude': latitude.toString(),
        if (longitude != null) 'longitude': longitude.toString(),
      });
      request.headers.addAll(ApiConstants.headers);

      http.StreamedResponse response = await request.send();
      String responseBody = await response.stream.bytesToString();

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error('Clock-in failed: ${response.reasonPhrase}');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Clock Out
  static Future<ApiResponse> clockOut({required String time}) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.clockOutEndpoint}'),
      );

      request.fields.addAll({'time': time});
      request.headers.addAll(ApiConstants.headers);

      http.StreamedResponse response = await request.send();
      String responseBody = await response.stream.bytesToString();

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error('Clock-out failed: ${response.reasonPhrase}');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Parse attendance list from response
  static List<AttendanceModel> parseAttendanceFromResponse(
    Map<String, dynamic> data,
  ) {
    try {
      final List<dynamic> attendanceData =
          data['data'] ?? data['attendance'] ?? [];
      return attendanceData
          .map((json) => AttendanceModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error parsing attendance data: $e');
      return [];
    }
  }

  // Fetch today's attendance for the logged-in employee
  static Future<ApiResponse> getTodayAttendance(
    String token, {
    String? date,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.todayAttendanceEndpoint}',
        ),
      );

      if (date != null) {
        request.fields['date'] = date;
      }

      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      print('🚀 [API] POST (Today Attendance) | Date: $date');
      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      print('📥 [API] Today Attendance Status: ${response.statusCode}');
      print('📖 [API] Today Attendance Body: $responseBody');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error(
          'Failed to fetch today attendance: ${response.reasonPhrase}',
        );
      }
    } on TimeoutException catch (_) {
      return ApiResponse.error(
        'Connection timed out. Please check your internet connection.',
      );
    } catch (e) {
      print('❌ [API] Today Attendance Exception: $e');
      return ApiResponse.error('Network error: $e');
    }
  }

  // Get Holidays
  static Future<ApiResponse> getHolidays({
    required String token,
    required String year,
  }) async {
    try {
      var request = http.MultipartRequest(
        'GET',
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.holidaysEndpoint}'),
      );
      request.fields.addAll({'year': year});
      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error(
          'Failed to fetch holidays: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Get Calendar Data (monthly attendance + holidays)
  static Future<ApiResponse> getCalendarData({
    required String token,
    required String month,
    required String year,
  }) async {
    try {
      var request = http.MultipartRequest(
        'GET',
        Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.calendarDataEndpoint}',
        ),
      );
      request.fields.addAll({'month': month, 'year': year});
      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      print('🚀 [API] GET Calendar Data: month=$month, year=$year');
      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      print('📥 [API] Calendar Data Status: ${response.statusCode}');
      print('📖 [API] Calendar Data Body: $responseBody');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error(
          'Failed to fetch calendar data: ${response.reasonPhrase}',
        );
      }
    } on TimeoutException catch (_) {
      return ApiResponse.error(
        'Connection timed out. Please check your internet connection.',
      );
    } catch (e) {
      print('❌ [API] Calendar Data Exception: $e');
      return ApiResponse.error('Network error: $e');
    }
  }

  // Get My Attendance (filtered attendance data)
  static Future<ApiResponse> getMyAttendance({
    required String token,
    required String filter,
    String fromDate = '',
    String toDate = '',
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.myAttendanceEndpoint}',
        ),
      );
      request.fields.addAll({
        'filter': filter,
        'from_date': fromDate,
        'to_date': toDate,
      });
      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      print(
        '🚀 [API] POST My Attendance: filter=$filter, from=$fromDate, to=$toDate',
      );
      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      print('📥 [API] My Attendance Status: ${response.statusCode}');
      print('📖 [API] My Attendance Body: $responseBody');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error(
          'Failed to fetch my attendance: ${response.reasonPhrase}',
        );
      }
    } on TimeoutException catch (_) {
      return ApiResponse.error(
        'Connection timed out. Please check your internet connection.',
      );
    } catch (e) {
      print('❌ [API] My Attendance Exception: $e');
      return ApiResponse.error('Network error: $e');
    }
  }

  // Get Branches
  static Future<List<BranchModel>> getBranches(String token) async {
    try {
      var request = http.Request(
        'POST',
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.getBranchesEndpoint}'),
      );

      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      http.StreamedResponse response = await request.send();
      String responseBody = await response.stream.bytesToString();

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        if (data['status'] == true && data['data'] != null) {
          final List<dynamic> branchesData = data['data'];
          return branchesData
              .map((json) => BranchModel.fromJson(json as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      print('Error fetching branches: $e');
      return [];
    }
  }

  // Get Employees by Branch
  static Future<List<UserModel>> getEmployeesByBranch({
    required String token,
    required int branchId,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.getEmployeesByBranchEndpoint}',
        ),
      );

      request.fields.addAll({'branch_id': branchId.toString()});
      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      print('🚀 [API] getEmployeesByBranch | Branch ID: $branchId');
      http.StreamedResponse response = await request.send();
      String responseBody = await response.stream.bytesToString();

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        if (data['success'] == true && data['employees'] != null) {
          final List<dynamic> employeesData = data['employees'];
          return employeesData
              .map((json) => UserModel.fromJson(json as Map<String, dynamic>))
              .toList();
        }
      } else {
        print('Failed to fetch employees by branch: ${response.reasonPhrase}');
      }
      return [];
    } catch (e) {
      print('Error fetching employees by branch: $e');
      return [];
    }
  }

  // --- Leave Approvals (Mock) ---

  // Get Employee Leaves List (for Leave Summary table)
  // Returns a richer result so the screen can use server-side pagination,
  // counts and the branches list that the API now includes.
  static Future<EmployeeLeavesListResult> getEmployeeLeavesList(
    String token, {
    int page = 1,
    int perPage = 20,
    String? brId,
    String? status,
    String? fromDate,
    String? toDate,
    String? empId,
    String? leaveTypeId,
    String? search,
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.employeeLeavesListEndpoint}',
      );

      final request = http.MultipartRequest('POST', url);
      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });
      request.fields.addAll({
        'page': page.toString(),
        'per_page': perPage.toString(),
        'br_id': brId ?? '',
        'status': status ?? '',
        'from_date': fromDate ?? '',
        'to_date': toDate ?? '',
        'emp_id': empId ?? '',
        'leave_type_id': leaveTypeId ?? '',
        'search': search ?? '',
      });

      print('🚀 [API] POST (Employee Leave List) $url');
      print('📦 [API] Fields: ${request.fields}');

      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode != 200) {
        print('Failed to fetch employee leaves list: ${streamed.reasonPhrase}');
        return EmployeeLeavesListResult.empty();
      }

      final decoded = json.decode(body);
      if (decoded is! Map<String, dynamic>) {
        return EmployeeLeavesListResult.empty();
      }

      // Response shape: { success, counts, leaves: {data, current_page, last_page, total, per_page, ...}, branches }
      final leavesNode = decoded['leaves'];
      List<dynamic> rawList;
      int currentPage = page;
      int lastPage = 1;
      int total = 0;
      int responsePerPage = perPage;
      if (leavesNode is Map<String, dynamic>) {
        rawList = (leavesNode['data'] as List?) ?? const [];
        currentPage = _asInt(leavesNode['current_page'], fallback: page);
        lastPage = _asInt(leavesNode['last_page'], fallback: 1);
        total = _asInt(leavesNode['total'], fallback: rawList.length);
        responsePerPage = _asInt(leavesNode['per_page'], fallback: perPage);
      } else if (leavesNode is List) {
        rawList = leavesNode;
        total = rawList.length;
      } else {
        rawList = const [];
      }

      final leaves = rawList
          .map((j) {
            try {
              return LeaveApplication.fromJson(j as Map<String, dynamic>);
            } catch (e) {
              print('⚠️ Error parsing employee leave item: $e');
              return null;
            }
          })
          .whereType<LeaveApplication>()
          .toList();

      final countsMap = decoded['counts'];
      final counts = countsMap is Map<String, dynamic>
          ? <String, int>{
              'total': _asInt(countsMap['total']),
              'pending': _asInt(countsMap['pending']),
              'approved': _asInt(countsMap['approved']),
              'rejected': _asInt(countsMap['rejected']),
              'cancelled': _asInt(countsMap['cancelled']),
            }
          : <String, int>{};

      final List<BranchModel> branches = [];
      final rawBranches = decoded['branches'];
      if (rawBranches is List) {
        for (final b in rawBranches) {
          if (b is Map<String, dynamic>) {
            try {
              branches.add(BranchModel.fromJson(b));
            } catch (e) {
              print('⚠️ Error parsing branch item: $e');
            }
          }
        }
      }

      return EmployeeLeavesListResult(
        leaves: leaves,
        counts: counts,
        currentPage: currentPage,
        lastPage: lastPage,
        total: total,
        perPage: responsePerPage,
        branches: branches,
      );
    } catch (e) {
      print('Error fetching employee leaves list: $e');
      return EmployeeLeavesListResult.empty();
    }
  }

  static int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  static Future<List<LeaveApplication>> getLeaveApprovals(String token) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.leaveApprovalEndpoint}',
      );

      final response = await http
          .get(
            url,
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> pending = data['pending_leaves'] ?? [];
        final List<dynamic> approved = data['approved_leaves'] ?? [];
        final List<dynamic> rejected = data['rejected_leaves'] ?? [];

        // Combine all lists
        final List<dynamic> allApprovals = [
          ...pending,
          ...approved,
          ...rejected,
        ];

        return allApprovals
            .map((json) {
              try {
                return LeaveApplication.fromJson(json as Map<String, dynamic>);
              } catch (e) {
                print('⚠️ Error parsing leave approval item: $e');
                return null;
              }
            })
            .whereType<LeaveApplication>()
            .toList();
      } else {
        print('Failed to fetch leave approvals: ${response.reasonPhrase}');
        return [];
      }
    } catch (e) {
      print('Error fetching leave approvals: $e');
      return [];
    }
  }

  /// Branch payroll approvals pending the logged-in approver. The API returns
  /// `data` as a map of approval-level buckets (e.g. `level5`) → list of
  /// request objects; this flattens them into a single list, tagging each
  /// request with the level key it came from.
  static Future<List<PayrollRequest>> getBranchPayrollApprovals(
    String token,
  ) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.branchPayrollApprovalsEndpoint}',
      );

      final response = await http
          .get(
            url,
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final data = decoded['data'];
        final out = <PayrollRequest>[];
        if (data is Map) {
          data.forEach((levelKey, list) {
            if (list is List) {
              for (final item in list) {
                if (item is Map<String, dynamic>) {
                  try {
                    out.add(
                      PayrollRequest.fromJson(
                        item,
                        levelKey: levelKey.toString(),
                      ),
                    );
                  } catch (e) {
                    debugPrint('⚠️ Error parsing payroll approval item: $e');
                  }
                }
              }
            }
          });
        }
        return out;
      } else {
        debugPrint(
          'Failed to fetch branch payroll approvals: ${response.reasonPhrase}',
        );
        return [];
      }
    } catch (e) {
      debugPrint('Error fetching branch payroll approvals: $e');
      return [];
    }
  }

  /// Pending manpower requisitions grouped per project, plus the top-level
  /// `stats` block. Follows pagination: fetches page 1, then pages 2..last_page
  /// and merges all requisition items into one list (so every branch with a
  /// pending requisition is available for filtering). Stats come from page 1.
  /// On any error returns [PendingRequisitionsResult.empty].
  static Future<PendingRequisitionsResult> getPendingRequisitions(
    String token,
  ) async {
    try {
      final first = await _fetchRequisitionsPage(token, 1);
      if (first == null) return PendingRequisitionsResult.empty;

      final items = <RequisitionItem>[...first.items];
      // Safety cap so an unexpected `last_page` can't spin forever.
      final lastPage = first.lastPage.clamp(1, 100);

      // Fetch the remaining pages concurrently (instead of one-by-one) so the
      // full list loads in roughly a single round-trip instead of N.
      if (lastPage > 1) {
        final rest = await Future.wait([
          for (var page = 2; page <= lastPage; page++)
            _fetchRequisitionsPage(token, page),
        ]);
        for (final next in rest) {
          if (next != null) items.addAll(next.items);
        }
      }

      return PendingRequisitionsResult(
        stats: first.stats,
        items: items,
        lastPage: first.lastPage,
      );
    } catch (e) {
      debugPrint('Error fetching pending requisitions: $e');
      return PendingRequisitionsResult.empty;
    }
  }

  /// Fetches a single page of `/pending-requisitions`. Returns null on a
  /// non-200 response so the caller can stop paginating.
  static Future<PendingRequisitionsResult?> _fetchRequisitionsPage(
    String token,
    int page,
  ) async {
    final url = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.pendingRequisitionsEndpoint}'
      '?page=$page',
    );

    final response = await http
        .get(
          url,
          headers: {...ApiConstants.headers, 'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));

    _checkAuth(response.statusCode);
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        return PendingRequisitionsResult.fromResponse(decoded);
      }
      return PendingRequisitionsResult.empty;
    }
    debugPrint(
      'Failed to fetch pending requisitions (page $page): '
      '${response.reasonPhrase}',
    );
    return null;
  }

  /// Full detail for a single branch payroll request (employee info, the
  /// activity `request_data` and the complete approval timeline).
  static Future<PayrollRequest?> getBranchPayrollRequestDetail(
    String token,
    int id, {
    String levelKey = '',
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}'
        '${ApiConstants.branchPayrollRequestDetailEndpoint}/$id',
      );

      final response = await http
          .get(
            url,
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final data = decoded['data'];
        if (data is Map<String, dynamic>) {
          return PayrollRequest.fromJson(data, levelKey: levelKey);
        }
        return null;
      } else {
        debugPrint(
          'Failed to fetch payroll request detail: ${response.reasonPhrase}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching payroll request detail: $e');
      return null;
    }
  }

  /// Approve or reject a branch payroll request.
  /// [action] is 'Approved' or 'Rejected'; [level] is the approval level
  /// number (e.g. '5'). Returns (success, message) from the API.
  static Future<({bool success, String message})> postBranchPayrollApproval({
    required String token,
    required int requestId,
    required String action,
    required String remarks,
    required String level,
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}'
        '${ApiConstants.postBranchPayrollApprovalEndpoint}',
      );

      final request = http.MultipartRequest('POST', url);
      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });
      request.fields.addAll({
        'action': action,
        'request_ids': '[$requestId]',
        'remarks': remarks,
        'level': level,
      });

      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final body = await streamed.stream.bytesToString();

      _checkAuth(streamed.statusCode);
      if (streamed.statusCode == 200) {
        final decoded = json.decode(body);
        final message = (decoded['message'] ?? '').toString();
        // The API can return status:true while processing 0 requests
        // (e.g. "0 request(s) approved successfully") — treat that as a
        // no-op, not a success.
        final processed = RegExp(r'\d+').firstMatch(message);
        final count = processed != null ? int.parse(processed.group(0)!) : 1;
        return (
          success: decoded['status'] == true && count > 0,
          message: message,
        );
      } else {
        debugPrint('Failed payroll approval: ${streamed.statusCode} $body');
        return (success: false, message: 'Failed (${streamed.statusCode})');
      }
    } catch (e) {
      debugPrint('Error posting payroll approval: $e');
      return (success: false, message: 'Something went wrong');
    }
  }

  static Future<bool> updateLeaveStatus({
    required String token,
    required String leaveId,
    required String status,
    required String remarks,
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.updateLeaveStatusEndpoint}',
      );

      var request = http.MultipartRequest('POST', url);
      request.headers.addAll({'Authorization': 'Bearer $token'});

      request.fields.addAll({
        'id': leaveId,
        'status': status,
        'remarks': remarks,
      });

      var response = await request.send();
      final responseBody = await response.stream.bytesToString();

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return data['success'] ?? false;
      } else {
        debugPrint('Error updating status: ${response.statusCode}');
        debugPrint('Response body: $responseBody');
        return false;
      }
    } catch (e) {
      debugPrint('Error in updateLeaveStatus: $e');
      return false;
    }
  }

  static Future<LeaveInfoResponse?> getLeaveInfo({
    required String token,
    required String leaveId,
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.leaveInfoEndpoint}',
      );

      var request = http.MultipartRequest('POST', url);
      request.fields.addAll({'leave_app_id': leaveId});
      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      print('🚀 [API] POST (Leave Info) $url | ID: $leaveId');
      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      print('📥 [API] Leave Info Status: ${response.statusCode}');
      print('📖 [API] Leave Info Body: $responseBody');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        try {
          final data = json.decode(responseBody);
          return LeaveInfoResponse.fromJson(data);
        } catch (parseError) {
          print('❌ [API] Leave Info JSON parse error: $parseError');
          return null;
        }
      } else {
        print('❌ Failed to fetch leave info: ${response.reasonPhrase}');
        return null;
      }
    } catch (e) {
      print('❌ Error fetching leave info: $e');
      return null;
    }
  }

  // Get Employee Onboarding Approvals
  static Future<ApiResponse> getOnboardingApprovals(String token) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.onboardingApprovalEndpoint}',
        ),
      );

      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      print('🚀 [API] POST (Onboarding Approvals)');
      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      print('📥 [API] Onboarding Status: ${response.statusCode}');
      print('📖 [API] Onboarding Body: $responseBody');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error(
          'Failed to fetch onboarding approvals: ${response.reasonPhrase}',
        );
      }
    } on TimeoutException catch (_) {
      return ApiResponse.error(
        'Connection timed out. Please check your internet connection.',
      );
    } catch (e) {
      print('❌ [API] Onboarding Exception: $e');
      return ApiResponse.error('Network error: $e');
    }
  }

  // Post Onboarding Approval (approve/reject)
  static Future<ApiResponse> postOnboardingApproval({
    required String token,
    required String action,
    required String empId,
    required String level,
    String remarks = '',
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.postOnboardingApprovalEndpoint}',
        ),
      );

      request.fields.addAll({
        'action': action,
        'emp_ids[]': empId,
        'remarks': remarks,
        'level': level,
      });

      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      print('🚀 [API] POST (Onboarding Approval Action: $action)');
      print('📦 [API] Fields: ${request.fields}');
      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      print('📥 [API] Onboarding Approval Status: ${response.statusCode}');
      print('📖 [API] Onboarding Approval Body: $responseBody');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        if (data['status'] == false) {
          return ApiResponse.error(
            data['message']?.toString() ?? 'Action failed',
          );
        }
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error('Failed: ${response.reasonPhrase}');
      }
    } on TimeoutException catch (_) {
      return ApiResponse.error(
        'Connection timed out. Please check your internet connection.',
      );
    } catch (e) {
      print('❌ [API] Onboarding Approval Exception: $e');
      return ApiResponse.error('Network error: $e');
    }
  }

  // Submit Attendance Regularization
  static Future<ApiResponse> submitRegularization({
    required String token,
    required String dailyAttendanceId,
    required String newInTime,
    required String newOutTime,
    String reason = '',
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.submitRegularizationRequestEndpoint}',
      );
      var request = http.MultipartRequest('POST', url);

      request.fields.addAll({
        'daily_attendance_id': dailyAttendanceId,
        'new_in_time': newInTime,
        'new_out_time': newOutTime,
        'reason': reason,
      });

      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      debugPrint('🚀 [API] POST (Multipart) $url');
      debugPrint('📦 [API] Fields: ${request.fields}');

      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      debugPrint('📥 Response Status: ${response.statusCode}');
      debugPrint('📖 Response Body: $responseBody');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final data = json.decode(responseBody);
          if (data is Map<String, dynamic> && data['status'] == true) {
            return ApiResponse.success(data);
          }
          return ApiResponse.error(
            (data is Map ? data['message']?.toString() : null) ??
                'Failed to submit regularization',
          );
        } catch (e) {
          return ApiResponse.error('Invalid response from server');
        }
      } else {
        try {
          final data = json.decode(responseBody);
          return ApiResponse.error(
            data['message']?.toString() ?? 'Failed to submit regularization',
          );
        } catch (e) {
          return ApiResponse.error(
            'Error ${response.statusCode}: ${response.reasonPhrase}',
          );
        }
      }
    } catch (e) {
      debugPrint('❌ [API] Regularization Exception: $e');
      return ApiResponse.error('Network error: $e');
    }
  }

  // Get Regularization Approvals (pending requests)
  static Future<ApiResponse> getRegularizationApprovals(String token) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.regularizationApprovalsEndpoint}',
      );

      var request = http.MultipartRequest('GET', url);
      request.headers.addAll({'Authorization': 'Bearer $token'});

      debugPrint('🚀 [API] GET (Multipart) $url');

      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      debugPrint('📥 Regularization Approvals Status: ${response.statusCode}');
      debugPrint('📖 Regularization Approvals Body: $responseBody');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return ApiResponse.success(
          data is Map<String, dynamic> ? data : {'data': data},
        );
      } else {
        return ApiResponse.error(
          'Failed to fetch regularization approvals: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      debugPrint('❌ [API] getRegularizationApprovals Exception: $e');
      return ApiResponse.error('Network error: $e');
    }
  }

  // Get My Regularization List (requests submitted by the current user)
  static Future<ApiResponse> getMyRegularizationList({
    required String token,
    required String fromDate,
    required String toDate,
    String status = 'All',
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.myRegularizationListEndpoint}',
      );

      var request = http.MultipartRequest('POST', url);
      request.headers.addAll({'Authorization': 'Bearer $token'});
      request.fields.addAll({
        'from_date': fromDate,
        'to_date': toDate,
        'status': status,
      });

      debugPrint('🚀 [API] POST (Multipart) $url');
      debugPrint('📦 [API] Fields: ${request.fields}');

      http.StreamedResponse response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      String responseBody = await response.stream.bytesToString();

      debugPrint('📥 My Regularization List Status: ${response.statusCode}');
      debugPrint('📖 My Regularization List Body: $responseBody');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return ApiResponse.success(
          data is Map<String, dynamic> ? data : {'data': data},
        );
      } else {
        return ApiResponse.error(
          'Failed to fetch regularization list: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      debugPrint('❌ [API] getMyRegularizationList Exception: $e');
      return ApiResponse.error('Network error: $e');
    }
  }

  // Approve / Reject Regularization
  static Future<ApiResponse> updateRegularizationStatus({
    required String token,
    required String requestId,
    required String status,
    String remarks = '',
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.approveRejectRegularizationEndpoint}',
      );

      var request = http.MultipartRequest('POST', url);
      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      request.fields.addAll({
        'regularization_id': requestId,
        'status': status,
        'remarks': remarks,
      });

      debugPrint('🚀 [API] POST (Multipart) $url');
      debugPrint('📦 [API] Fields: ${request.fields}');

      var response = await request.send().timeout(const Duration(seconds: 30));
      final responseBody = await response.stream.bytesToString();

      debugPrint('📥 Response Status: ${response.statusCode}');
      debugPrint('📖 Response Body: $responseBody');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final data = json.decode(responseBody);
          if (data is Map<String, dynamic> && data['status'] == true) {
            return ApiResponse.success(data);
          }
          return ApiResponse.error(
            (data is Map ? data['message']?.toString() : null) ??
                'Failed to update status',
          );
        } catch (_) {
          return ApiResponse.error('Invalid response from server');
        }
      } else {
        try {
          final data = json.decode(responseBody);
          return ApiResponse.error(
            data['message']?.toString() ?? 'Failed to update status',
          );
        } catch (_) {
          return ApiResponse.error(
            'Error ${response.statusCode}: ${response.reasonPhrase}',
          );
        }
      }
    } catch (e) {
      debugPrint('❌ [API] updateRegularizationStatus Exception: $e');
      return ApiResponse.error('Network error: $e');
    }
  }

  // Download Appointment Letter
  static Future<String?> downloadAppointmentLetter({
    required String token,
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.appointmentLetterEndpoint}',
      );

      debugPrint('📤 [API] Download appointment letter GET $url');

      final response = await http
          .get(
            url,
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 45));

      debugPrint('📥 Response Status: ${response.statusCode}');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final pdfBytes = response.bodyBytes;

        if (pdfBytes.isEmpty) {
          debugPrint('❌ [API] Download returned empty response');
          return null;
        }

        // Save to Downloads directory as PDF
        final dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        final fileName =
            'Appointment_Letter_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final filePath = '${dir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(pdfBytes);

        debugPrint('✅ [API] Appointment letter saved to: $filePath');
        return filePath;
      } else {
        debugPrint(
          '❌ [API] Download failed: ${response.statusCode} ${response.reasonPhrase}',
        );
        debugPrint('❌ [API] Error body: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ [API] Download error: $e');
      return null;
    }
  }

  // Download Confirmation Letter
  static Future<String?> downloadConfirmationLetter({
    required String token,
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.confirmationLetterEndpoint}',
      );

      debugPrint('📤 [API] Download confirmation letter GET $url');

      final response = await http
          .get(
            url,
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 45));

      debugPrint('📥 Response Status: ${response.statusCode}');

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final pdfBytes = response.bodyBytes;

        if (pdfBytes.isEmpty) {
          debugPrint('❌ [API] Download returned empty response');
          return null;
        }

        // Save to Downloads directory as PDF
        final dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        final fileName =
            'Confirmation_Letter_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final filePath = '${dir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(pdfBytes);

        debugPrint('✅ [API] Confirmation letter saved to: $filePath');
        return filePath;
      } else {
        debugPrint(
          '❌ [API] Download failed: ${response.statusCode} ${response.reasonPhrase}',
        );
        debugPrint('❌ [API] Error body: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ [API] Download error: $e');
      return null;
    }
  }

  // Get quick-action permissions for a specific user
  static Future<ApiResponse> getUserPermissions({
    required String token,
    required String userId,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.permissionsEndpoint}/$userId',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ApiResponse.success(
          data is Map<String, dynamic> ? data : {'data': data},
        );
      } else if (response.statusCode == 404) {
        // No record yet for this user — treat as empty (all defaults apply)
        return ApiResponse.success({'permissions': <String, dynamic>{}});
      } else {
        return ApiResponse.error(
          'Failed to fetch permissions: ${response.reasonPhrase}',
        );
      }
    } on TimeoutException catch (_) {
      return ApiResponse.error('Connection timed out.');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Update a single quick-action permission for a user (admin only)
  static Future<ApiResponse> updateUserPermission({
    required String token,
    required String userId,
    required String actionKey,
    required bool enabled,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.permissionsEndpoint}/$userId',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({'actionKey': actionKey, 'enabled': enabled}),
          )
          .timeout(const Duration(seconds: 20));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = response.body.isNotEmpty ? json.decode(response.body) : {};
        return ApiResponse.success(
          body is Map<String, dynamic> ? body : {'ok': true},
        );
      } else {
        return ApiResponse.error(
          'Failed to update permission: ${response.reasonPhrase}',
        );
      }
    } on TimeoutException catch (_) {
      return ApiResponse.error('Connection timed out.');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Get global quick-action permissions (defaults applied to all users).
  static Future<ApiResponse> getGlobalPermissions({
    required String token,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.globalPermissionsEndpoint}',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ApiResponse.success(
          data is Map<String, dynamic> ? data : {'data': data},
        );
      } else if (response.statusCode == 404) {
        return ApiResponse.success({'permissions': <String, dynamic>{}});
      } else {
        return ApiResponse.error(
          'Failed to fetch global permissions: ${response.reasonPhrase}',
        );
      }
    } on TimeoutException catch (_) {
      return ApiResponse.error('Connection timed out.');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Update a single global quick-action permission (admin only).
  static Future<ApiResponse> updateGlobalPermission({
    required String token,
    required String actionKey,
    required bool enabled,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.globalPermissionsEndpoint}',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({'actionKey': actionKey, 'enabled': enabled}),
          )
          .timeout(const Duration(seconds: 20));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = response.body.isNotEmpty ? json.decode(response.body) : {};
        return ApiResponse.success(
          body is Map<String, dynamic> ? body : {'ok': true},
        );
      } else {
        return ApiResponse.error(
          'Failed to update global permission: ${response.reasonPhrase}',
        );
      }
    } on TimeoutException catch (_) {
      return ApiResponse.error('Connection timed out.');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // ========== Geofencing / Session-based Attendance ==========
  // See docs/geofencing-backend-integration.md

  /// Fetches the authenticated employee's assigned branch geofence.
  static Future<ApiResponse> getMyGeofence(String token) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.myGeofenceEndpoint}',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final body = response.body.isNotEmpty ? json.decode(response.body) : {};
        return ApiResponse.success(
          body is Map<String, dynamic> ? body : {'data': body},
        );
      }
      return ApiResponse.error(
        'Failed to load geofence: ${response.reasonPhrase}',
      );
    } on TimeoutException catch (_) {
      return ApiResponse.error('Connection timed out.');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// Opens a new attendance session.
  static Future<ApiResponse> punchIn({
    required String token,
    required String selfiePath,
    required double latitude,
    required double longitude,
    double? accuracyM,
    String? address,
    required DateTime clientCapturedAt,
    Map<String, dynamic>? deviceInfo,
  }) async {
    return _punchMultipart(
      token: token,
      endpoint: ApiConstants.punchInEndpoint,
      selfiePath: selfiePath,
      latitude: latitude,
      longitude: longitude,
      accuracyM: accuracyM,
      address: address,
      clientCapturedAt: clientCapturedAt,
      deviceInfo: deviceInfo,
    );
  }

  /// Closes an active attendance session.
  static Future<ApiResponse> punchOut({
    required String token,
    required int sessionId,
    required String selfiePath,
    required double latitude,
    required double longitude,
    double? accuracyM,
    String? address,
    required DateTime clientCapturedAt,
    Map<String, dynamic>? deviceInfo,
  }) async {
    return _punchMultipart(
      token: token,
      endpoint: ApiConstants.punchOutEndpoint,
      selfiePath: selfiePath,
      latitude: latitude,
      longitude: longitude,
      accuracyM: accuracyM,
      address: address,
      clientCapturedAt: clientCapturedAt,
      deviceInfo: deviceInfo,
      extraFields: {'session_id': sessionId.toString()},
    );
  }

  static Future<ApiResponse> _punchMultipart({
    required String token,
    required String endpoint,
    required String selfiePath,
    required double latitude,
    required double longitude,
    double? accuracyM,
    String? address,
    required DateTime clientCapturedAt,
    Map<String, dynamic>? deviceInfo,
    Map<String, String>? extraFields,
  }) async {
    try {
      final selfie = File(selfiePath);
      if (!await selfie.exists()) {
        return ApiResponse.error('Selfie file missing: $selfiePath');
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseUrl}$endpoint'),
      );

      request.headers.addAll({
        ...ApiConstants.headers,
        'Authorization': 'Bearer $token',
      });

      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();
      if (accuracyM != null) {
        request.fields['accuracy_m'] = accuracyM.toString();
      }
      if (address != null) request.fields['address'] = address;
      request.fields['client_captured_at'] = isoWithOffset(clientCapturedAt);
      if (deviceInfo != null) {
        request.fields['device_info'] = json.encode(deviceInfo);
      }
      if (extraFields != null) request.fields.addAll(extraFields);

      request.files.add(
        await http.MultipartFile.fromPath('selfie', selfiePath),
      );

      debugPrint(
        '🟪 [PUNCH] POST $endpoint fields=${request.fields.keys.toList()} '
        'lat=$latitude lng=$longitude selfie=${await selfie.length()}B',
      );

      final streamed = await request.send().timeout(
        const Duration(seconds: 45),
      );
      final body = await streamed.stream.bytesToString();

      // A failing punch used to be completely silent in the logs — the only
      // trace was an error string in the UI. Without the status code and body
      // there was no way to tell a validation failure from a 403, a 409, or
      // the request never landing at all.
      debugPrint('🟪 [PUNCH] $endpoint → HTTP ${streamed.statusCode}');
      debugPrint('🟪 [PUNCH] body: $body');

      final parsed = body.isNotEmpty ? json.decode(body) : {};
      final parsedMap = parsed is Map<String, dynamic>
          ? parsed
          : <String, dynamic>{'raw': parsed};

      if (streamed.statusCode == 200 || streamed.statusCode == 201) {
        return ApiResponse.success(parsedMap);
      }

      if (streamed.statusCode == 409) {
        return ApiResponse.conflict(parsedMap);
      }

      return ApiResponse.error(
        parsedMap['message']?.toString() ??
            'Punch failed (${streamed.statusCode})',
        data: parsedMap,
      );
    } on TimeoutException catch (_) {
      debugPrint('🟪 [PUNCH] $endpoint → timeout, nothing recorded');
      return ApiResponse.error(
        _punchNotRecorded('The server did not respond.'),
      );
    } on SocketException catch (e) {
      debugPrint('🟪 [PUNCH] $endpoint → no connection: $e');
      return ApiResponse.error(_punchNotRecorded('No internet connection.'));
    } on http.ClientException catch (e) {
      debugPrint('🟪 [PUNCH] $endpoint → connection lost: $e');
      return ApiResponse.error(_punchNotRecorded('The connection was lost.'));
    } catch (e) {
      debugPrint('🟪 [PUNCH] $endpoint → unexpected failure: $e');
      return ApiResponse.error(_punchNotRecorded('Something went wrong.'));
    }
  }

  /// Wording for a punch that never reached the server.
  ///
  /// Attendance is deliberately online-only: a punch is real only once the
  /// server records it, so there is no offline queue to fall back on. That
  /// makes it critical the employee is told plainly that **nothing was
  /// saved** — otherwise they walk away believing they are clocked in. The
  /// old text ("Network error: SocketException…") left that ambiguous.
  static String _punchNotRecorded(String cause) =>
      '$cause Your attendance was NOT recorded. '
      'Please check your connection and punch again.';

  /// Sends a single location breadcrumb for an active session.
  static Future<ApiResponse> sendLocationPing({
    required String token,
    required int sessionId,
    required double latitude,
    required double longitude,
    double? accuracyM,
    String? address,
    int? batteryPct,
    required DateTime capturedAt,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.locationPingEndpoint}',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'session_id': sessionId,
              'latitude': latitude,
              'longitude': longitude,
              'accuracy_m': accuracyM,
              'address': address,
              'battery_pct': batteryPct,
              'captured_at': isoWithOffset(capturedAt),
            }),
          )
          .timeout(const Duration(seconds: 20));

      _checkAuth(response.statusCode);
      // Same reasoning as the punch logging: a rejected ping was invisible —
      // it went straight into the retry queue with nothing written to the log,
      // so "no pings on the timeline" gave no clue whether they were being
      // sent, refused, or never attempted.
      debugPrint(
        '🟨 [PING] session=$sessionId → HTTP ${response.statusCode} '
        '${response.statusCode == 200 ? "OK" : response.body}',
      );
      if (response.statusCode == 200) {
        final body = response.body.isNotEmpty ? json.decode(response.body) : {};
        return ApiResponse.success(
          body is Map<String, dynamic> ? body : {'data': body},
        );
      }
      return ApiResponse.error(
        'Ping failed (${response.statusCode}): ${response.reasonPhrase}',
      );
    } on TimeoutException catch (_) {
      return ApiResponse.error('Connection timed out.');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// Flushes the offline ping queue in a single call (max 100 pings).
  static Future<ApiResponse> flushPingBatch({
    required String token,
    required List<Map<String, dynamic>> pings,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.locationPingBatchEndpoint}',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({'pings': pings}),
          )
          .timeout(const Duration(seconds: 30));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final body = response.body.isNotEmpty ? json.decode(response.body) : {};
        return ApiResponse.success(
          body is Map<String, dynamic> ? body : {'data': body},
        );
      }
      return ApiResponse.error(
        'Batch flush failed (${response.statusCode}): ${response.reasonPhrase}',
      );
    } on TimeoutException catch (_) {
      return ApiResponse.error('Connection timed out.');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// Current session + today's punches for the authenticated employee.
  static Future<ApiResponse> getAttendanceToday(String token) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.attendanceTodayEndpoint}',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final body = response.body.isNotEmpty ? json.decode(response.body) : {};
        return ApiResponse.success(
          body is Map<String, dynamic> ? body : {'data': body},
        );
      }
      return ApiResponse.error(
        'Failed to load today: ${response.reasonPhrase}',
      );
    } on TimeoutException catch (_) {
      return ApiResponse.error('Connection timed out.');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// Live snapshot of active sessions, for roles the backend authorises.
  ///
  /// This one is polled from a map screen on mobile data, where a radio
  /// handover (VoWiFi ↔ VoLTE) or a doze wake-up routinely kills the socket
  /// mid-flight — Android surfaces that as "Software caused connection abort".
  /// Those are transient, so the request is retried briefly before the user is
  /// told anything went wrong. HTTP replies (403, 500, …) are never retried:
  /// the server answered, and repeating the call would just be noise.
  static Future<ApiResponse> getLiveAttendance({
    required String token,
    int? branchId,
    int limit = 100,
  }) async {
    const attemptDelays = [
      Duration(milliseconds: 600),
      Duration(milliseconds: 1500),
    ];

    final params = <String, String>{'limit': limit.toString()};
    if (branchId != null) params['branch_id'] = branchId.toString();

    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.attendanceLiveEndpoint}',
    ).replace(queryParameters: params);

    for (var attempt = 0; attempt <= attemptDelays.length; attempt++) {
      try {
        final response = await http
            .get(
              uri,
              headers: {
                ...ApiConstants.headers,
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 20));

        _checkAuth(response.statusCode);
        if (response.statusCode == 200) {
          final body = response.body.isNotEmpty
              ? json.decode(response.body)
              : {};
          return ApiResponse.success(
            body is Map<String, dynamic> ? body : {'data': body},
          );
        }
        if (response.statusCode == 403) {
          return ApiResponse.error('Not authorized to view live attendance.');
        }
        return ApiResponse.error(
          'Failed to load live attendance: ${response.reasonPhrase}',
        );
      } on TimeoutException catch (_) {
        if (attempt == attemptDelays.length) {
          return ApiResponse.error('Connection timed out.');
        }
      } on SocketException catch (e) {
        if (attempt == attemptDelays.length) {
          debugPrint('❌ getLiveAttendance socket failure: $e');
          return ApiResponse.error(_liveAttendanceNetworkError);
        }
      } on http.ClientException catch (e) {
        if (attempt == attemptDelays.length) {
          debugPrint('❌ getLiveAttendance client failure: $e');
          return ApiResponse.error(_liveAttendanceNetworkError);
        }
      } catch (e) {
        // Anything else is not known to be transient — surface it as-is.
        return ApiResponse.error('Network error: $e');
      }

      await Future.delayed(attemptDelays[attempt]);
    }

    return ApiResponse.error(_liveAttendanceNetworkError);
  }

  static const String _liveAttendanceNetworkError =
      "Couldn't reach the server. Check your connection and try again.";

  /// Geofence Live dashboard — every attendance session for one IST calendar
  /// date, each employee's last known position, the branch fences to draw,
  /// and the server's own summary counts, in a single call.
  ///
  /// Admin or Director only; anything else is 403. Unlike
  /// [getLiveAttendance] this one takes a `date` and returns closed sessions
  /// too, which is what a team map for a past day needs.
  ///
  /// Contract: docs/geofence-live-dashboard-api.md §1.
  static Future<ApiResponse> getGeofenceLive({
    required String token,
    DateTime? date,
    int? branchId,
  }) async {
    const attemptDelays = [
      Duration(milliseconds: 600),
      Duration(milliseconds: 1500),
    ];

    final params = <String, String>{};
    if (date != null) {
      // Plain `Y-m-d`, as the endpoint validates. Built by hand rather than
      // through intl so this file keeps its current imports.
      final m = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      params['date'] = '${date.year}-$m-$d';
    }
    if (branchId != null) params['branch_id'] = branchId.toString();

    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.geofenceLiveEndpoint}',
    ).replace(queryParameters: params.isEmpty ? null : params);

    for (var attempt = 0; attempt <= attemptDelays.length; attempt++) {
      try {
        final response = await http
            .get(
              uri,
              headers: {
                ...ApiConstants.headers,
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 20));

        _checkAuth(response.statusCode);
        if (response.statusCode == 200) {
          final body = response.body.isNotEmpty
              ? json.decode(response.body)
              : {};
          return ApiResponse.success(
            body is Map<String, dynamic> ? body : {'data': body},
          );
        }
        // Codes, not prose: the screen decides whether to offer Retry from
        // these, and matching on a message would break the moment someone
        // rewords it.
        if (response.statusCode == 403) {
          return ApiResponse.error(
            'Admin or Director access is required for the team map.',
            data: const {'code': 'FORBIDDEN'},
          );
        }
        if (response.statusCode == 422) {
          return ApiResponse.error(
            'That date was rejected by the server.',
            data: const {'code': 'INVALID_DATE'},
          );
        }
        return ApiResponse.error(
          'Failed to load the team map: ${response.reasonPhrase}',
        );
      } on TimeoutException catch (_) {
        if (attempt == attemptDelays.length) {
          return ApiResponse.error('Connection timed out.');
        }
      } on SocketException catch (e) {
        if (attempt == attemptDelays.length) {
          debugPrint('❌ getGeofenceLive socket failure: $e');
          return ApiResponse.error(_liveAttendanceNetworkError);
        }
      } on http.ClientException catch (e) {
        if (attempt == attemptDelays.length) {
          debugPrint('❌ getGeofenceLive client failure: $e');
          return ApiResponse.error(_liveAttendanceNetworkError);
        }
      } catch (e) {
        return ApiResponse.error('Network error: $e');
      }

      await Future<void>.delayed(attemptDelays[attempt]);
    }

    return ApiResponse.error(_liveAttendanceNetworkError);
  }

  /// One session's movement trail — punch-in, every ping in order, and
  /// punch-out — for drawing a route on the team map.
  ///
  /// Admin or Director only. Contract:
  /// docs/geofence-live-dashboard-api.md §2.
  static Future<ApiResponse> getGeofenceRoute({
    required String token,
    required int sessionId,
  }) async {
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.geofenceTimelineEndpoint}',
    ).replace(queryParameters: {'session_id': sessionId.toString()});

    try {
      final response = await http
          .get(
            uri,
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final body = response.body.isNotEmpty ? json.decode(response.body) : {};
        return ApiResponse.success(
          body is Map<String, dynamic> ? body : {'data': body},
        );
      }
      if (response.statusCode == 404) {
        return ApiResponse.error('That session no longer exists.');
      }
      if (response.statusCode == 403) {
        return ApiResponse.error('Not allowed to view this route.');
      }
      return ApiResponse.error(
        'Could not load the route: ${response.reasonPhrase}',
      );
    } on TimeoutException catch (_) {
      return ApiResponse.error('Connection timed out.');
    } on SocketException catch (e) {
      debugPrint('❌ getGeofenceRoute socket failure: $e');
      return ApiResponse.error(_liveAttendanceNetworkError);
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// Full breadcrumb for a specific session (admin or session owner).
  static Future<ApiResponse> getSessionTimeline({
    required String token,
    required int sessionId,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.attendanceSessionTimelineEndpoint}/$sessionId/timeline',
            ),
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final body = response.body.isNotEmpty ? json.decode(response.body) : {};
        return ApiResponse.success(
          body is Map<String, dynamic> ? body : {'data': body},
        );
      }
      return ApiResponse.error(
        'Failed to load timeline: ${response.reasonPhrase}',
      );
    } on TimeoutException catch (_) {
      return ApiResponse.error('Connection timed out.');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// Past-date attendance history for one calendar day (IST) via
  /// GET /attendance/history?date=YYYY-MM-DD. Returns every session for that
  /// day, each with its `punches[]` and `pings[]`, plus `total_seconds`.
  ///
  /// [userId] is the **admin-only** param to view another employee — pass
  /// null for own history (non-admins get 403 if it's sent). An empty day
  /// returns 200 with `sessions: []`, not 404.
  static Future<ApiResponse> getAttendanceHistoryByDate({
    required String token,
    required String date,
    int? userId,
  }) async {
    try {
      final params = <String, String>{'date': date};
      if (userId != null) params['user_id'] = userId.toString();
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.attendanceHistoryEndpoint}',
      ).replace(queryParameters: params);

      final response = await http
          .get(
            uri,
            headers: {
              ...ApiConstants.headers,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));

      _checkAuth(response.statusCode);
      if (response.statusCode == 200) {
        final body = response.body.isNotEmpty ? json.decode(response.body) : {};
        return ApiResponse.success(
          body is Map<String, dynamic> ? body : {'data': body},
        );
      }
      if (response.statusCode == 403) {
        return ApiResponse.error(
          'Admin access required to view other employees.',
        );
      }
      return ApiResponse.error(
        'Failed to load history: ${response.reasonPhrase}',
      );
    } on TimeoutException catch (_) {
      return ApiResponse.error('Connection timed out.');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }
}

// API Response wrapper
class ApiResponse {
  final bool isSuccess;
  final Map<String, dynamic>? data;
  final String? error;
  final String? errorCode;
  final bool isConflict;

  ApiResponse._({
    required this.isSuccess,
    this.data,
    this.error,
    this.errorCode,
    this.isConflict = false,
  });

  factory ApiResponse.success(Map<String, dynamic> data) {
    return ApiResponse._(isSuccess: true, data: data);
  }

  factory ApiResponse.error(String message, {Map<String, dynamic>? data}) {
    return ApiResponse._(
      isSuccess: false,
      error: message,
      data: data,
      errorCode: _readErrorCode(data),
    );
  }

  /// HTTP 409 — used by `/attendance/punch-in` when a session is already open.
  factory ApiResponse.conflict(Map<String, dynamic> body) {
    return ApiResponse._(
      isSuccess: false,
      isConflict: true,
      error: body['message']?.toString() ?? 'Conflict',
      errorCode: _readErrorCode(body),
      data: body,
    );
  }

  /// The attendance endpoints return the machine-readable code as `code`
  /// (see docs/geofence-module-guide.md §5); older endpoints use
  /// `error_code`. Read both so a 409/403 is never misclassified — reading
  /// only `error_code` is what made `ALREADY_PUNCHED_TODAY` fall through to
  /// the `SESSION_ALREADY_OPEN` branch.
  static String? _readErrorCode(Map<String, dynamic>? body) =>
      (body?['code'] ?? body?['error_code'])?.toString();
}

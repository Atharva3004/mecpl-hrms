// API Constants - Base URLs and Configuration
class ApiConstants {
  // Base URL
  static const String baseUrl = 'https://hrms.mecpl.in/api';

  // Host root (no /api) — used to resolve relative file/image paths returned
  // by the API (e.g. an emp_image stored under /storage/...).
  static const String fileBaseUrl = 'https://hrms.mecpl.in';

  // API Token
  static const String apiToken = '170|PYWnnqnt6XwyJT9LpvdMGXqtaqiB6TIN2oQhfwv0';

  // Endpoints
  static const String loginEndpoint = '/check_login_api';
  static const String validateTokenEndpoint = '/validate-token';
  static const String logoutEndpoint = '/logout';
  // Updates the FCM device token on the user's session row. Called when FCM
  // rotates the token mid-session (app reinstall, data clear).
  static const String updateFcmTokenEndpoint = '/update-fcm-token';

  // In-app notification list — paginated + read/unread state. Mirrored in
  // docs/flutter-notification-api.md from the backend dev.
  static const String notificationsEndpoint = '/notifications';
  static const String notificationsUnreadCountEndpoint = '/notifications/unread-count';
  static const String notificationsMarkAllReadEndpoint = '/notifications/mark-all-read';
  // Single-item mark-as-read: '/notifications/{id}/mark-as-read'. Built at call site.
  static const String employeeEndpoint = '/employee';
  static const String leaveTypesEndpoint = '/leaves/leave_types';
  static const String leaveCalculationEndpoint = '/leaves/calculate-days';
  static const String leaveApplyEndpoint = '/leaves/store-leave';
  static const String storeEmployeeLeaveEndpoint = '/leaves/store-employee-leave';
  static const String deleteEmployeeLeaveEndpoint = '/leaves/delete-employee-leave';
  static const String employeeLeavesListEndpoint = '/leaves/employee-leaves-list';
  static const String leaveHistoryEndpoint = '/leaves/my-applications';
  static const String leaveBalanceEndpoint = '/leaves/leave-balance';
  static const String leaveApprovalEndpoint = '/leaves/leave-approvals';
  static const String leaveInfoEndpoint = '/leaves/leave-info';
  static const String updateLeaveStatusEndpoint = '/leaves/update-status';
  static const String getBranchesEndpoint = '/leaves/get_branches';
  static const String getEmployeesByBranchEndpoint = '/leaves/get-employees-by-branch';

  // Branch payroll approvals — pending payroll activity requests (Release,
  // Resignation, Advance, etc.) grouped by approval level in `data`.
  static const String branchPayrollApprovalsEndpoint = '/branch-payroll-approvals';
  // Single payroll request detail — append `/{id}`. Returns request_data
  // (activity fields) and the full approval_timeline.
  static const String branchPayrollRequestDetailEndpoint =
      '/branch-payroll-request-detail';
  // Approve / reject a branch payroll request (multipart POST: action,
  // request_ids, remarks, level).
  static const String postBranchPayrollApprovalEndpoint =
      '/post-branch-payroll-approval';
  static const String appointmentLetterEndpoint = '/letters/appointment';
  static const String confirmationLetterEndpoint = '/letters/confirmation';

  // HR letters, one route per type — append the slug (warning, confirmation,
  // extension, experience, promotion, appointment) plus a `category` query of
  // staff | apprentice | consultant, since HR keeps a separate template per
  // employment category. Returns the raw PDF. Used by My Documents › Letters.
  static const String lettersEndpoint = '/letters';

  // Form 16 — per-employee availability of the TRACES / MECPL certificates,
  // split into Part A and Part B. Returns `financial_year` plus a `sources`
  // block giving an `id` + `available` flag per part.
  static const String form16StatusEndpoint = '/form16/status';
  // Raw PDF for one part — append `/{id}` from the status response.
  static const String form16DownloadEndpoint = '/form16/download';

  // My Documents — one call returning every document the employee has for the
  // current financial year: Form 16 (TRACES parts + the MECPL file list) and
  // the medical health card. See docs/my-documents-api.md.
  static const String myDocumentsEndpoint = '/my-documents';
  // Raw PDF for the health card — append `/{id}` from the my-documents call.
  static const String healthCardDownloadEndpoint = '/health-card/download';

  // Attendance Endpoints
  static const String attendanceHistoryEndpoint = '/attendance/history';
  static const String dailyAttendanceEndpoint = '/get_daily_attendance';
  static const String clockInEndpoint = '/attendance/clock-in';
  static const String clockOutEndpoint = '/attendance/clock-out';

  // Geofencing + session-based attendance (see docs/geofencing-backend-integration.md)
  static const String myGeofenceEndpoint = '/me/geofence';
  static const String punchInEndpoint = '/attendance/punch-in';
  static const String punchOutEndpoint = '/attendance/punch-out';
  static const String locationPingEndpoint = '/attendance/location-ping';
  static const String locationPingBatchEndpoint = '/attendance/location-ping/batch';
  static const String attendanceTodayEndpoint = '/attendance/today';
  static const String attendanceLiveEndpoint = '/attendance/live';
  // Geofence Live dashboard (admin/director). Contract:
  // docs/geofence-live-dashboard-api.md
  static const String geofenceLiveEndpoint = '/attendance/geofence-live';
  static const String geofenceTimelineEndpoint = '/attendance/geofence-timeline';
  static const String attendanceSessionTimelineEndpoint =
      '/attendance/session'; // append /{id}/timeline
  static const String todayAttendanceEndpoint = '/today-employee-attendance';
  static const String holidaysEndpoint = '/get_holidays';
  static const String calendarDataEndpoint = '/get_calendar_data';
  static const String myAttendanceEndpoint = '/get_my_attendance';
  static const String regularizeAttendanceEndpoint = '/attendance/regularize';
  static const String myRegularizationDataEndpoint = '/get_my_regularization_data';
  static const String submitRegularizationRequestEndpoint = '/submit_regularization_request';
  static const String regularizationApprovalsEndpoint = '/regularization-pending';
  static const String myRegularizationListEndpoint = '/get_my_regularization_requests';
  static const String updateRegularizationStatusEndpoint = '/attendance/update-regularization-status';
  static const String approveRejectRegularizationEndpoint = '/approve_reject_regularization';

  // Onboarding Endpoints
  static const String onboardingApprovalEndpoint = '/employeeOnboardingApproval';
  static const String postOnboardingApprovalEndpoint = '/postOnboardingApproval';

  // Requisition Endpoints — pending manpower requisitions grouped per project,
  // with a top-level `stats` block and pagination. Shown on the director
  // Requisition Summary screen.
  static const String pendingRequisitionsEndpoint = '/pending-requisitions';

  // Pre-Recruitment Endpoints
  static const String preRecruitmentCandidatesEndpoint =
      '/pre-recruitment/candidates';
  static const String preRecruitmentSubmitDetailsEndpoint =
      '/pre-recruitment/submit-details';

  // Permission Management Endpoints
  static const String permissionsEndpoint = '/permissions';
  static const String globalPermissionsEndpoint = '/permissions/global';

  // Headers
  static Map<String, String> get headers => {
    'X-API-Key': apiToken,
    'Accept': 'application/json',
    'X-Requested-With': 'XMLHttpRequest',
  };
}

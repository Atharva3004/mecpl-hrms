<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\LoginAPIController;
use App\Http\Controllers\Api\EmployeeController;
use App\Http\Controllers\Api\LeaveManagementController;
use App\Http\Controllers\Api\LeaveApplicationController;
use App\Http\Controllers\Api\MasterController;
use App\Http\Controllers\Api\PayrollController;
use App\Http\Controllers\Api\AttendanceController;
use App\Http\Controllers\Api\LetterController;
use App\Http\Controllers\Api\GeofenceController;
use App\Http\Controllers\Api\AttendancePunchController;
use App\Http\Controllers\Api\AttendanceLocationPingController;
use App\Http\Controllers\Api\AttendanceViewController;
use App\Http\Controllers\Api\FcmTokenController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\PreRecruitmentApiController;
use App\Http\Controllers\Api\RequisitionController as ApiRequisitionController;
use App\Http\Controllers\Api\Form16ApiController;
/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
|
| Here is where you can register API routes for your application. These
| routes are loaded by the RouteServiceProvider within a group which
| is assigned the "api" middleware group. Enjoy building your API!
|
*/


Route::post('/check_login_api', [LoginAPIController::class, 'checkLoginAPI']);

// PROTECTED (TOKEN REQUIRED)
Route::middleware('auth:sanctum')->group(function () {
    Route::post('/logout', [LoginAPIController::class, 'logout']);
    Route::get('/validate-token', [LoginAPIController::class, 'validateToken']);
    Route::post('/update-fcm-token', [FcmTokenController::class, 'update']);

    // ************** Notifications **************
    Route::get('/notifications', [NotificationController::class, 'index']);
    Route::get('/notifications/unread-count', [NotificationController::class, 'unreadCount']);
    Route::post('/notifications/mark-all-read', [NotificationController::class, 'markAllRead']);
    Route::post('/notifications/{id}/mark-as-read', [NotificationController::class, 'markAsRead']);

    Route::get('/employee', [EmployeeController::class, 'manageEmployee']);

    // ************** Letter Downloads (PDF) **************
    // Route::get('/letters/confirmation', [LetterController::class, 'downloadConfirmationLetter']);
    // Route::get('/letters/appointment', [LetterController::class, 'downloadAppointmentLetter']);

    // ************** Leave Management **************
    Route::group(['prefix' => 'leaves'], function () {

        //Leave Types
        Route::get('/leave_types', [LeaveApplicationController::class, 'leaveTypes'])->name('leaves.types');


        // Master/Admin: Leave Details & Configuration
        Route::get('/leave-details', [LeaveManagementController::class, 'manageLeaves'])->name('leaves.details');
        Route::post('/import-balances', [LeaveManagementController::class, 'importManualBalances'])->name('leaves.import_balances');
        
        // Employee: Leave Application
        Route::get('/apply', [LeaveApplicationController::class, 'applyLeave'])->name('leaves.apply');
        Route::post('/store-leave', [LeaveApplicationController::class, 'storeLeave'])->name('leaves.store');
        Route::get('/my-applications', [LeaveApplicationController::class, 'myApplications'])->name('leaves.my_applications');

        // Employee: Leave Balance
        Route::get('/leave-balance', [LeaveApplicationController::class, 'LeaveBalance'])->name('leaves.balance');


        // Manager: Leave Approval
        Route::get('/leave-approvals', [LeaveApplicationController::class, 'leaveApprovals'])->name('leaves.approvals');
        Route::post('/update-status', [LeaveApplicationController::class, 'approveReject'])->name('leaves.update_status');
        Route::get('/stats', [LeaveApplicationController::class, 'getLeaveStats'])->name('leaves.stats');
        Route::post('/calculate-days', [LeaveApplicationController::class, 'calculateLeaveDays'])->name('leaves.calculate_days');
        Route::post('/leave-info', [LeaveApplicationController::class, 'getLeaveDetails'])->name('leaves.info');
        Route::post('/bulk-approve', [LeaveApplicationController::class, 'bulkApprove'])->name('leaves.bulk_approve');
        
        // Reports
        Route::get('/reports/balance-summary', [LeaveManagementController::class, 'leaveBalanceSummary'])->name('leaves.reports.balance_summary');
        Route::get('/reports/monthly-register', [LeaveManagementController::class, 'monthlyLeaveRegister'])->name('leaves.reports.monthly_register');
        Route::get('/reports/absenteeism', [LeaveManagementController::class, 'absenteeismReport'])->name('leaves.reports.absenteeism');
        
        // Leave History Import
        Route::get('/history-upload', [LeaveManagementController::class, 'leaveHistoryUpload'])->name('leaves.history_upload');
        Route::post('/history-import', [LeaveManagementController::class, 'importLeaveHistory'])->name('leaves.history_import');
        
        // Site-Admin: Apply Leave for Employee
        Route::post('/apply-employee-leave', [LeaveApplicationController::class, 'applyEmployeeLeave'])->name('leaves.apply_employee');
        Route::post('/get_branches', [MasterController::class, 'getBranches'])->name('leaves.get_branches');
        Route::post('/get-employees-by-branch', [LeaveApplicationController::class, 'getEmployeesByBranch'])->name('leaves.get_employees');
        Route::post('/store-employee-leave', [LeaveApplicationController::class, 'storeEmployeeLeave'])->name('leaves.store_employee');
        Route::post('/employee-leaves-list', [LeaveApplicationController::class, 'employeeLeavesList'])->name('leaves.employee_list');
        Route::post('/cancel-employee-leave', [LeaveApplicationController::class, 'cancelEmployeeLeave'])->name('leaves.cancel_employee');
        Route::get('/get-employee-balance/{emp_id}', [LeaveApplicationController::class, 'getEmployeeBalance'])->name('leaves.get_employee_balance');
        Route::post('/delete-employee-leave', [LeaveApplicationController::class, 'deleteEmployeeLeave'])->name('leaves.delete_employee');
        Route::get('/get-optional-holidays/{emp_id}', [LeaveApplicationController::class, 'getOptionalHolidays'])->name('leaves.optional_holidays');

        // Settings
        Route::post('/settings/update', [LeaveManagementController::class, 'updateSettings'])->name('leaves.settings.update');
        

    });

    // get holidays
    Route::get('/get_holidays', [MasterController::class, 'getHolidays']);
    Route::get('/get_reason_leaving', [MasterController::class, 'getReasonLeaving']);

    //*************** Employee On-Boarding Approval ***************
    Route::post('/employeeOnboardingApproval', [EmployeeController::class, 'employeeOnboardingApproval'])->name('employee.onboarding.approval.page');
    Route::post('/postOnboardingApproval', [EmployeeController::class, 'postOnboardingApproval'])->name('employee.onboarding.approval.post');
    Route::get('/get_employee_summary/{id}', [EmployeeController::class, 'getEmployeeSummary'])->name('get.employee.summary');
    Route::get('/get-employee-full-details/{id}', [EmployeeController::class, 'getEmployeeFullDetails'])->name('get.employee.full.details');

    // ************** Pre-Recruitment **************
    Route::get('/pre-recruitment/candidates', [PreRecruitmentApiController::class, 'getSelectedPostponedCandidates']);
    Route::post('/pre-recruitment/submit-details', [PreRecruitmentApiController::class, 'submitPhotoAndStatutory']);

    // ************* Generate PaySlip *************
    Route::post('/emp_salary_payslip', [PayrollController::class, 'empSalaryPayslip'])->name('emp.salary.payslip');
    Route::post('/download-payslip', [PayrollController::class, 'downloadPaySlip'])->name('download.payslip');

    // ************* Branch Payroll Approval *************
    Route::get('/branch-payroll-approvals', [PayrollController::class, 'branchPayrollApprovals']);
    Route::get('/branch-payroll-request-detail/{id}', [PayrollController::class, 'branchPayrollRequestDetail']);
    Route::post('/post-branch-payroll-approval', [PayrollController::class, 'postBranchPayrollApprovalApi']);

    // *** ********** Employee Attendance *************
    Route::post('/today-employee-attendance', [AttendanceController::class, 'todayAttendance']);
    Route::post('/get_my_attendance', [AttendanceController::class, 'getMyAttendance']);
    Route::get('/get_calendar_data', [AttendanceController::class, 'getCalendarData']);

    // Daily Attendance (All Employees)
    Route::post('/get_daily_attendance', [AttendanceController::class, 'getDailyAttendance']);

    // Employee Self-Service Regularization (NEW)
    Route::post('/get_my_regularization_data', [AttendanceController::class, 'getMyRegularizationData']);
    Route::post('/submit_regularization_request', [AttendanceController::class, 'submitRegularizationRequest']);
    Route::post('/get_my_regularization_requests', [AttendanceController::class, 'getMyRegularizationRequests']);

    // Manager Regularization Approval (NEW)
    Route::get('/regularization-pending', [AttendanceController::class, 'regularizationPendingRequests'])->name('regularizationPendingRequests.page');
    Route::post('/approve_reject_regularization', [AttendanceController::class, 'approveRejectRegularization'])->name('regularization.approve_reject');
    Route::post('/bulk_approve_regularization', [AttendanceController::class, 'bulkApproveRegularization'])->name('regularization.bulk_approve');
    Route::get('/regularization-details/{id}', [AttendanceController::class, 'getRegularizationDetails'])->name('regularization.details');

    // Comp Off Logs
    Route::get('/get-active-comp-offs/{emp_id}', [AttendanceController::class, 'getActiveCompOffs'])->name('attendance.active_comp_offs');
    Route::post('/get-comp-off-logs', [AttendanceController::class, 'getCompOffLogs'])->name('attendance.comp_off_logs');

    // ************** Geofencing & Mobile Attendance **************
    Route::get('/me/geofence', [GeofenceController::class, 'me']);

    // Punches (multipart) — strict throttle to prevent button-spam
    Route::middleware('throttle:6,1')->group(function () {
        Route::post('/attendance/punch-in', [AttendancePunchController::class, 'punchIn']);
        Route::post('/attendance/punch-out', [AttendancePunchController::class, 'punchOut']);
    });

    // Location pings (json)
    Route::middleware('throttle:30,1')->group(function () {
        Route::post('/attendance/location-ping', [AttendanceLocationPingController::class, 'store']);
        Route::post('/attendance/location-ping/batch', [AttendanceLocationPingController::class, 'batch']);
    });

    // Self-views
    Route::get('/attendance/today', [AttendanceViewController::class, 'today']);
    Route::get('/attendance/history', [AttendanceViewController::class, 'history']);
    Route::get('/attendance/session/{id}/timeline', [AttendanceViewController::class, 'timeline']);

    // ************** Requisition **************
    Route::get('/pending-requisitions', [ApiRequisitionController::class, 'pendingRequisitions']);

    // ************** Form 16 **************
    Route::get('/form16/status', [Form16ApiController::class, 'getForm16Status']);
    Route::get('/form16/download/{id}', [Form16ApiController::class, 'downloadForm16']);

    // ************** My Documents **************
    Route::get('/my-documents', [Form16ApiController::class, 'getMyDocuments']);
    Route::get('/health-card/download/{id}', [Form16ApiController::class, 'downloadHealthCard']);

    // Admin-only
    Route::middleware('admin')->group(function () {
        Route::get('/attendance/live', [AttendanceViewController::class, 'live']);
    });

});
// User Roles for HRMS
enum UserRole {
  director,
  manager,
  admin,
  onSiteAdmin,
  hrAdmin,
  hoHr,
  staff,
  employee,
}

extension UserRoleExtension on UserRole {
  String get displayName {
    switch (this) {
      case UserRole.director:
        return 'Director';
      case UserRole.manager:
        return 'Manager';
      case UserRole.admin:
        return 'Admin';
      case UserRole.onSiteAdmin:
        return 'On-site Admin';
      case UserRole.hrAdmin:
        return 'HR Admin';
      case UserRole.hoHr:
        return 'HO HR';
      case UserRole.staff:
        return 'Staff';
      case UserRole.employee:
        return 'Employee';
    }
  }

  String get description {
    switch (this) {
      case UserRole.director:
        return 'Full system access with executive dashboard';
      case UserRole.manager:
        return 'Team management and approval access';
      case UserRole.admin:
        return 'System configuration and user management';
      case UserRole.onSiteAdmin:
        return 'Site-specific administration';
      case UserRole.hrAdmin:
        return 'Complete HR operations access';
      case UserRole.hoHr:
        return 'Head Office HR operations';
      case UserRole.staff:
        return 'Standard staff features';
      case UserRole.employee:
        return 'Basic employee self-service';
    }
  }

  int get accessLevel {
    switch (this) {
      case UserRole.director:
        return 100;
      case UserRole.manager:
        return 80;
      case UserRole.admin:
        return 70;
      case UserRole.hrAdmin:
        return 70;
      case UserRole.hoHr:
        return 75;
      case UserRole.onSiteAdmin:
        return 60;
      case UserRole.staff:
        return 40;
      case UserRole.employee:
        return 20;
    }
  }

  bool get canViewAllEmployees {
    return [
      UserRole.director,
      UserRole.manager,
      UserRole.admin,
      UserRole.hrAdmin,
      UserRole.hoHr,
      UserRole.onSiteAdmin,
    ].contains(this);
  }

  bool get canManagePayroll {
    return [
      UserRole.director,
      UserRole.hrAdmin,
      UserRole.hoHr,
      UserRole.admin,
    ].contains(this);
  }

  bool get canApproveLeaves {
    return [
      UserRole.director,
      UserRole.manager,
      UserRole.hrAdmin,
      UserRole.hoHr,
    ].contains(this);
  }

  bool get canViewReports {
    return [
      UserRole.director,
      UserRole.manager,
      UserRole.admin,
      UserRole.hrAdmin,
      UserRole.hoHr,
      UserRole.onSiteAdmin,
    ].contains(this);
  }

  bool get canManageSettings {
    return [UserRole.director, UserRole.admin].contains(this);
  }

  bool get canViewRequisition {
    return [
      UserRole.director,
      UserRole.manager,
      UserRole.admin,
      UserRole.hoHr,
      UserRole.onSiteAdmin,
    ].contains(this);
  }

  bool get canViewSurplus {
    return [UserRole.director, UserRole.admin].contains(this);
  }

  bool get canViewBranchStaff {
    return [
      UserRole.director,
      UserRole.manager,
      UserRole.hrAdmin,
      UserRole.hoHr,
      UserRole.admin,
    ].contains(this);
  }

  bool get canViewStaffTransfer {
    return [
      UserRole.director,
      UserRole.hrAdmin,
      UserRole.hoHr,
      UserRole.admin,
    ].contains(this);
  }

  bool get canViewPayroll {
    return [
      UserRole.director,
      UserRole.hrAdmin,
      UserRole.hoHr,
      UserRole.admin,
    ].contains(this);
  }

  bool get canViewLeave {
    return true; // All roles can now access Leave Management
  }

  bool get canApplyEmployeeLeave {
    return [
      UserRole.director,
      UserRole.admin,
      // UserRole.manager,
      // UserRole.hrAdmin,
      // UserRole.hoHr,
      UserRole.onSiteAdmin,
    ].contains(this);
  }

  bool get canApproveOnboarding {
    return [
      UserRole.director,
      UserRole.admin,
      // UserRole.hrAdmin,
      // UserRole.hoHr,
      UserRole.manager,
    ].contains(this);
  }

  bool get canViewEmployeePayslip {
    return [UserRole.admin].contains(this);
  }

  bool get canApproveRegularization {
    return [
      UserRole.director,
      UserRole.manager,
      UserRole.admin,
      UserRole.onSiteAdmin,
    ].contains(this);
  }

  bool get canViewPreRecruitment {
    // Pre-Recruitment is available to every role except plain staff and
    // employees (self-service users).
    return this != UserRole.staff && this != UserRole.employee;
  }

  bool get canViewLocationHistory {
    // Admin and Director can view all employees' locations
    // All users can view their own location history
    return [UserRole.director, UserRole.admin].contains(this);
  }
}

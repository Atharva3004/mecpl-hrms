// User Model for HRMS
import 'role_model.dart';

class UserModel {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String? avatarUrl;
  final UserRole role;
  final String? department;
  final String? designation;
  final String? employeeId;
  final String? phone;
  final DateTime? joinDate;
  final bool isActive;
  final int? branchId;
  final DateTime? dob;
  final String? address;
  final String? status;
  final String? firstIn;
  final String? lastOut;
  final String? totalWorkHours;

  UserModel({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    this.avatarUrl,
    required this.role,
    this.department,
    this.designation,
    this.employeeId,
    this.phone,
    this.joinDate,
    this.isActive = true,
    this.branchId,
    this.dob,
    this.address,
    this.status,
    this.firstIn,
    this.lastOut,
    this.totalWorkHours,
  });

  String get fullName => '$firstName $lastName';

  String get initials {
    final first = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    final last = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    return '$first$last';
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? firstName,
    String? lastName,
    String? avatarUrl,
    UserRole? role,
    String? department,
    String? designation,
    String? employeeId,
    String? phone,
    DateTime? joinDate,
    bool? isActive,
    int? branchId,
    DateTime? dob,
    String? address,
    String? status,
    String? firstIn,
    String? lastOut,
    String? totalWorkHours,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      department: department ?? this.department,
      designation: designation ?? this.designation,
      employeeId: employeeId ?? this.employeeId,
      phone: phone ?? this.phone,
      joinDate: joinDate ?? this.joinDate,
      isActive: isActive ?? this.isActive,
      branchId: branchId ?? this.branchId,
      dob: dob ?? this.dob,
      address: address ?? this.address,
      status: status ?? this.status,
      firstIn: firstIn ?? this.firstIn,
      lastOut: lastOut ?? this.lastOut,
      totalWorkHours: totalWorkHours ?? this.totalWorkHours,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'avatarUrl': avatarUrl,
      'role': role.name,
      'department': department,
      'designation': designation,
      'employeeId': employeeId,
      'phone': phone,
      'joinDate': joinDate?.toIso8601String(),
      'isActive': isActive,
      'branchId': branchId,
      'dob': dob?.toIso8601String(),
      'address': address,
      'status': status,
      'firstIn': firstIn,
      'lastOut': lastOut,
      'totalWorkHours': totalWorkHours,
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    // Handle "emp_name" from some API responses
    String fName = json['firstName']?.toString() ?? '';
    String lName = json['lastName']?.toString() ?? '';

    if (fName.isEmpty && (json['emp_name'] != null || json['name'] != null)) {
      final full = (json['emp_name'] ?? json['name']).toString().trim();
      final parts = full.split(' ');
      fName = parts[0];
      if (parts.length > 1) {
        lName = parts.sublist(1).join(' ');
      }
    }

    return UserModel(
      id: (json['id'] ?? json['user_id'] ?? '0').toString(),
      email: json['email']?.toString() ?? '',
      firstName: fName,
      lastName: lName,
      avatarUrl: (json['avatarUrl'] ?? json['emp_image'])?.toString(),
      role: UserRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => UserRole.employee,
      ),
      department: (json['department'] is Map)
          ? json['department']['department_name']?.toString()
          : (json['department']?.toString()),
      designation: (json['designation'] is Map)
          ? json['designation']['designation_name']?.toString()
          : (json['designation']?.toString()),
      employeeId: (json['employeeId'] ??
              json['emp_code'] ??
              json['emp_id'] ??
              json['code'])
          ?.toString(),
      phone: (json['phone'] ?? json['mobile_no'] ?? json['mobile'])?.toString(),
      joinDate: json['joinDate'] != null
          ? DateTime.tryParse(json['joinDate'].toString())
          : (json['doj'] != null
                ? DateTime.tryParse(json['doj'].toString())
                : null),
      isActive: json['isActive'] as bool? ?? true,
      branchId: json['branchId'] is int
          ? json['branchId']
          : int.tryParse((json['branchId'] ?? json['branch_id'])?.toString() ?? ''),
      dob: json['dob'] != null
          ? DateTime.tryParse(json['dob'].toString())
          : null,
      address: (json['address'] ?? json['personal_address'])?.toString(),
      status: json['status']?.toString(),
      firstIn: json['firstIn']?.toString(),
      lastOut: json['lastOut']?.toString(),
      totalWorkHours: json['totalWorkHours']?.toString(),
    );
  }

  // Demo users for testing
  static List<UserModel> get demoUsers => [
    UserModel(
      id: '1',
      email: 'director@mecpl.com',
      firstName: 'Rajesh',
      lastName: 'Sharma',
      role: UserRole.director,
      department: 'Executive',
      designation: 'Managing Director',
      employeeId: 'MECPL001',
      joinDate: DateTime(2015, 1, 1),
    ),
    UserModel(
      id: '2',
      email: 'manager@mecpl.com',
      firstName: 'Priya',
      lastName: 'Patel',
      role: UserRole.manager,
      department: 'Operations',
      designation: 'Operations Manager',
      employeeId: 'MECPL002',
      joinDate: DateTime(2018, 6, 15),
    ),
    UserModel(
      id: '3',
      email: 'admin@mecpl.com',
      firstName: 'Amit',
      lastName: 'Kumar',
      role: UserRole.admin,
      department: 'IT',
      designation: 'System Administrator',
      employeeId: 'MECPL003',
      joinDate: DateTime(2019, 3, 10),
    ),
    UserModel(
      id: '4',
      email: 'hr@mecpl.com',
      firstName: 'Sneha',
      lastName: 'Desai',
      role: UserRole.hrAdmin,
      department: 'Human Resources',
      designation: 'HR Manager',
      employeeId: 'MECPL004',
      joinDate: DateTime(2017, 9, 1),
    ),
    UserModel(
      id: '5',
      email: 'onsite@mecpl.com',
      firstName: 'Vikram',
      lastName: 'Singh',
      role: UserRole.onSiteAdmin,
      department: 'Field Operations',
      designation: 'Site Supervisor',
      employeeId: 'MECPL005',
      joinDate: DateTime(2020, 2, 20),
    ),
    UserModel(
      id: '6',
      email: 'staff@mecpl.com',
      firstName: 'Ananya',
      lastName: 'Reddy',
      role: UserRole.staff,
      department: 'Engineering',
      designation: 'Senior Engineer',
      employeeId: 'MECPL006',
      joinDate: DateTime(2021, 4, 5),
    ),
    UserModel(
      id: '7',
      email: 'employee@mecpl.com',
      firstName: 'Rohan',
      lastName: 'Mehta',
      role: UserRole.employee,
      department: 'Engineering',
      designation: 'Junior Developer',
      employeeId: 'MECPL007',
      joinDate: DateTime(2023, 1, 15),
    ),
  ];
}

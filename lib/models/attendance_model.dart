// Attendance Model for HRMS
import 'package:intl/intl.dart';

class AttendanceModel {
  final DateTime date;
  final String? checkIn;
  final String? checkOut;
  final String status;
  final String? type;
  final String? workingHours;
  final String? location;

  AttendanceModel({
    required this.date,
    this.checkIn,
    this.checkOut,
    required this.status,
    this.type,
    this.workingHours,
    this.location,
  });

  String get formattedDate => DateFormat('MMM dd, yyyy').format(date);
  String get dayName => DateFormat('EEEE').format(date);

  factory AttendanceModel.fromJson(Map<String, dynamic> json) {
    // Expected API date format: "2024-01-25" or ISO string
    DateTime parsedDate;
    if (json['date'] != null) {
      parsedDate = DateTime.parse(json['date']);
    } else {
      parsedDate = DateTime.now();
    }

    return AttendanceModel(
      date: parsedDate,
      checkIn: json['in_time']?.toString() ?? json['check_in']?.toString(),
      checkOut: json['out_time']?.toString() ?? json['check_out']?.toString(),
      status: json['status']?.toString() ?? 'Present',
      type:
          json['work_type']?.toString() ?? json['type']?.toString() ?? 'Office',
      workingHours: json['working_hours']?.toString(),
      location: json['location']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': DateFormat('yyyy-MM-dd').format(date),
      'in_time': checkIn,
      'out_time': checkOut,
      'status': status,
      'work_type': type,
      'working_hours': workingHours,
      'location': location,
    };
  }
}

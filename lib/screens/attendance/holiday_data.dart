import 'package:intl/intl.dart';

class Holiday {
  final int id;
  final DateTime date;
  final String name;
  final bool isOptional;
  final String dayName;

  const Holiday({
    required this.id,
    required this.date,
    required this.name,
    this.isOptional = false,
    required this.dayName,
  });

  factory Holiday.fromJson(Map<String, dynamic> json) {
    final date = DateTime.parse(json['holiday_date']);
    return Holiday(
      id: json['id'] ?? 0,
      date: date,
      name: json['holiday_name'] ?? '',
      isOptional:
          (json['holiday_type'] ?? '').toString().toLowerCase() == 'optional',
      dayName: json['day'] ?? DateFormat('EEEE').format(date),
    );
  }

  String get monthName => DateFormat('MMMM').format(date);
  int get day => date.day;
}

Map<String, List<Holiday>> groupHolidaysByMonth(List<Holiday> holidays) {
  final map = <String, List<Holiday>>{};
  for (final h in holidays) {
    final key = h.monthName.toUpperCase();
    map.putIfAbsent(key, () => []);
    map[key]!.add(h);
  }
  return map;
}

import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../screens/attendance/holiday_data.dart';

class HolidayProvider extends ChangeNotifier {
  List<Holiday> _holidays = [];
  bool _isLoading = false;
  String? _error;

  List<Holiday> get holidays => _holidays;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<Holiday> get upcomingHolidays {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1);
    return _holidays
        .where(
          (h) =>
              h.date.year == nextMonth.year && h.date.month == nextMonth.month,
        )
        .toList();
  }

  Future<void> fetchHolidays({
    required String token,
    required String year,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiService.getHolidays(token: token, year: year);

      if (response.isSuccess && response.data != null) {
        final data = response.data!;
        if (data['status'] == true && data['data'] != null) {
          final List<dynamic> holidayList = data['data'];
          final int currentYear = int.parse(year);
          _holidays = holidayList
              .where((h) => h['delete'] == 0)
              .map((h) => Holiday.fromJson(h as Map<String, dynamic>))
              .where((h) => h.date.year == currentYear)
              .toList();
          _holidays.sort((a, b) => a.date.compareTo(b.date));
        } else {
          _error = 'No holiday data available';
        }
      } else {
        _error = response.error ?? 'Failed to fetch holidays';
      }
    } catch (e) {
      _error = 'Error: $e';
    }

    _isLoading = false;
    notifyListeners();
  }
}

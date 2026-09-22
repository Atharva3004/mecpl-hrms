import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/holiday_provider.dart';
import 'holiday_data.dart';

class HolidayCalendarScreen extends StatelessWidget {
  const HolidayCalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final holidayProvider = context.watch<HolidayProvider>();
    final holidays = holidayProvider.holidays;
    final grouped = groupHolidaysByMonth(holidays);
    final year = DateTime.now().year.toString();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 20, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Text(
              'Holiday Calendar',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            Text(
              year,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                // color: const Color(0xFFFF7043),
                color: Color.fromARGB(255, 100, 112, 243),
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        children: grouped.entries.map((entry) {
          final monthName = entry.key;
          final monthHolidays = entry.value;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  // color: const Color(0xFFFFF0E8),
                  color: Color.fromARGB(255, 231, 234, 255),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  monthName,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    // color: const Color(0xFFFF7043),
                    color: Color.fromARGB(255, 100, 112, 243),
                  ),
                ),
              ),
              const SizedBox(height: 5),

              // Holiday cards for this month
              ...monthHolidays.map((holiday) => _buildHolidayCard(holiday)),
              const SizedBox(height: 8),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHolidayCard(Holiday holiday) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: holiday.isOptional ? const Color(0xFFFFF8F4) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          // Blue date circle - Smaller
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              // color: Color(0xFFFF7043),
              color: Color.fromARGB(255, 100, 112, 243),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                holiday.day.toString().padLeft(2, '0'),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,

                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Holiday info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  holiday.name,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Text(
                      holiday.dayName,
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (holiday.isOptional) ...[
                      const SizedBox(width: 4),
                      Text(
                        'Optional',
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          // color: const Color(0xFFFF7043),
                          color: Color.fromARGB(255, 100, 112, 243),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

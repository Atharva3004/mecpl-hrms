// Petty Contractors — searchable list of petty contractors with their work
// type, contact and assigned branch.
//
// NOTE: Runs on in-memory MOCK data (see `_contractors`). Swap for an
// ApiService call once the backend exposes a contractors endpoint.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class PettyContractorsScreen extends StatefulWidget {
  const PettyContractorsScreen({super.key});

  @override
  State<PettyContractorsScreen> createState() => _PettyContractorsScreenState();
}

class _PettyContractorsScreenState extends State<PettyContractorsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  // ---- MOCK DATA (replace with API once available) -----------------------
  final List<Map<String, String>> _contractors = [
    {'name': 'Sai Electricals', 'workType': 'Electrical', 'contact': '9820011223', 'branch': 'Pune'},
    {'name': 'Deccan Civil Works', 'workType': 'Civil', 'contact': '9820011224', 'branch': 'Pune'},
    {'name': 'Bright Housekeeping', 'workType': 'Housekeeping', 'contact': '9820011225', 'branch': 'Mumbai'},
    {'name': 'Metro Fabricators', 'workType': 'Fabrication', 'contact': '9820011226', 'branch': 'Mumbai'},
    {'name': 'AquaFlow Plumbing', 'workType': 'Plumbing', 'contact': '9820011227', 'branch': 'Delhi'},
    {'name': 'Sharp Painters', 'workType': 'Painting', 'contact': '9820011228', 'branch': 'Delhi'},
    {'name': 'Reliable Carpentry', 'workType': 'Carpentry', 'contact': '9820011229', 'branch': 'Hyderabad'},
    {'name': 'Green Landscapers', 'workType': 'Landscaping', 'contact': '9820011230', 'branch': 'Hyderabad'},
    {'name': 'Unity Welders', 'workType': 'Welding', 'contact': '9820011231', 'branch': 'Pune'},
    {'name': 'Prime Masonry', 'workType': 'Masonry', 'contact': '9820011232', 'branch': 'Mumbai'},
  ];

  List<Map<String, String>> get _filtered {
    if (_query.isEmpty) return _contractors;
    final q = _query.toLowerCase();
    return _contractors
        .where((c) =>
            c['name']!.toLowerCase().contains(q) ||
            c['workType']!.toLowerCase().contains(q) ||
            c['branch']!.toLowerCase().contains(q))
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Petty Contractors',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: AppTextStyles.bodySmall,
              decoration: InputDecoration(
                hintText: 'Search name, work type, branch…',
                hintStyle: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
                prefixIcon: const Icon(Iconsax.search_normal, size: 16),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text(
                  '${list.length} contractor${list.length == 1 ? '' : 's'}',
                  style: AppTextStyles.labelMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      'No contractors found',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _buildCard(list[index], index),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, String> c, int index) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: AppColors.secondary, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Iconsax.user_octagon,
                size: 20,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c['name']!,
                    style: AppTextStyles.titleSmall.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Iconsax.call,
                          size: 12, color: AppColors.textTertiary),
                      const SizedBox(width: 5),
                      Text(
                        c['contact']!,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Iconsax.location,
                          size: 12, color: AppColors.textTertiary),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          c['branch']!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Work-type chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                c['workType']!,
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 9.5,
                  color: AppColors.secondaryDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: (index * 40).ms).fadeIn(duration: 250.ms).slideY(
          begin: 0.05,
          end: 0,
          duration: 250.ms,
        );
  }
}

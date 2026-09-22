import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../widgets/common/custom_loader.dart';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:open_file/open_file.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  final List<String> _categories = [
    'All',
    'Personal',
    'Work',
  ];

  final List<Map<String, dynamic>> _documents = [
    {
      'title': 'Aadhar Card',
      'category': 'Personal',
      'type': 'JPG',
      'size': '450 KB',
      'date': 'Oct 20, 2024',
      'icon': Iconsax.personalcard,
      'color': Colors.orange,
    },
    {
      'title': 'PAN Card',
      'category': 'Personal',
      'type': 'JPG',
      'size': '320 KB',
      'date': 'Oct 20, 2024',
      'icon': Iconsax.card,
      'color': Colors.teal,
    },
    {
      'title': 'Appointment Letter',
      'category': 'Work',
      'type': 'PDF',
      'size': '1.2 MB',
      'date': 'Jan 15, 2023',
      'icon': Iconsax.document_text,
      'color': Colors.blue,
    },
    {
      'title': 'Confirmation Letter',
      'category': 'Work',
      'type': 'PDF',
      'size': '980 KB',
      'date': 'Jul 15, 2023',
      'icon': Iconsax.document_favorite,
      'color': Colors.indigo,
    },
    {
      'title': 'Form 16',
      'category': 'Work',
      'type': 'PDF',
      'size': '850 KB',
      'date': 'Jun 12, 2024',
      'icon': Iconsax.receipt_2,
      'color': Colors.green,
    },
  ];

  Map<String, String> _uploadedFiles = {};

  @override
  void initState() {
    super.initState();
    _loadUploadedFiles();
  }

  Future<void> _loadUploadedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _uploadedFiles['Aadhar Card'] = prefs.getString('doc_Aadhar Card') ?? '';
      _uploadedFiles['PAN Card'] = prefs.getString('doc_PAN Card') ?? '';
    });
  }

  Future<void> _pickAndSaveDocument(String title) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('doc_$title', image.path);
      setState(() {
        _uploadedFiles[title] = image.path;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title uploaded successfully!'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _removeDocument(String title) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('doc_$title');
    setState(() {
      _uploadedFiles.remove(title);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$title removed successfully!'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _viewDocument(Map<String, dynamic> doc) async {
    final title = doc['title'] as String;

    if (title == 'Aadhar Card' || title == 'PAN Card') {
      final path = _uploadedFiles[title];
      if (path != null && path.isNotEmpty) {
        final result = await OpenFile.open(path);
        if (result.type != ResultType.done && mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
               content: Text('Could not open file: ${result.message}'),
               backgroundColor: AppColors.error,
             ),
           );
        }
      } else {
        await _pickAndSaveDocument(title);
      }
      return;
    }

    if (title == 'Appointment Letter') {
      await _downloadAndOpenAppointmentLetter();
      return;
    }
    if (title == 'Confirmation Letter') {
      await _downloadAndOpenConfirmationLetter();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(doc['icon'] as IconData, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text('Opening ${doc['title']}...')),
          ],
        ),
        backgroundColor: doc['color'] as Color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _downloadDocument(Map<String, dynamic> doc) async {
    if (doc['title'] == 'Appointment Letter') {
      await _downloadAndOpenAppointmentLetter();
      return;
    }
    if (doc['title'] == 'Confirmation Letter') {
      await _downloadAndOpenConfirmationLetter();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const CustomLoader(size: 20, color: Colors.white),
            const SizedBox(width: 12),
            Text('Downloading ${doc['title']}...'),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Iconsax.tick_circle, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              const Text('Download Complete'),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _downloadAndOpenAppointmentLetter() async {
    final authProvider = context.read<AuthProvider>();
    final token = authProvider.token;

    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authentication error: Token not found')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            CustomLoader(size: 20, color: Colors.white),
            SizedBox(width: 12),
            Text('Fetching Appointment Letter...'),
          ],
        ),
        duration: Duration(seconds: 2),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );

    final String? filePath = await ApiService.downloadAppointmentLetter(
      token: token,
    );

    if (mounted) {
      if (filePath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Iconsax.tick_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Downloaded successfully. Opening...')),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Open the HTML file
        final result = await OpenFile.open(filePath);
        if (result.type != ResultType.done) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not open file: ${result.message}'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to fetch Appointment Letter'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadAndOpenConfirmationLetter() async {
    final authProvider = context.read<AuthProvider>();
    final token = authProvider.token;

    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authentication error: Token not found')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            CustomLoader(size: 20, color: Colors.white),
            SizedBox(width: 12),
            Text('Fetching Confirmation Letter...'),
          ],
        ),
        duration: Duration(seconds: 2),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );

    final String? filePath = await ApiService.downloadConfirmationLetter(
      token: token,
    );

    if (mounted) {
      if (filePath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Iconsax.tick_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Downloaded successfully. Opening...')),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Open the PDF file
        final result = await OpenFile.open(filePath);
        if (result.type != ResultType.done) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not open file: ${result.message}'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to fetch Confirmation Letter'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showUploadOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Upload Document',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            _buildUploadOption(
              icon: Iconsax.camera,
              label: 'Scan Document',
              color: Colors.blue,
            ),
            const SizedBox(height: 16),
            _buildUploadOption(
              icon: Iconsax.document_upload,
              label: 'Upload from Files',
              color: Colors.orange,
            ),
            const SizedBox(height: 16),
            _buildUploadOption(
              icon: Iconsax.image,
              label: 'Choose from Gallery',
              color: Colors.purple,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadOption({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(label, style: AppTextStyles.titleSmall),
      trailing: const Icon(Iconsax.arrow_right, size: 16),
      onTap: () {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label feature coming soon!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  List<Map<String, dynamic>> get _filteredDocuments {
    return _documents.where((doc) {
      final matchesCategory =
          _selectedCategory == 'All' || doc['category'] == _selectedCategory;
      final matchesSearch = doc['title'].toLowerCase().contains(
        _searchQuery.toLowerCase(),
      );
      return matchesCategory && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // App Bar
          _buildAppBar(context, isDark),

          // Search Bar
          SliverToBoxAdapter(child: _buildSearchBar(isDark)),

          // Category Selector
          SliverToBoxAdapter(child: _buildCategorySelector(isDark)),

          // Document List
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final doc = _filteredDocuments[index];
                return _buildDocumentCard(doc, isDark, index);
              }, childCount: _filteredDocuments.length),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showUploadOptions,
        backgroundColor: AppColors.primary,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Iconsax.add, color: Colors.white, size: 32),
      ).animate().scale(delay: 400.ms, curve: Curves.easeOutBack),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isDark) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      surfaceTintColor: Colors.transparent,
      title: Text(
        'My Documents',
        style: AppTextStyles.headlineLarge.copyWith(
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
      ),
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Icon(
          Icons.chevron_left,
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
      ),
      actions: [
        IconButton(
          onPressed: () {},
          icon: Icon(
            Iconsax.more,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        style: TextStyle(
          color: isDark ? Colors.white : AppColors.textPrimary,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: 'Search documents...',
          hintStyle: TextStyle(
            color: isDark ? Colors.white38 : AppColors.textTertiary,
            fontSize: 15,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          prefixIcon: Icon(
            Iconsax.search_normal,
            color: isDark ? Colors.white70 : AppColors.textSecondary,
            size: 20,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildCategorySelector(bool isDark) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = cat == _selectedCategory;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.darkSurface : Colors.white),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkBorder : AppColors.border),
                ),
                boxShadow: [
                  if (isSelected)
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Center(
                child: Text(
                  cat,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.white70 : AppColors.textSecondary),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDocumentCard(Map<String, dynamic> doc, bool isDark, int index) {
    final color = doc['color'] as Color;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
        ],
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(doc['icon'] as IconData, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  doc['title'],
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(
                        doc['type'],
                        style: AppTextStyles.caption.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        ' • ${doc['size']} • ${doc['date']}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (doc['title'] == 'Aadhar Card' || doc['title'] == 'PAN Card') ...[
            if (_uploadedFiles[doc['title']]?.isNotEmpty == true) ...[
              IconButton(
                onPressed: () => _viewDocument(doc),
                icon: Icon(
                  Iconsax.eye,
                  color: isDark ? Colors.white60 : Colors.black45,
                  size: 20,
                ),
              ),
              IconButton(
                onPressed: () => _pickAndSaveDocument(doc['title']),
                icon: const Icon(
                  Iconsax.edit,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              IconButton(
                onPressed: () => _removeDocument(doc['title']),
                icon: const Icon(
                  Iconsax.trash,
                  color: Colors.redAccent,
                  size: 20,
                ),
              ),
            ] else ...[
              TextButton.icon(
                onPressed: () => _pickAndSaveDocument(doc['title']),
                icon: const Icon(Iconsax.document_upload, size: 16),
                label: const Text('Upload'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ]
          ] else ...[
            IconButton(
              onPressed: () => _viewDocument(doc),
              icon: Icon(
                Iconsax.eye,
                color: isDark ? Colors.white60 : Colors.black45,
                size: 20,
              ),
            ),
            IconButton(
              onPressed: () => _downloadDocument(doc),
              icon: const Icon(
                Iconsax.document_download,
                color: AppColors.primary,
                size: 20,
              ),
            ),
          ],
        ],
      ),
    ).animate(delay: (index * 50).ms).fadeIn().slideX(begin: 0.1, end: 0);
  }
}

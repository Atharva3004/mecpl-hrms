import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/theme/app_colors.dart';

class Requisition {
  final String id;
  final String reqType;
  final String branch;
  final String designation;
  final String department;
  final DateTime requiredBy;
  final String remarks;
  final int requiredCount;
  final String status; // e.g., Pending, Approved, Rejected

  Requisition({
    required this.id,
    required this.reqType,
    required this.branch,
    required this.designation,
    required this.department,
    required this.requiredBy,
    this.remarks = '',
    this.requiredCount = 1,
    this.status = 'Pending',
  });
}

class RequisitionScreen extends StatefulWidget {
  const RequisitionScreen({super.key});

  @override
  State<RequisitionScreen> createState() => _RequisitionScreenState();
}

class _RequisitionScreenState extends State<RequisitionScreen> {
  final List<Requisition> _items = [
    Requisition(
      id: 'REQ-001',
      reqType: 'New Hiring',
      branch: 'Pune',

      designation: 'Project Manager',
      department: 'PROJECTS',
      requiredBy: DateTime.now().add(const Duration(days: 7)),
      remarks: 'Urgent for upcoming project',
      requiredCount: 2,
      status: 'Pending',
    ),

    Requisition(
      id: 'REQ-002',
      reqType: 'Replacement',
      branch: 'Mumbai',
      designation: 'Asst. Electrician',
      department: 'CONTRACTS',
      requiredBy: DateTime.now().add(const Duration(days: 14)),
      remarks: 'Replacement for resignation',
      requiredCount: 1,
      status: 'Approved',
    ),
  ];

  // Simple ID generator
  String _nextId() => 'REQ-${(_items.length + 1).toString().padLeft(3, '0')}';

  // Handler after returning from form
  Future<void> _openAddForm() async {
    final Requisition? newReq = await showModalBottomSheet<Requisition>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RequisitionFormPage(id: _nextId()),
    );
    if (newReq != null) {
      setState(() => _items.insert(0, newReq));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Requisition added')));
    }
  }

  void _openDetails(Requisition r) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RequisitionDetailPage(item: r)),
    );
  }

  void _removeItem(Requisition r) {
    setState(() => _items.removeWhere((e) => e.id == r.id));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Requisition removed')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: Colors.black,

        // 🔹 custom leading: arrow that pops the screen
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),

        title: const Text('Requisitions'),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.refresh),
            onPressed: () => setState(() {}),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _items.isEmpty ? _buildEmpty() : _buildList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddForm,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Icon(Iconsax.add),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Iconsax.box, size: 64, color: Colors.black26),
          SizedBox(height: 12),
          Text(
            'No requisitions yet',
            style: TextStyle(fontSize: 18, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final r = _items[idx];
        return Dismissible(
          key: ValueKey(r.id),
          direction: DismissDirection.endToStart,
          background: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerRight,
            color: Colors.redAccent,
            child: const Icon(Iconsax.trash, color: Colors.white),
          ),
          onDismissed: (_) => _removeItem(r),
          child: GestureDetector(
            onTap: () => _openDetails(r),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left status stripe
                    Container(
                      width: 6,
                      height: 70,
                      decoration: BoxDecoration(
                        color: _statusColor(r.status),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // top row: id + date + status
                          Row(
                            children: [
                              Text(
                                r.id,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _fmtDate(r.requiredBy),
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Text(
                                  r.status,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // main title
                          Text(
                            '${r.reqType} • ${r.designation}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // details row
                          Row(
                            children: [
                              Icon(
                                Iconsax.location,
                                size: 16,
                                color: Colors.black54,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                r.branch,
                                style: const TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(width: 16),
                              Icon(
                                Iconsax.hierarchy,
                                size: 16,
                                color: Colors.black54,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                r.department,
                                style: const TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(width: 16),
                              const Icon(
                                Iconsax.user,
                                size: 16,
                                color: Colors.black54,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'x${r.requiredCount}',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                          if (r.remarks.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              r.remarks,
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}';
}

class RequisitionFormPage extends StatefulWidget {
  final String id;
  const RequisitionFormPage({required this.id, super.key});

  @override
  State<RequisitionFormPage> createState() => _RequisitionFormPageState();
}

class _RequisitionFormPageState extends State<RequisitionFormPage> {
  final _formKey = GlobalKey<FormState>();

  String selectedReqType = 'New Hiring';
  String selectedBranch = 'Pune';
  String selectedDesignation = 'Project Manager';
  String selectedDepartment = 'PROJECTS';
  DateTime? selectedDate;
  final TextEditingController remarksController = TextEditingController();
  int requiredCount = 1;

  final List<String> reqTypes = ['New Hiring', 'Replacement'];
  final List<String> branches = ['Pune', 'Mumbai', 'Delhi', 'Hyderabad'];
  final List<String> designations = [
    'Project Manager',
    'Asst. Electrician',
    '3D DESIGNER',
    'Assistant',
  ];
  final List<String> departments = [
    'PROJECTS',
    'HR & ADMINISTRATION',
    'CONTRACTS',
    'Q.A',
  ];

  Future<void> _pickDate() async {
    final dt = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (dt != null) setState(() => selectedDate = dt);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select required by date')),
      );
      return;
    }

    final newReq = Requisition(
      id: widget.id,
      reqType: selectedReqType,
      branch: selectedBranch,
      designation: selectedDesignation,
      department: selectedDepartment,
      requiredBy: selectedDate!,
      remarks: remarksController.text.trim(),
      requiredCount: requiredCount,
      status: 'Pending',
    );

    Navigator.pop(context, newReq);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New Requisition',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Request manpower for your department',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Requisition Type
                    _buildLabel('Requisition Type'),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F7FB),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedReqType,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          items: reqTypes
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(
                                    e,
                                    style: GoogleFonts.poppins(fontSize: 14),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(
                            () => selectedReqType = v ?? reqTypes.first,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Branch
                    _buildLabel('Select Branch'),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F7FB),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedBranch,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          items: branches
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(
                                    e,
                                    style: GoogleFonts.poppins(fontSize: 14),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(
                            () => selectedBranch = v ?? branches.first,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Designation
                    _buildLabel('Designation'),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F7FB),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedDesignation,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          items: designations
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(
                                    e,
                                    style: GoogleFonts.poppins(fontSize: 14),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(
                            () => selectedDesignation = v ?? designations.first,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Department
                    _buildLabel('Department'),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F7FB),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedDepartment,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          items: departments
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(
                                    e,
                                    style: GoogleFonts.poppins(fontSize: 14),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(
                            () => selectedDepartment = v ?? departments.first,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Required count
                    _buildLabel('Required Count'),
                    TextFormField(
                      initialValue: '1',
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _inputDec(''),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Enter required count';
                        }
                        final n = int.tryParse(v);
                        if (n == null || n <= 0) return 'Enter valid number';
                        return null;
                      },
                      onChanged: (v) => requiredCount = int.tryParse(v) ?? 1,
                    ),
                    const SizedBox(height: 24),

                    // Date
                    _buildLabel('Required By'),
                    GestureDetector(
                      onTap: _pickDate,
                      child: AbsorbPointer(
                        child: TextFormField(
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: _inputDec('dd-mm-yyyy').copyWith(
                            suffixIcon: Icon(
                              Iconsax.calendar,
                              size: 18,
                              color: AppColors.primary,
                            ),
                          ),
                          controller: TextEditingController(
                            text: selectedDate == null
                                ? ''
                                : '${selectedDate!.day}-${selectedDate!.month}-${selectedDate!.year}',
                          ),
                          validator: (v) {
                            if (selectedDate == null) return 'Select date';
                            return null;
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Remarks
                    _buildLabel('Reason / Remarks'),
                    TextFormField(
                      controller: remarksController,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _inputDec('Describe here...'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 40),

                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 4,
                        ),
                        child: Text(
                          'Submit Requisition',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }

  InputDecoration _inputDec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(
        color: AppColors.textTertiary,
        fontSize: 13,
      ),
      filled: true,
      fillColor: const Color(0xFFF6F7FB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.all(16),
    );
  }
}

class RequisitionDetailPage extends StatelessWidget {
  final Requisition item;
  const RequisitionDetailPage({required this.item, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(item.id),
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _rowPair('Requisition Type', item.reqType),
                const SizedBox(height: 8),
                _rowPair('Branch', item.branch),
                const SizedBox(height: 8),
                _rowPair('Designation', item.designation),
                const SizedBox(height: 8),
                _rowPair('Department', item.department),
                const SizedBox(height: 8),
                _rowPair(
                  'Required By',
                  '${item.requiredBy.day}-${item.requiredBy.month}-${item.requiredBy.year}',
                ),
                const SizedBox(height: 8),
                _rowPair('Required Count', item.requiredCount.toString()),
                const SizedBox(height: 12),
                const Text(
                  'Remarks',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(item.remarks.isEmpty ? '-' : item.remarks),
                const SizedBox(height: 20),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        // Example action: mark approved (in real app call API)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Approve action')),
                        );
                      },
                      icon: const Icon(Iconsax.tick_circle),
                      label: const Text('Approve'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Reject action')),
                        );
                      },
                      icon: const Icon(Iconsax.close_circle),
                      label: const Text('Reject'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowPair(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

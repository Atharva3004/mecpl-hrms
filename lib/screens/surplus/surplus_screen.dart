import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';

class SurplusScreen extends StatefulWidget {
  const SurplusScreen({super.key});

  @override
  State<SurplusScreen> createState() => _SurplusScreenState();
}

class _SurplusScreenState extends State<SurplusScreen> {
  // sample list of surplus entries
  final List<Map<String, String>> _items = [
    {
      'title': 'Surplus - Finance',
      'subtitle': 'Branch: Pune • Dept: Accounts',
      'date': '10-12-2025',
      'status': 'Pending',
    },
    {
      'title': 'Surplus - Maintenance',
      'subtitle': 'Branch: Mumbai • Dept: Technical',
      'date': '20-12-2025',
      'status': 'Approved',
    },
  ];

  void _openSurplusForm() async {
    final newItem = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: FractionallySizedBox(
            heightFactor: 0.88,
            child: const SingleChildScrollView(child: SurplusForm()),
          ),
        );
      },
    );

    if (newItem != null) {
      setState(() => _items.insert(0, newItem));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Surplus added')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Employee Surplus'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      backgroundColor: const Color(0xFFFBF6FB),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: ListView.separated(
          itemCount: _items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final it = _items[i];
            return _surplusCard(it);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSurplusForm,
        backgroundColor: Colors.deepPurpleAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        icon: const Icon(Iconsax.add, color: Colors.white, size: 28),
        label: const Text(
          'Add Surplus',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _surplusCard(Map<String, String> item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item['title'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                item['date'] ?? '',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (item['status'] == 'Approved')
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  item['status'] ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: (item['status'] == 'Approved')
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item['subtitle'] ?? '',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class SurplusForm extends StatefulWidget {
  const SurplusForm({super.key});

  @override
  State<SurplusForm> createState() => _SurplusFormState();
}

class _SurplusFormState extends State<SurplusForm> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _surplusController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _wefController = TextEditingController();

  String? _selectedBranch;
  String? _selectedDesignation;
  String? _selectedDepartment;
  String? _selectedEmployee;

  final List<String> _branches = ['Pune', 'Mumbai', 'Delhi'];
  final List<String> _designations = [
    'Project Manager',
    'Asst. Electrician',
    'Accountant',
  ];
  final List<String> _departments = [
    'Projects',
    'Contracts',
    'Accounts',
    'Technical',
  ];
  final List<String> _employees = ['J. George', 'R. Kumar', 'S. Patil'];

  int _existingStrength = 0;
  DateTime? _wefDate;

  @override
  void dispose() {
    _surplusController.dispose();
    _reasonController.dispose();
    _wefController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _wefDate ?? now,
      firstDate: AppConstants.appStartDate,
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        _wefDate = picked;
        _wefController.text = DateFormat('dd-MM-yyyy').format(picked);
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final newItem = <String, String>{
      'title':
          '${_selectedDesignation ?? 'Surplus'} • ${_selectedBranch ?? ''}',
      'subtitle':
          'Branch: ${_selectedBranch ?? '-'} • Dept: ${_selectedDepartment ?? '-'} • Emp: ${_selectedEmployee ?? '-'}',
      'date': _wefController.text,
      'status': 'Pending',
      'reason': _reasonController.text,
    };

    Navigator.of(context).pop(newItem);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add Surplus',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildDropdown(
                    label: 'Branch',
                    value: _selectedBranch,
                    items: _branches,
                    onChanged: (v) => setState(() => _selectedBranch = v),
                  ),
                  const SizedBox(height: 10),
                  _buildDropdown(
                    label: 'Designation',
                    value: _selectedDesignation,
                    items: _designations,
                    onChanged: (v) {
                      setState(() {
                        _selectedDesignation = v;
                        _existingStrength = (v == 'Project Manager') ? 5 : 8;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildDropdown(
                    label: 'Department',
                    value: _selectedDepartment,
                    items: _departments,
                    onChanged: (v) => setState(() => _selectedDepartment = v),
                  ),
                  const SizedBox(height: 10),
                  _buildDropdown(
                    label: 'Select Employee',
                    value: _selectedEmployee,
                    items: _employees,
                    onChanged: (v) => setState(() => _selectedEmployee = v),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Existing Strength',
                          style: TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            '$_existingStrength',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _surplusController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Surplus Employees',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter number' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _wefController,
                    readOnly: true,
                    onTap: _pickDate,
                    decoration: InputDecoration(
                      labelText: 'W.E.F Date',
                      suffixIcon: const Icon(Iconsax.calendar),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Pick a date' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _reasonController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Reason (optional)',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Update',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      validator: (v) =>
          (v == null || v.isEmpty) ? 'Please select $label' : null,
    );
  }
}

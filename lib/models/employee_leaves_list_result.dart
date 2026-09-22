import 'branch_model.dart';
import 'leave_application_model.dart';

class EmployeeLeavesListResult {
  final List<LeaveApplication> leaves;
  final Map<String, int> counts; // total, pending, approved, rejected, cancelled
  final int currentPage;
  final int lastPage;
  final int total;
  final int perPage;
  final List<BranchModel> branches;

  const EmployeeLeavesListResult({
    required this.leaves,
    required this.counts,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.perPage,
    required this.branches,
  });

  factory EmployeeLeavesListResult.empty() => const EmployeeLeavesListResult(
        leaves: [],
        counts: {},
        currentPage: 1,
        lastPage: 1,
        total: 0,
        perPage: 20,
        branches: [],
      );

  int count(String key) => counts[key.toLowerCase()] ?? 0;
}

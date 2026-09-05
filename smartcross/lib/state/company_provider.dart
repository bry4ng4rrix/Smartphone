import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/company_repository.dart';
import '../models/company.dart';

final companyRepositoryProvider = Provider((ref) => CompanyRepository());

class PasswordResetRequestsNotifier extends AsyncNotifier<List<PasswordResetRequest>> {
  late final _repo = ref.read(companyRepositoryProvider);
  String _status = 'pending';

  @override
  Future<List<PasswordResetRequest>> build() => _repo.passwordResetRequests(status: _status);

  Future<void> setStatus(String status) async {
    _status = status;
    await refresh();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.passwordResetRequests(status: _status));
  }

  Future<void> resolve(int id, String action) async {
    await _repo.resolvePasswordReset(id, action);
    await refresh();
  }
}

final passwordResetRequestsProvider =
    AsyncNotifierProvider<PasswordResetRequestsNotifier, List<PasswordResetRequest>>(PasswordResetRequestsNotifier.new);

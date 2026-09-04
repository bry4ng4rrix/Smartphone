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

class CompanyDevicesNotifier extends AsyncNotifier<({List<CompanyDevice> devices, int count, int limit})> {
  late final _repo = ref.read(companyRepositoryProvider);

  @override
  Future<({List<CompanyDevice> devices, int count, int limit})> build() => _repo.devices();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.devices());
  }

  Future<void> requestDeletion(int deviceId) async {
    await _repo.requestDeviceDeletion(deviceId);
  }
}

final companyDevicesProvider =
    AsyncNotifierProvider<CompanyDevicesNotifier, ({List<CompanyDevice> devices, int count, int limit})>(CompanyDevicesNotifier.new);

final companySubscriptionProvider = FutureProvider.autoDispose<CompanySubscription>((ref) {
  return ref.read(companyRepositoryProvider).subscription();
});

class CompanyRequestsNotifier extends AsyncNotifier<List<CompanyRequest>> {
  late final _repo = ref.read(companyRepositoryProvider);

  @override
  Future<List<CompanyRequest>> build() => _repo.requests();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.requests());
  }

  Future<void> requestActivation() async {
    await _repo.requestActivation();
    await refresh();
  }
}

final companyRequestsProvider = AsyncNotifierProvider<CompanyRequestsNotifier, List<CompanyRequest>>(CompanyRequestsNotifier.new);

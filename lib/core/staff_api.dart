import 'net/api_client.dart';

/// Someone the owner lets work the shop from Hossouko Pro (`app/api/staff.py`).
class StaffMember {
  const StaffMember({required this.id, required this.phoneMasked, this.name, this.lastLoginAt});

  final int id;

  /// "07 •• •• 33 44".
  final String phoneMasked;
  final String? name;

  /// Null until they have signed in since being added.
  final DateTime? lastLoginAt;

  bool get hasSignedIn => lastLoginAt != null;

  factory StaffMember.fromJson(Map<String, Object?> json) => StaffMember(
        id: json['id']! as int,
        phoneMasked: json['phone_masked'] as String? ?? '',
        name: json['name'] as String?,
        lastLoginAt: json['last_login_at'] is String ? DateTime.tryParse('${json['last_login_at']}Z')?.toLocal() : null,
      );
}

/// The shop's cashiers. Owner only: the server answers 403 to a cashier.
class StaffApi {
  StaffApi(this._client);

  final ApiClient _client;

  Future<List<StaffMember>> list() async {
    final list = await _client.getJsonList('/api/merchant/staff');
    return [for (final m in list) StaffMember.fromJson(m! as Map<String, Object?>)];
  }

  /// Adds a cashier by phone number. They get an SMS and sign in to Hossouko Pro
  /// with that number.
  Future<StaffMember> add({required String phone, String? name}) async => StaffMember.fromJson(
        await _client.postJson('/api/merchant/staff', body: {
          'phone': phone,
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        }),
      );

  /// Removes a cashier. They lose access straight away, on every phone.
  Future<void> remove(int id) => _client.delete('/api/merchant/staff/$id');
}

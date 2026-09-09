/// A khata customer — someone the shopkeeper extends udhar to.
class Customer {
  final int? id;
  final int shopId;
  final String name;
  final String? phone;
  final DateTime createdAt;

  const Customer({
    this.id,
    required this.shopId,
    required this.name,
    this.phone,
    required this.createdAt,
  });

  Customer copyWith({
    int? id,
    int? shopId,
    String? name,
    String? phone,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'shop_id': shopId,
        'name': name,
        'phone': phone,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Customer.fromMap(Map<String, Object?> map) => Customer(
        id: map['id'] as int?,
        shopId: map['shop_id'] as int,
        name: map['name'] as String,
        phone: map['phone'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          map['created_at'] as int,
        ),
      );
}

/// A customer plus their derived running balance, for list screens.
/// [balance] is positive when the customer owes the shop money.
class CustomerBalance {
  final Customer customer;
  final double balance;
  final int transactionCount;
  final DateTime? lastActivity;

  const CustomerBalance({
    required this.customer,
    required this.balance,
    required this.transactionCount,
    this.lastActivity,
  });

  bool get owesMoney => balance > 0.005;
  bool get isSettled => balance.abs() <= 0.005;
}

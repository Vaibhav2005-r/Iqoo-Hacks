/// The single local shop profile. There is exactly one row of this table —
/// KhataSetu is deliberately single-tenant and offline; no auth, no sync.
class Shop {
  final int? id;
  final String name;
  final String ownerName;
  final String location;
  final DateTime createdAt;

  const Shop({
    this.id,
    required this.name,
    required this.ownerName,
    required this.location,
    required this.createdAt,
  });

  Shop copyWith({
    int? id,
    String? name,
    String? ownerName,
    String? location,
    DateTime? createdAt,
  }) {
    return Shop(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerName: ownerName ?? this.ownerName,
      location: location ?? this.location,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'owner_name': ownerName,
        'location': location,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Shop.fromMap(Map<String, Object?> map) => Shop(
        id: map['id'] as int?,
        name: map['name'] as String,
        ownerName: map['owner_name'] as String,
        location: (map['location'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          map['created_at'] as int,
        ),
      );
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// A client household owned by one or more advisors.
///
/// Stored at top-level `households/{id}` so an advisor can list every
/// household they belong to via a single `advisorIds arrayContains` query.
class Household {
  Household({
    required this.id,
    required this.name,
    required this.advisorIds,
    required this.createdAt,
    required this.createdBy,
  });

  final String id;
  final String name;
  final List<String> advisorIds;
  final DateTime createdAt;
  final String createdBy;

  factory Household.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Household(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      advisorIds: ((data['advisorIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate().toUtc() ?? DateTime.now(),
      createdBy: (data['createdBy'] as String?) ?? '',
    );
  }

  /// Write payload for a brand-new household. Uses
  /// [FieldValue.serverTimestamp] for `createdAt` so the timestamp is
  /// authoritative across clients.
  static Map<String, Object?> toCreatePayload({
    required String name,
    required String advisorUid,
  }) {
    return {
      'name': name,
      'advisorIds': [advisorUid],
      'createdBy': advisorUid,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/household.dart';

/// CRUD + streaming for the top-level `households` collection.
class HouseholdService {
  HouseholdService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('households');

  /// Newest-first stream of households the advisor belongs to.
  Stream<List<Household>> watchHouseholds(String advisorUid) {
    return _col
        .where('advisorIds', arrayContains: advisorUid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Household.fromDoc).toList());
  }

  /// Creates a household with the caller as the sole advisor. Returns
  /// the generated document id.
  Future<String> createHousehold({
    required String advisorUid,
    required String name,
  }) async {
    final doc = await _col.add(
      Household.toCreatePayload(name: name.trim(), advisorUid: advisorUid),
    );
    return doc.id;
  }

  Future<void> deleteHousehold(String hid) => _col.doc(hid).delete();
}

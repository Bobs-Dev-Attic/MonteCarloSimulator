import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/investment.dart';

/// CRUD + live stream for a customer's investments database, scoped to one
/// household. Mirrors [MemberService]; holdings are sorted by ticker.
class InvestmentService {
  InvestmentService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _investments(String hid) =>
      _db.collection('households').doc(hid).collection('investments');

  Stream<List<Investment>> watchInvestments(String householdId) {
    return _investments(householdId).snapshots().map((snap) {
      final list = snap.docs
          .map((d) => Investment.fromDoc(d, householdId))
          .toList()
        ..sort((a, b) =>
            a.ticker.toLowerCase().compareTo(b.ticker.toLowerCase()));
      return list;
    });
  }

  Future<String> createInvestment({
    required String householdId,
    required String advisorUid,
    required InvestmentDraft draft,
  }) async {
    final ref = await _investments(householdId).add(
      Investment.toCreatePayload(advisorUid: advisorUid, draft: draft),
    );
    return ref.id;
  }

  Future<void> updateInvestment({
    required String householdId,
    required String investmentId,
    required InvestmentDraft draft,
  }) {
    return _investments(householdId)
        .doc(investmentId)
        .update(draft.toUpdatePayload());
  }

  Future<void> deleteInvestment({
    required String householdId,
    required String investmentId,
  }) {
    return _investments(householdId).doc(investmentId).delete();
  }
}

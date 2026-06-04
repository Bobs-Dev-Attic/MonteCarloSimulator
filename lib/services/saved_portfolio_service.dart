import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/saved_portfolio.dart';

/// CRUD + live stream for a household's saved (model) portfolios, stored at
/// `households/{hid}/portfolios/{id}`. Mirrors [MemberService] /
/// [InvestmentService]; portfolios are sorted by name.
class SavedPortfolioService {
  SavedPortfolioService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _portfolios(String hid) =>
      _db.collection('households').doc(hid).collection('portfolios');

  Stream<List<SavedPortfolio>> watchPortfolios(String householdId) {
    return _portfolios(householdId).snapshots().map((snap) {
      final list = snap.docs
          .map((d) => SavedPortfolio.fromDoc(d, householdId))
          .toList()
        ..sort((a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  Future<String> createPortfolio({
    required String householdId,
    required String advisorUid,
    required SavedPortfolioDraft draft,
  }) async {
    final ref = await _portfolios(householdId).add(
      SavedPortfolio.toCreatePayload(advisorUid: advisorUid, draft: draft),
    );
    return ref.id;
  }

  Future<void> updatePortfolio({
    required String householdId,
    required String portfolioId,
    required SavedPortfolioDraft draft,
  }) {
    return _portfolios(householdId)
        .doc(portfolioId)
        .update(draft.toUpdatePayload());
  }

  Future<void> deletePortfolio({
    required String householdId,
    required String portfolioId,
  }) {
    return _portfolios(householdId).doc(portfolioId).delete();
  }
}

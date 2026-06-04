import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/member.dart';

class MemberService {
  MemberService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _members(String hid) =>
      _db.collection('households').doc(hid).collection('members');

  Stream<List<Member>> watchMembers(String householdId) {
    return _members(householdId).snapshots().map((snap) {
      final list = snap.docs
          .map((d) => Member.fromDoc(d, householdId))
          .toList()
        ..sort((a, b) {
          final byRel = a.relation.index.compareTo(b.relation.index);
          if (byRel != 0) return byRel;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      return list;
    });
  }

  Future<String> createMember({
    required String householdId,
    required String advisorUid,
    required MemberDraft draft,
  }) async {
    final ref = await _members(householdId).add(
      Member.toCreatePayload(advisorUid: advisorUid, draft: draft),
    );
    return ref.id;
  }

  Future<void> updateMember({
    required String householdId,
    required String memberId,
    required MemberDraft draft,
  }) {
    return _members(householdId)
        .doc(memberId)
        .update(draft.toUpdatePayload());
  }

  Future<void> deleteMember({
    required String householdId,
    required String memberId,
  }) {
    return _members(householdId).doc(memberId).delete();
  }
}

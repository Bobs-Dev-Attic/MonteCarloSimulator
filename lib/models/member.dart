import 'package:cloud_firestore/cloud_firestore.dart';

enum MemberRelation { primary, spouse, child, parent, dependent, other }

MemberRelation _relationFromString(String? s) {
  for (final r in MemberRelation.values) {
    if (r.name == s) return r;
  }
  return MemberRelation.other;
}

class MemberDraft {
  MemberDraft({
    required this.name,
    required this.relation,
    this.dateOfBirth,
    this.currentAge,
    this.retirementAge,
    this.lifeExpectancy,
    this.annualIncome,
  });

  final String name;
  final MemberRelation relation;
  final DateTime? dateOfBirth;
  final int? currentAge;
  final int? retirementAge;
  final int? lifeExpectancy;
  final double? annualIncome;

  Map<String, Object?> toUpdatePayload() {
    return {
      'name': name.trim(),
      'relation': relation.name,
      'dateOfBirth':
          dateOfBirth == null ? null : Timestamp.fromDate(dateOfBirth!),
      'currentAge': currentAge,
      'retirementAge': retirementAge,
      'lifeExpectancy': lifeExpectancy,
      'annualIncome': annualIncome,
    };
  }
}

class Member {
  Member({
    required this.id,
    required this.householdId,
    required this.name,
    required this.relation,
    this.dateOfBirth,
    this.currentAge,
    this.retirementAge,
    this.lifeExpectancy,
    this.annualIncome,
    required this.createdAt,
    required this.createdBy,
  });

  final String id;
  final String householdId;
  final String name;
  final MemberRelation relation;
  final DateTime? dateOfBirth;
  final int? currentAge;
  final int? retirementAge;
  final int? lifeExpectancy;
  final double? annualIncome;
  final DateTime createdAt;
  final String createdBy;

  int? get effectiveAge {
    final dob = dateOfBirth;
    if (dob != null) {
      final now = DateTime.now();
      var age = now.year - dob.year;
      final hadBirthdayThisYear = (now.month > dob.month) ||
          (now.month == dob.month && now.day >= dob.day);
      if (!hadBirthdayThisYear) age -= 1;
      return age;
    }
    return currentAge;
  }

  factory Member.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String householdId,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Member(
      id: doc.id,
      householdId: householdId,
      name: (data['name'] as String?) ?? '',
      relation: _relationFromString(data['relation'] as String?),
      dateOfBirth: (data['dateOfBirth'] as Timestamp?)?.toDate(),
      currentAge: (data['currentAge'] as num?)?.toInt(),
      retirementAge: (data['retirementAge'] as num?)?.toInt(),
      lifeExpectancy: (data['lifeExpectancy'] as num?)?.toInt(),
      annualIncome: (data['annualIncome'] as num?)?.toDouble(),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: (data['createdBy'] as String?) ?? '',
    );
  }

  static Map<String, Object?> toCreatePayload({
    required String advisorUid,
    required MemberDraft draft,
  }) {
    final base = draft.toUpdatePayload();
    return {
      ...base,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': advisorUid,
    };
  }
}

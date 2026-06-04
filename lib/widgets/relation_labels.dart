import 'package:flutter/material.dart';

import '../models/member.dart';

String relationLabel(MemberRelation r) {
  switch (r) {
    case MemberRelation.primary:
      return 'primary';
    case MemberRelation.spouse:
      return 'spouse';
    case MemberRelation.child:
      return 'child';
    case MemberRelation.parent:
      return 'parent';
    case MemberRelation.dependent:
      return 'dependent';
    case MemberRelation.other:
      return 'other';
  }
}

IconData relationIcon(MemberRelation r) {
  switch (r) {
    case MemberRelation.primary:
      return Icons.person;
    case MemberRelation.spouse:
      return Icons.favorite_outline;
    case MemberRelation.child:
      return Icons.child_care;
    case MemberRelation.parent:
      return Icons.elderly;
    case MemberRelation.dependent:
    case MemberRelation.other:
      return Icons.group;
  }
}

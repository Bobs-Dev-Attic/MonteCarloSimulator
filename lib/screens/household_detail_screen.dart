import 'package:flutter/material.dart';

import '../models/household.dart';

/// Stub placeholder shown when tapping a household row. Members and
/// portfolios CRUD land in a later sub-project; this screen exists so
/// the routing path is exercised end-to-end today.
class HouseholdDetailScreen extends StatelessWidget {
  const HouseholdDetailScreen({super.key, required this.household});
  final Household household;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(household.name)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Members and portfolios coming soon — household ID: ${household.id}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

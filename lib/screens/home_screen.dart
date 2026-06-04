import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/household.dart';
import '../state/providers.dart';
import 'create_household_screen.dart';
import 'household_detail_screen.dart';
import 'simulation_form_screen.dart';

/// Landing screen: lists the signed-in advisor's households and opens
/// the simulator form via an AppBar action.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final households = ref.watch(householdsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Households'),
        actions: [
          IconButton(
            tooltip: 'Run a simulation',
            icon: const Icon(Icons.science_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SimulationFormScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateHouseholdScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New household'),
      ),
      body: households.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          if (items.isEmpty) return const _EmptyState();
          return ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => _HouseholdTile(household: items[i]),
          );
        },
      ),
    );
  }
}

class _HouseholdTile extends ConsumerWidget {
  const _HouseholdTile({required this.household});
  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final created = DateFormat.yMMMd().format(household.createdAt);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.home_outlined)),
      title: Text(household.name),
      subtitle: Text('created $created'),
      trailing: IconButton(
        tooltip: 'Delete household',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _confirmDelete(context, ref),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HouseholdDetailScreen(household: household),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${household.name}"?'),
        content: const Text(
          'This removes the household record. Members and portfolios will be removed in a later release.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(householdServiceProvider).deleteHousehold(household.id);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_outlined, size: 64, color: scheme.primary),
            const SizedBox(height: 12),
            const Text(
              'No households yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap the + button to add your first household.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

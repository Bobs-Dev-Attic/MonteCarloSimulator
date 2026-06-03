import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/firestore_service.dart';
import '../state/providers.dart';
import 'results_screen.dart';
import 'simulation_form_screen.dart';

/// Landing screen: lists the user's saved simulations and launches new ones.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sims = ref.watch(savedSimulationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Simulations'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SimulationFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New simulation'),
      ),
      body: sims.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          if (items.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => _SimTile(sim: items[i]),
          );
        },
      ),
    );
  }
}

class _SimTile extends ConsumerWidget {
  const _SimTile({required this.sim});
  final SavedSimulation sim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGbm = sim.config.model == 'gbm';
    final date = DateFormat.yMMMd().add_jm().format(sim.createdAt);
    final summary = sim.result.summary;
    final subtitle = isGbm
        ? 'Median ${_money(summary.median)} · P(loss) ${(summary.probLoss * 100).toStringAsFixed(1)}%'
        : 'Success ${(summary.successRate * 100).toStringAsFixed(1)}%';
    return ListTile(
      leading: CircleAvatar(
        child: Icon(isGbm ? Icons.trending_up : Icons.savings),
      ),
      title: Text(sim.title ?? (isGbm ? 'Portfolio forecast' : 'Retirement plan')),
      subtitle: Text('$subtitle\n$date'),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () {
          final user = ref.read(authStateProvider).value;
          if (user != null) {
            ref
                .read(firestoreServiceProvider)
                .deleteSimulation(user.uid, sim.id);
          }
        },
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResultsScreen(
            result: sim.result,
            config: sim.config,
            title: sim.title,
          ),
        ),
      ),
    );
  }

  String _money(double v) =>
      NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 0).format(v);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insights, size: 72, color: Colors.grey),
          const SizedBox(height: 12),
          Text('No simulations yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Tap "New simulation" to run your first forecast.'),
        ],
      ),
    );
  }
}

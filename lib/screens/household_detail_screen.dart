import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/household.dart';
import '../models/member.dart';
import '../state/providers.dart';
import '../widgets/relation_labels.dart';
import 'member_form_screen.dart';

class HouseholdDetailScreen extends ConsumerWidget {
  const HouseholdDetailScreen({super.key, required this.household});

  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(household.name),
          bottom: const TabBar(
            tabs: [Tab(text: 'Members'), Tab(text: 'Portfolios')],
          ),
        ),
        body: TabBarView(
          children: [
            _MembersTab(household: household),
            const _PortfoliosTab(),
          ],
        ),
      ),
    );
  }
}

class _MembersTab extends ConsumerWidget {
  const _MembersTab({required this.household});
  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(membersProvider(household.id));
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              e.toString(),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
        data: (members) {
          if (members.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No members yet. Tap + to add the primary.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: members.length,
            itemBuilder: (_, i) =>
                _MemberTile(household: household, member: members[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add member'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MemberFormScreen(householdId: household.id),
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.household, required this.member});
  final Household household;
  final Member member;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this member?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(memberServiceProvider).deleteMember(
            householdId: household.id,
            memberId: member.id,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final age = member.effectiveAge;
    return Consumer(builder: (context, ref, _) {
      return ListTile(
        leading: Icon(relationIcon(member.relation)),
        title: Text(member.name),
        subtitle: Text(
          '${relationLabel(member.relation)} · age ${age ?? '—'}',
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MemberFormScreen(
              householdId: household.id,
              existing: member,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MemberFormScreen(
                    householdId: household.id,
                    existing: member,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ),
      );
    });
  }
}

class _PortfoliosTab extends StatelessWidget {
  const _PortfoliosTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Portfolios coming soon',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

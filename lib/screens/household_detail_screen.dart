import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/household.dart';
import '../models/investment.dart';
import '../models/member.dart';
import '../models/saved_portfolio.dart';
import '../services/quote_service.dart';
import '../state/providers.dart';
import '../widgets/relation_labels.dart';
import 'investment_form_screen.dart';
import 'member_form_screen.dart';
import 'saved_portfolio_form_screen.dart';
import 'simulation_form_screen.dart';

class HouseholdDetailScreen extends ConsumerWidget {
  const HouseholdDetailScreen({super.key, required this.household});

  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(household.name),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Members'),
              Tab(text: 'Investments'),
              Tab(text: 'Portfolios'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MembersTab(household: household),
            _InvestmentsTab(household: household),
            _PortfoliosTab(household: household),
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
    if (confirmed != true) return;
    try {
      await ref.read(memberServiceProvider).deleteMember(
            householdId: household.id,
            memberId: member.id,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _openEdit(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemberFormScreen(
          householdId: household.id,
          existing: member,
        ),
      ),
    );
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
        onTap: () => _openEdit(context),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _openEdit(context),
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

/// A customer's live investments database: holdings priced via yfinance, with a
/// running total and a one-tap bridge to simulate the basket.
class _InvestmentsTab extends ConsumerWidget {
  const _InvestmentsTab({required this.household});
  final Household household;

  /// Stable family key: unique, upper-cased, sorted tickers joined by commas.
  String _tickersCsv(List<Investment> holdings) {
    final set = <String>{for (final h in holdings) h.ticker.toUpperCase()}
      ..removeWhere((t) => t.isEmpty);
    final list = set.toList()..sort();
    return list.join(',');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(investmentsProvider(household.id));
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
        data: (holdings) {
          if (holdings.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No holdings yet. Tap + to add a ticker.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final quotesAsync = ref.watch(quotesProvider(_tickersCsv(holdings)));
          final quotes = quotesAsync.asData?.value ?? QuotesResult.empty;
          final priced = !quotesAsync.isLoading && quotesAsync.hasValue;

          return Column(
            children: [
              _PortfolioHeader(
                holdings: holdings,
                quotes: quotes,
                loading: quotesAsync.isLoading,
                household: household,
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: holdings.length,
                  itemBuilder: (_, i) => _InvestmentTile(
                    household: household,
                    investment: holdings[i],
                    quote: quotes.quotes[holdings[i].ticker.toUpperCase()],
                    quotesResolved: priced,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add holding'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InvestmentFormScreen(householdId: household.id),
          ),
        ),
      ),
    );
  }
}

class _PortfolioHeader extends StatelessWidget {
  const _PortfolioHeader({
    required this.holdings,
    required this.quotes,
    required this.loading,
    required this.household,
  });

  final List<Investment> holdings;
  final QuotesResult quotes;
  final bool loading;
  final Household household;

  double _total() {
    var sum = 0.0;
    for (final h in holdings) {
      final q = quotes.quotes[h.ticker.toUpperCase()];
      if (q != null) sum += h.quantity * q.price;
    }
    return sum;
  }

  /// Tickers and value-weights for the priced holdings, to seed a simulation.
  (List<String>, List<double>) _weighted() {
    final tickers = <String>[];
    final values = <double>[];
    for (final h in holdings) {
      final q = quotes.quotes[h.ticker.toUpperCase()];
      if (q != null && h.quantity > 0) {
        tickers.add(h.ticker.toUpperCase());
        values.add(h.quantity * q.price);
      }
    }
    final total = values.fold<double>(0, (a, b) => a + b);
    final weights = total > 0
        ? values.map((v) => v / total).toList()
        : List<double>.filled(tickers.length, 1 / tickers.length);
    return (tickers, weights);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _total();
    final (tickers, weights) = _weighted();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total market value',
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 2),
                  loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Text(
                          '\$${_formatMoney(total)}',
                          style:
                              Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: scheme.primary,
                                  ),
                        ),
                  if (quotes.missing.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'No price for: ${quotes.missing.join(', ')}',
                        style: TextStyle(color: scheme.error, fontSize: 12),
                      ),
                    ),
                  if (quotes.stale)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Prices may be delayed (cached)',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.show_chart),
                  label: const Text('Simulate'),
                  onPressed: tickers.isEmpty
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SimulationFormScreen(
                                initialTickers: tickers,
                                initialWeights: weights,
                              ),
                            ),
                          ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Save as portfolio'),
                  onPressed: tickers.isEmpty
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SavedPortfolioFormScreen(
                                householdId: household.id,
                                initialHoldings: [
                                  for (var i = 0; i < tickers.length; i++)
                                    PortfolioHolding(
                                      ticker: tickers[i],
                                      // value-weights as rounded percentages
                                      weight: double.parse(
                                        (weights[i] * 100).toStringAsFixed(1),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InvestmentTile extends ConsumerWidget {
  const _InvestmentTile({
    required this.household,
    required this.investment,
    required this.quote,
    required this.quotesResolved,
  });

  final Household household;
  final Investment investment;
  final Quote? quote;
  final bool quotesResolved;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this holding?'),
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
    if (confirmed != true) return;
    try {
      await ref.read(investmentServiceProvider).deleteInvestment(
            householdId: household.id,
            investmentId: investment.id,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _openEdit(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvestmentFormScreen(
          householdId: household.id,
          existing: investment,
        ),
      ),
    );
  }

  String _valueLabel() {
    final value = investment.marketValue(quote?.price);
    if (value != null) return '\$${_formatMoney(value)}';
    if (!quotesResolved) return '…';
    return 'No price';
  }

  String _priceLabel() {
    if (quote != null) {
      return '@ \$${_formatMoney(quote!.price)} · ${investment.quantity.toString().replaceAll(RegExp(r'\.0+$'), '')} sh';
    }
    return '${investment.quantity.toString().replaceAll(RegExp(r'\.0+$'), '')} sh';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: CircleAvatar(child: Text(_avatarText(investment.ticker))),
      title: Text(investment.ticker),
      subtitle: Text(_priceLabel()),
      onTap: () => _openEdit(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _valueLabel(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _openEdit(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }
}

String _avatarText(String ticker) =>
    ticker.isEmpty ? '?' : ticker.substring(0, ticker.length >= 2 ? 2 : 1);

/// Group-separated, two-decimals-when-needed money formatting (no intl import
/// to keep this widget self-contained).
String _formatMoney(double v) {
  final fixed = v.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final neg = intPart.startsWith('-');
  final digits = neg ? intPart.substring(1) : intPart;
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  final grouped = '${neg ? '-' : ''}$buf';
  return parts[1] == '00' ? grouped : '$grouped.${parts[1]}';
}

/// Saved (model) portfolios for the household: named baskets of tickers +
/// target weights that can be re-simulated on demand.
class _PortfoliosTab extends ConsumerWidget {
  const _PortfoliosTab({required this.household});
  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(savedPortfoliosProvider(household.id));
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
        data: (portfolios) {
          if (portfolios.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No portfolios yet. Tap + to model a basket of tickers.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: portfolios.length,
            itemBuilder: (_, i) => _PortfolioTile(
              household: household,
              portfolio: portfolios[i],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add portfolio'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                SavedPortfolioFormScreen(householdId: household.id),
          ),
        ),
      ),
    );
  }
}

class _PortfolioTile extends ConsumerWidget {
  const _PortfolioTile({required this.household, required this.portfolio});
  final Household household;
  final SavedPortfolio portfolio;

  String _subtitle() {
    final n = portfolio.holdings.length;
    final preview = portfolio.tickers.take(4).join(', ');
    final more = n > 4 ? ' +${n - 4}' : '';
    return '$n holding${n == 1 ? '' : 's'} · $preview$more';
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this portfolio?'),
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
    if (confirmed != true) return;
    try {
      await ref.read(savedPortfolioServiceProvider).deletePortfolio(
            householdId: household.id,
            portfolioId: portfolio.id,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _openEdit(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SavedPortfolioFormScreen(
          householdId: household.id,
          existing: portfolio,
        ),
      ),
    );
  }

  void _simulate(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SimulationFormScreen(
          initialTickers: portfolio.tickers,
          initialWeights: portfolio.weights,
          initialPeriod: portfolio.period,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.pie_chart_outline),
      title: Text(portfolio.name),
      subtitle: Text(_subtitle()),
      onTap: () => _openEdit(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            icon: const Icon(Icons.show_chart, size: 18),
            label: const Text('Simulate'),
            onPressed: () => _simulate(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }
}

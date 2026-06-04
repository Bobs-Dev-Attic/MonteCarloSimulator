import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/household.dart';
import '../models/investment.dart';
import '../models/member.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/household_service.dart';
import '../services/investment_service.dart';
import '../services/member_service.dart';
import '../services/portfolio_service.dart';
import '../services/quote_service.dart';
import '../services/simulation_service.dart';

/// Shared singletons.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final firestoreServiceProvider =
    Provider<FirestoreService>((ref) => FirestoreService());
final simulationServiceProvider =
    Provider<SimulationService>((ref) => SimulationService());

/// Current auth state, drives the login gate.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

/// Live list of the signed-in user's saved simulations.
final savedSimulationsProvider =
    StreamProvider.autoDispose<List<SavedSimulation>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(firestoreServiceProvider).watchSimulations(user.uid);
});

final householdServiceProvider =
    Provider<HouseholdService>((ref) => HouseholdService());

/// Live list of households the signed-in advisor belongs to.
final householdsProvider =
    StreamProvider.autoDispose<List<Household>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(householdServiceProvider).watchHouseholds(user.uid);
});

/// Read-only access to the current advisor's uid for screens that
/// don't want to depend on the full auth provider chain. Override in
/// tests to inject a fixed uid.
final currentAdvisorUidProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).value?.uid;
});

final memberServiceProvider =
    Provider<MemberService>((ref) => MemberService());

/// Live, sorted list of members under a household. Keyed by household id.
final membersProvider = StreamProvider.autoDispose
    .family<List<Member>, String>(
  (ref, hid) => ref.watch(memberServiceProvider).watchMembers(hid),
);

final investmentServiceProvider =
    Provider<InvestmentService>((ref) => InvestmentService());

/// Live, ticker-sorted list of a household's investments. Keyed by household id.
final investmentsProvider = StreamProvider.autoDispose
    .family<List<Investment>, String>(
  (ref, hid) => ref.watch(investmentServiceProvider).watchInvestments(hid),
);

final quoteServiceProvider =
    Provider<QuoteService>((ref) => QuoteService());

/// Live quotes for a basket of tickers. The family key is a comma-joined,
/// upper-cased, sorted ticker list so identical baskets share one request and
/// the provider re-runs only when the set of tickers actually changes.
final quotesProvider = FutureProvider.autoDispose
    .family<QuotesResult, String>((ref, tickersCsv) {
  if (tickersCsv.isEmpty) return Future.value(QuotesResult.empty);
  return ref.watch(quoteServiceProvider).fetchQuotes(tickersCsv.split(','));
});

final portfolioServiceProvider =
    Provider<PortfolioService>((ref) => PortfolioService());

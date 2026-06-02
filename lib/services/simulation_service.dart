import 'package:cloud_functions/cloud_functions.dart';

import '../models/simulation_config.dart';
import '../models/simulation_result.dart';

/// Invokes the server-side `runSimulation` Cloud Function, where the heavy
/// NumPy sampling happens, and parses the aggregated result.
class SimulationService {
  SimulationService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<SimulationResult> run(SimulationConfig config) async {
    final callable = _functions.httpsCallable(
      'runSimulation',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
    );
    final response = await callable.call<Map<String, dynamic>>(
      config.toCallablePayload(),
    );
    // Cloud Functions may return nested maps typed as Map<Object?, Object?>;
    // normalize to Map<String, dynamic> before parsing.
    final data = _deepCast(response.data) as Map<String, dynamic>;
    return SimulationResult.fromJson(data);
  }

  static dynamic _deepCast(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _deepCast(v)));
    }
    if (value is List) {
      return value.map(_deepCast).toList();
    }
    return value;
  }
}

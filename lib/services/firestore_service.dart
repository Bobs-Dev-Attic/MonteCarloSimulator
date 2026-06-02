import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/simulation_config.dart';
import '../models/simulation_result.dart';

/// A saved simulation: its config, aggregated result, and metadata.
class SavedSimulation {
  const SavedSimulation({
    required this.id,
    required this.config,
    required this.result,
    required this.createdAt,
    this.title,
  });

  final String id;
  final SimulationConfig config;
  final SimulationResult result;
  final DateTime createdAt;
  final String? title;

  factory SavedSimulation.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return SavedSimulation(
      id: doc.id,
      title: data['title'] as String?,
      config: SimulationConfig.fromJson(
          Map<String, dynamic>.from(data['config'] as Map)),
      result: SimulationResult.fromJson(
          Map<String, dynamic>.from(data['result'] as Map)),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// CRUD for `users/{uid}/simulations/{simId}`.
class FirestoreService {
  FirestoreService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('simulations');

  /// Live, newest-first stream of a user's saved simulations.
  Stream<List<SavedSimulation>> watchSimulations(String uid) {
    return _col(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(SavedSimulation.fromDoc).toList());
  }

  Future<String> saveSimulation({
    required String uid,
    required SimulationConfig config,
    required SimulationResult result,
    String? title,
  }) async {
    final doc = await _col(uid).add({
      if (title != null) 'title': title,
      'config': config.toJson(),
      'result': result.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> deleteSimulation(String uid, String simId) {
    return _col(uid).doc(simId).delete();
  }
}

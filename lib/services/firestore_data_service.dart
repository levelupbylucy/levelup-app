import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/level_up_models.dart';

class FirestoreDataService {
  const FirestoreDataService({FirebaseFirestore? firestore})
    : _dbOverride = firestore;

  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  Future<void> saveUserProfile({
    required String userId,
    required UserProfile user,
  }) async {
    await _db.collection('users').doc(userId).set({
      'profile': user.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> prepareUserDocument({
    required String userId,
    required AuthSession session,
  }) async {
    await _db.collection('users').doc(userId).set({
      'auth': session.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> mergeLocalDataAfterSignIn({
    required String userId,
    required UserProfile user,
    required List<Goal> goals,
    required List<DailyTask> tasks,
    required List<DailyTaskHistory> taskHistory,
  }) async {
    await saveUserProfile(userId: userId, user: user);
    // TODO: Merge goals, daily tasks, streaks, and calendar history into
    // users/{userId}/goals, users/{userId}/tasks, and users/{userId}/history
    // once the remote conflict policy is finalized.
  }
}

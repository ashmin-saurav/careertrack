import 'package:hive_flutter/hive_flutter.dart';

class AnalyticsEngine {
  static const String _boxName = 'question_history';

  // 1. RECORD SESSION
  static Future<void> recordSession(
      List<Map<String, dynamic>> questions, List<int?> userAnswers) async {
    final box = await Hive.openBox(_boxName);
    final int timestamp = DateTime.now().millisecondsSinceEpoch;

    // Batch operations are faster for DB writes
    final Map<int, Map<String, dynamic>> entries = {};

    for (int i = 0; i < questions.length; i++) {
      int? userAns = (i < userAnswers.length) ? userAnswers[i] : null;
      var rawAns = questions[i]['a'] ?? questions[i]['ans'];

      int correctIndex = -1;
      if (rawAns is int) {
        correctIndex = rawAns;
      } else if (rawAns is String) {
        correctIndex = int.tryParse(rawAns) ?? 0;
      }

      int status = -1; // -1: Skipped, 0: Wrong, 1: Correct
      if (userAns != null) {
        status = (userAns == correctIndex) ? 1 : 0;
      }

      String subject = questions[i]['s']?.toString() ?? 'General';
      String topic = questions[i]['t']?.toString() ?? 'Misc';

      // Auto-increment key handling by Hive, but we prepare the object
      await box.add({
        's': subject,
        't': topic,
        'st': status,
        'ts': timestamp,
      });
    }
  }

  // 2. GET REPORT (Optimized)
  static Future<Map<String, dynamic>> getReport() async {
    final box = await Hive.openBox(_boxName);

    // Explicit structure: Subject -> { Stats + Topics -> { TopicName -> Stats } }
    final Map<String, Map<String, dynamic>> report = {};

    if (box.isEmpty) return {};

    // OPTIMIZATION: Use .values instead of .getAt() loops.
    // Iterators are much lighter on memory for read operations.
    for (final record in box.values) {
      if (record == null || record is! Map) continue;

      final String subject = record['s']?.toString() ?? 'Unknown';
      final String topic = record['t']?.toString() ?? 'Unknown';
      final int status = (record['st'] as num?)?.toInt() ?? -1;

      // --- INITIALIZATION ---
      if (!report.containsKey(subject)) {
        report[subject] = {
          'total': 0,
          'correct': 0,
          'wrong': 0,
          'skipped': 0,
          'topics': <String, Map<String, dynamic>>{}, // Strongly typed sub-map
        };
      }

      final subjectData = report[subject]!;
      final topicsMap = subjectData['topics'] as Map<String, Map<String, dynamic>>;

      if (!topicsMap.containsKey(topic)) {
        topicsMap[topic] = {
          'att': 0, 'cor': 0, 'wrg': 0, 'skp': 0
        };
      }

      // --- AGGREGATION ---
      subjectData['total'] = (subjectData['total'] as int) + 1;
      final topicData = topicsMap[topic]!;
      topicData['att'] = (topicData['att'] as int) + 1;

      if (status == 1) {
        subjectData['correct'] = (subjectData['correct'] as int) + 1;
        topicData['cor'] = (topicData['cor'] as int) + 1;
      } else if (status == 0) {
        subjectData['wrong'] = (subjectData['wrong'] as int) + 1;
        topicData['wrg'] = (topicData['wrg'] as int) + 1;
      } else {
        subjectData['skipped'] = (subjectData['skipped'] as int) + 1;
        topicData['skp'] = (topicData['skp'] as int) + 1;
      }
    }

    // --- CALCULATIONS ---
    // Converting the strict Map back to dynamic for the UI to consume easily
    final Map<String, dynamic> finalReport = {};

    report.forEach((subjKey, subjData) {
      int total = subjData['total'] as int;
      int correct = subjData['correct'] as int;
      double subjAcc = total > 0 ? (correct / total) * 100 : 0.0;

      subjData['accuracy'] = subjAcc;

      final topicsMap = subjData['topics'] as Map<String, Map<String, dynamic>>;

      topicsMap.forEach((topicKey, tData) {
        int attempts = tData['att'] as int;
        int tCorrect = tData['cor'] as int;
        double topicAcc = attempts > 0 ? (tCorrect / attempts) * 100 : 0.0;

        tData['accuracy'] = topicAcc;

        // Smart Strength Logic
        String strength;
        if (attempts < 5) {
          strength = "New"; // Need more data
        } else if (topicAcc >= 80) {
          strength = "Strong";
        } else if (topicAcc <= 40) {
          strength = "Weak";
        } else {
          strength = "Average";
        }
        tData['strength'] = strength;
      });

      finalReport[subjKey] = subjData;
    });

    return finalReport;
  }

  static Future<void> clearAllData() async {
    final box = await Hive.openBox(_boxName);
    await box.clear();
  }
}
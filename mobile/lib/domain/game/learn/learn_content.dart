import 'content/unit1_budgeting.dart';
import 'content/unit2_saving.dart';
import 'content/unit3_debt.dart';
import 'content/unit4_investing.dart';
import 'content/unit5_zakat_tax.dart';
import 'content/unit6_security.dart';
import 'learn_models.dart';

/// The whole learning path, in order. Lessons unlock sequentially across units.
const List<LearnUnit> learnUnits = [unit1, unit2, unit3, unit4, unit5, unit6];

/// Finds a lesson (and its unit) by id in [units].
({LearnUnit unit, Lesson lesson, int unitIndex, int lessonIndex})? findLesson(
  String lessonId, [
  List<LearnUnit> units = learnUnits,
]) {
  for (var u = 0; u < units.length; u++) {
    final lessons = units[u].lessons;
    for (var l = 0; l < lessons.length; l++) {
      if (lessons[l].id == lessonId) {
        return (
          unit: units[u],
          lesson: lessons[l],
          unitIndex: u,
          lessonIndex: l,
        );
      }
    }
  }
  return null;
}

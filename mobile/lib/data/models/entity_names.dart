/// Wire entity names (contract "Entities").
abstract final class SyncEntity {
  static const wallets = 'wallets';
  static const categories = 'categories';
  static const transactions = 'transactions';
  static const budgets = 'budgets';
  static const subscriptions = 'subscriptions';
  static const planned = 'planned';
  static const prayers = 'prayers';
  static const health = 'health';
  static const food = 'food';
  static const taskAreas = 'taskAreas';
  static const tasks = 'tasks';
  static const noteLabels = 'noteLabels';
  static const notes = 'notes';
  static const socialAccounts = 'socialAccounts';
  static const contentPillars = 'contentPillars';
  static const contentItems = 'contentItems';
  static const contentPosts = 'contentPosts';

  /// Apply order for pulls (referenced entities first).
  static const all = [
    wallets,
    categories,
    transactions,
    budgets,
    subscriptions,
    planned,
    prayers,
    health,
    food,
    taskAreas,
    tasks,
    noteLabels,
    notes,
    socialAccounts,
    contentPillars,
    contentItems,
    contentPosts,
  ];

  /// Notes module (`docs/notes.md`): a pull carrying [noteLabels] comes from a
  /// notes-aware server.
  static const notesModule = [noteLabels, notes];

  /// Content planner (`docs/content.md`).
  static const contentModule = [
    socialAccounts,
    contentPillars,
    contentItems,
    contentPosts,
  ];
}

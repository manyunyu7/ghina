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
  ];
}

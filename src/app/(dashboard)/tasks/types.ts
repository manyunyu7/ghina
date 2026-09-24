import type { AreaSchedule, BucketId, Recurrence } from "@/lib/tasks";

/** Serializable task passed from the server page to the client board. */
export type TaskDTO = {
  id: string;
  areaId: string;
  title: string;
  note: string | null;
  bucket: BucketId;
  dueDate: string | null;
  dueTime: string | null;
  remindBefore: number | null;
  recurrence: Recurrence | null;
  seriesId: string | null;
  done: boolean;
  doneAt: string | null;
  sortOrder: number;
  amount: number | null;
  walletId: string | null;
  categoryId: string | null;
  transactionId: string | null;
  createdAt: string;
};

export type AreaDTO = {
  id: string;
  name: string;
  code: string;
  color: string;
  icon: string;
  schedule: AreaSchedule | null;
  sortOrder: number;
  archived: boolean;
};

export type WalletOption = { id: string; name: string; currency: string };
export type CategoryOption = { id: string; name: string; color: string; icon: string };

/** Everything the board needs to render. */
export type BoardData = {
  areas: AreaDTO[];
  tasks: TaskDTO[];
  doneTasks: TaskDTO[];
  wallets: WalletOption[];
  categories: CategoryOption[];
  currency: string;
};

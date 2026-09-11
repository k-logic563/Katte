export interface AccountMembership {
  userId: string;
  role: unknown;
  memberIds: readonly string[];
}

export function blocksAccountDeletion({
  userId,
  role,
  memberIds,
}: AccountMembership): boolean {
  return role === "owner" && memberIds.some((memberId) => memberId !== userId);
}

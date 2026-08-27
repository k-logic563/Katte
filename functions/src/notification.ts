export interface ShoppingItemNotificationData {
  name?: unknown;
  createdBy?: unknown;
  createdByName?: unknown;
  quantity?: unknown;
}

export interface NotificationContent {
  title: string;
  body: string;
}

export interface DeviceRegistration {
  userId: string;
  devicePath: string;
  token: string;
  notificationEnabled: boolean;
}

export function buildItemCreatedNotification(
  item: ShoppingItemNotificationData,
): NotificationContent | null {
  if (
    typeof item.createdBy !== "string" ||
    item.createdBy.trim().length === 0 ||
    typeof item.name !== "string" ||
    item.name.trim().length === 0
  ) {
    return null;
  }

  const itemName = item.name.trim();
  const quantity =
    typeof item.quantity === "number" &&
    Number.isInteger(item.quantity) &&
    item.quantity > 1
      ? ` ×${item.quantity}`
      : "";
  const creatorName =
    typeof item.createdByName === "string" &&
    item.createdByName.trim().length > 0
      ? item.createdByName.trim()
      : "メンバー";

  return {
    title: "Katte",
    body: `${creatorName}が「${itemName}${quantity}」を追加しました`,
  };
}

export function selectNotificationTargets(
  memberIds: readonly string[],
  createdBy: string,
  registrations: readonly DeviceRegistration[],
): DeviceRegistration[] {
  const recipients = new Set(
    memberIds.filter((memberId) => memberId !== createdBy),
  );
  const seenTokens = new Set<string>();

  return registrations.filter((registration) => {
    const token = registration.token.trim();
    if (
      !recipients.has(registration.userId) ||
      !registration.notificationEnabled ||
      token.length === 0 ||
      seenTokens.has(token)
    ) {
      return false;
    }
    seenTokens.add(token);
    return true;
  });
}

export function isPermanentlyInvalidTokenError(code: string): boolean {
  return (
    code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-registration-token"
  );
}

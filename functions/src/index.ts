import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {
  DocumentReference,
  Firestore,
  getFirestore,
} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {logger} from "firebase-functions";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";

import {
  buildItemCreatedNotification,
  DeviceRegistration,
  isPermanentlyInvalidTokenError,
  selectNotificationTargets,
} from "./notification";
import {blocksAccountDeletion} from "./account-deletion";

initializeApp();

const region = "us-central1";
const multicastLimit = 500;
const deleteBatchLimit = 450;

export const deleteCategory = onCall(
  {region},
  async (request) => {
    const userId = request.auth?.uid;
    const rawGroupId = request.data?.groupId;
    const rawCategoryId = request.data?.categoryId;
    if (!userId) {
      throw new HttpsError("unauthenticated", "Authentication is required.");
    }
    if (
      typeof rawGroupId !== "string" || rawGroupId.trim().length === 0 ||
      typeof rawCategoryId !== "string" || rawCategoryId.trim().length === 0
    ) {
      throw new HttpsError("invalid-argument", "Group and category are required.");
    }
    const groupId = rawGroupId.trim();
    const categoryId = rawCategoryId.trim();
    const firestore = getFirestore();
    const groupReference = firestore.collection("groups").doc(groupId);
    const member = await groupReference.collection("members").doc(userId).get();
    if (!member.exists) {
      throw new HttpsError("permission-denied", "Group membership is required.");
    }
    const categoryReference = groupReference
      .collection("categories")
      .doc(categoryId);
    const category = await categoryReference.get();
    if (!category.exists) {
      throw new HttpsError("not-found", "The category does not exist.");
    }
    await categoryReference.update({deleting: true, updatedAt: new Date()});

    let itemCount = 0;
    while (true) {
      const items = await groupReference
        .collection("items")
        .where("categoryId", "==", categoryId)
        .limit(deleteBatchLimit)
        .get();
      if (items.empty) {
        break;
      }
      const batch = firestore.batch();
      for (const item of items.docs) {
        batch.update(item.ref, {
          categoryId: null,
          updatedAt: new Date(),
        });
      }
      await batch.commit();
      itemCount += items.size;
    }

    const normalizedName = category.get("normalizedName");
    if (typeof normalizedName === "string") {
      const nameKey = Buffer.from(normalizedName, "utf8")
        .toString("base64url");
      await groupReference.collection("categoryNames").doc(nameKey).delete();
    }
    await categoryReference.delete();
    logger.info("Category deleted.", {
      groupId,
      categoryId,
      itemCount,
    });
    return {deleted: true};
  },
);

export const deleteGroup = onCall(
  {region},
  async (request) => {
    const userId = request.auth?.uid;
    const rawGroupId = request.data?.groupId;
    if (!userId) {
      throw new HttpsError("unauthenticated", "Authentication is required.");
    }
    if (typeof rawGroupId !== "string" || rawGroupId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "A group ID is required.");
    }
    const groupId = rawGroupId.trim();

    try {
      const firestore = getFirestore();
      const groupReference = firestore.collection("groups").doc(groupId);
      const ownerReference = groupReference.collection("members").doc(userId);
      const [group, owner] = await Promise.all([
        groupReference.get(),
        ownerReference.get(),
      ]);
      if (!group.exists) {
        throw new HttpsError("not-found", "The group does not exist.");
      }
      if (!owner.exists || owner.get("role") !== "owner") {
        logger.warn("Unauthorized group deletion rejected.", {groupId});
        throw new HttpsError(
          "permission-denied",
          "Only the group owner can delete this group.",
        );
      }

      const inviteCode = group.get("inviteCode");
      if (typeof inviteCode !== "string" || inviteCode.length === 0) {
        throw new HttpsError("failed-precondition", "The invite is invalid.");
      }

      const memberCount = await recursivelyDeleteGroup(
        firestore,
        groupReference,
        inviteCode,
      );

      logger.info("Group deleted.", {
        groupId,
        memberCount,
      });
      return {deleted: true};
    } catch (error) {
      logger.error("Group deletion failed.", {
        groupId,
        errorCode: getErrorCode(error),
      });
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", "The group could not be deleted.");
    }
  },
);

export const deleteAccount = onCall(
  {region},
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "Authentication is required.");
    }

    const firestore = getFirestore();
    try {
      await assertAccountDeletionAllowed(firestore, userId);
      // The collection-group query also catches membership documents if a
      // users/{uid}/groups pointer is missing or stale.
      const memberships = await firestore
        .collectionGroup("members")
        .where("userId", "==", userId)
        .get();
      const ownerGroups: Array<{
        reference: DocumentReference;
        inviteCode: unknown;
      }> = [];
      const memberGroups: DocumentReference[] = [];

      for (const membership of memberships.docs) {
        const groupReference = membership.ref.parent.parent;
        if (groupReference === null) {
          continue;
        }
        if (membership.get("role") === "owner") {
          const group = await groupReference.get();
          if (!group.exists) {
            memberGroups.push(groupReference);
            continue;
          }
          const members = await groupReference
            .collection("members")
            .limit(2)
            .get();
          if (blocksAccountDeletion({
            userId,
            role: membership.get("role"),
            memberIds: members.docs.map((member) => member.id),
          })) {
            throw new HttpsError(
              "failed-precondition",
              "Delete groups with other members before deleting the account.",
            );
          }
          ownerGroups.push({
            reference: groupReference,
            inviteCode: group.get("inviteCode"),
          });
        } else {
          memberGroups.push(groupReference);
        }
      }

      // All owner checks finish before the first destructive write.
      for (const group of ownerGroups) {
        await recursivelyDeleteGroup(
          firestore,
          group.reference,
          group.inviteCode,
        );
      }

      for (
        let offset = 0;
        offset < memberGroups.length;
        offset += deleteBatchLimit / 2
      ) {
        const batch = firestore.batch();
        for (const groupReference of memberGroups.slice(
          offset,
          offset + deleteBatchLimit / 2,
        )) {
          batch.delete(groupReference.collection("members").doc(userId));
          batch.delete(
            firestore
              .collection("users")
              .doc(userId)
              .collection("groups")
              .doc(groupReference.id),
          );
        }
        await batch.commit();
      }

      // This removes the profile, every device/FCM registration, and any stale
      // user-side membership pointers. Shared group content is retained.
      await firestore.recursiveDelete(firestore.collection("users").doc(userId));

      // Auth is deleted last so a retry remains possible after cleanup errors.
      await getAuth().deleteUser(userId);
      logger.info("Account deleted.", {
        userId,
        ownedGroupCount: ownerGroups.length,
        membershipCount: memberGroups.length,
      });
      return {deleted: true};
    } catch (error) {
      logger.error("Account deletion failed.", {
        userId,
        errorCode: getErrorCode(error),
      });
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", "The account could not be deleted.");
    }
  },
);

export const checkAccountDeletion = onCall(
  {region},
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "Authentication is required.");
    }
    await assertAccountDeletionAllowed(getFirestore(), userId);
    return {allowed: true};
  },
);

async function assertAccountDeletionAllowed(
  firestore: Firestore,
  userId: string,
): Promise<void> {
  const memberships = await firestore
    .collectionGroup("members")
    .where("userId", "==", userId)
    .get();
  for (const membership of memberships.docs) {
    if (membership.get("role") !== "owner") {
      continue;
    }
    const groupReference = membership.ref.parent.parent;
    if (groupReference === null) {
      continue;
    }
    const members = await groupReference.collection("members").limit(2).get();
    if (blocksAccountDeletion({
      userId,
      role: membership.get("role"),
      memberIds: members.docs.map((member) => member.id),
    })) {
      throw new HttpsError(
        "failed-precondition",
        "Delete groups with other members before deleting the account.",
      );
    }
  }
}

async function recursivelyDeleteGroup(
  firestore: Firestore,
  groupReference: DocumentReference,
  inviteCode: unknown,
): Promise<number> {
  // Remove the invite first so no new member can join while cleanup runs.
  if (typeof inviteCode === "string" && inviteCode.length > 0) {
    await firestore.collection("groupInvites").doc(inviteCode).delete();
  }
  const members = await groupReference.collection("members").get();
  const memberIds = members.docs.map((member) => member.id);

  // recursiveDelete includes members, items, categories, and history.
  await firestore.recursiveDelete(groupReference);

  for (
    let offset = 0;
    offset < memberIds.length;
    offset += deleteBatchLimit
  ) {
    const batch = firestore.batch();
    for (const memberId of memberIds.slice(
      offset,
      offset + deleteBatchLimit,
    )) {
      batch.delete(
        firestore
          .collection("users")
          .doc(memberId)
          .collection("groups")
          .doc(groupReference.id),
      );
    }
    await batch.commit();
  }
  return memberIds.length;
}

export const sendShoppingItemCreatedNotification = onDocumentCreated(
  {
    document: "groups/{groupId}/items/{itemId}",
    region,
  },
  async (event) => {
    const snapshot = event.data;
    const groupId = event.params.groupId;
    const itemId = event.params.itemId;
    try {
    if (!snapshot || !groupId || !itemId) {
      logger.warn("Shopping item create event is missing required data.");
      return;
    }

    const item = snapshot.data();
    const content = buildItemCreatedNotification(item);
    if (content === null || typeof item.createdBy !== "string") {
      logger.warn("Shopping item is invalid; notification skipped.", {
        groupId,
        itemId,
      });
      return;
    }

    const firestore = getFirestore();
    const members = await firestore
      .collection("groups")
      .doc(groupId)
      .collection("members")
      .get();
    const memberIds = members.docs.map((member) => member.id);
    const recipientIds = memberIds.filter(
      (memberId) => memberId !== item.createdBy,
    );
    const deviceSnapshots = await Promise.all(
      recipientIds.map((userId) =>
        firestore
          .collection("users")
          .doc(userId)
          .collection("devices")
          .where("notificationEnabled", "==", true)
          .get(),
      ),
    );
    const registrations: DeviceRegistration[] = [];
    for (let index = 0; index < deviceSnapshots.length; index++) {
      const userId = recipientIds[index];
      for (const device of deviceSnapshots[index].docs) {
        const token = device.get("fcmToken");
        if (typeof token !== "string") {
          continue;
        }
        registrations.push({
          userId,
          devicePath: device.ref.path,
          token,
          notificationEnabled: device.get("notificationEnabled") === true,
        });
      }
    }

    const targets = selectNotificationTargets(
      memberIds,
      item.createdBy,
      registrations,
    );
    if (targets.length === 0) {
      return;
    }

    const invalidDevicePaths = new Set<string>();
    for (let offset = 0; offset < targets.length; offset += multicastLimit) {
      const chunk = targets.slice(offset, offset + multicastLimit);
      const response = await getMessaging().sendEachForMulticast({
        tokens: chunk.map((target) => target.token),
        notification: content,
        data: {
          type: "shopping_item_created",
          groupId,
          itemId,
        },
        android: {
          notification: {
            channelId: "katte_item_updates",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
            },
          },
        },
      });

      response.responses.forEach((sendResult, index) => {
        const code = sendResult.error?.code;
        if (code && isPermanentlyInvalidTokenError(code)) {
          invalidDevicePaths.add(chunk[index].devicePath);
        }
      });
    }

    if (invalidDevicePaths.size > 0) {
      const paths = [...invalidDevicePaths];
      for (let offset = 0; offset < paths.length; offset += deleteBatchLimit) {
        const batch = firestore.batch();
        for (const path of paths.slice(offset, offset + deleteBatchLimit)) {
          batch.delete(firestore.doc(path));
        }
        await batch.commit();
      }
      logger.info("Invalid device registrations removed.", {
        count: invalidDevicePaths.size,
      });
    }
    } catch (error) {
      logger.error("Shopping notification failed.", {
        groupId,
        itemId,
        errorCode: getErrorCode(error),
      });
      throw error;
    }
  },
);

function getErrorCode(error: unknown): string {
  if (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    typeof error.code === "string"
  ) {
    return error.code;
  }
  return "unknown";
}

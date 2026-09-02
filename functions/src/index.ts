import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
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

initializeApp();

const region = "us-central1";
const multicastLimit = 500;
const deleteBatchLimit = 450;

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

      // Remove the invite first so no new member can join while cleanup runs.
      await firestore.collection("groupInvites").doc(inviteCode).delete();
      const members = await groupReference.collection("members").get();
      const memberIds = members.docs.map((member) => member.id);

      // recursiveDelete explicitly removes the group and every nested document,
      // including members and shopping items.
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
              .doc(groupId),
          );
        }
        await batch.commit();
      }

      logger.info("Group deleted.", {
        groupId,
        memberCount: memberIds.length,
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

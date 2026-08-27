import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {logger} from "firebase-functions";
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

export const sendShoppingItemCreatedNotification = onDocumentCreated(
  {
    document: "groups/{groupId}/items/{itemId}",
    region,
  },
  async (event) => {
    const snapshot = event.data;
    const groupId = event.params.groupId;
    const itemId = event.params.itemId;
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

    logger.info("Shopping item created.", {groupId, itemId});
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
    logger.info("Group members found.", {
      groupId,
      recipientCount: recipientIds.length,
    });

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
    logger.info("Notification targets resolved.", {
      groupId,
      targetCount: targets.length,
    });
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
      logger.info("Notification multicast completed.", {
        groupId,
        successCount: response.successCount,
        failureCount: response.failureCount,
      });
    }

    if (invalidDevicePaths.size > 0) {
      const batch = firestore.batch();
      for (const path of invalidDevicePaths) {
        batch.delete(firestore.doc(path));
      }
      await batch.commit();
      logger.info("Invalid device registrations removed.", {
        count: invalidDevicePaths.size,
      });
    }
  },
);

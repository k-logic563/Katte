import {strict as assert} from "node:assert";
import {describe, it} from "node:test";

import {
  buildItemCreatedNotification,
  DeviceRegistration,
  isPermanentlyInvalidTokenError,
  selectNotificationTargets,
} from "./notification";

describe("buildItemCreatedNotification", () => {
  it("誰が何を追加したか分かる本文を作る", () => {
    assert.deepEqual(
      buildItemCreatedNotification({
        name: "卵",
        quantity: 2,
        createdBy: "user-a",
        createdByName: "由美",
      }),
      {
        title: "Katte",
        body: "由美が「卵 ×2」を追加しました",
      },
    );
  });

  it("表示名がない場合は安全なfallbackを使う", () => {
    assert.equal(
      buildItemCreatedNotification({name: "牛乳", createdBy: "user-a"})
        ?.body,
      "メンバーが「牛乳」を追加しました",
    );
  });

  it("不正Itemでは通知を作らない", () => {
    assert.equal(
      buildItemCreatedNotification({name: "", createdBy: "user-a"}),
      null,
    );
    assert.equal(
      buildItemCreatedNotification({name: "牛乳", createdBy: null}),
      null,
    );
  });
});

describe("selectNotificationTargets", () => {
  const registrations: DeviceRegistration[] = [
    {
      userId: "user-a",
      devicePath: "users/user-a/devices/1",
      token: "creator-token",
      notificationEnabled: true,
    },
    {
      userId: "user-b",
      devicePath: "users/user-b/devices/1",
      token: "member-token",
      notificationEnabled: true,
    },
    {
      userId: "user-c",
      devicePath: "users/user-c/devices/1",
      token: "outsider-token",
      notificationEnabled: true,
    },
    {
      userId: "user-b",
      devicePath: "users/user-b/devices/2",
      token: "disabled-token",
      notificationEnabled: false,
    },
  ];

  it("追加者本人とGroup外Userを除外する", () => {
    const targets = selectNotificationTargets(
      ["user-a", "user-b"],
      "user-a",
      registrations,
    );
    assert.deepEqual(
      targets.map((target) => target.token),
      ["member-token"],
    );
  });

  it("TokenがないUserを安全にskipする", () => {
    assert.deepEqual(
      selectNotificationTargets(["user-d"], "user-a", registrations),
      [],
    );
  });
});

describe("isPermanentlyInvalidTokenError", () => {
  it("恒久的に無効なTokenだけを判定する", () => {
    assert.equal(
      isPermanentlyInvalidTokenError(
        "messaging/registration-token-not-registered",
      ),
      true,
    );
    assert.equal(
      isPermanentlyInvalidTokenError("messaging/internal-error"),
      false,
    );
  });
});

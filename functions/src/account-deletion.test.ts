import assert from "node:assert/strict";
import test from "node:test";

import {blocksAccountDeletion} from "./account-deletion";

test("member can delete an account when a group has other members", () => {
  assert.equal(
    blocksAccountDeletion({
      userId: "member-a",
      role: "member",
      memberIds: ["owner", "member-a"],
    }),
    false,
  );
});

test("owner can delete an account when they are the only member", () => {
  assert.equal(
    blocksAccountDeletion({
      userId: "owner",
      role: "owner",
      memberIds: ["owner"],
    }),
    false,
  );
});

test("owner cannot delete an account while another member remains", () => {
  assert.equal(
    blocksAccountDeletion({
      userId: "owner",
      role: "owner",
      memberIds: ["owner", "member-a"],
    }),
    true,
  );
});

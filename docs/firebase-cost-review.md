# Katte Firebase Cost Review

更新日: 2026-09-02。対象Projectは`katte-dev-jp`。本書は現在のFlutter、Firestore Rules、
Cloud Functions、deploy状態を追跡した概算であり、Firebase Consoleの実測値を置き換えるものではない。

## 結論

通常利用ではFirestore readが最大の費用要因で、特に購入履歴（最大100件）と候補（最大30件）の
画面open時readが支配的である。標準モデルでは1世帯あたり月49,080 reads、930 writes、300
notification function invocations。10,000世帯でも中心推計は約`$187/月`（1 USD = 150円の説明用
換算で約28,000円、税・為替・共有quota・保存容量を除く）だが、認証済みUserによる大量item追加は
Firestore write、Eventarc、Function、device read、FCMを同時に増幅する。公開前のabuse対策とBudget
Alertは必須である。Budget Alertは支出上限ではない。

## 実際に利用しているService

| Service | 用途 | 主な課金単位 |
| --- | --- | --- |
| Firebase Authentication / Google Sign-In | User認証 | MAU（構成により無料枠あり） |
| Cloud Firestore Standard | users、groups、members、items、suggestions、devices | read / write / delete / storage / egress |
| Firebase Cloud Messaging | Push配信 | FCM自体はno-cost |
| Cloud Run functions（Functions v2） | 商品追加通知、Group recursive delete | request、vCPU時間、memory時間、network |
| Eventarc Standard / Pub/Sub transport | Firestore create event配信 | Google source eventは$0、Pub/Sub data volume |
| Firebase Analytics | screen / 固定event集計 | no-cost（BigQuery export等は未使用） |
| Firebase Crashlytics | crash / diagnostics | no-cost |
| Cloud Logging | Functions log | ingest volume |
| Artifact Registry / Cloud Build | Functions deploy artifact | deploy/storage量 |

未使用: Firebase Storage、Realtime Database、Hosting、Remote Config、Performance Monitoring、
App Check、BigQuery export、scheduled Functions、Cloud Tasks。

## Firestore access map

Security Rulesの`exists/get/getAfter`もbillable readである。以下の「Rules read」は同一request内で
同じdependent documentがcacheされる前提の概算。

| Action / code | Path / query | Direct reads | Writes / deletes | Rules reads / note |
| --- | --- | ---: | ---: | --- |
| `ensureUser` | `users/{uid}` | 1 | profile差分時のみ1 write | selfのみ |
| `watchUserGroups` initial | `users/{uid}/groups` | `G` | 0 | selfのみ |
| Group hydration | 各`groups/{groupId}` | `G` | 0 | member確認`G` |
| FCM registration | `users/{uid}/devices/{deviceId}` | 1 | 新規・token/設定変更時のみ1 | selfのみ |
| pending listener | items: `status=pending`, `createdAt desc` | initial `P` | 0 | connect/updateごとmember確認1 |
| history listener | items: `status=purchased`, `purchasedAt desc`, `limit 100` | initial `min(H,100)` | 0 | connect/updateごとmember確認1 |
| suggestions | itemSuggestions: `lastUsedAt desc`, `limit 30` | `min(S,30)` | 0 | requestごとmember確認1 |
| members listener | `groups/{groupId}/members`, `joinedAt` | `M` | 0 | connect/updateごとmember確認1 |
| item add batch | item + deterministic suggestion | 0 | 2 writes | 同じmembership約1 read |
| purchase / undo | item document | 0 | 1 write | membership約1 read |
| item delete | item document | 0 | 1 delete | membership約1 read |
| create group transaction | invite existence | 1 | 4 writes | group/member/inviteの`getAfter`最大3 |
| join transaction + group get | invite、user group、group | 3 | 2 writes | invite/member/group membership最大3 |
| leave transaction | own member | 1 | 2 deletes | member dependent最大1 |

`G`: UserのGroup数、`P`: pending件数、`H`: purchased累積件数、`S`: unique suggestion件数、
`M`: member数。

### `watchUserGroups`の注意

membership snapshotが更新されるたび、現在の全membershipに対してGroup documentを再取得する
N+1構造である。標準の`G=1`では軽微だが、Groups per userに上限がないため大量Group作成時は
`2G`（group get + Rules membership read）が更新ごとに増える。大規模なdenormalizationは今回行わない。

## Realtime Listener

| Provider / Screen | Query | Initial billable reads | Update | Lifetime |
| --- | --- | ---: | ---: | --- |
| `userGroupsProvider` / router全体 | user group refs + Group hydration | `3G` | changed ref + 全Group再取得 | Auth session。logoutで終了 |
| `pendingShoppingItemsProvider` / Shopping | pending + createdAt | `P + 1 Rules` | changed item 1 + Rules 1 | 画面単位autoDispose |
| `purchasedShoppingItemsProvider` / History | purchased + purchasedAt、limit100 | `min(H,100)+1` | changed item 1 + Rules 1 | 画面単位autoDispose |
| `groupMembersProvider` / Group Details | members + joinedAt | `M+1` | changed member 1 + Rules 1 | 画面単位autoDispose |

同一items queryを複数Providerからlistenしていない。pendingとpurchasedは異なるstatus query。
Group切替では依存する`currentGroupProvider`が変わるため旧queryをcancelし、logoutではempty streamへ
切り替わる。今回、画面を離れた後も残り得た3 listenerをautoDispose化した。

Firestore mobile SDKのoffline persistenceが有効な場合でも、30分を超えるdisconnect後のreconnectは
new query相当で課金される。listener結果のdocument追加・更新・field変更による除外もread対象で、
document自体のdeleteによる除外はdocument read対象外。ただしRules dependent readはquery update時に発生する。

## Action別Cost

### App open

1 User、1 Group、pending `P`件、1 deviceのcold open / 30分超reconnectを想定すると:

```text
ensureUser                  1 read
user group refs             1 read
group document              1 read
group membership Rules      1 read
device registration check   1 read
pending initial             P reads
pending Rules               1 read
Total                       P + 6 reads
```

既存tokenが同じならdevice writeは今回0へ改善。新規device、token refresh、通知設定変更時のみ1 write。

### Item add / Push

Clientはitemとsuggestionをbatchで2 writes。item createだけがEventarcを1 event、notification
Functionを1 invocation発生させる。suggestion writeはtrigger対象外。

Functionはmembersを`M` readsし、追加者を除くUserごとにenabled devices queryを1回行う。空queryも
最低1 readなので、Push backend readは次式。

```text
M + Σ max(1, recipient userのenabled device数)
```

1 device/Userの場合:

| Family | Backend reads/add | Eventarc | Function | FCM sends |
| ---: | ---: | ---: | ---: | ---: |
| 2 users | 3 | 1 | 1 | 1 |
| 4 users | 7 | 1 | 1 | 3 |
| 6 users | 11 | 1 | 1 | 5 |

4 usersで各recipientが3 devicesなら、members 4 + devices 9 = 13 reads、9 sends。追加者本人の
devicesはqueryしない。恒久的invalid tokenは送信結果からdevice documentをdeleteし、450件ずつの
batchへ分割する。

全4 UserがShopping listenerを開いている保守的条件では、item addは各端末でitem 1 + Rules 1、
合計8 realtime reads。したがって4人/1deviceの1 addは概ね:

```text
Firestore reads: 1 Rules(client write) + 7 backend + 8 listeners = 16
Firestore writes: 2
Function/Eventarc: 1 / 1
FCM sends: 3
```

### Purchase / Undo / Delete

- Purchase: 1 write + Rules 1 read。pending listenerごとにitem 1 + Rules 1。create triggerなし。
- Undo: 1 write + Rules 1 read。pendingへ戻るためlistenerごとにitem 1 + Rules 1。triggerなし。
- Historyが同時に開いていればpurchase/undoで同様に1 item + 1 Rules read/Userが追加。
- Item delete: 1 delete + Rules 1 read。document delete自体はlistener document readを発生させないが、
  Rules再評価分は発生し得る。

### Suggestions

Bottom Sheet open時だけ`lastUsedAt desc limit 30`を1 query。文字入力は取得済み30件をClient filter
するため、keystrokeごとのFirestore accessはない。item add時のsuggestion create/updateはitemと同じ
batch内の1 write。unique name数に保存上限はない。

### Group operations

- Create: invite nonexistence 1 direct read、最大3 Rules reads、4 writes（group、owner member、
  user group ref、invite）。その後userGroups listenerが再評価。
- Join: invite + existing user ref + groupで3 direct reads、最大3 Rules reads、2 writes。
- Exit: member 1 direct read、最大1 Rules read、memberとuser group refの2 deletes。
- Delete callable: group + owner 2 reads、members `M` reads、invite 1 delete、recursive documents
  `N=1+M+I+S`の列挙readsとdeletes、user refs `M` deletes。概算は`reads≈2+M+N`、
  `deletes=1+N+M`。Admin SDKのrecursive deleteはcollectionを読み出して削除するため両方課金。

1,000 items、4 members、30 suggestionsなら`N=1,035`、約1,041 reads / 1,040 deletesに加えて
1 Function invocation。単価上は小さいが、60秒timeoutと大きなGroupでのpartial failureが運用risk。

## Eventarc / Functions / Region

- Trigger: `sendshoppingitemcreatednotification-460371`
- Source: `(default)` Firestore、`groups/{groupId}/items/{itemId}` create
- Event type: `google.cloud.firestore.document.v1.created`
- Trigger region: `nam5`
- Destination: `sendShoppingItemCreatedNotification`、`us-central1`
- Callable: `deleteGroup`、`us-central1`
- Runtime: Node.js 22、256 MiB、1 CPU、concurrency 80、timeout 60秒
- notification Functionのdeploy済み上限: `maxInstances=20`
- Retry: notification triggerは`RETRY_POLICY_DO_NOT_RETRY`

Firestoreは`nam5` multi-region、Eventarc sourceも`nam5`、Functionは対応する`us-central1`。
日本UserからのlatencyはTokyo構成より大きいが、現在の組合せはNorth America内であり、公開直前の
region migrationは行わない。Firestore locationはin-place変更できず、移行は別Project/DBとデータ移送を
伴う。将来Production projectを分離するときに日本regionを再評価する。

deploy済みFunctionは`deleteGroup`と`sendShoppingItemCreatedNotification`の2件で、いずれもACTIVE。

## Standard usage model

依頼のモデルを採用し、次を明示的に補った保守的steady-state:

- 1 household = 4 users、各1 device、各User 1 Group
- 1日12 cold opens（各User 3）、open時pending 10件
- 10 add、10 purchase、1 undo
- 全4 Userのpending listenerが全21 mutation時にactive
- historyは各User 2回、毎回limit上限100件
- suggestions sheetは各User 3回、毎回limit上限30件
- Group settingsは世帯全体で1回、4 members
- profile/tokenは不変、Group作成/削除、invalid token、item deleteは日常量から除外
- Security Rules dependent readsを含む

この条件は履歴・候補・同時listenerを上限寄りに置く。新規Groupでは実測は大幅に少ない。

### 1 household

| Component | Reads/day |
| --- | ---: |
| 12 app opens (`P+6`) | 192 |
| 8 history opens (`100+1`) | 808 |
| 12 suggestion opens (`30+1`) | 372 |
| 1 group settings (`4+1`) | 5 |
| pending realtime mutations | 168 |
| item mutation Rules reads | 21 |
| notification backend | 70 |
| **Total** | **1,636** |

| Metric | Per day | Per 30 days |
| --- | ---: | ---: |
| Firestore reads | 1,636 | 49,080 |
| Firestore writes | 31 | 930 |
| Firestore deletes | 0 | 0 |
| Function invocations | 10 | 300 |
| Eventarc events | 10 | 300 |
| FCM sends | 30 | 900 |

### Scale

| Households | Users | Monthly reads | Monthly writes | Monthly deletes | Functions | Eventarc events | Push sends |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 4 | 49,080 | 930 | 0 | 300 | 300 | 900 |
| 100 | 400 | 4,908,000 | 93,000 | 0 | 30,000 | 30,000 | 90,000 |
| 1,000 | 4,000 | 49,080,000 | 930,000 | 0 | 300,000 | 300,000 | 900,000 |
| 10,000 | 40,000 | 490,800,000 | 9,300,000 | 0 | 3,000,000 | 3,000,000 | 9,000,000 |

## Current pricing and estimate

2026-09-02時点の公式公開単価。Firestore `nam5`はStandard pricing groupでreads `$0.03/100k`、
writes `$0.09/100k`、deletes `$0.01/100k`。default DBの無料枠は50k reads/day、20k
writes/day、20k deletes/day、1 GiB storage、10 GiB outbound/month。無料枠は日次なので、
scale計算も`max(0, daily usage - daily quota) × 30`とした。

Cloud Run request-based `us-central1`は2M requests、180k vCPU-sec、360k GiB-sec/monthが無料。
超過はrequest `$0.40/M`、CPU `$0.000024/vCPU-sec`、memory `$0.0000025/GiB-sec`。
notification Functionを平均0.5秒、1 CPU、256 MiB、concurrency共有なしで中心推計し、0.2〜1.0秒を
感度幅とする。実際はCloud Monitoringのbilled instance timeで置き換える。

| Households | Gross / billable reads | Gross / billable writes | Firestore | Functions | Eventarc + Pub/Sub | Logging | Other | Total USD |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 4.908M / 3.408M | 93k / 0 | $1.02 | $0 | $0 | $0 | ≈$0 | **≈$1.02** |
| 1,000 | 49.08M / 47.58M | 930k / 330k | $14.57 | $0 | $0 | $0 | ≈$0 | **≈$14.57** |
| 10,000 | 490.8M / 489.3M | 9.3M / 8.7M | $154.62 | $32.12 | $0 | $0 | $0〜1 storage | **≈$187** |

10,000世帯のFunction感度は約`$10.48`（0.2秒）〜`$69.06`（1秒）、総額は概ね
`$165〜225/月`。説明用に1 USD=150円なら約`24,800〜33,800円/月`。実請求は日本円SKU、税、
為替、billing account全体で共有されるCloud Run free tier、network、実行時間、保存容量で変わる。

Eventarc StandardのGoogle source eventは$0。Pub/Sub transportは最初の10 GiBが無料で、2 KiB/event
相当なら3M eventsは約5.7 GiBとなり、単独Projectでは無料枠内。FCM、Analytics、Crashlyticsは
no-cost。Google/social
AuthはIdentity Platformへupgrade済みでも50k MAUまで無料のため40k usersモデル内では$0。

Cloud Loggingは50 GiB/project/monthまで無料。今回、itemごとの正常系info logを削除し、error、
warning、Group delete、invalid token cleanupだけを残した。Artifact Registryの`gcf-artifacts`には
1日超のimageを削除するFirebase管理cleanup policyが設定済み。

## Primary cost drivers

1. History open: `8 × 101 = 808 reads/day/household`
2. Suggestions open: `12 × 31 = 372 reads/day/household`
3. App open / reconnect: pending初期件数とGroup N+1 hydration
4. Active pending listeners: mutationごとに全active Userへitem + Rules read
5. Item add Push fan-out: members + recipient devices + Function compute

## Abuse and worst cases

| Scenario | Billing impact | Current protection |
| --- | --- | --- |
| item大量追加 | 2 writes/add + Eventarc + Function + member/device reads + Push + listeners | Auth/memberのみ。rate limitなし |
| Group大量作成 | invite check、4 writes、userGroups N+1再取得 | Authのみ。Groups/User上限なし |
| unique suggestion大量生成 | 1 extra write/add、storage/index増加 | name 200文字のみ。件数上限なし |
| app reopen/reconnect連打 | user/profile/device/group/pending initial reads | offline cacheのみ。30分超はnew query課金 |
| devices大量登録 | Push device reads/sends増加 | self writeのみ。Devices/User上限なし |
| Group delete巨大化 | recursive reads/deletes、timeout/partial cleanup | owner callable、batching。Items上限なし |

Rules上のfield制限はitem name 200、note 500、group name 100、display name 100、invite 6〜8。
quantityは1以上のみで上限なし。Groups/User、Items/Group、Suggestions/Group、Devices/Userの件数上限と
write rate limitはない。Security Rulesはauthorizationとshape validationには有効だが、正規memberの
大量writeを防がない。さらに拒否requestでもRules dependent readは課金され得る。

## Optimizations

### MUST FIX BEFORE RELEASE

- Google Cloud Billing Budgetを`¥1,000 / ¥3,000 / ¥5,000`で通知し、Billing emailを確認する。
- Firestore read/write、Function invocation/error、Cloud Run billed instance timeにmonitoring/alertを設定。
- 一般公開前にApp Checkを導入し、item/group/device writeのabuse対策方針を決定する。App Check単独は
  rate limitではないため、正規Userの大量操作にはserver-side rate limitまたは運用停止手順も必要。
- Productionとdevを同Projectで運用する場合、TestFlight負荷も同じquota/budgetへ合算されることを承認する。

### SHOULD FIX

- Groups/User、Items/Group、Devices/Userの現実的上限と、item/group create rate limitを設計する。
- Group deleteのdocument数・durationを記録し、大規模Groupをasync jobへ移す閾値を決める。
- `watchUserGroups`のN+1 hydrationを、Group数が増えた実測後にdenormalization等で解消する。
- purchase historyの保持期間またはarchive方針を決め、storageの無制限成長を避ける。

### CAN WAIT

- history 100→50への縮小やpagination。現在すでにlimit 100で事故級ではない。
- suggestions 30のさらなる縮小。keystroke queryは存在しない。
- region migration。Production project分離時に日本regionを評価する。
- Redis、SQL、独自WebSocket等への移行。

### 今回実装

- pending / history / members StreamProviderを画面単位autoDispose化。
- FCM token、platform、enabledが同値ならdevice writeをskip。
- notification正常系のitem単位info logを削除。
- invalid token cleanupを450 deletes/batchへ分割。

## Budget alerts and monitoring

Manual Setup Required:

1. Google Cloud Console → Billing → Budgets & alerts → Create budget。
2. Scopeをbilling account全体ではなく可能な限り`katte-dev-jp`へ絞る。
3. Budget `¥1,000`、threshold 50/90/100%。次に`¥3,000`と`¥5,000`も同様に作成。
4. Email recipientsを確認し、必要ならPub/Sub notificationを将来の自動停止runbookへ接続。
5. Billing → ReportsでService / SKU / Project別に確認し、FirestoreとCloud Runを分離する。

**Budget alert != automatic spending cap**。通知遅延もあり、課金をhard stopしない。緊急時はFunctionの
traffic/trigger停止、Rulesのwrite停止、API quota変更等を人が判断するrunbookが必要。

監視頻度:

- TestFlight: daily — Firestore Usage、Function invocations/errors/duration、Eventarc delivery、Logging、Billing
- 公開後1〜2週: daily — 1 active householdあたりread/writeとitem addあたりFunction時間を実測
- 安定後: weekly — usage trend、invalid tokens、storage、Artifact Registry
- Monthly: Billing report、free tier消費、予測と実績の差、上限/alert見直し

確認場所:

- Firebase Console → Firestore → Usage
- Firebase Console → Functions / Crashlytics / Analytics
- Google Cloud Console → Cloud Run functions metrics
- Google Cloud Console → Eventarc triggers / Pub/Sub metrics
- Logs Explorer（severity warning以上を中心）
- Billing → Reports / Cost table / Budgets & alerts

## Pricing sources

- [Firestore pricing](https://cloud.google.com/firestore/pricing)
- [Firestore listener / Rules billing](https://firebase.google.com/docs/firestore/pricing)
- [Cloud Run pricing](https://cloud.google.com/run/pricing)
- [Eventarc pricing](https://cloud.google.com/eventarc/pricing)
- [Cloud Logging pricing](https://cloud.google.com/logging)
- [Firebase pricing / no-cost products](https://firebase.google.com/pricing)
- [Identity Platform pricing](https://cloud.google.com/identity-platform/pricing)

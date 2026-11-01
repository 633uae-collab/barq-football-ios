# نشر FOTIQ على TestFlight من الآيفون فقط (بدون ماك)

كل البناء والتوقيع يصير على خوادم GitHub Actions المجانية (macOS 26 + Xcode 26). أنت تحتاج الآيفون والمتصفح فقط.

## قبل الدفع: وش الجاهز؟
- المشروع يُبنى بنجاح ويجتاز الاختبارات على محاكي iOS 26 في كل رفع (Push).
- معرّف التطبيق: `ae.barq.football` ومعرّف الودجت (Live Activity): `ae.barq.football.widgets`.
- مجموعة التطبيقات (App Group): `group.ae.barq.football`.
- الصلاحيات: الإشعارات (Push) + App Groups + Live Activities.
- أيقونة التطبيق 1024، وملف الخصوصية `PrivacyInfo.xcprivacy`، وملف التصدير `ci/ExportOptions.plist` (app-store-connect).
- رقم البناء يتولد تلقائياً من رقم تشغيل GitHub Actions، ورقم الإصدار `1.0.0` في `project.yml`.

## الخطوة 1: الاشتراك (99 دولار سنوياً)
1. من سفاري افتح https://developer.apple.com/programs/enroll/ وسجّل دخول بحساب Apple ID حقك.
2. الأسهل من الآيفون: تطبيق **Apple Developer** من App Store ثم Enroll Now. تدفع من داخله.
3. انتظر رسالة التفعيل (عادة من ساعات إلى يومين).

## الخطوة 2: رقم الفريق (Team ID)
- https://developer.apple.com/account ثم Membership details ثم انسخ **Team ID** (10 حروف/أرقام).

## الخطوة 3: تسجيل المعرّفات (مرة وحدة)
في https://developer.apple.com/account/resources/identifiers :
1. اضغط + ثم App IDs ثم App، الوصف `BARQ`، Bundle ID صريح: `ae.barq.football`. فعّل **Push Notifications** و**App Groups**.
2. كرر لـ `ae.barq.football.widgets` وفعّل **App Groups**.
3. في Identifiers اختر App Groups ثم + وسجّل `group.ae.barq.football`، وبعدين اربطها بالمعرّفين.
(التوقيع التلقائي يقدر يسويها بنفسه، لكن تسجيلها يدوياً يمنع أخطاء أول مرة.)

## الخطوة 4: سجل التطبيق في App Store Connect
1. https://appstoreconnect.apple.com ثم Apps ثم + ثم New App.
2. المنصة iOS، الاسم `FOTIQ` (لو كان محجوزاً جرّب `FOTIQ Football` أو `FOTIQ - Live Scores`)، اللغة العربية، Bundle ID: `ae.barq.football`، SKU: `barq-football`.

## الخطوة 5: مفتاح App Store Connect API
1. App Store Connect ثم Users and Access ثم Integrations ثم App Store Connect API ثم Team Keys.
2. Generate API Key، الاسم `GitHub CI`، الصلاحية **App Manager** (أو Admin).
3. انسخ **Key ID** و**Issuer ID** (فوق الجدول).
4. حمّل ملف `AuthKey_XXXX.p8`. **ينحمل مرة وحدة فقط**. افتحه من تطبيق الملفات وانسخ كل النص، من `-----BEGIN PRIVATE KEY-----` إلى `-----END PRIVATE KEY-----`.

## الخطوة 6: الأسرار في GitHub (لا ترسلها لي في المحادثة)
افتح: https://github.com/633uae-collab/barq-football-ios/settings/secrets/actions ثم **New repository secret** لكل واحد:

| الاسم | القيمة |
|---|---|
| `APPLE_TEAM_ID` | Team ID من الخطوة 2 |
| `ASC_KEY_ID` | Key ID من الخطوة 5 |
| `ASC_ISSUER_ID` | Issuer ID من الخطوة 5 |
| `ASC_KEY_P8` | نص ملف ‎.p8 كامل |

## الخطوة 7: تشغيل الرفع
1. https://github.com/633uae-collab/barq-football-ios/actions/workflows/ios.yml
2. **Run workflow** ثم main ثم Run.
3. يبني على المحاكي أولاً، وبعدها مهمة `testflight` تأرشف وتوقّع تلقائياً وترفع على App Store Connect.
4. بعد 10 إلى 30 دقيقة يظهر البناء في App Store Connect ثم TestFlight. أضف نفسك مختبر داخلي، وثبّت تطبيق **TestFlight** على الآيفون.

## الخطوة 8: الإشعارات الحقيقية و Live Activities من الخادم
1. developer.apple.com ثم Keys ثم + ثم فعّل **Apple Push Notifications service (APNs)**، وحمّل ملف ‎.p8.
2. على الخادم (ليس في GitHub ولا المحادثة) ضع: `APNS_KEY_ID`، `APNS_TEAM_ID`، `APNS_KEY_PATH`، `APNS_TOPIC=ae.barq.football`.
3. اربط `backend-addons/push.js` بالخادم.
4. لـ Live Activity يكون الـ topic هو `ae.barq.football.push-type.liveactivity` ونوع الدفع `liveactivity`.

## وش لازم يتجرب على الآيفون نفسه (ما ينعتبر مختبر قبلها)
- Live Activity على شاشة القفل و Dynamic Island مع تحديثات APNs والتطبيق مقفل.
- Push-to-start (تبدأ تلقائياً مع صافرة البداية لفريقك المفضل).
- الإشعارات الحقيقية من الخادم (APNs).
- إضافة المباراة لتقويم الآيفون.
